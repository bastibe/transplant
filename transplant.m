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
%    - 'set': saves the 'value' as a global variable called 'name'.
%    - 'get': retrieve the global variable 'name'.
%    - 'call': call function 'name' with 'args' and 'nargout'.
%
%    TRANSPLANT implements the following responses:
%    - 'ack': received message successfully.
%    - 'error': there was an error while handling the message.
%    - 'value': returns a value.
%
%    `set`, `get`, and `call` use a special encoding for matrices. See
%    `encode_matrices` and `decode_matrices` for more detail.

% (c) 2014 Bastian Bechtold

function transplant(url)

    % start 0MQ:
    messenger('open', url)

    proxied_objects = {};

    while 1 % main messaging loop

        msg = decode_values(receive_msg());

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
                        evalin('base', 'clear ans');
                        evalin('base', msg.string);
                        try
                            ans = evalin('base', 'ans');
                            send_value(ans);
                        catch err
                            send_ack();
                        end
                    end
                case 'set'
                    assignin('base', msg.name, msg.value);
                    send_ack();
                case 'get'
                    if isempty(evalin('base', ['who(''' msg.name ''')']))
                        error('TRANSPLANT:novariable' , ...
                            ['Undefined variable ''' msg.name '''.']);
                    end
                    value = evalin('base', msg.name);
                    send_value(value);
                case 'set_proxy'
                    obj = proxied_objects{msg.handle};
                    set(obj, msg.name, msg.value);
                    send_ack();
                case 'get_proxy'
                    obj = proxied_objects{msg.handle};
                    value = get(obj, msg.name);
                    send_value(value);
                case 'del_proxy'
                    proxied_objects{msg.handle} = [];
                case 'call'
                    fun = evalin('base', ['@' msg.name]);

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
                        [results{:}] = fun(msg.args{:});
                        if length(results) == 1
                            send_value(results{1});
                        else
                            send_value(results);
                        end
                    else
                        % try to get output from ans:
                        clear('ans');
                        fun(msg.args{:});
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

    function [out] = encode_object(object)
        if length(object) > 1
            out = {};
            for n=1:length(object)
                out{n} = encode_object(object(n));
            end
        else
            proxied_objects{length(proxied_objects)+1} = object;
            out = {'__proxy__', length(proxied_objects)};
        end
    end

    function [value] = encode_values(value)
        if isnumeric(value) && (any(size(value) > 1) || ~isreal(value))
            value = encode_matrix(value);
        elseif isobject(value)
            value = encode_object(value);
        elseif iscell(value)
            for idx=1:numel(value)
                value{idx} = encode_values(value{idx});
            end
        elseif isstruct(value)
            keys = fieldnames(value);
            for idx=1:numel(value)
                for n=1:length(keys)
                    key = keys{n};
                    value(idx).(key) = encode_values(value(idx).(key));
                end
            end
        end
    end

    function [value] = decode_values(value)
        if iscell(value) && numel(value) == 4 && strcmp(value{1}, '__matrix__')
            value = decode_matrix(value);
        elseif iscell(value) && numel(value) == 2 && strcmp(value{1}, '__proxy__')
            value = proxied_objects{value{2}};
        elseif iscell(value)
            for idx=1:numel(value)
                value{idx} = decode_values(value{idx});
            end
        elseif isstruct(value)
            keys = fieldnames(value);
            for idx=1:numel(value)
                for n=1:length(keys)
                    key = keys{n};
                    value(idx).(key) = decode_values(value(idx).(key));
                end
            end
        end
    end

    % Send a message that contains a value
    function send_value(value)
        msg.value = encode_values(value);
        send_msg('value', msg);
    end

    % Wait for and receive a message
    function msg = receive_msg()
        blob = messenger('receive');
        msg = decode_values(parsejson(blob));
    end

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

% The matrix `np.array([[1, 2], [3, 4]], dtype='int32')` would be
% encoded as
% `["__matrix__", "int32", [2, 2], "AQAAAAIAAAADAAAABAAAA==\n"]`
%
% where `"int32"` is the data type, `[2, 2]` is the matrix shape and
% `"AQAAAAIAAAADAAAABAAAA==\n"` is the base64-encoded matrix content.
function [value] = encode_matrix(value)
    if ~isreal(value) && isinteger(value)
        value = double(value); % Numpy does not know complex
    end
    if isreal(value)
        % convert column-major (FORTRAN, Matlab) to
        % row-major (C, Python)
        value = permute(value, length(size(value)):-1:1);
        binary = typecast(value(:), 'uint8');
    else
        % convert [complex, complex] into [real, imag, real, imag]
        % since encodeBase64Chunked can only deal with real 1-D
        % arrays.
        tmp = zeros(numel(value)*2, 1);
        if isa(value, 'single')
            tmp = single(tmp);
        end
        value = permute(value, length(size(value)):-1:1);
        tmp(1:2:end) = real(value(:));
        tmp(2:2:end) = imag(value(:));
        binary = typecast(tmp, 'uint8');
    end
    if islogical(value)
        % convert logicals (bool) into one-byte-per-bit
        binary = cast(value,'uint8');
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
    elseif isa(value, 'logical')
        dtype = 'bool';
    elseif isinteger(value)
        dtype = class(value);
    else
        return % don't encode
    end
    % save as row-major (C, Python)
    value = {'__matrix__', dtype, fliplr(size(value)), base64};
end

% The matrix `np.array([[1, 2], [3, 4]], dtype='int32')` would be
% encoded as
% `["__matrix__", "int32", [2, 2], "AQAAAAIAAAADAAAABAAAA==\n"]`
%
% where `"int32"` is the data type, `[2, 2]` is the matrix shape and
% `"AQAAAAIAAAADAAAABAAAA==\n"` is the base64-encoded matrix content.
function [value] = decode_matrix(value)
    dtype = value{2};
    shape = cell2mat(value{3});
    if length(shape) == 1
        shape = [1 shape];
    end
    binary = base64decode(value{4});
    % translate numpy dtypes into Matlab class names
    if strcmp(dtype, 'complex128')
        value = typecast(binary, 'double')';
        value = value(1:2:end) + 1i*value(2:2:end);
    elseif strcmp(dtype, 'float64')
        value = typecast(binary, 'double')';
    elseif strcmp(dtype, 'complex64')
        value = typecast(binary, 'single')';
        value = value(1:2:end) + 1i*value(2:2:end);
    elseif strcmp(dtype, 'float32')
        value = typecast(binary, 'single')';
    elseif strcmp(dtype, 'bool')
        value = logical(binary);
    else
        value = typecast(binary, dtype);
    end
    % convert row-major (C, Python) to column-major (FORTRAN, Matlab)
    value = reshape(value, fliplr(shape));
    value = permute(value, length(shape):-1:1);
end
