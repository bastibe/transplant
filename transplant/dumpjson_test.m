%% String dumping
if ~strcmp('"ABCdef123"', dumpjson('ABCdef123'))
    error('String dumping failed')
end

%% String dumping with unicode
if ~strcmp('"Bl\u00E4\u00DFhuhn"', dumpjson('Bläßhuhn'))
    error('String dumping with unicode failed')
end

%% String dumping with escaped characters
if ~strcmp('"\\\t\r\n\f\b\"\/\\"', dumpjson(sprintf('\\\t\r\n\f\b"/\\')))
    error('String dumping with escaped characters failed')
end

%% Number dumping
if ~strcmp('-12300', dumpjson(-1.23e4))
    error('Number dumping failed')
end

%% Bool dumping
if ~strcmp('true', dumpjson(true))
    error('Boolean dumping failed')
end

if ~strcmp('false', dumpjson(false))
    error('Boolean dumping failed')
end

%% Null dumping
if ~strcmp('null', dumpjson([]))
    error('Null dumping failed')
end

%% Array dumping
if ~strcmp('[1,"a",true]', dumpjson({1 'a' true}))
    error('Array dumping failed')
end

%% Object dumping
s = dumpjson(struct('test', 1, 'foo', 'bar'));
if ~(strcmp('{"test":1,"foo":"bar"}', s) || ...
     strcmp('{"foo":"bar","test":1}', s))
    error('Object dumping failed')
end

%% Data roundtrip
% Note that UniformValues must be false, since Matlab assumes double otherwise
% and parsejson can't make the same inference at parse time.
data = {containers.Map('test', 1, 'UniformValues', false), true, [], 'über'};
if ~isequal(data, parsejson(dumpjson(data)))
    error('Data roundtrip failed')
end
