%BASE64ENCODE encodes a vector of uint8s as a base64 string
% BASE64ENCODE(BYTES)
%    Encodes every tree BYTES in four printable ASCII characters.
%    If LENGTH(BYTES) is not a multiple of three, it is padded with
%    zeros and unused characters are replaced with '='.

% (c) 2014 Bastian Bechtold

function base64 = base64encode(bytes)
    if mod(length(bytes), 3) ~= 0
        padding = 3-mod(length(bytes), 3);
        % pad to multiple of 3
        bytes = [bytes; zeros(3-mod(length(bytes), 3), 1, 'uint8')];
    else
        padding = 0;
    end

    base64 = zeros(length(bytes)/3*4, 1, 'uint8');
    base64(1:4:end) = bitshift(bytes(1:3:end), -2);
    base64(2:4:end) = bitor(bitshift(bitand(bytes(1:3:end),  3),  4), ... % two LSB
                      bitshift(bytes(2:3:end), -4));
    base64(3:4:end) = bitor(bitshift(bitand(bytes(2:3:end),  15),  2), ... % four LSB
                            bitshift(bytes(3:3:end), -6));
    base64(4:4:end) = bitand(bytes(3:3:end), 63); % six LSB

    table = ['A':'Z' 'a':'z' '0':'9' '+' '/'];
    base64 = table(base64+1);
    base64(end-padding+1:end) = '=';
end
