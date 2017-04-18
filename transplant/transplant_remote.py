import sys
import types
import traceback
from collections import deque
import zmq
import numpy as np
import base64

class TransplantClient:

    def __init__(self, url):
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.REP)
        self.socket.connect(url)
        self.object_cache = []
        self.empty_cache_indexes = deque()

    def message_loop(self):
        """Main messaging loop."""
        while True:
            msg = self.decode_values(self.socket.recv_json())
            print('received', msg)
            try:
                if msg['type'] == 'die': # exit python
                    self.send_ack()
                    sys.exit(0)
                elif msg['type'] == 'set': # save msg['value'] as a global variable
                    globals()[msg['name']] = msg['value']
                    self.send_ack()
                elif msg['type'] == 'get': # retrieve the value of a global variable
                    if msg['name'] in dir(__builtins__):
                        value = getattr(__builtins__, msg['name'])
                    elif msg['name'] in globals():
                        value = globals()[msg['name']]
                    else:
                        # value does not exist:
                        raise NameError('Undefined variable "{name}".'.format(**msg))
                    self.send_value(value)
                elif msg['type'] == 'set_proxy': # set field value of a cached object
                    obj = self.object_cache[msg['handle']]
                    setattr(obj, msg['name'], msg['value'])
                    self.send_ack()
                elif msg['type'] == 'get_proxy': # retrieve field value of a cached object
                    obj = self.object_cache[msg['handle']]
                    value = getattr(obj, msg['name'])
                    self.send_value(value);
                elif msg['type'] == 'del_proxy': # invalidate cached object
                    self.object_cache[msg['handle']] = None
                    self.empty_cache_indexes.append(msg['handle'])
                    self.send_ack()
                elif msg['type'] == 'call': # call a function
                    if callable(msg['name']):
                        func = msg['name']
                    elif isinstance(msg['name'], int):
                        func = self.object_cache[msg['name']]
                    elif msg['name'] in globals():
                        func = globals()[msg['name']]
                    elif msg['name'] in dir(__builtins__):
                        func = getattr(__builtins__, msg['name'])
                    else:
                        raise RuntimeError('Undefined function "{name}".'.format(**msg))
                    results = func(*msg['args'], **msg['kwargs'])
                    if results is not None:
                        self.send_value(results)
                    else:
                        self.send_ack()
            except Exception as err:
                self.send_error(err)

    def send_message(self, message_type, message={}):
        """Send a message

        This is the base function for the specialized senders below.

        """
        print('responding', message_type, message)
        self.socket.send_json(dict(message, type=message_type));

    def send_ack(self):
        """Send an acknowledgement message."""
        self.send_message('ack')

    def send_error(self, err):
        """Send an error message.

        along with the error message, send the full stack trace."""
        identifier, message, stack = sys.exc_info()
        self.send_message('error', {"message":str(message),
                                    "stack":[{"file":frame[0],
                                              "line":frame[1],
                                              "name":frame[2]} for frame in
                                             traceback.extract_tb(stack)],
                                    "identifier":identifier.__name__});


    def send_value(self, value):
        """Send a message that contains a value."""
        self.send_message('value', {'value': self.encode_values(value)});


    def receive_msg(self):
        """Wait for and receive a message."""
        return self.decode_values(zmq.recv())

    def encode_values(self, data):
        """Recursively walk through data and encode special entries."""
        if isinstance(data, (str, bytes, float, int, bool)) or data is None:
            return data
        elif isinstance(data, np.ndarray):
            return self.encode_matrix(data)
        elif isinstance(data, (types.FunctionType, types.BuiltinFunctionType)):
            return self.encode_function(data)
        elif isinstance(data, dict):
            out = {}
            for key in data:
                out[key] = self.encode_values(data[key])
            return out
        elif isinstance(data, list) or isinstance(data, tuple):
            out = list(data)
            for idx in range(len(data)):
                out[idx] = self.encode_values(data[idx])
            return out
        else:
            return self.encode_proxy(data)

    def decode_values(self, data):
        """Recursively walk through data and decode special entries."""
        if (isinstance(data, list) and
            len(data) == 4 and
            data[0] == "__matrix__"):
            return self.decode_matrix(data)
        elif (isinstance(data, list) and
              len(data) == 2 and
              data[0] == "__object__"):
            return self.decode_proxy(data)
        elif (isinstance(data, list) and
              len(data) == 2 and
              data[0] == "__function__"):
            return self.decode_function(data)
        elif isinstance(data, dict):
            out = {}
            for key in data:
                out[key] = self.decode_values(data[key])
        elif isinstance(data, list) or isinstance(data, tuple):
            out = list(data)
            for idx in range(len(data)):
                out[idx] = self.decode_values(data[idx])
        else:
            out = data
        return out

    def encode_proxy(self, data):
        """Encode a ProxyObject as a special list.

        A proxy with handle `42` would be be encoded as
        `["__object__", 42]`

        """
        if len(self.empty_cache_indexes) > 0:
            idx = self.empty_cache_indexes.popleft()
            self.object_cache[idx] = data
        else:
            idx = len(self.object_cache)
            self.object_cache.append(data)
        return ["__object__", idx]

    def decode_proxy(self, data):
        """Decode a special list to a ProxyObject.

        A proxy with handle `42` would be be encoded as
        `["__object__", 42]`

        """
        return self.object_cache[data[1]]

    def encode_function(self, func):
        if len(self.empty_cache_indexes) > 0:
            idx = self.empty_cache_indexes.popleft()
            self.object_cache[idx] = func
        else:
            idx = len(self.object_cache)
            self.object_cache.append(func)
        return ["__function__", idx]

    def decode_function(self, data):
        """Decode a special list to a wrapper function."""

        return self.object_cache[data[1]]

    def encode_matrix(self, data):
        """Encode a Numpy array as a special list.

        The matrix `np.array([[1, 2], [3, 4]], dtype='int32')` would be
        encoded as `["__matrix__", "int32", [2, 2],
        "AQAAAAIAAAADAAAABAAAA==\n"]`

        where `"int32"` is the data type, `[2, 2]` is the matrix shape and
        `"AQAAAAIAAAADAAAABAAAA==\n"` is the base64-encoded matrix
        content.

        """

        return ["__matrix__", data.dtype.name, data.shape,
                base64.encodebytes(data.tostring()).decode()]

    def decode_matrix(self, data):
        """Decode a special list to a Numpy array.

        The matrix `np.array([[1, 2], [3, 4]], dtype='int32')` would be
        encoded as `["__matrix__", "int32", [2, 2],
        "AQAAAAIAAAADAAAABAAAA==\n"]`

        where `"int32"` is the data type, `[2, 2]` is the matrix shape and
        `"AQAAAAIAAAADAAAABAAAA==\n"` is the base64-encoded matrix
        content.

        """

        dtype, shape, data = data[1:]
        out = np.fromstring(base64.decodebytes(data.encode()), dtype)
        return out.reshape(*shape)

if __name__ == "__main__":
    _client = TransplantClient(sys.argv[1])
    _client.message_loop()
