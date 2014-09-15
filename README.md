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

By default, Matlab is called with `-nodesktop` and `-nosplash`, so no IDE or splash screen show up. If you want to use different arguments, you can supply them like this: `transplant.Matlab(arguments=('-nodesktop', '-nosplash', '-c licensefile' , '-nojvm'))`. Note that `'-nojvm'` will speed up startup considerably, but you won't be able to plot any more.

CALLING MATLAB FUNCTIONS
------------------------

```python
matlab.disp("Hello, World")
```

Will call Matlab's `disp` function with the argument `'Hello, World'`. It is equivalent to `disp('Hello, World')` in Matlab. Return values will be returned to Python, and errors will be converted to Python errors (Matlab stack traces will be given, too!).

Input arguments are converted to Matlab data structures:

- Strings and numbers stay strings and numbers
- `True` and `False` become `logical(1)` and `logical(0)`
- `None` becomes `[]`
- Lists become cell arrays
- Dictionaries become structs
- Numpy arrays become matrices

In Matlab, some functions behave differently depending on the number of output arguments. By default, Transplant uses `nargout` in Matlab to figure out the number of return values for a function. If `nargout` does not know the number of output arguments either, Matlab functions will return the value of `ans` after the function call.

In some cases, `nargout` will report a wrong number of output arguments. For example `nargout profile` will say `1`, but `x = profile('on')` will raise an error that too few output arguments were used. To fix this, every function has a keyword argument `nargout`, which can be used in these cases: `matlab.profile('on', nargout=0)` calls `profile on` with no output arguments. `s, f, t, p = matlab.spectrogram(numpy.random.randn(1000), nargout=4)` returns all four output arguments of `spectrogram`.

Note that functions are not called in the base workspace. Functions that access the current non-lexical workspace will therefore not work as expected. For example, `matlab.truth = 42', `matlab.exist('truth')` will not find the `truth` variable. Use `matlab.eval('exist truth')` instead in this case.

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

* `eval` evaluates a string and returns the result.
* `put` and `get` set and retrieve a global variable.
* `call` calls a Matlab function with some function arguments and returns the result.
* `die` tells Matlab to shut down.

Matlab can then respond with one of three message types:

* `ack` for successful execution.
* `value` for return values.
* `error` if there was an error during execution.

In addition to the regular JSON data types, _transplant_ uses a specially formatted JSON array for transmitting numerical matrices as binary data. A numerical 2x2 32-bit integer matrix containing `[[1, 2], [3, 4]]` would be encoded as `["__matrix__", "int32", [2, 2], "AQAAAAIAAAADAAAABAAAA==\n"]`, where `"int32"` is the data type, `[2, 2]` is the matrix shape and the long string is the base64-encoded matrix content. This allows for efficient data exchange and prevents rounding errors due to JSON serialization.

Note that this project includes a JSON serializer/parser and a Base64 encoder/decoder in pure Matlab.

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

MATLAB (R) is copyright of the Mathworks

Copyright (c) 2014 Bastian Bechtold
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the
   distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived
   from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
