%DUMPJSON dumps Matlab data as a JSON string
% DUMPJSON(DATA)
%    recursively walks through DATA and creates a JSON string from it.
%    - strings are converted to strings with escape sequences
%    - scalars are converted to numbers
%    - logicals are converted to `true` and `false`
%    - arrays are converted to arrays of numbers
%    - matrices are converted to arrays of arrays of numbers
%    - empty matrices are converted to null
%    - cell arrays are converted to arrays
%    - cell matrices are converted to arrays of arrays
%    - structs are converted to objects
%    - struct arrays are converted to arrays of objects
%    - function handles and matlab objects will raise an error.
%
%    In contrast to may other JSON parsers, this one does not try
%    special-case numeric matrices. Also, this correctly transplates
%    escape sequences in strings.

% (c) 2014 Bastian Bechtold
% This code is licensed under the BSD 3-clause license

function [json] = dumpjson(data)
    if numel(data) > 10000
       warning('JSON:dump:toomuchdata', ...
               'dumping big data structures to JSON might take a while')
    end
    json = value(data);
end

% dispatches based on data type
function [json] = value(data)
    try
        if any(size(data) == 0)
            json = null(data);
        elseif ndims(data) > 2 || all(size(data) > 1)
            json = multidim(data);
        else
            if ischar(data)
                json = string(data);
            elseif iscell(data)
                json = cell(data);
            elseif isa(data, 'containers.Map')
                % this must come before the next branch, since Maps
                % are any((data) > 1) as well.
                json = map(data);
            elseif any(size(data) > 1)
                json = array(data);
            elseif isstruct(data)
                json = struct(data);
            elseif isscalar(data)
                if islogical(data)
                    json = logical(data);
                elseif isnumeric(data)
                    json = number(data);
                else
                    error();
                end
            else
                error();
            end
        end
    catch err
        error('JSON:dump:unknowntype', ...
              ['can''t encode ' char(data) ' (' class(data) ') as JSON']);
    end
end

% dumps a string value as a string
function [json] = string(data)
    data = strrep(data, '\', '\\');
    data = strrep(data, '"', '\"');
    data = strrep(data, '/', '\/');
    data = strrep(data, sprintf('\b'), '\b');
    data = strrep(data, sprintf('\f'), '\f');
    data = strrep(data, sprintf('\n'), '\n');
    data = strrep(data, sprintf('\r'), '\r');
    data = strrep(data, sprintf('\t'), '\t');
    % convert non-ASCII characters to `\uXXXX` sequences, where XXX is
    % the hex unicode codepoint of the character.
    data = regexprep(data, '([^\x00-\x7F])', '\\u${sprintf(''%04s'', dec2hex($1))}');
    json = sprintf('"%s"', data);
end

% dumps a numeric value as a number
function [json] = number(data)
    if isinteger(data)
        json = sprintf('%i', data);
    else
        json = sprintf('%.50g', data);
    end
end

% dumps a logical value as `true` or `false`
function [json] = logical(data)
    if data
        json = 'true';
    else
        json = 'false';
    end
end

% dumps an n-dimensional value as a cell array of (n-1)-D values
function [json] = multidim(data)
    % convert 2x3x4 into {1x3x4, 1x3x4}
    cell = num2cell(data, 2:(ndims(data)));
    % convert {1x3x4, 1x3x4} into {3x4, 3x4}
    for idx=1:length(cell)
        cell{idx} = shiftdim(cell{idx}, 1);
    end
    json = value(cell);
end

% dumps a one-dimensional array of values as an array
function [json] = array(data)
    json = '[';
    for idx=1:length(data)
        json = [json value(data(idx))];
        if idx < length(data)
            json = [json ','];
        end
    end
    json = [json ']'];
end

% dumps a one-dimensional cell array of values as an array
function [json] = cell(data)
    json = '[';
    for idx=1:length(data)
        json = [json value(data{idx})];
        if idx < length(data)
            json = [json ','];
        end
    end
    json = [json ']'];
end

% dumps a 0-dimensional container.Map as an object
function [json] = map(data)
    json = '{';
    keys = data.keys();
    for idx=1:length(keys)
        key = keys{idx};
        json = [json value(key) ':' value(data(key))];
        if idx < length(keys)
            json = [json ','];
        end
    end
    json = [json '}'];
end

% dumps a 0-dimensional struct as an object
function [json] = struct(data)
    json = '{';
    keys = fieldnames(data);
    for idx=1:length(keys)
        key = keys{idx};
        json = [json value(key) ':' value(data.(key))];
        if idx < length(keys)
            json = [json ','];
        end
    end
    json = [json '}'];
end

% dumps `null`
function [json] = null(~)
    json = 'null';
end
