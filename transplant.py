from subprocess import Popen
import tempfile
import zmq


"""Transplant is a Python client for remote code execution

It can start and connect Matlab servers and send them messages. All
messages are JSON-encoded strings. All messages are dictionaries with
at least one key: 'type'.

Depending on the message type, other keys may or may not be set.

These message types are implemented:
- 'eval': the server evaluates the content of the message.
- 'die': the server closes its 0MQ session and quits.
- 'put': saves the 'value' as a global variable called 'name'.
- 'get': retrieves the global variable 'name'.

These response types are implemented:
- 'ack': the server received the message successfully.
- 'error': there was an error while handling the message.
- 'value': returns a value.

"""


class Matlab:
    """An instance of Matlab, running in its own process."""

    def __init__(self):
        """Starts a Matlab instance and opens a communication channel."""
        self.ipcfile = tempfile.NamedTemporaryFile()
        self.context = zmq.Context.instance()
        self.socket = self.context.socket(zmq.REQ)
        self.socket.bind('ipc://' + self.ipcfile.name)
        self.process = Popen(['matlab',
                              '-r', "transplant {}".format('ipc://' + self.ipcfile.name)])

    def eval(self, string):
        """Send some code to Matlab to execute."""
        self.send_message('eval', string=string)

    def put(self, name, value):
        """Save a named variable."""
        self.send_message('put', name=name, value=value)

    def get(self, name):
        """Retrieve a named variable."""
        result = self.send_message('get', name=name)
        return result['value']

    def __del__(self):
        """Close the connection, and kill the process."""
        self.send_message('die')
        self.process.terminate()

    def send_message(self, msg_type, **kwargs):
        """Send a message and return the response"""
        self.socket.send_json(dict(kwargs, type=msg_type))
        result = self.socket.recv_json()
        if result['type'] == 'error':
            raise RuntimeError('Error in Matlab: {message} ({identifier})'.format(**result))
        return result
