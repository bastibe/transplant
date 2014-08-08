TRANSPLANT
==========

Transplant is an easy way of calling Matlab from Python.

```python
import transplant
m = transplant.Matlab()
m.put("name", "Matlab")
m.eval("disp(['Hello, ' name '!'])")
```

HOW DOES IT WORK?
-----------------

Transplant opens Matlab as a subprocess, then connects both ends via 0MQ in a request-response pattern. Matlab then runs the _transplant_ server and starts listening for messages. Now, Python can send messages to Matlab, and Matlab will respond.

All messages are JSON-encoded objects, with a `type` and `type`-dependant other keys. This way, Python can ask for different things, and Matlab can answer with different items. For example, Python might ask for a function to be executed, and Matlab might answer with either a return value, or an error.

TODO
----

- Implement `call_function` message.
- Implement `import` message.

- Implement _transplant_ servers in Julia and PyPy.
- Implement _transplant_ clients in Python, Julia, PyPy and Matlab.

INSTALLATION
------------

1. Compile the mex-file _messenger.c_ and link against _libzmq_. You will need to have [0MQ](http://zeromq.org) installed for this. The mex-call could look something like this: `mex -lzmq messenger.c`. On OS X, you typically have to convince the compiler that _mex.h_ is actually C code, and that system libraries are actually where they should be: `mex -lzmq messenger.c -I/usr/local/include -Dchar16_t=UINT16_T`.

2. Install [JSONlab](http://iso2mesh.sourceforge.net/cgi-bin/index.cgi?jsonlab), an implementation of JSON for Matlab. Install this into the subdirectory _jsonlab_ inside this directory.

3. Make sure that `matlab` is reachable in your shell. Transplant will try to start Matlab as a sub-process.

4. On the Python side, make sure to have PyZMQ installed as well. 

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
