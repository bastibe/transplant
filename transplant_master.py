from subprocess import Popen, DEVNULL, PIPE
from signal import SIGINT
import re
import os
import tempfile
import zmq
import numpy as np
import base64
from threading import Thread
import msgpack
try:
    from scipy.sparse import spmatrix as sparse_matrix
except ImportError:
    # this will fool the `isinstance(data, sparse_matrix)` in
    # `_encode_values` to never trigger in case scipy.sparse is not
    # installed:
    sparse_matrix = tuple()


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
- 'set_global': saves the 'value' as a global variable called 'name'.
- 'get_global': retrieves the value of a global variable 'name'.
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


class TransplantError(RuntimeError):
    """An exception that retains some Remote-specific metadata."""

    def __init__(self, message, stack, identifier, original_message):
        super(TransplantError, self).__init__(message)
        self.stack = stack
        self.identifier = identifier
        self.original_message = original_message


class TransplantMaster:
    """Base class for Transplant Master objects.

    This starts a subprocess and opens a communications channel to
    that process using ZMQ. This class handles data serialization and
    communication. In order to use this class, the `ProxyObject` and
    `__init__` have to be overloaded.

    """

    ProxyObject = None

    def __init__(self, address):
        pass

    def _set_global(self, name, value):
        """Save a value as a named variable."""
        self.send_message('set_global', name=name, value=value)

    def _get_global(self, name):
        """Retrieve a value from a named variable."""
        response = self.send_message('get_global', name=name)
        return response['value']

    def _set_proxy(self, handle, name, value):
        """Save a value to a named field of a proxy object."""
        self.send_message('set_proxy', handle=handle, name=name, value=value)

    def _get_proxy(self, handle, name):
        """Retrieve a value from a named field of a proxy object."""
        response = self.send_message('get_proxy', handle=handle, name=name)
        return response['value']

    def _del_proxy(self, handle):
        """Tell the remote to forget about this proxy object."""
        self.send_message('del_proxy', handle=handle)

    def __getattr__(self, name):
        """Retrieve a value or function from the remote."""
        return self._get_global(name)

    def __setattr__(self, name, value):
        """Retrieve a value or function from the remote."""
        if name in ['ipcfile', 'context', 'socket', 'process', 'msgformat']:
            self.__dict__[name] = value
        else:
            self._set_global(name, value)

    def _call(self, name, args=[], kwargs=[]):
        """Call a function on the remote."""
        args = list(args)
        kwargs = dict(kwargs)
        response = self.send_message('call', name=name, args=args, kwargs=kwargs)
        if response['type'] == 'value':
            return response['value']

    def _start_reader(self):
        """Starts an asynchronous reader that echos everything the remote says"""
        stdout = self.process.stdout
        def reader():
            """Echo what the remote says using print"""
            for line in iter(stdout.readline, bytes()):
                print(line.decode(), end='')
        Thread(target=reader, daemon=True).start()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()

    def close(self):
        """Close the connection, and kill the process."""
        if self.process.returncode is not None:
            return
        self.send_message('die')
        self.process.wait()

    def __del__(self):
        """Close the connection, and kill the process."""
        self.close()

    def send_message(self, msg_type, **kwargs):
        """Send a message and return the response"""
        kwargs = self._encode_values(kwargs)
        if self.msgformat == 'msgpack':
            self.socket.send(msgpack.packb(dict(kwargs, type=msg_type), use_bin_type=True))
            response = msgpack.unpackb(self.socket.recv(), encoding='utf-8')
        else:
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
                    trace += '    ' + open(frame['file'], 'r').readlines()[int(frame['line'])-1].strip(' ')
            raise TransplantError('{message} ({identifier})\n'.format(**response) + trace,
                              response['stack'], response['identifier'], response['message'])
        return response

    def _encode_values(self, data):
        """Recursively walk through data and encode special entries."""
        if isinstance(data, (np.ndarray, np.number)):
            return self._encode_matrix(data)
        elif isinstance(data, complex):
            # encode python complex numbers as scalar numpy arrays
            return self._encode_matrix(np.complex128(data))
        elif isinstance(data, sparse_matrix):
            # sparse_matrix will be an empty tuple if scipy.sparse is
            # not installed.
            return self._encode_sparse_matrix(data)
        elif isinstance(data, self.ProxyObject):
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
            len(data) == 5 and
            data[0] == "__sparse__"):
            return self._decode_sparse_matrix(data)
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

        if self.msgformat == 'json':
            return ["__matrix__", data.dtype.name, data.shape,
                    base64.b64encode(data.tostring()).decode()]
        else:
            return ["__matrix__", data.dtype.name, data.shape,
                    data.tobytes()]

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
        if isinstance(data, str):
            out = np.fromstring(base64.b64decode(data.encode()), dtype)
        else:
            out = np.fromstring(data, dtype)
        shape = [int(n) for n in shape]; # numpy requires integer indices
        return out.reshape(*shape)

    def _encode_sparse_matrix(self, data):
        """Encode a scipy.sparse matrix as a special list.

        A sparse matrix `[[2, 0], [0, 3]]` would be encoded as
        `["__sparse__", [2, 2],
          <matrix for row indices [0, 1]>,
          <matrix for row indices [1, 0]>,
          <matrix for values [2, 3]>]`,
        where each `<matrix>` is encoded according to `_encode_matrix`
        and `[2, 2]` is the data shape.
        """

        # import scipy here to avoid a global import
        import scipy.sparse
        return ["__sparse__", data.shape] + \
            [self._encode_matrix(d) for d in scipy.sparse.find(data)]

    def _decode_sparse_matrix(self, data):
        """Decode a special list to a scipy.sparse matrix.

        A sparse matrix
        `["__sparse__", [2, 2],
          <matrix for row indices [0, 1]>,
          <matrix for row indices [1, 0]>,
          <matrix for values [2, 3]>]`,
        where each `matrix` is encoded according to `_encode_matrix`,
        would be decoded as `[[2, 0], [0, 3]]`.
        """

        # import scipy here to avoid a global import
        import scipy.sparse
        # either decode as vector, or as [], since coo_matrix doesn't
        # know what to do with 2D-arrays or None.
        row, col, value = (self._decode_matrix(d).ravel()
                           if d is not None else []
                           for d in data[2:])
        return scipy.sparse.coo_matrix((value, (row, col)), shape=data[1])

    def _encode_proxy(self, data):
        """Encode a ProxyObject as a special list.

        A proxy with handle `42` would be be encoded as
        `["__object__", 42]`

        """
        return ["__object__", data.handle]

    def _decode_proxy(self, data):
        """Decode a special list to a ProxyObject.

        A proxy with handle `42` would be be encoded as
        `["__object__", 42]`

        """
        return self.ProxyObject(self, data[1])

    def _decode_function(self, data):
        """Decode a special list to a wrapper function."""

        def call_remote(*args, **kwargs):
            return self._call(data[1], args, kwargs)
        return call_remote


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


