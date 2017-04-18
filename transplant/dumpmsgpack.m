%DUMPMSGPACK dumps Matlab data structures as a msgpack data
% DUMPMSGPACK(DATA)
%    recursively walks through DATA and creates a msgpack byte buffer from it.
%    - strings are converted to strings
%    - scalars are converted to numbers
%    - logicals are converted to `true` and `false`
%    - arrays are converted to arrays of numbers
%    - matrices are converted to arrays of arrays of numbers
%    - empty matrices are converted to nil
%    - cell arrays are converted to arrays
%    - cell matrices are converted to arrays of arrays
%    - struct arrays are converted to arrays of maps
%    - structs and container.Maps are converted to maps
%    - function handles and matlab objects will raise an error.
%
%    There is no way of encoding bins or exts

% (c) 2016 Bastian Bechtold
% This code is licensed under the BSD 3-clause license

function msgpack = dumpmsgpack(data)
    msgpack = dump(data);
    % collect all parts in a cell array to avoid frequent uint8
    % concatenations.
    msgpack = [msgpack{:}];
end

function msgpack = dump(data)
    % convert numeric matrices to cell matrices since msgpack doesn't know matrices
    if (isnumeric(data) || islogical(data)) && ...
       ~(isvector(data) && isa(data, 'uint8')) && ~isscalar(data) && ~isempty(data)
        data = num2cell(data);
    end
    % convert character matrices to cell of strings or cell matrices
    if ischar(data) && ~(isvector(data)||isempty(data)) && ndims(data) == 2
        data = cellstr(data);
    elseif ischar(data) && ~isvector(data)
        data = num2cell(data);
    end
    % convert struct arrays to cell of structs
    if isstruct(data) && ~isscalar(data)
        data = num2cell(data);
    end
    % standardize on always using maps instead of structs
    if isstruct(data)
        if ~isempty(fieldnames(data))
            data = containers.Map(fieldnames(data), struct2cell(data));
        else
            data = containers.Map();
        end
    end

    if isnumeric(data) && isempty(data)
        msgpack = {uint8(192)}; % encode nil
    elseif isa(data, 'uint8') && numel(data) > 1
        msgpack = dumpbin(data);
    elseif islogical(data)
        if data
            msgpack = {uint8(195)}; % encode true
        else
            msgpack = {uint8(194)}; % encode false
        end
    elseif isinteger(data)
        msgpack = {dumpinteger(data)};
    elseif isnumeric(data)
        msgpack = {dumpfloat(data)};
    elseif ischar(data)
        msgpack = dumpstring(data);
    elseif iscell(data)
        msgpack = dumpcell(data);
    elseif isa(data, 'containers.Map')
        msgpack = dumpmap(data);
    else
        error('transplant:dumpmsgpack:unknowntype', ...
              ['Unknown type "' class(data) '"']);
    end
end

function bytes = scalar2bytes(value)
    % reverse byte order to convert from little endian to big endian
    bytes = typecast(swapbytes(value), 'uint8');
end

function msgpack = dumpinteger(value)
    % if the values are small enough, encode as fixnum:
    if value >= 0 && value < 128
        % first bit is 0, last 7 bits are value
        msgpack = uint8(value);
        return
    elseif value < 0 && value > -32
        % first three bits are 111, last 5 bytes are value
        msgpack = typecast(int8(value), 'uint8');
        return
    end

    % otherwise, encode by type:
    switch class(value)
        case 'uint8' % encode as uint8
            msgpack = uint8([204, value]);
        case 'uint16' % encode as uint16
            msgpack = uint8([205, scalar2bytes(value)]);
        case 'uint32' % encode as uint32
            msgpack = uint8([206, scalar2bytes(value)]);
        case 'uint64' % encode as uint64
            msgpack = uint8([207, scalar2bytes(value)]);
        case 'int8' % encode as int8
            msgpack = uint8([208, scalar2bytes(value)]);
        case 'int16' % encode as int16
            msgpack = uint8([209, scalar2bytes(value)]);
        case 'int32' % encode as int32
            msgpack = uint8([210, scalar2bytes(value)]);
        case 'int64' % encode as int64
            msgpack = uint8([211, scalar2bytes(value)]);
        otherwise
            error('transplant:dumpmsgpack:unknowninteger', ...
                  ['Unknown integer type "' class(value) '"']);
    end
