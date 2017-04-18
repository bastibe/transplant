%% positive integer parsing
if parsemsgpack(uint8(0)) ~= uint8(0)
    error('Parsing 0 failed')
end
if any(parsemsgpack(uint8(1)) ~= uint8(1))
    error('Parsing positive fixnum failed')
end
if any(parsemsgpack(uint8([204, 128])) ~= uint8(128))
    error('Parsing uint8  failed')
end
if any(parsemsgpack(uint8([205, 1, 0])) ~= uint16(256))
    error('Parsing uint16 failed')
end
if any(parsemsgpack(uint8([206, 0, 1, 0, 0])) ~= uint32(2^16))
    error('Parsing uint32 failed')
end
if any(parsemsgpack(uint8([207, 0, 0, 0, 1, 0, 0, 0, 0])) ~= uint64(2^32))
    error('Parsing uint64 failed')
end

%% negative integer parsing
if any(parsemsgpack(uint8(255)) ~= int8(-1))
    error('Parsing negative fixnum failed')
end
if any(parsemsgpack(uint8([208, 128])) ~= int8(-128))
    error('Parsing int8 failed')
end
if any(parsemsgpack(uint8([209, 255, 0])) ~= int16(-256))
    error('Parsing int16 failed')
end
if any(parsemsgpack(uint8([210, 255, 255, 0, 0])) ~= int32(-2^16))
    error('Parsing int32 failed')
end
if any(parsemsgpack(uint8([211, 255, 255, 255, 255, 0, 0, 0, 0])) ~= int64(-2^32))
    error('Parsing int64 failed')
end

%% float parsing
if any(parsemsgpack(uint8([202, 63, 192, 0, 0])) ~= single(1.5))
    error('Parsing float32 failed')
end
if any(parsemsgpack(uint8([203, 63, 248, 0, 0, 0, 0, 0, 0])) ~= double(1.5))
    error('Parsing float64 failed')
end

%% string parsing
if any(parsemsgpack(uint8([163, 102, 111, 111])) ~= 'foo')
    error('Parsing fixstr failed')
end
if any(parsemsgpack(uint8([217, 32, ones(1, 32)*'a'])) ~= repmat('a', [1, 32]))
    error('Parsing str8 failed')
end
if any(parsemsgpack(uint8([218, 1, 0, ones(1, 2^8)*'a'])) ~= repmat('a', [1, 2^8]))
    error('Parsing str16 failed')
end
if any(parsemsgpack(uint8([219, 0, 1, 0, 0, ones(1, 2^16)*'a'])) ~= repmat('a', [1, 2^16]))
    error('Parsing str16 failed')
end

%% bin parsing
if any(parsemsgpack(uint8([196, 32, ones(1, 32)*42])) ~= repmat(uint8(42), [1, 32]))
    error('Parsing str8 failed')
end
if any(parsemsgpack(uint8([197, 1, 0, ones(1, 2^8)*42])) ~= repmat(uint8(42), [1, 2^8]))
    error('Parsing str16 failed')
end
if any(parsemsgpack(uint8([198, 0, 1, 0, 0, ones(1, 2^16)*42])) ~= repmat(uint8(42), [1, 2^16]))
    error('Parsing str16 failed')
end

%% array parsing
c = parsemsgpack(uint8([146, 1, 2]));
d = {uint8(1), uint8(2)};
for n=1:max([length(c), length(d)])
    if c{n} ~= d{n}
        error('Parsing fixarray failed')
    end
end
c = parsemsgpack(uint8([220, 0, 16, repmat(42, [1, 16])]));
d = num2cell(repmat(uint8(42), [1, 16]));
for n=1:max([length(c), length(d)])
    if c{n} ~= d{n}
        error('Parsing array16 failed')
    end
end
% array32 takes too long

%% map parsing
c = parsemsgpack(uint8([130, dumpmsgpack('one'), 1, dumpmsgpack('two'), 2]));
d = struct('one', uint8(1), 'two', uint8(2));
f = [fieldnames(d)' c.keys()];
for n=1:length(f)
    if c(f{n}) ~= d.(f{n})
        error('Parsing fixmap failed')
    end
end
data = struct();
msgpack = uint8([222, 0, 16]);
for n=[1 10 11 12 13 14 15 16 2 3 4 5 6 7 8 9] % default struct field order
    data.(['x' num2str(n)]) = uint8(n);
    msgpack = [msgpack dumpmsgpack(['x' num2str(n)]) uint8(n)];
end
c = parsemsgpack(msgpack);
d = data;
f = [fieldnames(d)' c.keys()];
for n=1:length(f)
    if c(f{n}) ~= d.(f{n})
        error('Parsing map16 failed')
    end
end
% map32 takes too long
