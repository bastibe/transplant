from subprocess import Popen, DEVNULL, PIPE
from signal import SIGINT
import sys
import re
import os
import tempfile
from glob import glob
import zmq
import numpy as np
import base64
from threading import Thread
import msgpack
import ctypes.util

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

    def _del_proxy(self, handle):
        """Tell the remote to forget about this proxy object."""
        # ignore if remote already shut down:
        if self.socket.closed:
            return
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
        self.exit()

    def exit(self):
        """Close the connection, and kill the process."""
        if self.process.returncode is not None:
            return
        self.send_message('die')
        self.process.wait()

    def __del__(self):
        """Close the connection, and kill the process."""
        self.exit()

    def send_message(self, msg_type, **kwargs):
        """Send a message and return the response"""
        kwargs = self._encode_values(kwargs)

        self._wait_socket(zmq.POLLOUT)
        if self.msgformat == 'msgpack':
            self.socket.send(msgpack.packb(dict(kwargs, type=msg_type), use_bin_type=True), flags=zmq.NOBLOCK)
        else:
            self.socket.send_json(dict(kwargs, type=msg_type), flags=zmq.NOBLOCK)

        self._wait_socket(zmq.POLLIN)
        if self.msgformat == 'msgpack':
            response = msgpack.unpackb(self.socket.recv(flags=zmq.NOBLOCK), raw=False, max_bin_len=2**31-1)
        else:
            response = self.socket.recv_json(flags=zmq.NOBLOCK)

        response = self._decode_values(response)
        if response['type'] == 'error':
            # Create a pretty backtrace almost like Python's:
            trace = 'Traceback (most recent call last):\n'
            if isinstance(response['stack'], dict):
                response['stack'] = [response['stack']]
            for frame in reversed(response['stack']):
                trace += '  File "{file}", line {line:.0f}, in {name}\n'.format(**frame)
                if frame['file'] is not None and os.path.exists(frame['file']) and frame['file'].endswith('.m'):
                    trace += '    ' + open(frame['file'], 'r', errors='replace').readlines()[int(frame['line'])-1].strip(' ')
            raise TransplantError('{message} ({identifier})\n'.format(**response) + trace,
                              response['stack'], response['identifier'], response['message'])
        return response

    def _wait_socket(self, flags, timeout=1000):
        """Wait for socket or crashed process."""
        while True:
            if self.process.poll() is not None:
                raise RuntimeError('Process died unexpectedly')
            if self.socket.poll(timeout, flags) != 0:
                return

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
        elif isinstance(data, MatlabStruct):
            out = ["__struct__", {}]
            for key in data:
                out[1][key] = self._encode_values(data[key])
        elif isinstance(data, MatlabFunction):
            out = ["__function__", data._fun]
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
            out = np.frombuffer(data, dtype)
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
        shape = (int(d) for d in data[1]) # convert shape to int
        return scipy.sparse.coo_matrix((value, (row, col)), shape=shape)

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
    """A Proxy for an object that exists in Matlab.

    All property accesses and function calls are executed on the
    Matlab object in Matlab.

    """

    def __init__(self, process, handle):
        """foo"""
        self.__dict__['handle'] = handle
        self.__dict__['process'] = process

    def _getAttributeNames(self):
        return self.process.fieldnames(self)

    def __getattr__(self, name):
        """Retrieve a value or function from the object.

        Properties are returned as native Python objects or
        :class:`MatlabProxyObject` objects.

        Functions are returned as :class:`MatlabFunction` objects.

        """
        m = self.process
        # if it's a property, just retrieve it
        if name in m.properties(self, nargout=1):
            return m.subsref(self, MatlabStruct(m.substruct('.', name)))
        # if it's a method, wrap it in a functor
        if name in m.methods(self, nargout=1):
            class matlab_method:
                def __call__(_self, *args, nargout=-1, **kwargs):
                    # serialize keyword arguments:
                    args += sum(kwargs.items(), ())
                    return getattr(m, name)(self, *args, nargout=nargout)

                # only fetch documentation when it is actually needed:
                @property
                def __doc__(_self):
                    classname = getattr(m, 'class')(self)
                    return m.help('{0}.{1}'.format(classname, name), nargout=1)
            return matlab_method()

    def __setattr__(self, name, value):
        access = MatlabStruct(self.process.substruct('.', name))
        self.process.subsasgn(self, access, value)

    def __repr__(self):
        getclass = self.process.str2func('class')
        return "<proxy for Matlab {} object>".format(getclass(self))

    def __str__(self):
        # remove pseudo-html tags from Matlab output
        html_str = self.process.eval("@(x) evalc('disp(x)')")(self)
        return re.sub('</?a[^>]*>', '', html_str)

    def __del__(self):
        self.process._del_proxy(self.handle)

    @property
    def __doc__(self):
        return self.process.help(self, nargout=1)


