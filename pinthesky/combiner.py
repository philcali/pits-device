from pinthesky.handler import Handler
import logging
import os

logger = logging.getLogger(__name__)


class VideoCombiner(Handler):
    """
    Combines motion video by concatenating video buffering in memory with
    real-time video. The result of this handle will fire a `combine_end`
    event to signal waiters to do something with the video.
    """
    def __init__(self, events, combine_dir):
        self.events = events
        self.combine_dir = combine_dir

    def on_flush_end(self, event):
        """
        Responds to the camera thread that flushes the videos from buffers
        onto disk. This handle will combine both video parts into a full
        video stream.
        """
        if not os.path.exists(self.combine_dir):
            os.mkdir(self.combine_dir)
        file_name = os.path.join(
            self.combine_dir,
            f'{event["start_time"]}.motion.h264')
        with open(file_name, 'w') as o:
            for n in ['before', 'after']:
                part_name = f'{event["start_time"]}.{n}.h264'
                with open(part_name, 'r') as i:
                    o.write(i.read())
                os.remove(part_name)
        self.events.fire_event('combine_end', {
            'start_time': event['start_time'],
            'combine_video': file_name
        })
        logger.info(f'Finish concatinating to {file_name}')
