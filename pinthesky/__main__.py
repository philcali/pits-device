import logging
from pinthesky import events, input, output, upload, session, combiner
import pinthesky
from pinthesky.camera import CameraThread
import argparse
import sys
import signal


VERSION = "0.1.1"


def create_parser():
    parser = argparse.ArgumentParser(
        description="Simple camera stream that captures motion video events")
    parser.add_argument(
        "--version",
        help="displays the current version",
        type=bool)
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
    return parser


def main():
    parsed = create_parser().parse_args(sys.argv[1:])
    if parsed.version:
        print(VERSION)
        exit(0)
    # TODO: make this externally configurable
    pinthesky.set_stream_logger("pinthesky", level=logging.INFO)
    event_thread = events.EventThread()
    notify_thread = input.INotifyThread(events=event_thread)
    event_output = output.Output(output_file=parsed.event_output)
    auth_session = session.Session(
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
        session=auth_session)
    camera_thread = CameraThread(
        events=event_thread,
        sensitivity=parsed.sensitivity,
        resolution=tuple(map(int, parsed.resolution.split('x'))),
        rotation=parsed.rotation,
        framerate=parsed.framerate,
        recording_window=parsed.recording_window)
    video_combiner = combiner.VideoCombiner(
        events=event_thread,
        combine_dir=parsed.combine_dir)
    event_input_handler = input.InputHandler(events=event_thread)
    event_thread.on(camera_thread)
    event_thread.on(video_combiner)
    event_thread.on(video_uploader)
    event_thread.on(event_output)
    event_thread.on(event_input_handler)
    event_thread.on(auth_session)
    notify_thread.notify_change(parsed.event_input)
    notify_thread.notify_change(parsed.configure_output)
    event_thread.start()
    camera_thread.start()
    notify_thread.start()

    def signal_handler(signum, frame):
        notify_thread.stop()
        camera_thread.stop()
        event_thread.stop()

    signal.signal(signalnum=signal.SIGINT, handler=signal_handler)
    camera_thread.join()


if __name__ == "__main__":
    main()
