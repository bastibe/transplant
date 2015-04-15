%BASE64DECODE decodes a base64 string as a vector of uint8s
% BASE64DECODE(BASE64)
%    Decodes every four BASE64 characters to three bytes.
%    If BASE64 is padded with '=', these are translated to zeros, and
%    stripped from the resulting bytes.

% (c) 2014 Bastian Bechtold
% This code is licensed under the BSD 3-clause license

function bytes = base64decode(base64)
    % strip line breaks
    base64 = strrep(base64, sprintf('\n'), '');
    % add padding if missing
    if mod(length(base64), 4) ~= 0
        base64 = [base64 repmat('=', [1 mod(length(base64), 4)])];
    end
    % remember padding
    padding = sum(base64 == '=');
    % convert from string representation to base64 bytes
    table = zeros(1, 128, 'uint8');
    table(['A':'Z' 'a':'z' '0':'9' '+' '/']+0) = 0:63;
    base64 = table(base64');

    % convert every four base64 bytes to three uint8 bytes
    bytes = zeros(length(base64)/4*3, 1, 'uint8');
    bytes(1:3:end) = bitor(bitshift(base64(1:4:end), 2), ...
                           bitshift(base64(2:4:end), -4));
    bytes(2:3:end) = bitor(bitshift(bitand(base64(2:4:end), 15), 4), ... % four LSB
                           bitshift(base64(3:4:end), -2));
    bytes(3:3:end) = bitor(bitshift(bitand(base64(3:4:end), 3), 6), ... % two LSB
                           base64(4:4:end));
    % strip padding
    bytes = bytes(1:end-padding);
end
