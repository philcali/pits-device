
class Handler():
    """
    Base handler that provides all of the methods to implement
    """
    def on_combine_end(self, event):
        """
        Handle the event signaling for when video is combined.
        Event field is: `combine_dir`
        """
        pass

    def on_flush_end(self, event):
        """
        Handle the event signaling the camera flushing.
        Event fields are `start_time`
        """
        pass

    def on_motion_start(self, event):
        """
        Handle the event signaling when motion is detected.
        """
        pass

    def on_upload_end(self, event):
        """
        Handle the event signaling when upload to S3 has finished.
        Event fields are `start_time` and `upload` which is a doucument
        containing `bucket_name` and `bucket_key`.
        """
        pass

    def on_file_change(self, event):
        """
        Handle the event signaling when there is a file change.
        Event fields are `content` which contains the content of the file.
        """
        pass

    def on_capture_video(self, event):
        """
        Handle the event signaling the user's intent to capture a video feed.
        Event fields are `duration` (optional... will use buffer)
        """
        pass

    def on_capture_image(self, event):
        """
        Handle the call capture event image.
        """
        pass

    def on_capture_image_end(self, event):
        """
        Handle when the capture of an image is created.
        Event field is: `image_file`
        """
        pass

    def on_recording_change(self, event):
        """
        Handle when the camera's recording state changes.
        Event field is: `recording` boolean
        """
        pass

    def on_health(self, event):
        """
        Handle for starting a health metric push.
        """
        pass

    def on_health_end(self, event):
        """
        Handle when attempting to read health metric data.
        Event fields are
        - `start_time`: pinthesky process started
        - `up_time`: duration in seconds of pinthesky process
        - `recording_status`: whether camera is actively recording
        - `motions_captured`: number of motions captured
        - `ip_addr`: ip of the default route
        - `version`: version of pinthesky running
        - `disk_free`: disk free in bytes
        - `disk_used`: disk used in bytes
        - `disk_total`: disk total in bytes
        - `mem_free`: memory free in KB
        - `mem_avail`: memory available in KB
        - `mem_total`: memory total in KB
        """
        pass
