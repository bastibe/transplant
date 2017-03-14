classdef MethodProxy
%METHODPROXY is a class for storing methods
%  Transplant uses func2str to store functions. This does not work for
%  methods, since it doesn't capture the object. METHODPROXY stores an
%  object and a method name, and overloads nargout and help for such
%  methods.

    properties(GetAccess='protected', SetAccess='protected')
        target
        methodname
    end

    methods
        function obj = MethodProxy(target, methodname)
            obj.target = target;
            obj.methodname = methodname;
        end

        function handle = gethandle(obj)
            %GETHANDLE returns a function handle
            func = str2func(obj.methodname);
            handle = @(varargin)func(obj.target, varargin{:});
        end

        function num = nargout(obj)
            classname = class(obj.target);
            num = builtin('nargout', [classname '>' classname '.' obj.methodname]);
        end

        function str = help(obj)
            str = help([class(obj.target) '.' obj.methodname]);
        end
    end
end
