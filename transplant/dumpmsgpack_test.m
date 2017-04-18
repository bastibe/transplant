%% positive integer dumping
if dumpmsgpack(int8(0)) ~= uint8(0)
    error('Dumping 0 failed')
end
if any(dumpmsgpack(uint8(1)) ~= uint8(1))
    error('Dumping positive fixnum failed')
end
if any(dumpmsgpack(uint8(128)) ~= uint8([204, 128]))
    error('Dumping uint8  failed')
end
if any(dumpmsgpack(uint16(256)) ~= uint8([205, 1, 0]))
    error('Dumping uint16 failed')
end
if any(dumpmsgpack(uint32(2^16)) ~= uint8([206, 0, 1, 0, 0]))
    error('Dumping uint32 failed')
end
if any(dumpmsgpack(uint64(2^32)) ~= uint8([207, 0, 0, 0, 1, 0, 0, 0, 0]))
    error('Dumping uint64 failed')
end

%% negative integer dumping
if dumpmsgpack(int8(-1)) ~= uint8(255)
    error('Dumping negative fixnum failed')
end
if any(dumpmsgpack(int8(-128)) ~= uint8([208, 128]))
    error('Dumping int8  failed')
end
if any(dumpmsgpack(int16(-256)) ~= uint8([209, 255, 0]))
    error('Dumping int16 failed')
end
if any(dumpmsgpack(int32(-2^16)) ~= uint8([210, 255, 255, 0, 0]))
    error('Dumping int32 failed')
end
if any(dumpmsgpack(int64(-2^32)) ~= uint8([211, 255, 255, 255, 255, 0, 0, 0, 0]))
    error('Dumping int64 failed')
end

%% float dumping
if any(dumpmsgpack(single(1.5)) ~= uint8([202, 63, 192, 0, 0]))
    error('Dumping float32 failed')
end
if any(dumpmsgpack(double(1.5)) ~= uint8([203, 63, 248, 0, 0, 0, 0, 0, 0]))
    error('Dumping float64 failed')
end

%% string dumping
if any(dumpmsgpack('foo') ~= uint8([163, 102, 111, 111]))
    error('Dumping fixstr failed')
end
if any(dumpmsgpack(repmat('a', [1, 32])) ~= uint8([217, 32, ones(1, 32)*'a']))
    error('Dumping str8 failed')
end
if any(dumpmsgpack(repmat('a', [1, 2^8])) ~= uint8([218, 1, 0, ones(1, 2^8)*'a']))
    error('Dumping str16 failed')
end
if any(dumpmsgpack(repmat('a', [1, 2^16])) ~= uint8([219, 0, 1, 0, 0, ones(1, 2^16)*'a']))
    error('Dumping str16 failed')
end

%% bin dumping
if any(dumpmsgpack(repmat(uint8(42), [1, 32])) ~= uint8([196, 32, ones(1, 32)*42]))
    error('Dumping str8 failed')
end
if any(dumpmsgpack(repmat(uint8(42), [1, 2^8])) ~= uint8([197, 1, 0, ones(1, 2^8)*42]))
    error('Dumping str16 failed')
end
if any(dumpmsgpack(repmat(uint8(42), [1, 2^16])) ~= uint8([198, 0, 1, 0, 0, ones(1, 2^16)*42]))
    error('Dumping str16 failed')
end

%% array dumping
if any(dumpmsgpack({uint8(1), uint8(2)}) ~= uint8([146, 1, 2]))
    error('Dumping fixarray failed')
end
if any(dumpmsgpack(num2cell(repmat(uint8(42), [1, 16]))) ~= uint8([220, 0, 16, repmat(42, [1, 16])]))
    error('Dumping array16 failed')
end
% takes too long:
% if any(dumpmsgpack(num2cell(repmat(uint8(42), [1, 2^16]))) ~= uint8([221, 0, 1, 0, 0 repmat(42, [1, 2^16])]))
%     error('Dumping array32 failed')
% end

%% map dumping
if any(dumpmsgpack(struct('one', uint8(1), 'two', uint8(2))) ~= uint8([130, dumpmsgpack('one'), 1, dumpmsgpack('two'), 2]))
    error('Dumping fixmap failed')
end
data = struct();
msgpack = uint8([]);
for n=[1 10 11 12 13 14 15 16 2 3 4 5 6 7 8 9] % default struct field order
    data.(['x' num2str(n)]) = uint8(n);
    msgpack = [msgpack dumpmsgpack(['x' num2str(n)]) uint8(n)];
end
if any(dumpmsgpack(data) ~= uint8([222, 0, 16, msgpack]))
    error('Dumping map16 failed')
end
% map32 takes too long
