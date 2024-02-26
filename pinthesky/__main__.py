from datetime import timedelta
import logging

from pinthesky import VERSION, input, output, upload, set_stream_logger
from pinthesky.camera import CameraThread
from pinthesky.combiner import VideoCombiner
from pinthesky.config import ShadowConfig
from pinthesky.events import EventThread
from pinthesky.health import DeviceHealth
from pinthesky.session import Session
import argparse
import sys
import signal


def create_parser():
    parser = argparse.ArgumentParser(
        description="Simple camera stream that captures motion video events")
    parser.add_argument(
        "--log-level",
        help="configured log level of the pinthesky app, default INFO",
        required=False,
        default='INFO')
    parser.add_argument(
        "--version",
        help="displays the current version",
        action='store_true')
    parser.add_argument(
        "--combine-dir",
        help="the directory to combine video, defaults to motion_videos",
        default="motion_videos")
    parser.add_argument(
        "--rotation",
        help="rotate the video, valid arguments [0, 90, 180, 270]",
        default=270,
        type=int)
    parser.add_argument(
        "--encoding-bitrate",
        help="the bitrate for the camera, default 17000000",
        default=17000000,
        type=int)
    parser.add_argument(
        "--encoding-profile",
        help="the camera encoding profile, default high",
        default="high")
    parser.add_argument(
        "--encoding-level",
        help="the encoding level, default 4",
        default="4")
    parser.add_argument(
        "--resolution",
        help="camera resolution, defaults 640x480",
        default="640x480")
    parser.add_argument(
        "--framerate",
        help="framerate of the camera, defaults to 20",
        type=int,
        default=20)
    parser.add_argument(
        "--buffer",
        help="buffer size in seconds, defaults to 15",
        type=int,
        default=15)
    parser.add_argument(
        "--buffer-size",
        help="buffer size in bytes, unset by default and uses buffer",
        type=int,
        required=False,
        default=None)
    parser.add_argument(
        "--sensitivity",
        help="sensitivity of the motion detection math, default 10",
        type=int,
        default=10)
    parser.add_argument(
        "--event-input",
        help="file representing external input, default input.json",
        default="input.json")
    parser.add_argument(
        "--event-output",
        help="file representing external output, default output.json",
        default="output.json")
    parser.add_argument(
        "--configure-input",
        help="file for configuration input, default config-input.json",
        default="config-input.json")
    parser.add_argument(
        "--configure-output",
        help="file for configuration output, default config-output.json",
        default="config-output.json")
    parser.add_argument(
        "--thing-name",
        help="the AWS IoT ThingName for use in upload",
        default=None,
        required=False)
    parser.add_argument(
        "--thing-cert",
        help="the AWS IoT certificate associated to the Thing",
        default=None,
        required=False)
    parser.add_argument(
        "--thing-key",
        help="the AWS IoT certificate pair associated to the Thing",
        default=None,
        required=False)
    parser.add_argument(
        "--ca-cert",
        help="the root CA certificate to authenticate the certificate",
        default=None,
        required=False)
    parser.add_argument(
        "--credentials-endpoint",
        help="the AWS IoT Credentials Provider endpoint",
        default=None,
        required=False)
    parser.add_argument(
        "--role-alias",
        help="the AWS IoT Role Alias to pull credentials",
        default=None,
        required=False)
    parser.add_argument(
        "--bucket-name",
        help="the S3 bucket to upload motion detection files",
        default=None,
        required=False)
    parser.add_argument(
        "--bucket-prefix",
        help="the prefix to upload the motion files to, default motion_videos",
        default="motion_videos")
    parser.add_argument(
        "--recording-window",
        help="the recording window for the camera relative to the host time," +
        " ie: '08-18' for a ten hour window, defaults to always recordding",
        required=False,
        default=None)
    parser.add_argument(
        "--capture-dir",
        help="the directory to write temporary images, default capture_images",
        default="capture_images",
        required=False)
    parser.add_argument(
        "--bucket-image-prefix",
        help="the prefix to upload the latest images, default capture_images",
        default="capture_images",
        required=False)
    parser.add_argument(
        "--shadow-update",
        help="behavior for the camera shadow document: always, never, empty",
        default="empty",
        required=False)
    parser.add_argument(
        "--health-interval",
        help="seconds in which to emit health metrics, default: 3600",
        default=3600,
        type=int,
        required=False)
    return parser


def main():
    parsed = create_parser().parse_args(sys.argv[1:])
    if parsed.version:
        print(VERSION)
        exit(0)
    set_stream_logger("pinthesky", level=logging.getLevelName(parsed.log_level))
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
        buffer_size=parsed.buffer_size)
    video_combiner = VideoCombiner(
        events=event_thread,
        combine_dir=parsed.combine_dir)
    event_input_handler = input.InputHandler(events=event_thread)
    event_thread.on(camera_thread)
    event_thread.on(video_combiner)
    event_thread.on(video_uploader)
    event_thread.on(event_output)
    event_thread.on(event_input_handler)
    event_thread.on(auth_session)
    event_thread.on(device_health)
    shadow_update = ShadowConfig(
        events=event_thread,
        configure_input=parsed.configure_input,
        configure_output=parsed.configure_output)
    event_thread.on(shadow_update)
    shadow_update.add_handler(camera_thread)
    shadow_update.add_handler(auth_session)
    shadow_update.add_handler(device_health)
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

    signal.signal(signalnum=signal.SIGINT, handler=signal_handler)
    camera_thread.join()


if __name__ == "__main__":
    main()
