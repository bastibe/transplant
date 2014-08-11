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
    idx = next(json, 1);
    [obj, idx] = value(json, idx);
    idx = next(json, idx);
    if idx ~= length(json)+1
        error(['malformed json (char ' num2str(idx) ')']);
    end
end

% advances idx to the first non-whitespace
function [idx] = next(json, idx)
    while idx <= length(json) && any(json(idx) == sprintf(' \t\r\n'))
        idx = idx+1;
    end
end

% dispatches based on JSON type
function [obj, idx] = value(json, idx)
    char = json(idx);
    if char == '"'
        [obj, idx] = string(json, idx);
    elseif any(char == '0123456789-')
        [obj, idx] = number(json, idx);
    elseif char == '{'
        [obj, idx] = object(json, idx);
    elseif char == '['
        [obj, idx] = array(json, idx);
    elseif char == 't'
        [obj, idx] = true(json, idx);
    elseif char == 'f'
        [obj, idx] = false(json, idx);
    elseif char == 'n'
        [obj, idx] = null(json, idx);
    else
        error(['unrecognized character "' char ...
               '" (char ' num2str(idx) ')']);
    end
end

% parses a string and advances idx
function [obj, idx] = string(json, idx)
    obj = '';
    if json(idx) ~= '"'
        error(['string must start with " (char ' num2str(idx) ')']);
    end
    idx = idx+1;
    while json(idx) ~= '"'
        if json(idx) == '\'
            idx = idx+1;
            switch json(idx)
                case '"'
                    obj = [obj '"'];
                case '\'
                    obj = [obj '\'];
                case '/'
                    obj = [obj '/'];
                case 'b'
                    obj = [obj sprintf('\b')];
                case 'f'
                    obj = [obj sprintf('\f')];
                case 'n'
                    obj = [obj sprintf('\n')];
                case 'r'
                    obj = [obj sprintf('\r')];
                case 't'
                    obj = [obj sprintf('\t')];
                case 'u'
                    obj = [obj char(hex2dec(json(idx+1:idx+4)))];
                    idx = idx+4;
            end
        else
            obj = [obj json(idx)];
        end
        idx = idx+1;
    end
    idx = idx+1;
end

% parses a number and advances idx
function [obj, idx] = number(json, idx)
    start = idx;
    if getchar() == '-'
        idx = idx+1;
    end
    if getchar == '0'
        idx = idx+1;
    elseif any(getchar() == '123456789')
        idx = idx+1;
        digits();
    else
        error(['number ' json(start:idx-1) ' must start with digit' ...
               '(char ' num2str(start) ')']);
    end
    if getchar() == '.'
        idx = idx+1;
        if any(getchar() == '0123456789')
            idx = idx+1;
        else
            error(['no digit after decimal point in ' ...
                    json(start:idx-1) ' (char ' num2str(start) ')']);
        end
        digits();
    end
    if getchar() == 'e' || getchar() == 'E'
        idx = idx+1;
        if getchar() == '+' || getchar() == '-'
            idx = idx+1;
        end
        if any(getchar() == '0123456789')
            idx = idx+1;
            digits();
        else
            error(['no digit in exponent of ' json(start:idx-1) ...
                   ' (char ' num2str(start) ')']);
        end
    end
    obj = str2num(json(start:idx-1));

    function digits()
        while any(getchar() == '1234567890')
            idx = idx+1;
        end
    end

    function c = getchar()
        if idx > length(json)
            c = ' ';
        else
            c = json(idx);
        end
    end
end

% parses an object and advances idx
function [obj, idx] = object(json, idx)
    start = idx;
    obj = struct();
    if json(idx) ~= '{'
        error(['object must start with "{" (char ' num2str(idx) ')']);
    end
    idx = idx+1;
    idx = next(json, idx);
    if json(idx) ~= '}'
        while 1
            [k, idx] = string(json, idx);
            idx = next(json, idx);
            if json(idx) == ':'
                idx = idx+1;
            else
                error(['no ":" after object key in "' json(start:idx-1) ...
                       '" (char ' num2str(idx) ')']);
            end
            idx = next(json, idx);
            [v, idx] = value(json, idx);
            obj.(k) = v;
            idx = next(json, idx);
            if json(idx) == ','
                idx = idx+1;
                idx = next(json, idx);
                continue
            elseif json(idx) == '}'
                break
            else
                error(['no "," or "}" after entry in "' json(start:idx-1) ...
                       '" (char ' num2str(idx) ')']);
            end
        end
    end
    idx = idx+1;
end

% parses an array and advances idx
function [obj, idx] = array(json, idx)
    start = idx;
    obj = {};
    if json(idx) ~= '['
        error(['array must start with "[" (char ' num2str(idx) ')']);
    end
    idx = idx+1;
    idx = next(json, idx);
    if json(idx) ~= ']'
        while 1
            [v, idx] = value(json, idx);
            obj = [obj, {v}];
            idx = next(json, idx);
            if json(idx) == ','
                idx = idx+1;
                idx = next(json, idx);
                continue
            elseif json(idx) == ']'
                break
            else
                error(['no "," or "]" after entry in "' json(start:idx-1) ...
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
        error(['not enough data for "true" in "' json(start:end) ...
               '" (char ' num2str(start) ')']);
    end
    if json(idx:idx+3) == 'true'
        obj = logical(1);
        idx = idx+4;
    else
        error(['not "true": "' json(start:idx+3) ...
               '" (char ' num2str(idx) ')']);
    end
end

% parses false and advances idx
function [obj, idx] = false(json, idx)
    start = idx;
    if length(json) < idx+4
        error(['not enough data for "false" in "' json(start:end) ...
               '" (char ' num2str(start) ')']);
    end
    if json(idx:idx+4) == 'false'
        obj = logical(0);
        idx = idx+5;
    else
        error(['not "false": "' json(start:idx+4) ...
               '" (char ' num2str(idx) ')']);
    end
end

% parses null and advances idx
function [obj, idx] = null(json, idx)
    start = idx;
    if length(json) < idx+3
        error(['not enough data for "null" in "' json(start:end) ...
               '" (char ' num2str(start) ')']);
    end
    if json(idx:idx+3) == 'null'
        obj = [];
        idx = idx+4;
    else
        error(['not "null": "' json(start:idx+3) ...
               '" (char ' num2str(idx) ')']);
    end
end
