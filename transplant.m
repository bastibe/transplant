%TRANSPLANT receives commands via 0MQ
% TRANSPLANT(URL) connects to a 0MQ server at a given URL.
%    The server can send two kinds of messages:
%    - "die": Quit Matlab.
%    - anything else: eval the message
function transplant(url)
    messenger('open', url)

    while 1
        msg = messenger('receive')
        if (strcmp(msg, 'die'))
           messenger('send', 'ack')
           quit
        else
            try
               eval(msg)
            catch err
               disp(err)
            end
        end
        messenger('send', 'ack');
    end
end
