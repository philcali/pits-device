from math import floor
import os
import time
from pinthesky.combiner import VideoCombiner
from pinthesky.events import EventThread
from test_handler import TestHandler


def test_combiner():
    combine_dir = "combine_dir"
    handler = TestHandler()
    events = EventThread()
    combiner = VideoCombiner(events, combine_dir)
    events.on(handler)
    events.on(combiner)
    events.start()
    start_time = floor(time.time())
    with open(f'{start_time}.before.h264', 'w') as f:
        f.write("Hello ")
    with open(f'{start_time}.after.h264', 'w') as f:
        f.write("World!")
    events.fire_event("flush_end", {
        'start_time': start_time,
        'trigger': 'motion',
    })
    while not hasattr(handler, 'calls') or "combine_end" not in handler.calls:
        pass
    motion_file = f'{combine_dir}/{start_time}.motion.h264'
    try:
        assert os.path.exists(motion_file)
        os.remove(motion_file)
    finally:
        os.removedirs(combine_dir)
