%% String parsing
if ~strcmp(parsejson('"ABCdef123"'), 'ABCdef123')
    error('String parsing failed')
end

%% String parsing with unicode
if ~strcmp(parsejson('"Bl\u00E4\u00DFhuhn"'), 'Bläßhuhn')
    error('String parsing with unicode failed')
end

%% String parsing with escaped characters
if ~strcmp(parsejson('"\\\t\r\n\f\b\"\/\\"'), sprintf('\\\t\r\n\f\b"/\\'))
    error('String parsing with escaped characters failed')
end

%% Number parsing
if parsejson('-12.34e56') ~= -12.34e56
    error('Number parsing failed')
end

%% Bool parsing
bool = parsejson('true');
if bool ~= true || ~islogical(bool)
    error('Boolean parsing failed')
end

bool = parsejson('false');
if bool ~= false || ~islogical(bool)
    error('Boolean parsing failed')
end

%% Null parsing
if parsejson('null') ~= []
    error('Null parsing failed')
end

%% Array parsing
if ~isequal(parsejson('[1, "a", true]'), {1 'a' true})
    error('Array parsing failed')
end

%% Object parsing
s = parsejson('{"test": 1, "foo": "bar"}');
if s('test') ~= 1 || ~strcmp(s('foo'), 'bar') || length(keys(s)) ~= 2
    error('Object parsing failed')
end

%% Data roundtrip
data = '[{"test":1},true,null,"\u00FCber"]';
if ~isequal(data, dumpjson(parsejson(data)))
    error('Data roundtrip failed')
end
