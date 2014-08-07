from subprocess import Popen
import tempfile
import zmq


"""Transplant is a Python client for remote code execution

It can start and connect Matlab servers and send them messages. All
messages are JSON-encoded strings. All messages are dictionaries with
two keys: 'type' and 'content'.

These message types are implemented:
- 'eval': the server evaluates the content of the message.
- 'die': the server closes its 0MQ session and quits.

These response types are implemented:
- 'ack': the server received the message successfully.
- 'error': there was an error while handling the message.

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

    def eval(self, msg_content):
        """Send some code to Matlab to execute."""
        result = self.send_message('eval', msg_content)
        if result['type'] == 'error':
            raise RuntimeError(result['content'])
        elif result['content']:
            return result['content']

    def __del__(self):
        """Close the connection, and kill the process."""
        self.send_message('die')
        self.process.terminate()

    def send_message(self, msg_type, msg_content=''):
        """Send a message and return the response"""
        self.socket.send_json({'type':msg_type,
                               'content':msg_content})
        return self.socket.recv_json()
