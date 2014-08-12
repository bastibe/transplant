TRANSPLANT
==========

Transplant is an easy way of calling Matlab from Python.

```python
import transplant
matlab = transplant.Matlab()
matlab.put("name", "Matlab")
matlab.eval("disp(['Hello, ' name '!'])")
n, m = matlab.size([1, 2, 3])
magic = matlab.magic(2)
print(matlab.help('magic')[0])
```

Note that Python lists are converted to cell arrays in Matlab. Matlab matrices are converted to Numpy arrays and vice versa.

HOW DOES IT WORK?
-----------------

Transplant opens Matlab as a subprocess, then connects to it via [0MQ](http://zeromq.org/) in a request-response pattern. Matlab then runs the _transplant_ server and starts listening for messages. Now, Python can send messages to Matlab, and Matlab will respond. Roundtrip time for sending/receiving and encoding/decoding values from Python to Matlab and back is about 10 ms.

All messages are JSON-encoded objects. There are five messages types used by Python: 

* `eval` evaluates a string.
* `put` and `get` set and retrieve a global variable.
* `call` calls a Matlab function with some function arguments.
* `die` tells Matlab to shut down.

Matlab can then respond with one of three message types:

* `ack` for successful execution.
* `value` for a return value.
* `error` if there was an error during execution.

In addition to the regular JSON data types, _transplant_ uses a specially formatted JSON array for transmitting numerical matrices as binary data. A numerical 2x2 32-bit integer matrix containing `[[1, 2], [3, 4]]` would be encoded as `["__matrix__", "int32", [2, 2], "AQAAAAIAAAADAAAABAAAA==\n"]`, where `"int32"` is the data type, `[2, 2]` is the matrix shape and the long string is the base64-encoded matrix content. This allows for efficient data exchange and prevents rounding errors due to JSON serialization.

The maximum size of matrices that can be transmitted is limited by the Java heap space. Increase your heap space if you need to transmit matrices larger than about 64 Mb.

TODO
----

- Implement _transplant_ servers in Julia and PyPy.
- Implement _transplant_ clients in Python, Julia, PyPy and Matlab.

INSTALLATION
------------

1. Compile the mex-file _messenger.c_ and link against _libzmq_. You will need to have [0MQ](http://zeromq.org) installed for this. The mex-call could look something like this: `mex -lzmq messenger.c`. On OS X, you typically have to convince the compiler that _mex.h_ is actually C code, and that system libraries are actually where they should be: `mex -lzmq messenger.c -I/usr/local/include -Dchar16_t=UINT16_T`.

2. On the Python side, make sure to have PyZMQ installed as well.

3. If `matlab` is not reachable in your shell, give the full path to your Matlab executable to the `Matlab` constructor.

LICENSE
-------

Copyright (c) 2014 Bastian Bechtold

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
