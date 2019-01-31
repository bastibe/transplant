TRANSPLANT
==========

|version| |python| |status| |license|

|contributors| |downloads|

Transplant is an easy way of calling Matlab from Python.

.. code:: python

    import transplant
    matlab = transplant.Matlab()
    # call Matlab functions:
    length = matlab.numel([1, 2, 3])
    magic = matlab.magic(2)
    spectrum = matlab.fft(numpy.random.randn(100))
    # inject variables into Matlab:
    matlab.signal = numpy.zeros(100)

Python lists are converted to cell arrays in Matlab, dicts are
converted to Maps, and Numpy arrays are converted do native Matlab
matrices.

All Matlab functions and objects can be accessed from Python.

| Transplant is licensed under the terms of the BSD 3-clause license
| (c) 2014 Bastian Bechtold


|open-issues| |closed-issues| |open-prs| |closed-prs|

.. |contributors| image:: https://img.shields.io/github/contributors/bastibe/transplant.svg
.. |version| image:: https://img.shields.io/pypi/v/transplant.svg
.. |python| image:: https://img.shields.io/pypi/pyversions/transplant.svg
.. |license| image:: https://img.shields.io/github/license/bastibe/transplant.svg
.. |downloads| image:: https://img.shields.io/pypi/dm/transplant.svg
.. |open-issues| image:: https://img.shields.io/github/issues/bastibe/transplant.svg
.. |closed-issues| image:: https://img.shields.io/github/issues-closed/bastibe/transplant.svg
.. |open-prs| image:: https://img.shields.io/github/issues-pr/bastibe/transplant.svg
.. |closed-prs| image:: https://img.shields.io/github/issues-pr-closed/bastibe/transplant.svg
.. |status| image:: https://img.shields.io/pypi/status/transplant.svg


RECENT CHANGES
--------------

- Should now reliably raise an error if Matlab dies unexpectedly.
- Keyword arguments are now automatically translated to string-value
  pairs in Matlab.
- ``close`` was renamed ``exit``. Even though Python typically uses
  ``close`` to close files and connections, this conflicts with Matlab's
  own ``close`` function.
- Matlab will now start Matlab at the current working directory.
- Transplant can now be installed through ``pip install transplant``.
- You can now use ``jvm=False`` and ``desktop=False`` to auto-supply
  common command line arguments for Matlab.


STARTING MATLAB
----------------

.. code:: python

    matlab = transplant.Matlab()

Will start a Matlab session and connect to it. This will take a few
seconds while Matlab starts up. All of Matlab's output will go to the
standard output and will appear interspersed with Python output.
Standard input is suppressed to make REPLs work, so Matlab's ``input``
function will not work.

By default, this will try to call ``matlab`` on the command line. If
you want to use a different version of Matlab, or ``matlab`` is not in
PATH, use ``Matlab(executable='/path/to/matlab')``.

By default, Matlab is called with ``-nodesktop`` and ``-nosplash``
(and ``-minimize`` on Windows), so no IDE or splash screen show up.
You can change this by setting ``desktop=True``.

You can start Matlab without loading the Java-based GUI system
(``'-nojvm'``) by setting ``jvm=False``. This will speed up startup
considerably, but you won't be able to open figures any more.

If you want to start Matlab with additional command line arguments,
you can supply them like this: ``Matlab(arguments=['-c licensefile'])``.

By default, Matlab will be started on the local machine. To start
Matlab on a different computer, supply the IP address of that
computer: ``Matlab(address='172.168.1.5')``. This only works if that
computer is reachable through ``ssh``, Matlab is available on the
other computer's command line, and transplant is in the other Matlab's
path.

Note that due to a limitation of Matlab on Windows, command line
output from Matlab running on Windows isn't visible to Transplant.


CALLING MATLAB
--------------

.. code:: python

    matlab.disp("Hello, World")

Will call Matlab's ``disp`` function with the argument ``'Hello, World'``.
It is equivalent to ``disp('Hello, World')`` in Matlab. Return values
will be returned to Python, and errors will be converted to Python
errors (Matlab stack traces will be given, too!).

