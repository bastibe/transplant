%TRANSPLANT is a Matlab server for remote code execution
% TRANSPLANT(URL) connects to a 0MQ client at a given URL.
%
%    The client can send messages, which TRANSPLANT will answer.
%    All messages are JSON-encoded strings. All message are structures
%    with two keys: 'type' and 'content'.
%
%    TRANSPLANT implements the following message types:
%    - 'eval': evaluates the content of the message.
%    - 'die': closes the 0MQ session and quits Matlab.
%
%    TRANSPLANT implements the following responses:
%    - 'ack': received message successfully.
%    - 'error': there was an error while handling the message.

function transplant(url)
  addpath('jsonlab')

    messenger('open', url)

    while 1

        [msg_type, msg] = receive_msg();

        switch msg_type
            case 'die'
                send_ack();
                quit;
            case 'eval'
                try
                    eval(msg);
                    send_ack();
                catch err
                    send_error(err);
                end
        end
    end
end


% Wait for and receive a message
function [msg_type, msg_content] = receive_msg()
    blob = messenger('receive');
    data = loadjson(blob);
    msg_type = data.type;
    msg_content = data.content;
end

% Send a message
function send_msg(msg_type, msg_content)
    data.type = msg_type;
    data.content = msg_content;
    messenger('send', savejson('', data));
end


function send_ack()
    send_msg('ack', '');
end

function send_error(err)
    send_msg('error', struct('identifier', err.identifier, ...
                             'message', err.message))
end
