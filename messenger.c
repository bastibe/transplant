// compile with mex -I/usr/local/include -lzmq -Dchar16_t=UINT16_T messenger.c
// This is adapted from https://github.com/arokem/python-matlab-bridge
/*
  Copyright (c) 2013. See "Contributors". MATLAB (R) is copyright of
  the Mathworks.

  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions
  are met:

  - Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
  - Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
  FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
  COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
  BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
  ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
  POSSIBILITY OF SUCH DAMAGE.
*/

#include <stdio.h>
#include <string.h>
#include "mex.h"
#include "zmq.h"

void *ctx = NULL;
void *socket = NULL;


/* Create the socket and start 0MQ */
void open(int nlhs, mxArray *plhs[],
          int nrhs, const mxArray *prhs[]) {

    if (nrhs != 2) {
        mexErrMsgTxt("Missing argument: socket address");
    }

    char *socket_addr = mxArrayToString(prhs[1]);

    if (!socket_addr) {
        mexErrMsgTxt("Cannot read socket address");
    }

    ctx = zmq_ctx_new();
    socket = zmq_socket(ctx, ZMQ_REP);

    if (!socket) {
        switch (errno) {
        case EINVAL:
            mexErrMsgTxt("The requested socket type is invalid");
            break;
        case EFAULT:
            mexErrMsgTxt("The provided context is invalid");
            break;
        case EMFILE:
            mexErrMsgTxt("The limit on the total number of open "
                         "0MQ sockets has been reached");
            break;
        case ETERM:
            mexErrMsgTxt("The context specified was terminated");
            break;
        }
    }

    int err = zmq_connect(socket, socket_addr);

    if (err) {
        switch (errno) {
        case EINVAL:
            mexErrMsgTxt("The endpoint supplied is invalid");
            break;
        case EPROTONOSUPPORT:
            mexErrMsgTxt("The requested transport protocol is not "
                         "supported");
            break;
        case ENOCOMPATPROTO:
            mexErrMsgTxt("The requested transport protocol is not "
                         "compatible with the socket type");
            break;
        case ETERM:
            mexErrMsgTxt("The 0MQ context associated with the "
                         "specified socket was terminated");
            break;
        case ENOTSOCK:
            mexErrMsgTxt("The provided socket was invalid");
            break;
        case EMTHREAD:
            mexErrMsgTxt("No I/O thread is available to accomplish "
                         "the task");
            break;
        }
    }
}


/* Receive a message from the socket */
void receive(int nlhs, mxArray *plhs[],
             int nrhs, const mxArray *prhs[]) {

    zmq_msg_t msg;
    int err = zmq_msg_init(&msg);
    if (err) {
        mexErrMsgTxt("Unknown ZMQ error");
    }

    int msglen = zmq_msg_recv(&msg, socket, 0);
    if (msglen == -1) {
        switch (errno) {
        case EAGAIN:
            mexErrMsgTxt("Non-blocking mode was requested and no "
                         "messages are available at the moment");
            break;
        case ENOTSUP:
            mexErrMsgTxt("The zmq_recv() operation is not "
                         "supported by this socket type");
            break;
        case EFSM:
            mexErrMsgTxt("The zmq_recv() operation cannot be "
                         "performed on this socket at the moment "
                         "due to the socket not being in the "
                         "appropriate state. This error may occur "
                         "with socket types that switch between "
                         "several states, such as ZMQ_REP. See the "
                         "messaging patterns section of zmq_socket "
                         "for more information");
            break;
        case ETERM:
            mexErrMsgTxt("The 0MQ context associated with the "
                         "specified socket was terminated");
            break;
        case ENOTSOCK:
            mexErrMsgTxt("The provided socket was invalid");
            break;
        case EINTR:
            mexErrMsgTxt("The operation was interrupted by "
                         "delivery of a signal before a message "
                         "was available");
            break;
        case EFAULT:
            mexErrMsgTxt("The message passed to the function was invalid");
            break;
        }
    }

    const char *data = mxCalloc(msglen, 1);
    memcpy((void*)data, zmq_msg_data(&msg), msglen);
    plhs[0] = mxCreateString(data);
    err = zmq_msg_close(&msg);
    if (err) {
        switch (errno) {
        case EFAULT:
            mexErrMsgTxt("Invalid message");
            break;
        }
    }
}


/* Send a message to the socket. */
void send(int nlhs, mxArray *plhs[],
          int nrhs, const mxArray *prhs[]) {

    if (nrhs != 2) {
        mexErrMsgTxt("Please provide the message to send");
    }

    size_t msglen = mxGetNumberOfElements(prhs[1]);
    char *msg_out = mxArrayToString(prhs[1]);

    size_t sentlen = zmq_send(socket, msg_out, msglen, 0);

    if (msglen != sentlen) {
        switch (errno) {
        case EAGAIN:
            mexErrMsgTxt("Non-blocking mode was requested and the "
                         "messages cannot be sent at the moment");
            break;
        case ENOTSUP:
            mexErrMsgTxt("The zmq_send() operation is not "
                         "supported by this socket type");
            break;
        case EFSM:
            mexErrMsgTxt("The zmq_send() operation cannot be "
                         "performed on this socket at the moment "
                         "due to the socket not being in the "
                         "appropriate state. This error may occur "
                         "with socket types that switch between "
                         "several states, such as ZMQ_REP. See the "
                         "messaging patterns section of zmq_socket "
                         "for more information");
            break;
        case ETERM:
            mexErrMsgTxt("The 0MQ context associated with the "
                         "specified socket was terminated");
            break;
        case ENOTSOCK:
            mexErrMsgTxt("The provided socket was invalid");
            break;
        case EINTR:
            mexErrMsgTxt("The operation was interrupted by "
                         "delivery of a signal before a message "
                         "was sent");
            break;
        case EHOSTUNREACH:
            mexErrMsgTxt("The message cannot be routed");
            break;
        }
    }
}


/* Close the socket and terminate 0MQ */
void close(int nlhs, mxArray *plhs[],
           int nrhs, const mxArray *prhs[]) {

    int err = zmq_close(socket);
    err |= zmq_term(ctx);

    if (err) {
        switch (errno) {
        case ENOTSOCK:
            mexErrMsgTxt("The provided socket was invalid");
            break;
        case EFAULT:
            mexErrMsgTxt("The provided context was invalid");
            break;
        case EINTR:
            mexErrMsgTxt("Termination was interrupted by a signal. "
                         "It can be restarted if needed");
            break;
        }
    }
}


/* Gateway to Matlab. Just a dispatcher. */
void mexFunction(int nlhs, mxArray *plhs[],
                 int nrhs, const mxArray *prhs[]) {

    if (nrhs == 0) {
        mexErrMsgTxt("Usage: messenger('open', 'url')\n"
                     "       messenger('receive')\n"
                     "       messenger('send', 'content')\n"
                     "       messenger('close')");
    }

    char *cmd = mxArrayToString(prhs[0]);
    if(!cmd) {
        mexErrMsgTxt("Cannot read the command");
    }

    if (strcmp(cmd, "open") == 0) {
        open(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(cmd, "receive") == 0) {
        receive(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(cmd, "send") == 0) {
        send(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(cmd, "close") == 0) {
        close(nlhs, plhs, nrhs, prhs);
    } else {
        mexErrMsgTxt("Unidentified command");
    }
}