Input arguments are converted to Matlab data structures:

+-----------------------------------+-------------------------------+
| Python Argument                   | Matlab Type                   |
+===================================+===============================+
| ``str``                           | ``char`` vector               |
+-----------------------------------+-------------------------------+
| ``float``                         | ``double`` scalar             |
+-----------------------------------+-------------------------------+
| ``int``                           | an ``int{8,16,32,64}`` scalar |
+-----------------------------------+-------------------------------+
| ``True``/``False``                | ``logical`` scalar            |
+-----------------------------------+-------------------------------+
| ``None``                          | ``[]``                        |
+-----------------------------------+-------------------------------+
| ``list``                          | ``cell``                      |
+-----------------------------------+-------------------------------+
| ``dict``                          | ``containers.Map``            |
+-----------------------------------+-------------------------------+
| ``transplant.MatlabStruct(dict)`` | ``struct``                    |
+-----------------------------------+-------------------------------+
| ``numpy.ndarray``                 | ``double`` matrix             |
+-----------------------------------+-------------------------------+
| ``scipy.sparse``                  | ``sparse`` matrix             |
+-----------------------------------+-------------------------------+
| proxy object                      | original object               |
+-----------------------------------+-------------------------------+

Return values are treated similarly:

+----------------------------------+---------------------+
| Matlab Return Value              | Python Type         |
+==================================+=====================+
| ``char`` vector                  | ``str``             |
+----------------------------------+---------------------+
| numeric scalar                   | number              |
+----------------------------------+---------------------+
| ``logical`` scalar               | ``True``/``False``  |
+----------------------------------+---------------------+
| ``[]``                           | ``None``            |
+----------------------------------+---------------------+
| ``cell``                         | ``list``            |
+----------------------------------+---------------------+
| ``struct`` or ``containers.Map`` | ``dict``            |
+----------------------------------+---------------------+
| numeric matrix                   | ``numpy.ndarray``   |
+----------------------------------+---------------------+
| sparse matrix                    | ``scipy.sparse``    |
+----------------------------------+---------------------+
| function                         | proxy function      |
+----------------------------------+---------------------+
| object                           | proxy object        |
+----------------------------------+---------------------+

If the function returns a function handle or an object, a matching
Python functions/objects will be created that forwards every access to
Matlab. Objects can also be handed back to Matlab and will work as
intended.

.. code:: python

    f = matlab.figure() # create a Figure object
    f.Visible = 'off' # modify a property of the Figure object
    matlab.set(f, 'Visible', 'on') # pass the Figure object to a function

In Matlab, some functions behave differently depending on the number
of output arguments. By default, Transplant uses the Matlab function
``nargout`` to figure out the number of return values for a function.
If ``nargout`` can not determine the number of output arguments
either, Matlab functions will return the value of ``ans`` after the
function call.

In some cases, ``nargout`` will report a wrong number of output
arguments. For example ``nargout profile`` will say ``1``, but ``x =
profile('on')`` will raise an error that too few output arguments were
used. To fix this, every function has a keyword argument ``nargout``,
which can be used in these cases: ``matlab.profile('on', nargout=0)``
calls ``profile on`` with no output arguments. ``s, f, t, p =
matlab.spectrogram(numpy.random.randn(1000), nargout=4)`` returns all
four output arguments of ``spectrogram``.

When working with plots, note that the Matlab program does not wait
for drawing on its own. Use ``matlab.drawnow()`` to make figures
appear.

Note that functions are not called in the base workspace. Functions
that access the current non-lexical workspace (this is very rare) will
therefore not work as expected. For example, ``matlab.truth = 42``,
``matlab.exist('truth')`` will not find the ``truth`` variable. Use
``matlab.evalin('base', "exist('truth')", nargout=1)`` instead in this
case.

If you hit Ctrl-C, the ``KeyboardInterrupt`` will be applied to both
Python and Matlab, stopping any currently running function. Due to a
limitation of Matlab, the error and stack trace of that function will
be lost.


MATRIX DIMENSIONS
-----------------

