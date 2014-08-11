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
%    - 'call': call function 'name' with 'args' and 'nargout'.
%
%    TRANSPLANT implements the following responses:
%    - 'ack': received message successfully.
%    - 'error': there was an error while handling the message.
%    - 'value': returns a value.

function transplant(url)

    % start 0MQ:
    messenger('open', url)

    while 1 % main messaging loop

        msg = receive_msg();

        try
            switch msg.type
                case 'die'
                    send_ack();
                    quit;
                case 'eval'
                    % try to get output from ans:
                    clear('ans');
                    evalin('base', msg.string);
                    try
                        send_value(ans);
                    catch err
                        send_ack();
                    end
                case 'put'
                    assignin('base', msg.name, msg.value);
                    send_ack();
                case 'get'
                    if isempty(evalin('base', ['who(''' msg.name ''')']))
                       error('TRANSPLANT:undefinedvariable' , ...
                             ['Undefined variable ''' msg.name '''.']);
                    end
                    value = evalin('base', msg.name)
                    send_value(value);
                case 'call'
                    fun = evalin('base', ['@' msg.name]);
                    args = msg.args;

                    % get the number of output arguments
                    if isfield(msg, 'nargout') && msg.nargout >= 0
                        resultsize = msg.nargout;
                    else
                        resultsize = nargout(fun);
                    end

                    if resultsize > 0
                        % call the function with the given number of
                        % output arguments:
                        results = cell(resultsize, 1);
                        [results{:}] = fun(args{:});
                        send_value(results);
                    else
                        % try to get output from ans:
                        clear('ans');
                        fun(args{:});
                        try
                            send_value(ans);
                        catch err
                            send_ack();
                        end
                    end
                end
        catch err
            send_error(err)
        end
    end
end


% Wait for and receive a message
function msg = receive_msg()
    blob = messenger('receive');
    msg = parsejson(blob);
end


% Send a message
function send_msg(msg_type, msg)
    msg.type = msg_type;
    messenger('send', dumpjson(msg));
end


% Send an acknowledgement message
function send_ack()
    send_msg('ack', struct());
end


% Send an error message
function send_error(err)
    msg.identifier = err.identifier;
    msg.message = err.message;
    msg.stack = err.stack;
    send_msg('error', msg);
end


% Send a value message
function send_value(value)
    msg.value = value;
    send_msg('value', msg);
end
