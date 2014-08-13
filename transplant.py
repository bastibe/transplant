from subprocess import Popen
import tempfile
import zmq
import numpy as np
import base64


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
- 'call': call function 'name' with 'args' and 'nargout'.

These response types are implemented:
- 'ack': the server received the message successfully.
- 'error': there was an error while handling the message.
- 'value': returns a value.

`put`, `get`, and `call` use a special encoding for matrices. See
`Matlab.encode_matrices` and `Matlab.decode_matrices` for more detail.

"""


class Matlab:
    """An instance of Matlab, running in its own process."""

    def __init__(self, matlab='matlab', args=('-nodesktop', '-nosplash')):
        """Starts a Matlab instance and opens a communication channel."""
        self.ipcfile = tempfile.NamedTemporaryFile()
        self.context = zmq.Context.instance()
        self.socket = self.context.socket(zmq.REQ)
        self.socket.bind('ipc://' + self.ipcfile.name)
        self.process = Popen([matlab] + list(args) +
                             ['-r', "transplant {}".format('ipc://' + self.ipcfile.name)])
        self.eval('') # wait for Matlab startup to complete

    def eval(self, string):
        """Send some code to Matlab to execute."""
        response = self.send_message('eval', string=string)
        if response['type'] == 'value':
            return response['value']

    def put(self, name, value):
        """Save a named variable."""
        self.send_message('put', name=name, value=value)

    def get(self, name):
        """Retrieve a variable."""
        response = self.send_message('get', name=name)
        return response['value']

    def __getattr__(self, name):
        """Retrieve a value or function from Matlab."""
        type = self.call('exist', [name], nargout=1)
        if type == 1:
            return self.get(name)
        elif type in (2, 3, 5, 6):
            def call_matlab(*args, nargout=-1):
                args = self.encode_matrices(args)
                return self.call(name, args, nargout=nargout)
            return call_matlab
        else:
            raise NameError("Name '{}' is not defined in Matlab.".format(name))

    def call(self, name, args, nargout=-1):
        """Call a Matlab function."""
        args = list(args)
        response = self.send_message('call', name=name, args=args,
                                     nargout=nargout)
        if response['type'] == 'value':
            return self.decode_matrices(response['value'])

    def __del__(self):
        """Close the connection, and kill the process."""
        self.send_message('die')
        self.process.terminate()

    def send_message(self, msg_type, **kwargs):
        """Send a message and return the response"""
        self.socket.send_json(dict(kwargs, type=msg_type))
        response = self.socket.recv_json()
        if response['type'] == 'error':
            # Create a pretty backtrace almost like Python's:
            trace = 'Traceback (most recent call last):\n'
            if isinstance(response['stack'], dict):
                response['stack'] = [response['stack']]
            for frame in reversed(response['stack']):
                trace += '  File "{file}", line {line}, in {name}\n'.format(**frame)
                trace += '    ' + open(frame['file'], 'r').readlines()[frame['line']-1].strip(' ')
            raise RuntimeError('{message} ({identifier})\n'.format(**response) + trace)
        return response

    def encode_matrices(self, data):
        """Recursively walk through data and encode all matrices as JSON data.

        The matrix `np.array([[1, 2], [3, 4]], dtype='int32')` would
        be encoded as
        `["__matrix__", "int32", [2, 2], "AQAAAAIAAAADAAAABAAAA==\n"]`

        where `"int32"` is the data type, `[2, 2]` is the matrix shape
        and `"AQAAAAIAAAADAAAABAAAA==\n"` is the base64-encoded matrix
        content.

        """

        if isinstance(data, dict):
            out = {}
            for key in data:
                out[key] = self.encode_matrices(data[key])
        elif isinstance(data, list) or isinstance(data, tuple):
            out = list(data)
            for idx in range(len(data)):
                out[idx] = self.encode_matrices(data[idx])
        elif isinstance(data, np.ndarray):
            out = ["__matrix__", data.dtype.name, data.shape,
                   base64.encodebytes(data.tostring()).decode()]
        else:
            out = data
        return out

    def decode_matrices(self, data):
        """Recursively walk through data and decode all matrices to np.ndarray

        The matrix `np.array([[1, 2], [3, 4]], dtype='int32')` would
        be encoded as
        `["__matrix__", "int32", [2, 2], "AQAAAAIAAAADAAAABAAAA==\n"]`

        where `"int32"` is the data type, `[2, 2]` is the matrix shape
        and `"AQAAAAIAAAADAAAABAAAA==\n"` is the base64-encoded matrix
        content.

        """

        if (isinstance(data, list) and
            len(data) == 4 and
            data[0] == "__matrix__"):
            dtype, shape, data = data[1:]
            out = np.fromstring(base64.decodebytes(data.encode()), dtype)
            out.reshape(*shape)
        elif isinstance(data, dict):
            out = {}
            for key in data:
                out[key] = self.decode_matrices(data[key])
        elif isinstance(data, list) or isinstance(data, tuple):
            out = list(data)
            for idx in range(len(data)):
                out[idx] = self.decode_matrices(data[idx])
        else:
            out = data
        return out


if __name__ == '__main__':
    m = Matlab()
    m.put('name', 'Matlab')
    m.eval("disp(['Hello, ' name '!'])")
    print('size([1 2 3]) = ', m.call('size', [[1, 2, 3]]))
    print('deal(1, 2) = ', m.call('deal', [1, 2], nargout=2))
    print('size([1 2 3]) = ', m.call('size', [[1, 2, 3]]), '(no nargout)')
    print('size([1 2 3]) = ', m.call('size', [[1, 2, 3]], nargout=0), '(nargout = 0)')
    print('size([1 2 3]) = ', m.call('size', [[1, 2, 3]], nargout=1), '(nargout = 1)')
    print('size([1 2 3]) = ', m.call('size', [[1, 2, 3]], nargout=2), '(nargout = 2)')
    print('max([1 2; 3 4]) = ', m.max(np.array([[1, 2], [3, 4]])))
    print('max([1 2 3 4+5j]) = ', m.max(np.array([[1, 2, 3, 4+5j]], dtype='complex64')))
    print(m.help('disp')[0])
