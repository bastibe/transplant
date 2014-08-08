%TRANSPLANT is a Matlab server for remote code execution
% TRANSPLANT(URL) connects to a 0MQ client at a given URL.
%
%    The client can send messages, which TRANSPLANT will answer.
%    All messages are JSON-encoded strings. All message are structures
%    with at least one key: 'type'
%
%    Depending on the message type, other keys may or may not be set.
%
%    TRANSPLANT implements the following message types:
%    - 'eval': evaluates the 'string' of the message.
%    - 'die': closes the 0MQ session and quits Matlab.
%    - 'put': saves the 'value' as a global variable called 'name'.
%    - 'get': retrieve the global variable 'name'.
%
%    TRANSPLANT implements the following responses:
%    - 'ack': received message successfully.
%    - 'error': there was an error while handling the message.
%    - 'value': returns a value.

function transplant(url)
    addpath('jsonlab')

    messenger('open', url)

    while 1

        msg = receive_msg();

        try
            switch msg.type
                case 'die'
                    send_ack();
                    quit;
                case 'eval'
                    evalin('base', msg.string);
                    send_ack();
                case 'put'
                    assignin('base', msg.name, msg.value);
                    send_ack();
                case 'get'
                    send_value(evalin('base', msg.name));
                end
        catch err
            send_error(err)
        end
    end
end


% Wait for and receive a message
function msg = receive_msg()
    blob = messenger('receive');
    msg = loadjson(blob);
end


% Send a message
function send_msg(msg_type, msg)
    msg.type = msg_type;
    messenger('send', savejson('', msg));
end


% Send an acknowledgement message
function send_ack()
    send_msg('ack', struct());
end


% Send an error message
function send_error(err)
    send_msg('error', struct('identifier', err.identifier, ...
                             'message', err.message))
end


% Send a value message
function send_value(value)
    send_msg('value', struct('value', value))
end
