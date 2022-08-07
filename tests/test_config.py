from collections import namedtuple
import json
import os
from pathlib import Path
from pinthesky.config import ConfigUpdate, ShadowConfig, ShadowConfigHandler
from pinthesky.events import EventThread
from tests.test_handler import TestHandler

Parser = namedtuple('Parser', ['shadow_update'])


class TestShadowHandler(ShadowConfigHandler):
    def update_document(self) -> ConfigUpdate:
        return ConfigUpdate('tests', {
            'send': 'value',
            'complex': {
                'key': 'value'
            }
        })


def test_shadow_config():
    configure_input = "test_shadow_input.json"
    configure_output = "test_shadow_output.json"
    shadow_config = ShadowConfig(
        events=EventThread(),
        configure_input=configure_input,
        configure_output=configure_output)
    assert not shadow_config.update_document(Parser('always'))


def test_shadow_config_empty():
    configure_input = "test_shadow_input.json"
    configure_output = "test_shadow_output.json"
    shadow_config = ShadowConfig(
        events=EventThread(),
        configure_input=configure_input,
        configure_output=configure_output)
    # Does not exists
    assert shadow_config.is_empty()
    # Empty file
    Path(configure_output).touch()
    assert shadow_config.is_empty()
    # Empty JSON
    with open(configure_output, 'w') as f:
        f.write("{}")
    assert shadow_config.is_empty()
    # Non-empty JSON
    with open(configure_output, 'w') as f:
        f.write(json.dumps({
            'some': 'key'
        }))
    assert not shadow_config.is_empty()
    os.remove(configure_output)


def test_shadow_update():
    events = EventThread()
    configure_input = "test_shadow_input.json"
    configure_output = "test_shadow_output.json"
    shadow_config = ShadowConfig(
        events=events,
        configure_input=configure_input,
        configure_output=configure_output)
    shadow_config.add_handler(TestShadowHandler())
    assert shadow_config.update_document(Parser('empty'))
    assert os.path.exists(configure_input)
    with open(configure_input, 'r') as f:
        payload = json.loads(f.read())
        assert payload == {
            'tests': {
                'send': 'value',
                'complex': {
                    'key': 'value'
                }
            }
        }
    os.remove(configure_input)


def test_shadow_reset():
    test_handler = TestHandler()
    events = EventThread()
    events.on(test_handler)
    events.start()
    configure_input = "test_shadow_input.json"
    configure_output = "test_shadow_output.json"
    shadow_config = ShadowConfig(
        events=events,
        configure_input=configure_input,
        configure_output=configure_output)
    with open(configure_output, 'w') as f:
        f.write(json.dumps({
            'current': {
                'state': {
                    'desired': {
                        'some': 'key',
                        'a': 'value'
                    }
                }
            }
        }))
    shadow_config.reset_from_document()
    while not events.event_queue.empty():
        pass
    os.remove(configure_output)
    assert test_handler.calls['file_change'] == 1
    events.stop()
