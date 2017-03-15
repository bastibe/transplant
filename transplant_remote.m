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

function transplant_remote(msgformat, url, is_zombie)
    % this must be persistent to survive a SIGINT:
    persistent proxied_objects is_receiving should_die messenger

    % wait for user interaction
    waitforAllGUIClose = false;

    % since the onCleanup prevents direct exit, quit here after revival before
    % a new onCleanup is created:
    if should_die
        quit('force')
    end

    try
        if nargin == 2
            % normal startup
            messenger = ZMQ(url);
            proxied_objects = {};
            is_receiving = false;
            should_die = false;
        elseif nargin > 2 && is_zombie && ~is_receiving
            % SIGINT has killed transplant_remote, but onCleanup has revived it
            % At this point, neither lasterror nor MException.last is available,
            % so we don't actually know where we were killed.
            send_ack();
        elseif nargin > 2 && is_zombie && is_receiving
            % Sometimes, functions return normally, then trow a delayed error after
            % they return. In that case, we crash within receive_msg. To recover,
            % just continue receiving as if nothing had happened.
        else
            % no idea what happened. I don't want to live any more.
            return
        end
    catch
        return
    end

    % make sure that transplant doesn't crash on SIGINT
    zombie = onCleanup(@()transplant_remote(msgformat, url, true));

    while 1 % main messaging loop

        try
            is_receiving = true;
            msg = receive_msg();
            is_receiving = false;
            msg = decode_values(msg);
            switch msg('type')
                case 'die' % exit matlab
                    send_ack();
                    should_die = true;
                    % At this point, we can't just quit, since onCleanup *will*
                    % revive us as a zombie. Instead, we mark ourselves as
                    % suicidial, and return. This will quit Matlab directly
                    % after revival, before the next onCleanup is created.
                    return
                case 'set_global' % save msg.value as a global variable
                    assignin('base', msg('name'), msg('value'));
                    send_ack();
                case 'get_global' % retrieve the value of a global variable
                    % simply evalin('base', msg.name) would call functions,
                    % so that can't be used.
                    existance = evalin('base', ['exist(''' msg('name') ''')']);
                    % exist doesn't find methods, though.
                    existance = existance | any(which(msg('name')));
                    % value does not exist:
                    if ~existance
                        error('TRANSPLANT:novariable' , ...
                              ['Undefined variable ''' msg('name') '''.']);
                    % value is a function or method:
                    elseif any(existance == [2, 3, 5, 6]) | any(which(msg('name')))
                        value = str2func(msg('name'));
                    else
                        value = evalin('base', msg('name'));
                    end
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
                        % nargout fails if fun is a method:
                        try
                            resultsize = nargout(fun);
                        catch
                            resultsize = -1;
                        end
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
                    
                    % always draw objects
                    drawnow
                    % wait for user interaction
                    if waitforAllGUIClose
                        hFigure = get(0,'child');
                        while ~isempty(hFigure)
                            waitfor(hFigure(1))
                            hFigure = get(0,'child');
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
        if strcmp(msgformat, 'msgpack')
            messenger.send(dumpmsgpack(message));
        else
            str = dumpjson(message);
            messenger.send(unicode2native(str, 'utf-8'));
        end
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
        % ignore stack frames from the last restart
        is_cleanup = @(s)~isempty(strfind(s.name, 'onCleanup.delete'));
        cleanup_idx = find(arrayfun(is_cleanup, err.stack), 1);
        if ~isempty(cleanup_idx)
            message('stack') = err.stack([1:cleanup_idx-2]);
        else
            message('stack') = err.stack;
        end
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
        blob = messenger.receive();
        if strcmp(msgformat, 'msgpack')
            message = decode_values(parsemsgpack(blob));
        else
            str = native2unicode(blob, 'utf-8');
            message = decode_values(parsejson(str));
        end
    end

    % recursively step through value and encode all occurrences of
    % matrices, objects and functions as special cell arrays.
    function [value] = encode_values(value)
        if issparse(value)
            value = encode_sparse_matrix(value);
        elseif (isnumeric(value) && numel(value) ~= 0 && ...
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
            elseif special && len == 5 && strcmp(value{1}, '__sparse__')
                value = decode_sparse_matrix(value);
            elseif special && len == 2 && strcmp(value{1}, '__object__')
                value = proxied_objects{value{2}};
            elseif special && len == 2 && strcmp(value{1}, '__function__')
                if ischar(value{2})
                    value = str2func(value{2});
                else
                    value = proxied_objects{value(2)};
                end
            elseif special && len == 2 && strcmp(value{1}, '__struct__')
                % convert containers.map to struct
                out = struct();
                for key=value{2}.keys()
                    structkey = matlab.lang.makeValidName(key{1});
                    out.(structkey) = decode_values(value{2}(key{1}));
                end
                value = out;
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

    % The matrix `int32([1 2; 3 4])` would be encoded as
    % `{'__matrix__', 'int32', [2, 2], 'AQAAAAIAAAADAAAABAAAA==\n'}`
    %
    % where `'int32'` is the data type, `[2, 2]` is the matrix shape and
    % `'AQAAAAIAAAADAAAABAAAA==\n"'` is the base64-encoded matrix content.
    function [value] = encode_matrix(value)
        if ~isreal(value) && isinteger(value)
            value = double(value); % Numpy does not know complex int
        end
        % convert column-major (Matlab, FORTRAN) to row-major (C, Python)
        value = permute(value, length(size(value)):-1:1);
        % convert to uint8 1-D array
        if isreal(value)
            binary = typecast(value(:), 'uint8');
        else
            % convert [complex, complex] into [real, imag, real, imag]
            tmp = zeros(numel(value)*2, 1);
            if isa(value, 'single')
                tmp = single(tmp);
            end
            tmp(1:2:end) = real(value(:));
            tmp(2:2:end) = imag(value(:));
            binary = typecast(tmp, 'uint8');
        end
        if islogical(value)
            % convert logicals (bool) into one-byte-per-bit
            binary = cast(value, 'uint8');
        end
        % not all typecasts return column vectors, so use (:)
        if strcmp(msgformat, 'json')
            binary = base64encode(binary(:));
        else
            binary = binary(:);
        end
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
        value = {'__matrix__', dtype, fliplr(size(value)), binary};
    end

    % The matrix `int32([1 2; 3 4])` would be encoded as
    % `{'__matrix__', 'int32', [2, 2], 'AQAAAAIAAAADAAAABAAAA==\n'}`
    %
    % where `'int32'` is the data type, `[2, 2]` is the matrix shape and
    % `'AQAAAAIAAAADAAAABAAAA==\n'` is the base64-encoded matrix content.
    function [value] = decode_matrix(value)
        dtype = value{2};
        % make sure shape is a double array even if its elements are
        % less than double:
        shape = cellfun(@double, value{3});
        if length(shape) == 0
            shape = [1 1];
        elseif length(shape) == 1
            shape = [1 shape];
        end
        if ischar(value{4})
            binary = base64decode(value{4});
        else
            binary = value{4};
        end
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
        % convert row-major (C, Python) to column-major (Matlab, FORTRAN)
        value = reshape(value, fliplr(shape));
        value = permute(value, length(shape):-1:1);
    end

    % Encode a sparse matrix as a special list.
    % A sparse matrix `[[2, 0], [0, 3]]` would be encoded as
    % `["__sparse__", [2, 2],
    %   <matrix for row indices [0, 1]>,
    %   <matrix for row indices [1, 0]>,
    %   <matrix for values [2, 3]>]`,
    % where each `<matrix>` is encoded according `encode_matrix` and `[2,
    % 2]` is the data shape.
    function [value] = encode_sparse_matrix(value)
        [row, col, data] = find(value);
        if numel(data) > 0
            value = {'__sparse__', fliplr(size(value)), ...
                     encode_matrix(row-1), encode_matrix(col-1), ...
                     encode_matrix(data)};
        else
            % don't try to encode empty matrices as matrices
            value = {'__sparse__', fliplr(size(value)), [], [], []};
        end
    end

    % Decode a special list to a sparse matrix.
    % A sparse matrix
    % `["__sparse__", [2, 2],
    %   <matrix for row indices [0, 1]>,
    %   <matrix for row indices [1, 0]>,
    %   <matrix for values [2, 3]>]`,
    % where each `<matrix>` is encoded according `encode_matrix` would be
    % decoded as `[[2, 0], [0, 3]]`.
    function [value] = decode_sparse_matrix(value)
        % make sure shape is a double array even if its elements are
        % less than double:
        shape = cellfun(@double, value{2});
        if length(shape) == 0
            shape = [1 1];
        elseif length(shape) == 1
            shape = [1 shape];
        end
        row = double(decode_matrix(value{3}));
        col = double(decode_matrix(value{4}));
        data = double(decode_matrix(value{5}));
        value = sparse(row+1, col+1, data, shape(1), shape(2));
    end

end
