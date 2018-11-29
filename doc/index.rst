.. Transplant documentation master file, created by
   sphinx-quickstart on Thu Nov 29 13:20:41 2018.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

.. include:: ../README.rst

API Documentation
=================

To start Matlab, instantiate an instance of:

.. autoclass:: transplant.Matlab
.. automethod:: transplant.Matlab.__getattr__
.. automethod:: transplant.Matlab.exit

Any function you call on a :class:`Matlab` object will be executed in
the Matlab process. Any property you access on a :class:`Matlab`
object will access the Matlab variable of the same name.

Proxy Objects
-------------

Matlab objects are returned as:

.. class:: transplant.MatlabProxyObject()

   A Proxy for an object that extists in Matlab.

   All property accesses and function calls are executed on the Matlab
   object in Matlab.

.. automethod:: transplant.MatlabProxyObject.__getattr__
.. method:: MatlabProxyObject.__doc__

   Documentation is only fetched on demand (for performance reasons).

Proxy Functions
---------------

Matlab functions are returned as:

.. autoclass:: transplant.MatlabFunction
.. automethod:: transplant.MatlabFunction.__call__
.. method:: MatlabFunction.__doc__

   Documentation is only fetched on demand (for performance reasons).

Matlab Structs
--------------

By default, ``dict`` are translated as ``containers.Map``. If you want
them to be translated to ``struct``, wrap them in a
:class:`MatlabStruct` object:

.. autoclass:: transplant.MatlabStruct


Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`
