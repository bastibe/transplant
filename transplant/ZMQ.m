%ZMQ socket communication via ZMQ
%
% ZMQ is a wrapper for libzmq, which exposes a simple ZMQ REP
% endpoint. You can receive messages from the socket, and send messages
% to the socket.
%
% ZMQ Methods:
%   receive - read a message from the socket
%   send    - write a message to the socket

% Copyright (c) 2016, Bastian Bechtold
% This code is published under the terms of the BSD 3-clause license

classdef ZMQ < handle
    properties (Access=private)
        context
        socket
    end
    methods
        function obj = ZMQ(libname, address)
            ZMQ_REP = 4;
            try
                if not(libisloaded('libzmq'))
                    [notfound, warnings] = ...
                        loadlibrary(libname, 'transplantzmq.h', ...
                                    'alias', 'libzmq');
                    % the library did not contain the functions we need:
                    assert(isempty(notfound), 'Could not load ZMQ library')
                end
                obj.context = calllib('libzmq', 'zmq_ctx_new');
                assert(not(obj.context.isNull), ...
                       'zmq_ctx_new failed: Could not create context');
                obj.socket = calllib('libzmq', 'zmq_socket', obj.context, ZMQ_REP);
                assert(not(obj.socket.isNull), obj.errortext('zmq_socket'));
                err = calllib('libzmq', 'zmq_connect', obj.socket, address);
                assert(err == 0, obj.errortext('zmq_connect'));
            catch exception
                % print exception, since we probably don't have a working connection
                % to the transplant master yet for reporting errors properly:
                disp(['Error loading libzmq: ' exception.message]);
                throw(exception);
            end
        end

        function str = receive(obj)
            msg = libstruct('zmq_msg_t', struct('hidden', zeros(1, 64, 'uint8')));
            calllib('libzmq', 'zmq_msg_init', msg); % always returns 0
            msglen = calllib('libzmq', 'zmq_msg_recv', msg, obj.socket, 0);
            assert(msglen >= 0, obj.errortext('zmq_msg_recv'));
            msgptr = calllib('libzmq', 'zmq_msg_data', msg);
            if not(msgptr.isNull)
                setdatatype(msgptr, 'uint8Ptr', 1, msglen);
                str = uint8(msgptr.Value);
            else
                str = uint8([]);
            end
            err = calllib('libzmq', 'zmq_msg_close', msg);
            assert(err == 0, obj.errortext('zmq_msg_close'));
        end

        function send(obj, data)
            dataptr = libpointer('uint8Ptr', data);
            msglen = calllib('libzmq', 'zmq_send', obj.socket, dataptr, numel(data), 0);
            assert(msglen >= 0, obj.errortext('zmq_send'));
        end

        function delete(obj)
            % if we crashed in the constructor:
            if ~libisloaded('libzmq')
                return
            end
            err = calllib('libzmq', 'zmq_close', obj.socket);
            assert(err == 0, obj.errortext('zmq_close'));
            err = calllib('libzmq', 'zmq_ctx_term', obj.context);
            assert(err == 0, obj.errortext('zmq_ctx_term'));
            unloadlibrary('libzmq');
        end
    end

    methods (Hidden=true)
        function str = errortext(obj, instruction)
            base = 156384712;
            errno = calllib('libzmq', 'zmq_errno');
            switch errno
                case 4 % EINTR
                    if strcmp(instruction, 'zmq_ctx_term')
                        str = 'Termination was interrupted by a signal. It can be restarted if needed.';
                    elseif strcmp(instruction, 'zmq_send')
                        str = 'The operation was interrupted by delivery of a signal before the message was sent.';
                    elseif strcmp(instruction, 'zmq_msg_recv')
                        str = 'The operation was interrupted by delivery of a signal before a message was available.';
                    else
                        str = 'Interrupted system call';
                    end
                case 11 % EAGAIN
                    if strcmp(instruction, 'zmq_send')
                        str = 'Non-blocking mode was requested and the message cannot be sent at the moment.';
                    elseif strcmp(instruction, 'zmq_msg_recv')
                        str = 'Non-blocking mode was requested and no message are available at the moment.';
                    else
                        str = 'Try again';
                    end
                case 22 % EINVAL
                    if strcmp(instruction, 'zmq_socket')
                        str = 'The requested socket *type* is invalid.';
                    elseif strcmp(instruction, 'zmq_connect')
                        str = 'The endpoint supplied is invalid.';
                    else
                        str = 'Invalid argument';
                    end
                case 14 % EFAULT
                    if strcmp(instruction, 'zmq_socket') || strcmp(instruction, 'zmq_ctx_term')
                        str = 'The provided *context* is invalid.';
                    elseif strcmp(instruction, 'zmq_msg_close')
                        str = 'Invalid message';
                    elseif strcmp(instruction, 'zmq_msg_recv')
                        str = 'The message passed to the function was invalid.';
                    else
                        str = 'Invalid argument';
                    end
                case 24 % EMFILE
                    if strcmp(instruction, 'zmq_socket')
                        str = 'The limit on the total number of open ZMQ sockets has been reached.';
                    else
                        str = 'Too many open files';
                    end
                case base + 1 % ENOTSUP
                    str = 'The *zmq_send()* operation is not supported by this socket type.';
                case base + 2 % EPROTONOSUPPORT
                    str = 'The requested *transport* protocol is not supported.';
                case base + 9 % ENOTSOCK
                    str = 'The provided *socket* was invalid.';
                case base + 17 % EHOSTUNREACH
                    str = 'The message cannot be routed.';
                case base + 51 % EFSM
                    if strcmp(instruction, 'zmq_send')
                        str = 'The *zmq_send()* operation cannot be performed on this socket at the moment due to the socket not being in the appropriate state.';
                    else
                        str = 'socket not in appropriate state.';
                    end
                case base + 52 % ENOCOMPATPROTO
                    str = 'The requested *transport* protocol is not compatible with the socket type.';
                case base + 53 % ETERM
                    str = 'The ZMQ *context* associated with the specified *socket* was terminated.';
                case base + 54 % EMTHREAD
                    str = 'No I/O thread is available to accomplish the task.';
                otherwise
                    str = sprintf('Unknown error %d', errno);
            end
            str = sprintf('Error in %s: %s', instruction, str);
        end
    end
end
