from datetime import timedelta

from pinthesky import VERSION, input, output, upload, set_stream_logger
from pinthesky.camera import CameraThread
from pinthesky.cloudwatch import CloudWatchManager
from pinthesky.combiner import VideoCombiner
from pinthesky.connection import ConnectionManager, ConnectionHandler
from pinthesky.config import ShadowConfig
from pinthesky.events import EventThread
from pinthesky.health import DeviceHealth
from pinthesky.session import Session
import argparse
import os
import sys
import signal


def create_parser():
    parser = argparse.ArgumentParser(
        description="Simple camera stream that captures motion video events")
    parser.add_argument(
        "--version",
        help="displays the current version",
        action='store_true')
    parser.add_argument(
        "--log-level",
        help="configured log level of the pinthesky app, default INFO",
        required=False,
        default='INFO')
    parser.add_argument(
        "--health-interval",
        help="seconds in which to emit health metrics, default: 3600",
        default=3600,
        type=int,
        required=False)
    camera = parser.add_argument_group(
        title="Camera",
        description="Configuration for camera options")
    camera.add_argument(
        "--rotation",
        help="rotate the video, valid arguments [0, 90, 180, 270]",
        default=270,
        type=int)
    camera.add_argument(
        "--encoding-bitrate",
        help="the bitrate for the camera, default 17000000",
        default=17000000,
        type=int)
    camera.add_argument(
        "--encoding-profile",
        help="the camera encoding profile, default high",
        default="high")
    camera.add_argument(
        "--encoding-level",
        help="the encoding level, default 4",
        default="4")
    camera.add_argument(
        "--resolution",
        help="camera resolution, defaults 640x480",
        default="640x480")
    camera.add_argument(
        "--framerate",
        help="framerate of the camera, defaults to 20",
        type=int,
        default=20)
    camera.add_argument(
        "--buffer",
        help="buffer size in seconds, defaults to 15",
        type=int,
        default=15)
    camera.add_argument(
        "--buffer-size",
        help="buffer size in bytes, unset by default and uses buffer",
        type=int,
        required=False,
        default=None)
    camera.add_argument(
        "--sensitivity",
        help="sensitivity of the motion detection math, default 10",
        type=int,
        default=10)
    camera.add_argument(
        "--recording-window",
        help="the recording window for the camera relative to the host time," +
        " ie: '08-18' for a ten hour window, defaults to always recordding",
        required=False,
        default=None)
    events = parser.add_argument_group(
        title="Events",
        description="Configuration for reading and writing events")
    events.add_argument(
        "--event-input",
        help="file representing external input, default input.json",
        default="input.json")
    events.add_argument(
        "--event-output",
        help="file representing external output, default output.json",
        default="output.json")
    events.add_argument(
        "--configure-input",
        help="file for configuration input, default config-input.json",
        default="config-input.json")
    events.add_argument(
        "--configure-output",
        help="file for configuration output, default config-output.json",
        default="config-output.json")
    iot = parser.add_argument_group(
        title='AWS IoT',
        description='Configuration for integrating with AWS IoT')
    iot.add_argument(
        "--thing-name",
        help="the AWS IoT ThingName for use in upload",
        default=None,
        required=False)
    iot.add_argument(
        "--thing-cert",
        help="the AWS IoT certificate associated to the Thing",
        default=None,
        required=False)
    iot.add_argument(
        "--thing-key",
        help="the AWS IoT certificate pair associated to the Thing",
        default=None,
        required=False)
    iot.add_argument(
        "--ca-cert",
        help="the root CA certificate to authenticate the certificate",
        default=None,
        required=False)
    iot.add_argument(
        "--credentials-endpoint",
        help="the AWS IoT Credentials Provider endpoint",
        default=None,
        required=False)
    iot.add_argument(
        "--role-alias",
        help="the AWS IoT Role Alias to pull credentials",
        default=None,
        required=False)
    iot.add_argument(
        "--shadow-update",
        help="behavior for the camera shadow document: always, never, empty",
        default="empty",
        required=False)
    storage = parser.add_argument_group(
        title="Storage",
        description="Configuration for remote storage")
    storage.add_argument(
        "--bucket-name",
        help="the S3 bucket to upload motion detection files",
        default=None,
        required=False)
    storage.add_argument(
        "--bucket-prefix",
        help="the prefix to upload the motion files to, default motion_videos",
        default="motion_videos")
    storage.add_argument(
        "--capture-dir",
        help="the directory to write temporary images, default capture_images",
        default="capture_images",
        required=False)
    storage.add_argument(
        "--bucket-image-prefix",
        help="the prefix to upload the latest images, default capture_images",
        default="capture_images",
        required=False)
    storage.add_argument(
        "--combine-dir",
        help="the directory to combine video, defaults to motion_videos",
        default="motion_videos")
    cloudwatch = parser.add_argument_group(
        title="CloudWatch",
        description="Configuration for CloudWatch logging")
    cloudwatch.add_argument(
        "--cloudwatch",
        help="enable the cloudwatch upload, default false",
        required=False,
        default=os.getenv("CLOUDWATCH", "false") == "true",
        action='store_true')
    cloudwatch.add_argument(
        "--cloudwatch-region",
        help="the AWS region name override for CloudWatch",
        default=os.getenv("AWS_DEFAULT_REGION", None),
        required=False)
    cloudwatch.add_argument(
        "--cloudwatch-thread",
        action='store_true',
        default=os.getenv("CLOUDWATCH_THREADED", "false") == "true",
        required=False,
        help="enable cloudwatch logs to upload in background, default false")
    cloudwatch.add_argument(
        "--cloudwatch-event-type",
        default="logs",
        required=False,
        help="event type to upload: logs,emf,all")
    cloudwatch.add_argument(
        "--cloudwatch-metric-namespace",
        required=False,
        default="Pits/Device",
        help="metric namespace when using emf event type, default Pits/Device")
    cloudwatch.add_argument(
        "--cloudwatch-log-group",
        help="uploads to this cloudwatch log group",
        default=None,
        required=False)
    cloudwatch.add_argument(
        "--disable-cloudwatch-stream-split",
        help="disables splitting the log stream by thing name",
        default=os.getenv("CLOUDWATCH_DELINEATE_STREAM", "true") == "false",
        required=False,
        action='store_true')
    dataplane = parser.add_argument_group(
        title="Data Plane",
        description="Configuration for the data plane integration")
    dataplane.add_argument(
        "--dataplane",
        help="enable the dataplane integration",
        required=False,
        default=os.getenv("DATAPLANE", "false") == "true",
        action='store_true')
    dataplane.add_argument(
        "--dataplane-endpoint",
        help="endpoint for the dataplane",
        required=False,
        default=None)
    dataplane.add_argument(
        "--dataplane-region",
        help="the AWS region name override for the Data Plane",
        required=False,
        default=os.getenv("AWS_DEFAULT_REGION", None))
    return parser


