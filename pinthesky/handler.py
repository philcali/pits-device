
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
