%PARSEJSON parses a json string into Matlab data structures
% PARSEJSON(STRING)
%    reads STRING as JSON data, and creates Matlab data structures
%    from it.
%    - strings are converted to strings
%    - numbers are converted to doubles
%    - true, false are converted to logical 1, 0
%    - null is converted to []
%    - arrays are converted to cell arrays
%    - objects are converted to structs
%
%    In contrast to many other JSON parsers, this one does not try to
%    convert all-numeric arrays into matrices. Thus, nested data
%    structures are encoded correctly.
%
%    This is a complete implementation of the JSON spec, and invalid
%    data will generally throw errors.

% (c) 2014 Bastian Bechtold

function [obj] = parsejson(json)
    json = unescape_strings(json);
    str_tokens = tokenize_strings(json);
    num_tokens = tokenize_numbers(json);
    idx = next(json, 1);
    [obj, idx] = value(json, idx, str_tokens, num_tokens);
    idx = next(json, idx);
    if idx ~= length(json)+1
        error('JSON:parse:multipletoplevel', ...
              ['more than one top-level item (char ' num2str(idx) ')']);
    end
end

% advances idx to the first non-whitespace
function [idx] = next(json, idx)
    while idx <= length(json) && any(json(idx) == sprintf(' \t\r\n'))
        idx = idx+1;
    end
end

% dispatches based on JSON type
function [obj, idx] = value(json, idx, str_tokens, num_tokens)
    char = json(idx);
    if char == '"'
        [obj, idx] = string(json, idx, str_tokens);
    elseif any(char == '0123456789-')
        [obj, idx] = number(json, idx, num_tokens);
    elseif char == '{'
        [obj, idx] = object(json, idx, str_tokens, num_tokens);
    elseif char == '['
        [obj, idx] = array(json, idx, str_tokens, num_tokens);
    elseif char == 't'
        [obj, idx] = true(json, idx);
    elseif char == 'f'
        [obj, idx] = false(json, idx);
    elseif char == 'n'
        [obj, idx] = null(json, idx);
    else
        error('JSON:parse:unknowntype', ...
              ['unrecognized character "' char ...
               '" (char ' num2str(idx) ')']);
    end
end

% parses a string and advances idx
function [obj, idx] = string(json, idx, str_tokens)
    stop = str_tokens(idx);
    obj = json(idx+1:stop-1);
    obj = strrep(obj, '\"', '"');
    obj = strrep(obj, '\\', '\');
    idx = stop+1;
end

function tokens = tokenize_strings(s)
    [string_start string_end] = regexp(s, '".*?(?<!\\)"');
    tokens = sparse(string_start, ones(1, length(string_start)), string_end);
end

function s = unescape_strings(s)
    s = regexprep(s, '(?<!\\)\\[trnfb]', '${sprintf($0)}');
    s = strrep(s, '\/', '/');
    s = regexprep(s, '(?<!\\)\\u([0-9a-fA-F]{4})', '${char(hex2dec($1))}');
end

function tokens = tokenize_numbers(s)
    [string_start string_end] = regexp(s, '-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?');
    tokens = sparse(string_start, ones(1, length(string_start)), string_end);
end

% parses a number and advances idx
function [obj, idx] = number(json, idx, num_tokens)
    stop = num_tokens(idx);
    obj = str2num(json(idx:stop));
    idx = stop+1;
end

% parses an object and advances idx
function [obj, idx] = object(json, idx, str_tokens, num_tokens)
    start = idx;
    obj = struct();
    if json(idx) ~= '{'
        error('JSON:parse:object:nobrace', ...
              ['object must start with "{" (char ' num2str(idx) ')']);
    end
    idx = idx+1;
    idx = next(json, idx);
    if json(idx) ~= '}'
        while 1
            if json(idx) ~= '"'
                error('JSON:parse:string:noquote', ...
                      ['string must start with " (char ' num2str(idx) ')']);
            end
            [key, idx] = string(json, idx, str_tokens);
            idx = next(json, idx);
            if json(idx) == ':'
                idx = idx+1;
            else
                error('JSON:parse:object:nocolon', ...
                      ['no ":" after object key in "' json(start:idx-1) ...
                       '" (char ' num2str(idx) ')']);
            end
            idx = next(json, idx);
            [val, idx] = value(json, idx, str_tokens, num_tokens);
            obj.(genvarname(key)) = val; % make sure it's a valid name
            idx = next(json, idx);
            if json(idx) == ','
                idx = idx+1;
                idx = next(json, idx);
                continue
            elseif json(idx) == '}'
                break
            else
                error('JSON:parse:object:unknownseparator', ...
                      ['no "," or "}" after entry in "' json(start:idx-1) ...
                       '" (char ' num2str(idx) ')']);
            end
        end
    end
    idx = idx+1;
end

% parses an array and advances idx
function [obj, idx] = array(json, idx, str_tokens, num_tokens)
    start = idx;
    obj = {};
    if json(idx) ~= '['
        error('JSON:parse:array:nobracket', ...
              ['array must start with "[" (char ' num2str(idx) ')']);
    end
    idx = idx+1;
    idx = next(json, idx);
    if json(idx) ~= ']'
        while 1
            [val, idx] = value(json, idx, str_tokens, num_tokens);
            obj = [obj, {val}];
            idx = next(json, idx);
            if json(idx) == ','
                idx = idx+1;
                idx = next(json, idx);
                continue
            elseif json(idx) == ']'
                break
            else
                error('JSON:parse:array:unknownseparator', ...
                      ['no "," or "]" after entry in "' json(start:idx-1) ...
                       '" (char ' num2str(idx) ')']);
            end
        end
    end
    idx = idx+1;
end

% parses true and advances idx
function [obj, idx] = true(json, idx)
    start = idx;
    if length(json) < idx+3
        error('JSON:parse:true:notenoughdata', ...
              ['not enough data for "true" in "' json(start:end) ...
               '" (char ' num2str(start) ')']);
    end
    if json(idx:idx+3) == 'true'
        obj = logical(1);
        idx = idx+4;
    else
        error('JSON:parse:true:nottrue', ...
              ['not "true": "' json(start:idx+3) ...
               '" (char ' num2str(idx) ')']);
    end
end

% parses false and advances idx
function [obj, idx] = false(json, idx)
    start = idx;
    if length(json) < idx+4
        error('JSON:parse:false:notenoughdata', ...
              ['not enough data for "false" in "' json(start:end) ...
               '" (char ' num2str(start) ')']);
    end
    if json(idx:idx+4) == 'false'
        obj = logical(0);
        idx = idx+5;
    else
        error('JSON:parse:false:notfalse', ...
              ['not "false": "' json(start:idx+4) ...
               '" (char ' num2str(idx) ')']);
    end
end

% parses null and advances idx
function [obj, idx] = null(json, idx)
    start = idx;
    if length(json) < idx+3
        error('JSON:parse:null:notenoughdata', ...
              ['not enough data for "null" in "' json(start:end) ...
               '" (char ' num2str(start) ')']);
    end
    if json(idx:idx+3) == 'null'
        obj = [];
        idx = idx+4;
    else
        error('JSON:parse:null:notnull', ...
              ['not "null": "' json(start:idx+3) ...
               '" (char ' num2str(idx) ')']);
    end
end
