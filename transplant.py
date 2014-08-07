from subprocess import Popen
import tempfile
import zmq

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

    def eval(self, msg):
        """Send some code to Matlab to execute."""
        self.socket.send_string(msg)
        return self.socket.recv()

    def __del__(self):
        """Close the connection, and kill the process."""
        self.socket.send_string('die')
        self.socket.recv()
        self.process.terminate()
