TRANSPLANT
==========

Transplant is an easy way of calling Matlab from Python.

```python
 import transplant
 matlab = transplant.Matlab()
 # call Matlab functions:
 n, m = matlab.size([1, 2, 3])
 magic = matlab.magic(2)
 spectrum = matlab.fft(numpy.random.randn(100))
 print(matlab.help('magic')[0])
 # inject variables into Matlab:
 matlab.name = "Matlab"
 # eval statements in Matlab:
 matlab.eval("disp(['Hello, ' name '!'])")
```

Python lists are converted to cell arrays in Matlab. Use Numpy matrices for Matlab matrices.

STARTING MATLAB
----------------

```python
matlab = transplant.Matlab()
```

Will start a Matlab session and connect to it. This will take a few seconds while Matlab starts up. All of Matlab's output will go to the standard output and will appear interspersed with Python output. Standard input is suppressed to make REPLs work, so Matlab's `input` function will not work.

By default, this will try to call `matlab` on the command line. If you want to use a different version of Matlab, or `matlab` is not available on the command line, use `transplant.Matlab(executable='/path/to/matlab')`.

By default, Matlab is called with `-nodesktop` and `-nosplash`, so no IDE or splash screen show up. If you want to use different arguments, you can supply them like this: `transplant.Matlab(arguments=('-nodesktop', '-nosplash', '-c licensefile'))`.

CALLING MATLAB FUNCTIONS
------------------------

```python
matlab.disp("Hello, World")
```

Will call Matlab's `disp` function with the argument `'Hello, World'`. It is equivalent to `disp('Hello, World')` in Matlab. Return values will be returned to Python, and errors will be converted to Python errors (a stack trace will be given, too!).

Input arguments are converted to Matlab data structures:

- Strings and numbers stay strings and numbers
- `True` and `False` become `logical(1)` and `logical(0)`
- `None` becomes `[]`
- Lists become cell arrays
- Dictionaries become structs
- Numpy arrays become matrices

In Matlab, some functions behave differently depending on the number of output arguments. By default, Transplant uses `nargout` in Matlab to figure out the number of return values for a function. If `nargout` does not know the number of output arguments either, Matlab functions will return the value of `ans` after the function call.

In some cases, `nargout` will report a wrong number of output arguments. For example `nargout profile` will say `1`, but `x = profile('on')` will raise an error that too few output arguments were used. To fix this, every function has a keyword argument `nargout`, which can be used in these cases: `matlab.profile('on', nargout=0)` calls `profile on` with no output arguments. `s, f, t, p = matlab.spectrogram(numpy.random.randn(1000), nargout=4)` returns all four output arguments of `spectrogram`.

OTHER FUNCTIONS
---------------

```python
matlab.name = value
```

Will save `value` as a global variable called `'name'` in Matlab. It is equivalent to `name = value` in Matlab.

```python
value = matlab.name
```

Will retrieve a global variable called `'name'` from Matlab. It is equivalent to `value = name` in Matlab.

```python
return_value = matlab.eval('profile on')
```

Will eval an arbitrary string in the global workspace in Matlab and return its result. Just like any other function, this accepts a keyword argument `nargout` to specify the number of output arguments.


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

2. On the Python side, make sure to have PyZMQ and Numpy installed as well.

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