end

function msgpack = dumpfloat(value)
    % do double first, as it is more common in Matlab
    if isa(value, 'double') % encode as float64
        msgpack = uint8([203, scalar2bytes(value)]);
    elseif isa(value, 'single') % encode as float32
        msgpack = uint8([202, scalar2bytes(value)]);
    else
        error('transplant:dumpmsgpack:unknownfloat', ...
              ['Unknown float type "' class(value) '"']);
    end
end

function msgpack = dumpstring(value)
    b10100000 = 160;

    encoded = unicode2native(value, 'utf-8');
    len = length(encoded);

    if len < 32 % encode as fixint:
        % first three bits are 101, last 5 are length:
        msgpack = {uint8(bitor(len, b10100000)), encoded};
    elseif len < 256 % encode as str8
        msgpack = {uint8([217, len]), encoded};
    elseif len < 2^16 % encode as str16
        msgpack = {uint8(218), scalar2bytes(uint16(len)), encoded};
    elseif len < 2^32 % encode as str32
        msgpack = {uint8(219), scalar2bytes(uint32(len)), encoded};
    else
        error('transplant:dumpmsgpack:stringtoolong', ...
              sprintf('String is too long (%d bytes)', len));
    end
end

function msgpack = dumpbin(value)
    len = length(value);
    if len < 256 % encode as bin8
        msgpack = {uint8([196, len]) value(:)'};
    elseif len < 2^16 % encode as bin16
        msgpack = {uint8(197), scalar2bytes(uint16(len)), value(:)'};
    elseif len < 2^32 % encode as bin32
        msgpack = {uint8(198), scalar2bytes(uint32(len)), value(:)'};
    else
        error('transplant:dumpmsgpack:bintoolong', ...
              sprintf('Bin is too long (%d bytes)', len));
    end
end

function msgpack = dumpcell(value)
    b10010000 = 144;

    % Msgpack can only work with 1D-arrays. Thus, Convert a
    % multidimensional AxBxC array into a cell-of-cell-of-cell, so
    % that indexing value{a, b, c} becomes value{a}{b}{c}.
    if length(value) ~= prod(size(value))
        for n=ndims(value):-1:2
            value = cellfun(@squeeze, num2cell(value, n), ...
                            'uniformoutput', false);
        end
    end

    % write header
    len = length(value);
    if len < 16 % encode as fixarray
        % first four bits are 1001, last 4 are length
        msgpack = {uint8(bitor(len, b10010000))};
    elseif len < 2^16 % encode as array16
        msgpack = {uint8(220), scalar2bytes(uint16(len))};
    elseif len < 2^32 % encode as array32
        msgpack = {uint8(221), scalar2bytes(uint32(len))};
    else
        error('transplant:dumpmsgpack:arraytoolong', ...
              sprintf('Array is too long (%d elements)', len));
    end

    % write values
    for n=1:len
        stuff = dump(value{n});
        msgpack = [msgpack stuff{:}];
    end
end

function msgpack = dumpmap(value)
    b10000000 = 128;

    % write header
    len = length(value);
    if len < 16 % encode as fixmap
        % first four bits are 1000, last 4 are length
        msgpack = {uint8(bitor(len, b10000000))};
    elseif len < 2^16 % encode as map16
        msgpack = {uint8(222), scalar2bytes(uint16(len))};
    elseif len < 2^32 % encode as map32
        msgpack = {uint8(223), scalar2bytes(uint32(len))};
    else
        error('transplant:dumpmsgpack:maptoolong', ...
              sprintf('Map is too long (%d elements)', len));
    end

    % write key-value pairs
    keys = value.keys();
    values = value.values();
    for n=1:len
        keystuff = dump(keys{n});
        valuestuff = dump(values{n});
        msgpack = [msgpack, keystuff{:}, valuestuff{:}];
    end
end
