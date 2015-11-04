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
%    - 'die': closes the 0MQ session and quits Matlab.
%    - 'set_global': saves the 'value' as a global variable called 'name'.
%    - 'get_global': retrieve the value of a global variable 'name'.
%    - 'set_proxy': saves the 'value' as a field called 'name' on cached
%                   object 'handle'.
%    - 'get_proxy': retrieves the field called 'name' on cached object
%                   'handle'.
%    - 'del_proxy': remove cached object 'handle'.
%    - 'call': call function 'name' with 'args' and 'nargout'.
%
%    TRANSPLANT implements the following responses:
%    - 'ack': received message successfully.
%    - 'error': there was an error while handling the message.
%    - 'value': returns a value.
%
%    To enable cross-language functions, objects and matrices, these are
%    encoded specially when transmitted between Python and Matlab:
%    - Matrices are encoded as {"__matrix__", ... }
%    - Functions are encoded as {"__function__", str2func(f) }
%    - Objects are encoded as {"__object__", handle }

% (c) 2014 Bastian Bechtold

function transplant_remote(url, is_zombie)
    % this must be persistent to survive a SIGINT:
    persistent proxied_objects
    persistent is_receiving
    if nargin == 1
        % normal startup
        messenger('open', url); % start 0MQ
        proxied_objects = {};
    elseif nargin > 1 && is_zombie && ~is_receiving
        % SIGINT has killed transplant_remote, but onCleanup has revived it
        % At this point, neither lasterror nor MException.last is available,
        % so we don't actually know where we were killed.
        send_ack();
    elseif nargin > 1 && is_zombie && is_receiving
        % Sometimes, functions return normally, then trow a delayed error after
        % they return. In that case, we crash within receive_msg. To recover,
        % just continue receiving as if nothing had happened.
    else
        % no idea what happened. I don't want to live any more.
        exit();
    end

    % make sure that transplant doesn't crash on SIGINT
    zombie = onCleanup(@()transplant_remote(url, true));

    while 1 % main messaging loop

        try
            is_receiving = true;
            msg = receive_msg();
            is_receiving = false;
            msg = decode_values(msg);
            switch msg('type')
                case 'die' % exit matlab
                    send_ack();
                    quit;
                case 'set_global' % save msg.value as a global variable
                    assignin('base', msg('name'), msg('value'));
                    send_ack();
                case 'get_global' % retrieve the value of a global variable
                    % simply evalin('base', msg.name) would call functions,
                    % so that can't be used.
                    existance = evalin('base', ['exist(''' msg('name') ''')']);
                    % value does not exist:
                    if existance == 0
                        error('TRANSPLANT:novariable' , ...
                              ['Undefined variable ''' msg('name') '''.']);
                    % value is a function:
                    elseif any(existance == [2, 3, 5, 6])
                        value = str2func(msg('name'));
                    else
                        value = evalin('base', msg('name'));
                    end
                    send_value(value);
                case 'set_proxy' % set field value of a cached object
                    obj = proxied_objects{msg('handle')};
                    set(obj, msg.name, msg('value'));
                    send_ack();
                case 'get_proxy' % retrieve field value of a cached object
                    obj = proxied_objects{msg('handle')};
                    value = get(obj, msg('name'));
                    send_value(value);
                case 'del_proxy' % invalidate cached object
                    proxied_objects{msg('handle')} = [];
                    send_ack();
                case 'call' % call a function
                    fun = str2func(msg('name'));

                    % get the number of output arguments
                    if isKey(msg, 'nargout') && msg('nargout') >= 0
                        resultsize = msg('nargout');
                    else
                        resultsize = nargout(fun);
                    end

                    if resultsize > 0
                        % call the function with the given number of
                        % output arguments:
                        results = cell(resultsize, 1);
                        args = msg('args');
                        [results{:}] = fun(args{:});
                        if length(results) == 1
                            send_value(results{1});
                        else
                            send_value(results);
                        end
                    else
                        % try to get output from ans:
                        clear('ans');
                        args = msg('args');
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

    % Send a message
    %
    % This is the base function for the specialized senders below
    function send_message(message_type, message)
        message('type') = message_type;
        messenger('send', dumpjson(message));
    end

    % Send an acknowledgement message
    function send_ack()
        send_message('ack', containers.Map());
    end

    % Send an error message
    function send_error(err)
        message = containers.Map();
        message('identifier') = err.identifier;
        message('message') = err.message;
        message('stack') = err.stack;
        send_message('error', message);
    end

    % Send a message that contains a value
    function send_value(value)
        message = containers.Map();
        message('value') = encode_values(value);
        send_message('value', message);
    end

    % Wait for and receive a message
    function message = receive_msg()
        blob = messenger('receive');
        message = decode_values(parsejson(blob));
    end

    % recursively step through value and encode all occurrences of
    % matrices, objects and functions as special cell arrays.
    function [value] = encode_values(value)
        if (isnumeric(value) && numel(value) ~= 0 && ...
            (numel(value) > 1 || ~isreal(value)))
            value = encode_matrix(value);
        elseif isa(value, 'containers.Map')
            % containers.Map is a handle object, so we need to create a
            % new copy her in order to not change the original object.
            out = containers.Map();
            for key=value.keys()
                out(key{1}) = encode_values(value(key{1}));
            end
            value = out;
        elseif isobject(value)
            value = encode_object(value);
        elseif isa(value, 'function_handle')
            value = {'__function__', func2str(value)};
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

    % recursively step through value and decode all special cell arrays
    % that contain matrices, objects, or functions.
    function [value] = decode_values(value)
        if iscell(value)
            len = numel(value);
            special = len > 0 && ischar(value{1});
            if special && len == 4 && strcmp(value{1}, '__matrix__')
                value = decode_matrix(value);
            elseif special && len == 2 && strcmp(value{1}, '__object__')
                value = proxied_objects{value{2}};
            elseif special && len == 2 && strcmp(value{1}, '__function__')
                value = str2func(value{2});
            else
                for idx=1:numel(value)
                    value{idx} = decode_values(value{idx});
                end
            end
        elseif isa(value, 'containers.Map')
            for key=value.keys()
                value(key{1}) = decode_values(value(key{1}));
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

    % Objects are cached, and they are encoded as special cell arrays
    % `{"__object__", cache_index}`
    function [out] = encode_object(object)
        if length(object) > 1
            out = {};
            for n=1:length(object)
                out{n} = encode_object(object(n));
            end
        else
            first_empty_entry = find(cellfun('isempty', proxied_objects), 1);
            if isempty(first_empty_entry)
                first_empty_entry = length(proxied_objects)+1;
            end
            proxied_objects{first_empty_entry} = object;
            out = {'__object__', first_empty_entry};
        end
    end

end

% The matrix `int32([1 2; 3 4])` would be encoded as
% `{'__matrix__', 'int32', [2, 2], 'AQAAAAIAAAADAAAABAAAA==\n'}`
%
% where `'int32'` is the data type, `[2, 2]` is the matrix shape and
% `'AQAAAAIAAAADAAAABAAAA==\n"'` is the base64-encoded matrix content.
function [value] = encode_matrix(value)
    if ~isreal(value) && isinteger(value)
        value = double(value); % Numpy does not know complex int
    end
    % convert to uint8 1-D array in row-major order
    if length(size(value)) > 2
        row_major_order = [2, 1, 3:length(size(value))];
    else
        row_major_order = [2, 1];
    end
    if isreal(value)
        value = permute(value, row_major_order);
        binary = typecast(value(:), 'uint8');
    else
        % convert [complex, complex] into [real, imag, real, imag]
        tmp = zeros(numel(value)*2, 1);
        if isa(value, 'single')
            tmp = single(tmp);
        end
        value = permute(value, row_major_order);
        tmp(1:2:end) = real(value(:));
        tmp(2:2:end) = imag(value(:));
        binary = typecast(tmp, 'uint8');
    end
    if islogical(value)
        % convert logicals (bool) into one-byte-per-bit
        value = permute(value, row_major_order);
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

% The matrix `int32([1 2; 3 4])` would be encoded as
% `{'__matrix__', 'int32', [2, 2], 'AQAAAAIAAAADAAAABAAAA==\n'}`
%
% where `'int32'` is the data type, `[2, 2]` is the matrix shape and
% `'AQAAAAIAAAADAAAABAAAA==\n'` is the base64-encoded matrix content.
function [value] = decode_matrix(value)
    dtype = value{2};
    shape = cell2mat(value{3});
    if length(shape) == 0
        shape = [1 1];
    elseif length(shape) == 1
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
    % convert row-major (C, Python) to whatever the hell Matlab thinks
    % is a proper order of things.
    value = reshape(value, fliplr(shape));
    if length(shape) > 2
        value = permute(value, [2 1 3:length(shape)]);
    else
        value = permute(value, [2 1]);
    end
end
