#!/usr/bin/env python

from distutils.core import setup

setup(name='Transplant',
      version='0.7.4',
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
      requires=['matlab', 'libzmq']
     )