class MatlabStruct(dict):
    "Mark a dict to be decoded as struct instead of containers.Map"
    pass


class MatlabFunction:
    """A Proxy for a Matlab function."""
    def __init__(self, parent, fun):
        self._parent = parent
        self._fun = fun

    def __call__(self, *args, nargout=-1, **kwargs):
        """Call the Matlab function.

        Calling this function will transfer all function arguments
        from Python to Matlab, and translate them to the appropriate
        Matlab data structures.

        Return values are translated the same way, and transferred
        back to Python.

        Parameters
        ----------
        nargout : int
            Call the function in Matlab with this many output
            arguments. If not given, will execute ``nargout(func)`` in
            Matlab to figure out the correct number of output
            arguments. If this fails, execute ``ans = func(...)``, and
            return the value of ``ans``.
        **kwargs : dict
            Keyword arguments are transparently translated to Matlab's
            key-value pairs. For example, ``matlab.struct(foo="bar")``
            will be translated to ``struct('foo', 'bar')``.

        """
        # serialize keyword arguments:
        args += sum(kwargs.items(), ())
        return self._parent._call(self._fun, args, nargout=nargout)


class Matlab(TransplantMaster):
    """An instance of Matlab, running in its own process.

    if ``address`` is supplied, Matlab is started on a remote machine.
    This is done by opening an SSH connection to that machine
    (optionally using user account ``user``), and then starting Matlab
    on that machine. For this to work, `address` must be reachable
    using SSH, ``matlab`` must be in the ``user``'s PATH, and
    ``transplant_remote`` must be in Matlab's ``path`` and `libzmq`
    must be available on the remote machine.

    All Matlab errors are caught in Matlab, and re-raised as
    :class:`TransplantError` in Python. Some Matlab errors can not be
    caught with try-catch. In this case, Transplant will not be able
    to get a backtrace, but will continue running (as part of
    ``atexit`` in Matlab). If this happens often, performance might
    degrade.

    In case Matlab segfaults or otherwise terminates abnormally,
    Transplant will raise a :class:`TransplantError`, and you will
    need to create a new :class:`Matlab` instance.

    ``SIGINT``/``KeyboardInterrupt`` will be forwarded to Matlab. Be
    aware however, that some Matlab functions silently ignore
    ``SIGINT``, and will continue running regardless.

    Parameters
    ----------
    executable : str
        The executable name, defaults to ``matlab``.
    arguments : tuple
        Additional arguments to supply to the executable, defaults to
        ``-nodesktop``, ``-nosplash``, and on Windows, ``-minimize``.
    msgformat : str
        The communication format to use for talking to Matlab,
        defaults to ``"msgpack"``. For debugging, you can use
        ``"json"`` instead.
    address : str
        An address of a remote SSH-reachable machine on which to call
        Matlab.
    user : str
        The user name to use for the SSH connection (if ``address`` is
        given).
    print_to_stdout : bool
        Whether to print outputs to stdout, defaults to ``True``.
    desktop : bool
        Whether to start Matlab with ``-nodesktop``, defaults to ``True``.
    jvm : bool
        Whether to start Matlab with ``-nojvm``, defaults to ``False``.

    """

    ProxyObject = MatlabProxyObject

    def __init__(self, executable='matlab', arguments=tuple(), msgformat='msgpack', address=None, user=None, print_to_stdout=True, desktop=False, jvm=True):
        """Starts a Matlab instance and opens a communication channel."""
        if msgformat not in ['msgpack', 'json']:
            raise ValueError('msgformat must be "msgpack" or "json"')

        # build up command line arguments:
        if not desktop:
            if '-nodesktop' not in arguments:
                arguments += '-nodesktop',
            if '-nosplash' not in arguments:
                arguments += '-nosplash',
            if '-minimize' not in arguments and sys.platform in ('cygwin', 'win32'):
                arguments += '-minimize',
        if not jvm and '-nojvm' not in arguments:
            arguments += '-nojvm',

        if address is None:
            if sys.platform == 'linux' or sys.platform == 'darwin':
                # generate a valid and unique local pathname
                with tempfile.NamedTemporaryFile() as f:
                    zmq_address = 'ipc://' + f.name
            else: # cygwin/win32
                # ZMQ does not support ipc:// on Windows, so use tcp:// instead
                from random import randint
                port = randint(49152, 65535)
                zmq_address = 'tcp://127.0.0.1:' + str(port)

            process_arguments = ([executable] + list(arguments) +
                                 ['-r', "addpath('{}');cd('{}');"
                                  "transplant_remote('{}','{}','{}');".format(
                                      os.path.dirname(__file__), os.getcwd(),
                                      msgformat, zmq_address, self._locate_libzmq()
)])
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
                                 ['-r', '"transplant_remote {} {} {}"'
                                      .format(msgformat, zmq_address, "zmq")])
        if sys.platform == 'win32' or sys.platform == 'cygwin':
            process_arguments += ['-wait']
        self.msgformat = msgformat
        # Create a new ZMQ context instead of sharing the global ZMQ context.
        # We now have ownership of it, and can terminate it with impunity.
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.REQ)
        self.socket.bind(zmq_address)
        # start Matlab, but make sure that it won't eat the REPL stdin
        # (stdin=DEVNULL).
        self.process = Popen(process_arguments, stdin=DEVNULL, stdout=PIPE)
        if print_to_stdout:
            self._start_reader()
        self.eval('0;') # no-op. Wait for Matlab startup to complete.

    def exit(self):
        """Close the connection, and kill the process."""
        super(self.__class__, self).exit()
        self.socket.close()
        self.context.term()

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
                response = msgpack.unpackb(self.socket.recv(), raw=False, max_bin_len=2**31-1)
            else:
                response = self.socket.recv_json()
            # continue with the exception
            raise exc

        if response['type'] == 'value':
            return response['value']

    def _decode_function(self, data):
        """Decode a special list to a wrapper function."""

        # Wrap functions in a MatlabFunction class with a __doc__
        # property.
        # However, there are two ways of accessing documentation:
        # - help(func) will access __doc__ on type(func), so __doc__
        #   must be accessible on the class of the returned value.
        # - func.__doc__ must also be accessible on the object itself.
        #
        # The following constructs a new class with the appropriate
        # __doc__ property that is accessible both on the class and
        # the object.

        class classproperty(property):
            def __get__(self, cls, owner):
                return classmethod(self.fget).__get__(None, owner)()

        class ThisFunc(MatlabFunction):
            # only fetch documentation when it is actually needed:
            @classproperty
            def __doc__(_self):
                return self.help(data[1], nargout=1)

        return ThisFunc(self, data[1])


    def __getattr__(self, name):
        """Retrieve a value or function from the remote.

        Global variables are returned as native Python objects or
        :class:`MatlabProxyObject` objects.

        Functions are returned as :class:`MatlabFunction` objects.

        """

        try:
            return self._get_global(name)
        except TransplantError as err:
            # package identifiers for `what` use '/' instead of '.':
            packagedict = self.what(name.replace('.', '/'))
            if not (err.identifier == 'TRANSPLANT:novariable' and packagedict):
                raise err
            else: # a package of the given name exists. Return a wrapper:
                class MatlabPackage:
                    def __getattr__(self_, attrname):
                        return self.__getattr__(name + '.' + attrname)
                    def __repr__(self_):
                        return "<MatlabPackage {}>".format(name)
                    @property
                    def __doc__(_self):
                        return self.help(name, nargout=1)
                return MatlabPackage()

    def _locate_libzmq(self):
        """Find the full path to libzmq.

        CFFI can import a library by its name, but Matlab's `loadlibrary`
        requires the full library path. This walks the file system, and
        looks for the libzmq binary. If it can't find libzmq in the normal
        library locations, it additionally tries common install
        directories such as a conda installation or the ZMQ Windows
        installer.

        """

        if sys.platform == 'linux' or sys.platform == 'darwin':
            libzmq = ctypes.util.find_library('zmq')
        else: # cygwin/win32
            libzmq = ctypes.util.find_library('libzmq.dll')

        # depending on the OS, either of these outcomes is possible:
        if libzmq is not None and os.path.isabs(libzmq):
            return libzmq

        # manually try to locate libzmq
        if sys.platform == 'linux':
            # according to man dlopen:
            search_dirs = ((os.getenv('LD_LIBRARY_PATH') or '').split(':') +
                           self._read_ldsoconf('/etc/ld.so.conf') +
                           self._ask_ld_for_paths() +
                           ['/lib/', '/lib64/',
                            '/usr/lib/', '/usr/lib64/'])
            extension = '.so'
        elif sys.platform == 'darwin':
            # according to man dlopen:
            search_dirs = ((os.getenv('LD_LIBRARY_PATH') or '').split(':') +
                           (os.getenv('DYLD_LIBRARY_PATH') or '').split(':') +
                           (os.getenv('DYLD_FALLBACK_PATH') or '').split(':') +
                           [os.getenv('HOME') + '/lib',
                            '/usr/local/lib',
                            '/usr/lib'])
            extension = '.dylib'
        elif sys.platform == 'win32' or sys.platform == 'cygwin':
            # according to https://msdn.microsoft.com/en-us/library/windows/desktop/ms682586(v=vs.85).aspx
            search_dirs = ((os.getenv('PATH') or '').split(':') +
                           ['C:/Program Files/ZeroMQ*/bin'])
            extension = '.dll'

        if libzmq is None:
            libzmq = '*zmq*' + extension

        # add anaconda libzmq install locations:
        search_dirs.append(sys.prefix + '/lib')
        search_dirs.append(os.path.dirname(zmq.__file__))

        for directory in search_dirs:
            candidates = glob(directory + '/' + libzmq)
            if candidates:
                return candidates[0]

        raise RuntimeError('could not locate libzmq for Matlab')

    def _ask_ld_for_paths(self):
        """Asks `ld` for the paths it searches for libraries."""

        try:
            ld = Popen(['ld', '--verbose'], stdin=DEVNULL, stdout=PIPE)
            output = ld.stdout.read().decode()
        except:
            return []

        search_dirs = re.compile(r'SEARCH_DIR\(([^)]*)\)').findall(output)
        return [d.strip(' "') for d in search_dirs]

    def _read_ldsoconf(self, file):
        """Read paths from a library list referenced from /etc/ld.so.conf."""

        search_dirs = []
        with open(file) as f:
            for line in f:
                if '#' in line:
                    line = line.split('#')[0]
                if line.startswith('include'):
                    for search_dir in glob(line[len('include'):].strip()):
                        search_dirs += self._read_ldsoconf(search_dir)
                elif os.path.isabs(line):
                    search_dirs.append(line.strip())

        return search_dirs
