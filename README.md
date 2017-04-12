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
 # inject variables into Matlab:
 matlab.signal = numpy.zeros(100)
```

Python lists are converted to cell arrays in Matlab, dicts are
converted to stucts, and numpy matrices are converted do native Matlab
matrices.

All Matlab functions and objects can be accessed from Python.

RECENT CHANGES
--------------

- `close` was renamed `exit`. Even though Python typically uses
  `close` to close files and connections, this conflicts with Matlab's
  own `close` function. 

STARTING MATLAB
----------------

```python
matlab = transplant.Matlab()
```

Will start a Matlab session and connect to it. This will take a few
seconds while Matlab starts up. All of Matlab's output will go to the
standard output and will appear interspersed with Python output.
Standard input is suppressed to make REPLs work, so Matlab's `input`
function will not work.

By default, this will try to call `matlab` on the command line. If you
want to use a different version of Matlab, or `matlab` is not
available on the command line, use
`Matlab(executable='/path/to/matlab')`.

By default, Matlab is called with `-nodesktop` and `-nosplash`, so no
IDE or splash screen show up. If you want to use different arguments,
you can supply them like this: `Matlab(arguments=('-nodesktop',
'-nosplash', '-c licensefile' , '-nojvm'))`. Note that `'-nojvm'` will
speed up startup considerably, but you won't be able to open figures
any more.

By default, Matlab will be started on the local machine. To start
Matlab on a different computer, supply the IP address of that
computer: `Matlab(address='172.168.1.5')`. This only works if that
computer is reachable through `ssh`, Matlab is available on the other
computer's command line, and transplant is in the other Matlab's path.

Note that due to a limitation of Matlab on Windows, command line
output from Matlabs running on Windows aren't visible to Transplant.

CALLING MATLAB 
--------------

```python
matlab.disp("Hello, World")
```

Will call Matlab's `disp` function with the argument `'Hello, World'`.
It is equivalent to `disp('Hello, World')` in Matlab. Return values
will be returned to Python, and errors will be converted to Python
errors (Matlab stack traces will be given, too!).

Input arguments are converted to Matlab data structures:

- Strings and numbers stay strings and numbers
- `True` and `False` become `logical(1)` and `logical(0)`
- `None` becomes `[]`
- Lists become cell arrays
- Dictionaries become `containers.Map`
- Numpy arrays become matrices

If the function returns a function handle or an object, a matching
Python functions/objects will be created that forwards every access to
Matlab. These objects and functions can also be handed back to Matlab
and will work as intended.

```python
f = matlab.figure() # create a Figure object
f.Visible = 'off' # modify a property of the Figure object
matlab.set(f, 'Visible', 'on') # pass the Figure object to a function
```

In Matlab, some functions behave differently depending on the number
of output arguments. By default, Transplant uses the Matlab function
`nargout` to figure out the number of return values for a function. If
`nargout` can not determine the number of output arguments either,
Matlab functions will return the value of `ans` after the function
call.

In some cases, `nargout` will report a wrong number of output
arguments. For example `nargout profile` will say `1`, but `x =
profile('on')` will raise an error that too few output arguments were
used. To fix this, every function has a keyword argument `nargout`,
which can be used in these cases: `matlab.profile('on', nargout=0)`
calls `profile on` with no output arguments. `s, f, t, p =
matlab.spectrogram(numpy.random.randn(1000), nargout=4)` returns all
four output arguments of `spectrogram`.

When working with plots, note that the Matlab program does not wait
for drawing on its own. Use `matlab.drawnow()` to make figures appear.

Note that functions are not called in the base workspace. Functions
that access the current non-lexical workspace (this is very rare) will
therefore not work as expected. For example, `matlab.truth = 42`,
`matlab.exist('truth')` will not find the `truth` variable. Use
`matlab.evalin('base', "exist('truth')", nargout=1)` instead in this
case.

If you hit Ctrl-C, the `KeyboardInterrupt` will be applied to both
Python and Matlab, stopping any currently running function. Due to a
limitation of Matlab, the error and stack trace of that function will
be lost.

MATRIX DIMENSIONS
-----------------

The way multidimensional arrays are indexed in Matlab and Python are
fundamentally different. Thankfully, the two-dimensional case works as
expected:

               Python         |        Matlab
    --------------------------+------------------------
     array([[  1,   2,   3],  |     1   2   3
            [ 10,  20,  30]]) |    10  20  30

In both languages, this array has the shape `(2, 3)`.

With higher-dimension arrays, this becomes harder. The next array is
again identical:

               Python         |        Matlab
    --------------------------+------------------------
     array([[[  1,   2],      | (:,:,1) =
             [  3,   4]],     |              1    3
                              |             10   30
            [[ 10,  20],      |            100  300
             [ 30,  40]],     | (:,:,2) =
                              |              2    4
            [[100, 200],      |             20   40
             [300, 400]]])    |            200  400

Even though they look radically different, they both have the same
shape `(3, 2, 2)`, and are indexed in the same way. The element at
position `a, b, c` in Python is the same as the element at position
`a+1, b+1, c+1` in Matlab (`+1` due to zero-based/one-based indexing).

You can think about the difference in presentation like this: Python
displays multidimensional arrays as `[n,:,:]`, whereas Matlab displays
them as `(:,:,n)`.

STOPPING MATLAB
---------------

Matlab processes end when the `Matlab` instance goes out of scope or
is explicitly closed using the `exit` method. Alternatively, the
`Matlab` class can be used as a context manager, which will properly
clean up after itself.

If you are not using the context manager or the `exit` method, you
will notice that some Matlab processes don't die when you expect them
to die. If you are running the regular `python` interpreter, chances
are that the Matlab process is still referenced to in
`sys.last_traceback`, which holds the value of the last exception that
was raised. Your Matlab process will die once the next exception is
raised.

If you are running `ipython`, though, all bets are off. I have noticed
that `ipython` keeps all kinds of references to all kinds of things.
Sometimes, `%reset` will clear them, sometimes it won't. Sometimes
they only go away when `ipython` quits. And sometimes, even stopping
`ipython` doesn't kill it (how is this even possible?). This can be
quite annoying. Use the `exit` method or the context manager to make
sure the processes are stopped correctly.

HOW DOES IT WORK?
-----------------

Transplant opens Matlab as a subprocess (optionally over SSH), then
connects to it via [0MQ](http://zeromq.org/) in a request-response
pattern. Matlab then runs the _transplant_ remote and starts listening
for messages. Now, Python can send messages to Matlab, and Matlab will
respond. Roundtrip time for sending/receiving and encoding/decoding
values from Python to Matlab and back is about 3-7 ms.

All messages are Msgpack-encoded or JSON-encoded objects. You can
choose between Msgpack (faster) and JSON (slower, human-readable)
using the `msgformat` attribute of the `Matlab` constructor. There are
seven messages types used by Python:

* `set_global` and `get_global` set and retrieve a global variable.
* `del_proxy` removes a cached object.
* `call` calls a Matlab function with some function arguments and
  returns the result.
* `die` tells Matlab to shut down.

Matlab can then respond with one of three message types:

* `ack` for successful execution.
* `value` for return values.
* `error` if there was an error during execution.

In addition to the regular Msgpack/JSON data types, _transplant_ uses
a specially formatted Msgpack/JSON array for transmitting numerical
matrices as binary data. A numerical 2x2 32-bit integer matrix
containing `[[1, 2], [3, 4]]` would be encoded as
`["__matrix__", "int32", [2, 2], "AQAAAAIAAAADAAAABAAAA==\n"]`, where
`"int32"` is the data type, `[2, 2]` is the matrix shape and the long
string is the base64-encoded matrix content. This allows for efficient
data exchange and prevents rounding errors due to JSON serialization.

When Matlab returns a function handle, it is encoded as
`["__function__", func2str(f)]`. When Matlab returns an object, it
caches its value and returns `["__object__", cache_idx]`. These arrays
are translated back to their original Matlab values if passed to
Matlab.

Note that this project includes a Msgpack serializer/parser, a JSON
serializer/parser, and a Base64 encoder/decoder in pure Matlab.

INSTALLATION
------------

1. Install the zeromq library on your computer in a path that is known
   to Matlab.

2. Add *ZMQ.m*, *transplantzmq.h*, and *transplant_remote.m* to your
   Matlab path.

3. On the Python side, make sure to have PyZMQ and Numpy installed as
   well.

4. If `matlab` is not reachable in your shell, give the full path to
   your Matlab executable to the `Matlab` constructor.

5. If you indent to start Matlab on a remote computer, make sure that
   computer is reachable through SSH and fullfills the above steps.
   
   
   
Extra installation tips for windows:
-----------------------------------

* Notice that a "MATLAB Command Window" is created when you initialize transplant. If the command window is interactive then it means that Matlab had a problem loading transplant, most likely on the matlab side. It's most likely related to loading ZeroMQ library into matlab, see instructions on the next bullet on how to solve that. 

* Solving ZeroMQ and matlab's LoadLibrary issues
	* Install zeromq from here:
	http://zeromq.org/distro:microsoft-windows
	"Stable Release 4.0.4" worked well for me.

	* Copy libzmq-v90-mt-4_0_4.dll into libzmq.dll

	* Make sure that matlab knows the path of this dll (I don't remember if I did this using the PATH env. variable, or by adding addpath('path/to/zeromq/bin') to matlabrc.m )

	* Put addpath('path/to/transplant_library') in matlabrc.m

	* Matlab doesn't always ship with a C/C++ compiler, In my case of Matlab 2014b x64 it didn't.
	Matlab needs a compiler in order to load and use the zeromq binary DLLs, which is a C++ library. Note that it's needed for using matlab "LoadLibrary" function to load any C/C++ DLL.

	* In the case that you don't have a compiler that Matlab knows, one of the options that you can do is download  Win 7 SDK.
	https://www.microsoft.com/en-us/download/details.aspx?id=8279
	Note that the sdk installer checks for .net framework 4, and in the likely case that you have a newer version it will not install.
	You can trick it into installing with some simple registry trickery (*remember to restore it back after the installation is complete*)
	Make sure that compilers are selected as a component to be installed.
	Look at the accepted answer here for the registry trickery:
	http://stackoverflow.com/questions/31455926/windows-sdk-setup-failure

	* Now, manually run a *new* Matlab session, and verify that you can manually use LoadLibrary('lib
	zmq.dll','transplantzmq.h') without getting any errors/warnings.

	* You are ready to go!
   

FAQ
---

* I get errors with integer numbers  
  For some reason, many Matlab functions crash if called with integers. Convert your numbers to `float` in Python to fix this problem.
  
* How do I pass structs to Matlab?__
  Since Matlab structs can't use arbitrary keys, all Python dictionaries are converted to Matlab `containers.Map` instead of structs. Wrap your dicts in `MatlabStruct` in Python to have them converted to structs. Note that this will change all invalid keys to whatever Matlab thinks is an appropriate key name using `matlab.lang.makeValidName`.


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
