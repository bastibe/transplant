%PARSEJSON parses a json string into Matlab data structures
% PARSEJSON(STRING)
%    reads STRING as JSON data, and creates Matlab data structures
%    from it.
%    - strings are converted to strings with escape sequences removed
%    - numbers are converted to doubles
%    - true, false are converted to logical 1, 0
%    - null is converted to []
%    - arrays are converted to cell arrays
%    - objects are converted to containers.Map
%
%    In contrast to many other JSON parsers, this one does not try to
%    convert all-numeric arrays into matrices. Thus, nested data
%    structures are encoded correctly. Also, this correctly translates
%    escape sequences in strings.
%
%    This is a complete implementation of the JSON spec, and invalid
%    data will generally throw errors.

% (c) 2014 Bastian Bechtold
% This code is licensed under the BSD 3-clause license

function [obj] = parsejson(json)
    json = unescape_strings(json);
    tokens = tokenize(json);
    idx = next(json, 1);
    [obj, idx] = value(json, idx, tokens);
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
function [obj, idx] = value(json, idx, tokens)
    char = json(idx);
    if char == '"'
        [obj, idx] = string(json, idx, tokens);
    elseif any(char == '0123456789-')
        [obj, idx] = number(json, idx, tokens);
    elseif char == '{'
        [obj, idx] = object(json, idx, tokens);
    elseif char == '['
        [obj, idx] = array(json, idx, tokens);
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
function [obj, idx] = string(json, idx, tokens)
    stop = tokens(idx);
    obj = json(idx+1:stop-1);
    if ~isempty(strfind(obj, '\"'))
        % This regex replaces escaped quotes with quotes:
        % Find (an even number of `\`) followed by `\"`
        % and replace with the aforementioned `\` and `"`
        obj = regexprep(obj, '((?<!\\)(?>\\\\)*)\\"', '$1"');
    end
    % replace escaped backslashes with backslashes:
    obj = strrep(obj, '\\', '\');
    idx = stop+1;
end

% searches for the start and end points of things, and returns their indices
function tokens = tokenize(s)
    % This regex finds the starting points and end points of all strings:
    % Find strings that contain anything but backslashes or quotes, or
    % several single backslash-escaped characters followed by anything
    % but backslashes or quotes.
    strings = '"[^"\\]*(?:\\.[^"\\]*)*"';
    punctuation = '[\s{}\[\]=:,]+';
    keywords = '(true|false|null)';
    numbers = '[-+0-9.eE]+';
    everything = ['(' strings ')|(?>' punctuation ')|(?>' keywords ')|(' numbers ')'];
    [start, stop] = regexp(s, everything);
    tokens = sparse(start, ones(1, length(start)), stop);
end

% replace all backslash-escaped sequences in all strings
function s = unescape_strings(s)
    % This does not replace escaped quotes or escaped backslashes
    % since those mark beginnings and ends of JSON strings.

    % The regex operations are *very* time-consuming for long strings
    % and are only run if the string may contain an escaped sequence.
    % Note that the s_has_token calls  only check for the existance of
    % escaped characters (i.e. \n), but not for an escaped backslash,
    % followed by a characters (i.e. \\n), but the regexes do.
    % s_has_tokens takes milliseconds, where the regexes take seconds.

    s_has_token = @(token)~isempty(strfind(s, token));

    % These regexes mean:
    % Find (an even number of `\`) followed by an escape sequence and
    % replace with the aforementioned `\` and a replacement.

    if cellfun(s_has_token, {'\t', '\r', '\n', '\f', '\b'})
         % replace `\t` with tab, `\r` with return, `\n` with newline,
         % `\f` with formfeed and `\b` with backspace.
         s = regexprep(s, '((?<!\\)(?>\\\\)*)(\\[trnfb])', '$1${sprintf($2)}');
    end
    if s_has_token('\/')
        % replace `\/` with `/`
        s = regexprep(s, '((?<!\\)(?>\\\\)*)\\/', '$1/');
    end
    if s_has_token('\u')
        % replace `\uXXXX` with the unicode character at codepoint XXXX
        s = regexprep(s, '((?<!\\)(?>\\\\)*)\\u([0-9a-fA-F]{4})', '$1${char(hex2dec($2))}');
    end
end

% parses a number and advances idx
function [obj, idx] = number(json, idx, tokens)
    stop = tokens(idx);
    obj = str2num(json(idx:stop));
    if isempty(obj)
        error('JSON:parse:number:nonumber', ...
              ['not a number: "' json(idx:stop) '" (char ' num2str(idx) ')']);
    end
    idx = stop+1;
end

% parses an object and advances idx
function [obj, idx] = object(json, idx, tokens)
    start = idx;
    obj = containers.Map();
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
            [key, idx] = string(json, idx, tokens);
            idx = next(json, idx);
            if json(idx) == ':'
                idx = idx+1;
            else
                error('JSON:parse:object:nocolon', ...
                      ['no ":" after object key in "' json(start:idx-1) ...
                       '" (char ' num2str(idx) ')']);
            end
            idx = next(json, idx);
            [val, idx] = value(json, idx, tokens);
            obj(key) = val;
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
function [obj, idx] = array(json, idx, tokens)
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
            [val, idx] = value(json, idx, tokens);
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
    if strcmp(json(idx:idx+3), 'true')
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
    if strcmp(json(idx:idx+4), 'false')
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
    if strcmp(json(idx:idx+3), 'null')
        obj = [];
        idx = idx+4;
    else
        error('JSON:parse:null:notnull', ...
              ['not "null": "' json(start:idx+3) ...
               '" (char ' num2str(idx) ')']);
    end
end