class Matlab(TransplantMaster):
    """An instance of Matlab, running in its own process.

    if `address` is supplied, Matlab is started on a remote machine.
    This is done by opening an SSH connection to that machine
    (optionally using user account `user`), and then starting Matlab
    on that machine. For this to work, `address` must be reachable
    using SSH, `matlab` must be in the `user`'s PATH, and
    `transplant_remote` must be in Matlab's `path` and `messenger`
    must be available on both the local and the remote machine.

    """

    ProxyObject = MatlabProxyObject

    def __init__(self, executable='matlab', arguments=('-nodesktop', '-nosplash'), msgformat='msgpack', address=None, user=None):
        """Starts a Matlab instance and opens a communication channel."""
        if msgformat not in ['msgpack', 'json']:
            raise ValueError('msgformat must be "msgpack" or "json"')
        if address is None:
            if os.name != 'nt':
                # generate a valid and unique local pathname
                with tempfile.NamedTemporaryFile() as f:
                    zmq_address = 'ipc://' + f.name
            else:
                # ZMQ does not support ipc:// on Windows, so use tcp:// instead
                from random import randint
                port = randint(49152, 65535)
                zmq_address = 'tcp://127.0.0.1:' + str(port)
            process_arguments = ([executable] + list(arguments) +
                                 ['-r', 'transplant_remote {} {}'.format(msgformat, zmq_address)])
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
                                 ['-r', '"transplant_remote {} {}"'.format(msgformat, zmq_address)])
        self.msgformat = msgformat
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

    def _call(self, name, args, nargout=-1):
        """Call a function on the remote."""
        args = list(args)
        try:
            response = self.send_message('call', name=name, args=args,
                                         nargout=nargout)
        except KeyboardInterrupt as exc:
            # hand the interrupt down to Matlab:
            self.process.send_signal(SIGINT)
            # receive outstanding message to get ZMQ back in the right state
            if self.msgformat == 'msgpack':
                response = msgpack.unpackb(self.socket.recv(), encoding='utf-8')
            else:
                response = self.socket.recv_json()
            # continue with the exception
            raise exc

        if response['type'] == 'value':
            return response['value']

    def _decode_function(self, data):
        """Decode a special list to a wrapper function."""

        class matlab_method:
            def __call__(_self, *args, nargout=-1):
                return self._call(data[1], args, nargout=nargout)

            # only fetch documentation when it is actually needed:
            @property
            def __doc__(_self):
                return self._call('help', [data[1]], nargout=1)
        return matlab_method()
