%% encode zeros
if ~strcmp(base64encode(uint8([0 0 0]')), 'AAAA')
    error('Encoding zeros failed')
end

%% decode zeros
if ~all([0 0 0]' == base64decode('AAAA'))
    error('Decoding zeros failed')
end

%% encode BEEF
if ~strcmp(base64encode(uint8([4 65 5]')), 'BEEF')
    error('Encoding BEEF failed')
end

%% decode BEEF
if ~all([4 65 5]' == base64decode('BEEF'))
    error('Decoding BEEF failed')
end

%% encode with padding
if ~strcmp(base64encode(uint8([1]')), 'AQ==')
    error('Encoding with padding failed')
end

%% decode with padding
if ~all([1]' == base64decode('AQ=='))
    error('Decoding with padding failed')
end

%% decode with missing padding
if ~all([1]' == base64decode('AQ'))
    error('Decoding with missing padding failed')
end