The way multidimensional arrays are indexed in Matlab and Python are
fundamentally different. Thankfully, the two-dimensional case works as
expected:

::

               Python         |        Matlab
    --------------------------+------------------------
     array([[  1,   2,   3],  |     1   2   3
            [ 10,  20,  30]]) |    10  20  30

In both languages, this array has the shape ``(2, 3)``.

With higher-dimension arrays, this becomes harder. The next array is
again identical:

::

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

Even though they look different, they both have the same shape ``(3,
2, 2)``, and are indexed in the same way. The element at position ``a,
b, c`` in Python is the same as the element at position ``a+1, b+1,
c+1`` in Matlab (``+1`` due to zero-based/one-based indexing).

You can think about the difference in presentation like this: Python
displays multidimensional arrays as ``[n,:,:]``, whereas Matlab
displays them as ``(:,:,n)``.


STOPPING MATLAB
---------------

Matlab processes end when the ``Matlab`` instance goes out of scope or
is explicitly closed using the ``exit`` method. Alternatively, the
``Matlab`` class can be used as a context manager, which will properly
clean up after itself.

If you are not using the context manager or the ``exit`` method, you
will notice that some Matlab processes don't die when you expect them
to die. If you are running the regular ``python`` interpreter, chances
are that the Matlab process is still referenced to in
``sys.last_traceback``, which holds the value of the last exception
that was raised. Your Matlab process will die once the next exception
is raised.

If you are running ``ipython``, though, all bets are off. I have
noticed that ``ipython`` keeps all kinds of references to all kinds of
things. Sometimes, ``%reset`` will clear them, sometimes it won't.
Sometimes they only go away when ``ipython`` quits. And sometimes,
even stopping ``ipython`` doesn't kill it (how is this even
possible?). This can be quite annoying. Use the ``exit`` method or the
context manager to make sure the processes are stopped correctly.


INSTALLATION
------------

1. Install the zeromq library on your computer and add it to your
   PATH. Alternatively, Transplant automatically uses ``conda``'s
   zeromq if you use conda.

2. Install Transplant using ``pip install transplant``. This will
   install ``pyzmq``, ``numpy`` and ``msgpack`` as
   dependencies.

If you want to run Transplant over the network, the remote Matlab has
to have access to *ZMQ.m* and *transplant_remote.m* and the zeromq
library and has to be reachable through SSH.

INSTALLATION GUIDE FOR LINUX
----------------------------

1. Install the latest version of zeromq through your package manager.
   Install version 4 (often called 5).

2. Make sure that Matlab is using the system's version of libstdc++.
   If it is using an incompatible version, starting Transplant might
   fail with an error like ``GLIBCXX_3.4.21 not found``. If you
   experience this, disable Matlab's own libstdc++ either by
   removing/renaming $MATLABROOT/sys/os/glnxa64/libstdc++, or by
   installing ``matlab-support`` (if you are running Ubuntu).


INSTALLATION GUIDE FOR WINDOWS
------------------------------

1. Install the latest version of zeromq from here:
   http://zeromq.org/distro:microsoft-windows OR through conda.

2. Install a compiler. See here for a list of supported compilers:
   http://uk.mathworks.com/support/compilers/R2017a/ Matlab needs a
   compiler in order to load and use the ZeroMQ library using
   ``loadlibrary``.


HOW DOES IT WORK?
-----------------

Transplant opens Matlab as a subprocess (optionally over SSH), then
connects to it via `0MQ <http://zeromq.org/>`_ in a request-response
pattern. Matlab then runs the *transplant* remote and starts listening
for messages. Now, Python can send messages to Matlab, and Matlab will
respond. Roundtrip time for sending/receiving and encoding/decoding
values from Python to Matlab and back is about 2 ms.

All messages are Msgpack-encoded or JSON-encoded objects. You can
choose between Msgpack (faster) and JSON (slower, human-readable)
using the ``msgformat`` attribute of the ``Matlab`` constructor. There
are seven messages types used by Python:

* ``set_global`` and ``get_global`` set and retrieve a global
  variable.
* ``del_proxy`` removes a cached object.
* ``call`` calls a Matlab function with some function arguments and
  returns the result.
