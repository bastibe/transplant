from subprocess import Popen, DEVNULL, PIPE
import re
import tempfile
import zmq
import numpy as np
import base64
from os.path import dirname
from threading import Thread


"""Transplant is a Python client for remote code execution

You can call Matlab functions and interact with Matlab objects. Matlab
functions and objects are wrapped in proxy functions and objects in
Python, which forward all interactions to Matlab, and get resolved to
the original functions/objects when transferred back to Matlab.

All basic data types are passed by value, and Matlab matrices are
converted to Numpy arrays and vice versa.

It can start and connect Matlab servers and send them messages. All
messages are JSON-encoded strings. All messages are dictionaries with
at least one key: 'type'.

Depending on the message type, other keys may or may not be set.

There are seven request types sent by Python:
- 'die': the server closes its 0MQ session and quits.
- 'set': saves the 'value' as a global variable called 'name'.
- 'get': retrieves the value of a global variable 'name'.
- 'set_proxy': saves the 'value' as a field called 'name' on cached
               object 'handle'.
- 'get_proxy': retrieves the field called 'name' on cached object
               'handle'.
- 'del_proxy': remove cached object 'handle'.
- 'call': call function 'name' with 'args' and 'nargout'.

There are three response types:
- 'ack': the server received the message successfully.
- 'error': there was an error while handling the message.
- 'value': returns a value.

To enable cross-language functions, objects and matrices, these are
encoded specially when transmitted between Python and Matlab:
- Matrices are encoded as {"__matrix__", ... }
- Functions are encoded as {"__function__", str2func(f) }
- Objects are encoded as {"__object__", handle }

"""


class MatlabError(RuntimeError):
    """An exception that retains some Matlab-specific metadata."""

    def __init__(self, message, stack, identifier, original_message):
        super(MatlabError, self).__init__(message)
        self.stack = stack
        self.identifier = identifier
        self.original_message = original_message


class MatlabProxyObject:
    """Forwards all property access to an associated Matlab object."""

    def __init__(self, process, handle):
        self.__dict__['handle'] = handle
        self.__dict__['process'] = process

    def _getAttributeNames(self):
        return self.process.fieldnames(self)

    def __getattr__(self, name):
        return self.process._get_proxy(self.handle, name)

    def __setattr__(self, name, value):
        self.process._set_proxy(self.handle, name, value)

    def __repr__(self):
        getclass = self.process.str2func('class')
        return "<proxy for Matlab {} object>".format(getclass(self))

    def __str__(self):
        # remove pseudo-html tags from Matlab output
        html_str = self.process.eval("@(x) evalc('disp(x)')")(self)
        return re.sub('</?a[^>]*>', '', html_str)

    def __del__(self):
        self.process._del_proxy(self.handle)