def main():
    parsed = create_parser().parse_args(sys.argv[1:])
    if parsed.version:
        print(VERSION)
        exit(0)
    set_stream_logger("pinthesky", level=parsed.log_level)
    event_thread = EventThread()
    device_health = DeviceHealth(
        events=event_thread,
        flush_delta=timedelta(seconds=parsed.health_interval))
    notify_thread = input.INotifyThread(events=event_thread)
    event_output = output.Output(
        output_file=parsed.event_output,
        thing_name=parsed.thing_name)
    auth_session = Session(
        cacert_path=parsed.ca_cert,
        cert_path=parsed.thing_cert,
        key_path=parsed.thing_key,
        role_alias=parsed.role_alias,
        thing_name=parsed.thing_name,
        credentials_endpoint=parsed.credentials_endpoint)
    connection_manager = ConnectionManager(
        session=auth_session,
        enabled=parsed.dataplane,
        endpoint_url=parsed.dataplane_endpoint,
        region_name=parsed.dataplane_region)
    connection_handler = ConnectionHandler(manager=connection_manager)
    video_uploader = upload.S3Upload(
        events=event_thread,
        bucket_name=parsed.bucket_name,
        bucket_prefix=parsed.bucket_prefix,
        bucket_image_prefix=parsed.bucket_image_prefix,
        session=auth_session)
    camera_thread = CameraThread(
        device_health=device_health,
        events=event_thread,
        sensitivity=parsed.sensitivity,
        resolution=tuple(map(int, parsed.resolution.split('x'))),
        rotation=parsed.rotation,
        framerate=parsed.framerate,
        encoding_bitrate=parsed.encoding_bitrate,
        encoding_level=parsed.encoding_level,
        encoding_profile=parsed.encoding_profile,
        recording_window=parsed.recording_window,
        capture_dir=parsed.capture_dir,
        buffer_size=parsed.buffer_size,
        connection_manager=connection_manager)
    video_combiner = VideoCombiner(
        events=event_thread,
        combine_dir=parsed.combine_dir)
    event_input_handler = input.InputHandler(events=event_thread)
    cloudwatch_manager = CloudWatchManager(
        session=auth_session,
        log_level=parsed.log_level,
        delineate_stream=not parsed.disable_cloudwatch_stream_split,
        threaded=parsed.cloudwatch_thread,
        enabled=parsed.cloudwatch,
        log_group_name=parsed.cloudwatch_log_group,
        namespace=parsed.cloudwatch_metric_namespace,
        event_type=parsed.cloudwatch_event_type,
        region_name=parsed.cloudwatch_region)
    event_thread.on(camera_thread)
    event_thread.on(video_combiner)
    event_thread.on(video_uploader)
    event_thread.on(event_output)
    event_thread.on(event_input_handler)
    event_thread.on(auth_session)
    event_thread.on(device_health)
    event_thread.on(cloudwatch_manager)
    event_thread.on(connection_manager)
    event_thread.on(connection_handler)
    shadow_update = ShadowConfig(
        events=event_thread,
        configure_input=parsed.configure_input,
        configure_output=parsed.configure_output)
    event_thread.on(shadow_update)
    shadow_update.add_handler(camera_thread)
    shadow_update.add_handler(auth_session)
    shadow_update.add_handler(device_health)
    shadow_update.add_handler(cloudwatch_manager)
    shadow_update.add_handler(video_uploader)
    shadow_update.add_handler(connection_manager)
    # Allow adaptation before shadow document kicks in
    cloudwatch_manager.adapt_logging()

    if not shadow_update.update_document(parsed):
        shadow_update.reset_from_document()
    notify_thread.notify_change(parsed.event_input)
    notify_thread.notify_change(parsed.configure_output, persist=True)
    event_thread.start()
    camera_thread.start()
    notify_thread.start()

    # Trigger an initial health metric on process start
    device_health.emit_health(force=True)

    def signal_handler(signum, frame):
        notify_thread.stop()
        camera_thread.stop()
        event_thread.stop()
        event_output.reset()
        cloudwatch_manager.stop()

    signal.signal(signalnum=signal.SIGINT, handler=signal_handler)
    camera_thread.join()


if __name__ == "__main__":
    main()
