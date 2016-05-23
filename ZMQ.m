classdef ZMQ < handle
    properties
        context
        socket
    end
    methods
        function obj = ZMQ(address)
            ZMQ_REP = 4;
            if not(libisloaded('libzmq'))
                loadlibrary('libzmq', 'transplantzmq.h')
            end
            obj.context = calllib('libzmq', 'zmq_ctx_new');
            if obj.context.isNull
                'zmq_ctx_new'
                calllib('libzmq', 'zmq_errno')
            end
            obj.socket = calllib('libzmq', 'zmq_socket', obj.context, ZMQ_REP);
            if obj.socket.isNull
                'zmq_socket'
                calllib('libzmq', 'zmq_errno')
            end
            err = calllib('libzmq', 'zmq_connect', obj.socket, address);
            if err ~= 0
                'zmq_connect'
                calllib('libzmq', 'zmq_errno')
            end
        end

        function str = receive(obj)
            msg = libstruct('zmq_msg_t', struct('hidden', zeros(1, 64, 'uint8')));
            err = calllib('libzmq', 'zmq_msg_init', msg);
            if err ~= 0
                'zmq_msg_init'
                calllib('libzmq', 'zmq_errno')
            end
            msglen = calllib('libzmq', 'zmq_msg_recv', msg, obj.socket, 0);
            if msglen < 0
                'zmq_msg_recv'
                calllib('libzmq', 'zmq_errno')
            end
            msgptr = calllib('libzmq', 'zmq_msg_data', msg);
            if msgptr.isNull
                'zmq_msg_data'
                calllib('libzmq', 'zmq_errno')
            end
            setdatatype(msgptr, 'uint8Ptr', 1, msglen);
            str = uint8(msgptr.Value);
            err = calllib('libzmq', 'zmq_msg_close', msg);
            if err ~= 0
                'zmq_msg_close'
                calllib('libzmq', 'zmq_errno')
            end
        end

        function send(obj, data)
            dataptr = libpointer('uint8Ptr', data);
            msglen = calllib('libzmq', 'zmq_send', obj.socket, dataptr, numel(data), 0);
            if msglen < 0
                'zmq_send'
                calllib('libzmq', 'zmq_errno')
            end
        end

        function delete(obj)
            err = calllib('libzmq', 'zmq_close', obj.socket);
            if err ~= 0
                'zmq_close'
                calllib('libzmq', 'zmq_errno')
            end
            err = calllib('libzmq', 'zmq_ctx_term', obj.context);
            if err ~= 0
                'zmq_term'
                calllib('libzmq', 'zmq_errno')
            end
            unloadlibrary('libzmq');
        end
    end
    methods (Hidden=true)
        function str = errors(obj, errno)
            base = 156384712;
            switch errno
                case base + 51
                    str = 'socket not in appropriate state';
            end
        end
    end
end