class Matlab:
    """An instance of Matlab, running in its own process."""

    def __init__(self, executable='matlab', arguments=('-nodesktop', '-nosplash'), address=None, user=None):
        """Starts a Matlab instance and opens a communication channel."""
        if address is None:
            self.ipcfile = tempfile.NamedTemporaryFile()
            zmq_address = 'ipc://' + self.ipcfile.name
            process_arguments = ([executable] + list(arguments) +
                                 ['-r', 'transplant {}'.format(zmq_address)])
        else:
            # get local IP address
            from socket import create_connection
            with create_connection((address, 22)) as s:
                local_address, _ = s.getsockname()
            # generate a random port number
            from random import randint
            port = randint(49152, 65535)
            zmq_address = 'tcp://' + local_address + ':' + str(port)
            if user is not None:
                address = '{}@{}'.format(user, address)
            process_arguments = (['ssh', address, executable, '-wait'] + list(arguments) +
                                 ['-r', '"transplant {}"'.format(zmq_address)])
        self.context = zmq.Context.instance()
        self.socket = self.context.socket(zmq.REQ)
        self.socket.bind(zmq_address)
        # start Matlab, but make sure that it won't eat the REPL stdin
        # (stdin=DEVNULL), and that it won't respond to signals like
        # C-c of the REPL (start_new_session=True).
        self.process = Popen(process_arguments, stdin=DEVNULL, stdout=PIPE,
                             start_new_session=True)
        self._start_reader()
        self.eval('close') # no-op. Wait for Matlab startup to complete.

    def _set_value(self, name, value):
        """Save a value as a named variable."""
        self.send_message('set', name=name, value=value)

    def _get_value(self, name):
        """Retrieve a value from a named variable."""
        response = self.send_message('get', name=name)
        return response['value']

    def _set_proxy(self, handle, name, value):
        """Save a value to a named field of a proxy object."""
        self.send_message('set_proxy', handle=handle, name=name, value=value)

    def _get_proxy(self, handle, name):
        """Retrieve a value from a named field of a proxy object."""
        response = self.send_message('get_proxy', handle=handle, name=name)
        return response['value']

    def _del_proxy(self, handle):
        """Tell Matlab to forget about this proxy object."""
        self.send_message('del_proxy', handle=handle)

    def __getattr__(self, name):
        """Retrieve a value or function from Matlab."""
        return self._get_value(name)

    def __setattr__(self, name, value):
        """Retrieve a value or function from Matlab."""
        if name in ['ipcfile', 'context', 'socket', 'process']:
            self.__dict__[name] = value
        else:
            self._set_value(name, value)

    def _call(self, name, args, nargout=-1):
        """Call a Matlab function."""
        args = list(args)
        response = self.send_message('call', name=name, args=args,
                                     nargout=nargout)
        if response['type'] == 'value':
            return response['value']

    def _start_reader(self):
        """Starts an asynchronous reader that echos everything Matlab says"""
        stdout = self.process.stdout
        def reader():
            """Echo what Matlab says using print"""
            for line in iter(stdout.readline, bytes()):
                print(line.decode(), end='')
        Thread(target=reader, daemon=True).start()

    def __del__(self):
        """Close the connection, and kill the process."""
        self.send_message('die')
        self.process.terminate()

    def send_message(self, msg_type, **kwargs):
        """Send a message and return the response"""
        kwargs = self._encode_values(kwargs)
        self.socket.send_json(dict(kwargs, type=msg_type))
        response = self.socket.recv_json()
        response = self._decode_values(response)
        if response['type'] == 'error':
            # Create a pretty backtrace almost like Python's:
            trace = 'Traceback (most recent call last):\n'
            if isinstance(response['stack'], dict):
                response['stack'] = [response['stack']]
            for frame in reversed(response['stack']):
                trace += '  File "{file}", line {line}, in {name}\n'.format(**frame)
                if frame['file'] is not None and frame['file'].endswith('.m'):
                    trace += '    ' + open(frame['file'], 'r').readlines()[frame['line']-1].strip(' ')
            raise MatlabError('{message} ({identifier})\n'.format(**response) + trace,
                              response['stack'], response['identifier'], response['message'])
        return response

    def _encode_values(self, data):
        """Recursively walk through data and encode special entries."""
        if isinstance(data, np.ndarray):
            return self._encode_matrix(data)
        elif isinstance(data, MatlabProxyObject):
            return self._encode_proxy(data)
        elif isinstance(data, dict):
            out = {}
            for key in data:
                out[key] = self._encode_values(data[key])
        elif isinstance(data, list) or isinstance(data, tuple):
            out = list(data)
            for idx in range(len(data)):
                out[idx] = self._encode_values(data[idx])
        else:
            out = data
        return out

    def _decode_values(self, data):
        """Recursively walk through data and decode special entries."""
        if (isinstance(data, list) and
            len(data) == 4 and
            data[0] == "__matrix__"):
            return self._decode_matrix(data)
        elif (isinstance(data, list) and
            len(data) == 2 and
            data[0] == "__object__"):
            return self._decode_proxy(data)
        elif (isinstance(data, list) and
            len(data) == 2 and
            data[0] == "__function__"):
            return self._decode_function(data)
        elif isinstance(data, dict):
            out = {}
            for key in data:
                out[key] = self._decode_values(data[key])
        elif isinstance(data, list) or isinstance(data, tuple):
            out = list(data)
            for idx in range(len(data)):
                out[idx] = self._decode_values(data[idx])
        else:
            out = data
        return out


    def _encode_matrix(self, data):
        """Encode a Numpy array as a special list.

        The matrix `np.array([[1, 2], [3, 4]], dtype='int32')` would
        be encoded as
        `["__matrix__", "int32", [2, 2], "AQAAAAIAAAADAAAABAAAA==\n"]`

        where `"int32"` is the data type, `[2, 2]` is the matrix shape
        and `"AQAAAAIAAAADAAAABAAAA==\n"` is the base64-encoded matrix
        content.

        """

        return ["__matrix__", data.dtype.name, data.shape,
                base64.encodebytes(data.tostring()).decode()]

    def _decode_matrix(self, data):
        """Decode a special list to a Numpy array.

        The matrix `np.array([[1, 2], [3, 4]], dtype='int32')` would
        be encoded as
        `["__matrix__", "int32", [2, 2], "AQAAAAIAAAADAAAABAAAA==\n"]`

        where `"int32"` is the data type, `[2, 2]` is the matrix shape
        and `"AQAAAAIAAAADAAAABAAAA==\n"` is the base64-encoded matrix
        content.

        """

        dtype, shape, data = data[1:]
        out = np.fromstring(base64.decodebytes(data.encode()), dtype)
        return out.reshape(*shape)

    def _encode_proxy(self, data):
        """Encode a MatlabProxyObject as a special list.

        A proxy with handle `42` would be be encoded as
        `["__object__", 42]`

        """
        return ["__object__", data.handle]

    def _decode_proxy(self, data):
        """Decode a special list to a MatlabProxyObject.

        A proxy with handle `42` would be be encoded as
        `["__object__", 42]`

        """
        return MatlabProxyObject(self, data[1])

    def _decode_function(self, data):
        """Decode a special list to a wrapper function."""

        def call_matlab(*args, nargout=-1):
                return self._call(data[1], args, nargout=nargout)
        call_matlab.__doc__, _ = self._call('help', [data[1]])
        return call_matlab
