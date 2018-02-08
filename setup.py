#!/usr/bin/env python

import sys
from setuptools import setup

if sys.version_info < (3, 4):
    error = """
Transplant does not support Python < 3.4.
This may be due to an out of date pip.
Make sure you have pip >= 9.0.1.
"""
    sys.exit(error)

setup(name='Transplant',
      version='0.8.5',
      description='Call Matlab from Python (requires Matlab)',
      author='Bastian Bechtold',
      author_email='basti@bastibe.de',
      url='https://github.com/bastibe/transplant',
      packages=['transplant'],
      package_data={'transplant': ['parsemsgpack.m', 'dumpmsgpack.m',
                                   'parsejson.m', 'dumpjson.m',
                                   'base64decode.m', 'base64encode.m',
                                   'transplant_remote.m', 'ZMQ.m',
                                   'transplantzmq.h']},
      classifiers=['Development Status :: 4 - Beta',
                   'Intended Audience :: Science/Research',
                   'License :: OSI Approved :: BSD License',
                   'Operating System :: MacOS',
                   'Operating System :: Microsoft :: Windows',
                   'Operating System :: POSIX :: Linux',
                   'Programming Language :: Python :: 3'],
      license='BSD 3-clause License',
      install_requires=['numpy', 'pyzmq', 'msgpack-python'],
      python_requires='>=3.4',
      requires=['matlab', 'libzmq']
     )
