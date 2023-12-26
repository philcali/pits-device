import logging
import re
import os
import psutil
import shutil
import socket
import sys
from datetime import datetime, timedelta
from math import floor
from threading import Lock
from pinthesky import VERSION
from pinthesky.config import ConfigUpdate, ShadowConfigHandler
from pinthesky.events import Handler

logger = logging.getLogger(__name__)


class DeviceHealthMetric:
    def report(self):
        return {}


class DeviceDiskMetric(DeviceHealthMetric):
    def report(self):
        fields = ['free', 'used', 'total']
        usage = shutil.disk_usage(path='/')
        return dict([(f'disk_{key}', getattr(usage, key)) for key in fields])


class DeviceCpuMetric(DeviceHealthMetric):
    def report(self):
        cpu_percent = psutil.cpu_percent()
        cpu_count = os.cpu_count()
        return {
            'cpu_used': cpu_percent,
            'cpu_count': cpu_count
        }


class DeviceMemoryMetric(DeviceHealthMetric):
    def report(self):
        fields = {
            'MemFree:': 'free',
            'MemAvailable:': 'avail',
            'MemTotal:': 'total'
        }
        usage = {}
        with open('/proc/meminfo', 'r') as mem:
            for line in mem.readlines():
                parts = re.split('\\s+', line)
                if parts[0] in fields:
                    usage[f'mem_{fields[parts[0]]}'] = int(parts[1])
        return usage


class DeviceHostAddress(DeviceHealthMetric):
    def report(self):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
                s.connect(('<broadcast>', 0))
                return {'ip_addr': s.getsockname()[0]}
        except Exception as e:
            logger.error(f'Failed to read ip: ${e}')
            return {'ip_addr': 'unknown'}


class DeviceHostRunningTime(DeviceHealthMetric):
    def __init__(self) -> None:
        self.start_time = datetime.utcnow()

    def report(self):
        delta = datetime.utcnow() - self.start_time
        return {
            'start_time': floor(self.start_time.timestamp()),
            'up_time': delta.seconds
        }


class DeviceOperatingSystem(DeviceHealthMetric):
    def __init__(self, release='/etc/os-release') -> None:
        self.release = []
        try:
            with open(release, 'r') as f:
                self.release = f.readlines()
        except Exception as e:
            logger.error(f'Failed to read OS release info: ${e}')

    def report(self):
        allowed_keys = set(['VERSION', 'ID'])
        reported = {'os_version': 'unknown', 'os_id': 'unknown'}
        for line in self.release:
            [key, value] = line.rstrip().split('=', 1)
            reported_key = f'os_{key.lower()}'
            if key in allowed_keys and reported_key in reported:
                reported[reported_key] = value.replace('"', '')
        return reported


class DeviceHealth(Handler, ShadowConfigHandler):
    def __init__(
            self,
            events,
            flush_delta=timedelta(seconds=60*60),
            metrics=[
                DeviceHostRunningTime(),
                DeviceMemoryMetric(),
                DeviceDiskMetric(),
                DeviceCpuMetric(),
                DeviceHostAddress(),
                DeviceOperatingSystem(),
            ]) -> None:
        self.events = events
        self.metrics = metrics
        self.motion_captured = 0
        self.flush_delta = flush_delta
        self.last_flush_time = datetime.utcnow()
        self.recording_status = False
        self.emit_health_lock = Lock()

    def update_document(self) -> ConfigUpdate:
        return ConfigUpdate('health', {
            'interval': self.flush_delta.seconds
        })

    def on_file_change(self, event):
        if "current" in event["content"]:
            desired = event["content"]["current"]["state"]["desired"]
            health = desired["health"]
            with self.emit_health_lock:
                if "interval" in health:
                    interval = int(health["interval"])
                    self.flush_delta = timedelta(seconds=interval)

    def on_flush_end(self, event):
        self.motion_captured += 1

    def on_recording_change(self, event):
        self.recording_status = event["recording"]

    def __flush_metrics(self):
        p_vs = sys.version_info
        context = {
            'version': VERSION,
            'python_version': f'{p_vs.major}.{p_vs.minor}.{p_vs.micro}',
            'motion_captured': self.motion_captured,
            'recording_status': self.recording_status,
        }
        for metric in self.metrics:
            context = dict(context, **metric.report())
        self.events.fire_event('health_end', context)
        self.last_flush_time = datetime.utcnow()
        logger.debug('Emitted health metric data')
        return context

    def emit_health(self, force=False):
        with self.emit_health_lock:
            now = datetime.utcnow()
            if force or now - self.last_flush_time > self.flush_delta:
                self.__flush_metrics()
                return True
        return False

    def on_health(self, event):
        with self.emit_health_lock:
            self.__flush_metrics()
