%TRANSPLANT is a Matlab server for remote code execution
% TRANSPLANT(URL) connects to a 0MQ client at a given URL.
%
%    The client can send messages, which TRANSPLANT will answer.
%    All messages are JSON-encoded strings. All message are structures
%    with at least one key: 'type'
%
%    Depending on the message type, other keys may or may not be set.
%
%    TRANSPLANT implements the following message types:
%    - 'eval': evaluates the 'string' of the message.
%    - 'die': closes the 0MQ session and quits Matlab.
%    - 'put': saves the 'value' as a global variable called 'name'.
%    - 'get': retrieve the global variable 'name'.
%    - 'call': call function 'name' with 'args' and 'nargout'.
%
%    TRANSPLANT implements the following responses:
%    - 'ack': received message successfully.
%    - 'error': there was an error while handling the message.
%    - 'value': returns a value.
%
%    `put`, `get`, and `call` use a special encoding for matrices. See
%    `encode_matrices` and `decode_matrices` for more detail.

% (c) 2014 Bastian Bechtold

function transplant(url)

    % start 0MQ:
    messenger('open', url)

    while 1 % main messaging loop

        msg = receive_msg();

        try
            switch msg.type
                case 'die'
                    send_ack();
                    quit;
                case 'eval'
                    % get the number of output arguments
                    if isfield(msg, 'nargout') && msg.nargout >= 0
                        results = cell(msg.nargout, 1);
                        [results{:}] = evalin('base', msg.string);
                        if length(results) == 1
                            send_value(results{1});
                        else
                            send_value(results);
                        end
                    else
                        % try to get output from ans:
                        clear('ans');
                        evalin('base', msg.string);
                        try
                            send_value(ans);
                        catch err
                            send_ack();
                        end
                    end
                case 'put'
                    assignin('base', msg.name, decode_matrices(msg.value));
                    send_ack();
                case 'get'
                    if isempty(evalin('base', ['who(''' msg.name ''')']))
                       error('TRANSPLANT:novariable' , ...
                             ['Undefined variable ''' msg.name '''.']);
                    end
                    value = evalin('base', msg.name)
                    send_value(value);
                case 'call'
                    fun = evalin('base', ['@' msg.name]);
                    args = decode_matrices(msg.args);

                    % get the number of output arguments
                    if isfield(msg, 'nargout') && msg.nargout >= 0
                        resultsize = msg.nargout;
                    else
                        resultsize = nargout(fun);
                    end

                    if resultsize > 0
                        % call the function with the given number of
                        % output arguments:
                        results = cell(resultsize, 1);
                        [results{:}] = fun(args{:});
                        if length(results) == 1
                            send_value(results{1});
                        else
                            send_value(results);
                        end
                    else
                        % try to get output from ans:
                        clear('ans');
                        fun(args{:});
                        try
                            send_value(ans);
                        catch err
                            send_ack();
                        end
                    end
                end
        catch err
            send_error(err)
        end
    end
end


% Wait for and receive a message
function msg = receive_msg()
    blob = messenger('receive');
    msg = parsejson(blob);
end

% Send a message
%
% This is the base function for the specialized senders below
function send_msg(msg_type, msg)
    msg.type = msg_type;
    messenger('send', dumpjson(msg));
end

% Send an acknowledgement message
function send_ack()
    send_msg('ack', struct());
end

% Send an error message
function send_error(err)
    msg.identifier = err.identifier;
    msg.message = err.message;
    msg.stack = err.stack;
    send_msg('error', msg);
end

% Send a message that contains a value
function send_value(value)
    msg.value = encode_matrices(value);
    send_msg('value', msg);
end

% recursively walk through value and encode all matrices
%
% The matrix `np.array([[1, 2], [3, 4]], dtype='int32')` would be
% encoded as
% `["__matrix__", "int32", [2, 2], "AQAAAAIAAAADAAAABAAAA==\n"]`
%
% where `"int32"` is the data type, `[2, 2]` is the matrix shape and
% `"AQAAAAIAAAADAAAABAAAA==\n"` is the base64-encoded matrix content.
function [value] = encode_matrices(value)
    if isnumeric(value) && (any(size(value) > 1) || ~isreal(value))
        if ~isreal(value) && isinteger(value)
            value = double(value); % Numpy does not know complex
        % integers
        end
        if isreal(value)
            binary = typecast(value(:), 'uint8');
        else
            % convert [complex, complex] into [real, imag, real, imag]
            % since encodeBase64Chunked can only deal with real 1-D
            % arrays.
            tmp = zeros(numel(value)*2, 1);
            if isa(value, 'single')
                tmp = single(tmp);
            end
            tmp(1:2:end) = real(value(:));
            tmp(2:2:end) = imag(value(:));
            binary = typecast(tmp, 'uint8');
        end
        base64 = base64encode(binary);
        % translate Matlab class names into numpy dtypes
        if isa(value, 'double') && isreal(value)
            dtype = 'float64';
        elseif isa(value, 'double')
            dtype = 'complex128';
        elseif isa(value, 'single') && isreal(value)
            dtype = 'float32';
        elseif isa(value, 'single')
            dtype = 'complex64';
        elseif isinteger(value)
            dtype = class(value);
        else
            return % don't encode
        end
        value = {'__matrix__', dtype, size(value), base64};
    elseif iscell(value)
        for idx=1:numel(value)
            value{idx} = encode_matrices(value{idx});
        end
    elseif isstruct(value)
        keys = getfields(value);
        for idx=1:numel(value)
            for n=1:length(keys)
                key = keys{n};
                value(idx).(key) = encode_matrices(value(idx).(key));
            end
        end
    end
end

% recursively walk through value and decode all matrices
%
% The matrix `np.array([[1, 2], [3, 4]], dtype='int32')` would be
% encoded as
% `["__matrix__", "int32", [2, 2], "AQAAAAIAAAADAAAABAAAA==\n"]`
%
% where `"int32"` is the data type, `[2, 2]` is the matrix shape and
% `"AQAAAAIAAAADAAAABAAAA==\n"` is the base64-encoded matrix content.
function [value] = decode_matrices(value)
    if iscell(value) && numel(value) == 4 && strcmp(value{1}, '__matrix__')
        dtype = value{2};
        shape = cell2mat(value{3});
        if length(shape) == 1
           shape = [1 shape];
        end
        binary = base64decode(value{4});
        % translate numpy dtypes into Matlab class names
        if strcmp(dtype, 'complex128')
            value = typecast(binary, 'double')';
            value = value(1:2:end) + j*value(2:2:end);
        elseif strcmp(dtype, 'float64')
            value = typecast(binary, 'double')';
        elseif strcmp(dtype, 'complex64')
            value = typecast(binary, 'single')';
            value = value(1:2:end) + j*value(2:2:end);
        elseif strcmp(dtype, 'float32')
            value = typecast(binary, 'single')';
        else
            value = typecast(binary, dtype);
        end
        reshape(value, shape);
    elseif iscell(value)
        for idx=1:numel(value)
            value{idx} = decode_matrices(value{idx});
        end
    elseif isstruct(value)
        keys = getfields(value);
        for idx=1:numel(value)
            for n=1:length(keys)
                key = keys{n};
                value(idx).(key) = decode_matrices(value(idx).(key));
            end
        end
    end
end