* ``die`` tells Matlab to shut down.

Matlab can then respond with one of three message types:

* ``ack`` for successful execution.
* ``value`` for return values.
* ``error`` if there was an error during execution.

In addition to the regular Msgpack/JSON data types, _transplant_ uses
specially formatted Msgpack/JSON arrays for transmitting numerical
matrices as binary data. A numerical 2x2 32-bit integer matrix
containing ``[[1, 2], [3, 4]]`` would be encoded as ``["__matrix__",
"int32", [2, 2], "AQAAAAIAAAADAAAABAAAA==\n"]``, where ``"int32"`` is
the data type, ``[2, 2]`` is the matrix shape and the long string is
the base64-encoded matrix content. This allows for efficient data
exchange and prevents rounding errors due to JSON serialization. In
Msgpack, the data is not base64-encoded.

When Matlab returns a function handle, it is encoded as
``["__function__", func2str(f)]``. When Matlab returns an object, it
caches its value and returns ``["__object__", cache_idx]``. These
arrays are translated back to their original Matlab values if passed
to Matlab.

Note that this project includes a Msgpack serializer/parser, a JSON
serializer/parser, and a Base64 encoder/decoder in pure Matlab.


FAQ
---

* I get errors with integer numbers
  Many Matlab functions crash if called with integers. Convert your
  numbers to ``float`` in Python to fix this problem.

* How do I pass structs to Matlab?
  Since Matlab structs can't use arbitrary keys, all Python
  dictionaries are converted to Matlab ``containers.Map`` instead of
  structs. Wrap your dicts in ``transplant.MatlabStruct`` in Python to
  have them converted to structs. Note that this will change all
  invalid keys to whatever Matlab thinks is an appropriate key name
  using ``matlab.lang.makeValidName``.

* I get errors like ``GLIBCXX_3.4.21 not found``
  Matlab's version of libstdc++ is incompatible with your OS's
  version. See INSTALLATION GUIDE FOR LINUX for details.

* Does Transplant work in Python 2.7?
  No, it does not.


SIMILAR PROGRAMS
----------------

I know of two programs that try to do similar things as Transplant:

- Mathwork's own `MATLAB Engine API for Python`_ provides a CPython
  extension for calling Matlab code from some versions of Python. In
  my experience, it is significantly slower than Transplant, less
  feature-complete (no support for non-scalar structs, objects,
  methods, packages, numpy), and more cumbersome to use (all arguments
  and return values need to be wrapped in a ``matlab.double`` instead
  of Numpy Arrays). For a comparison of the two, here are two blog
  posts on the topic: `Intro to Transplant`_, `Transplant speed`_.
- Oct2Py calls Octave from Python. It is very similar to Transplant,
  but uses Octave instead of Matlab. This has huge benefits in startup
  time, but of course doesn't support all Matlab code.

.. _MATLAB Engine API for Python: http://mathworks.com/help/matlab/matlab-engine-for-python.html
.. _Intro to Transplant: http://bastibe.de/2016-06-21-transplant-revisited.html
.. _Transplant speed: http://bastibe.de/2015-11-03-matlab-engine-performance.html

KNOWN ISSUES
-------------

Transplant is a side project of mine that I use for running
cross-language experiments on a small compute cluster. As such, my
usage of Transplant is very narrow, and I do not see bugs that don't
happen in my typical usage. That said, I have used Transplant for
hundreds of hours, and hundreds of Gigabytes of data without errors.

If you find a bug, or would like to discuss a new feature, or would
like to contribute code, please open an issue on Github.

I do not have a Windows machine to test Transplant. Windows support
might contain bugs, but at least one user has used it on Windows in
the past. If you are hitting problems on Windows, please open an issue
on Github.

Running Transplant over the network might contain bugs. If you are
hitting problems, please open an issue on Github.

Finally, I would like to remind you that I am developing this project
for free, and in my spare time. While I try to be as accomodating as
possible, I can not guarantee a timely response to issues. Publishing
Open Source Software on Github does not imply an obligation to *fix
your problem right now*. Please be civil.
