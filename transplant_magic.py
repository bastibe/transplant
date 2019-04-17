from IPython.core.magic import Magics, magics_class
from IPython.core.magic import line_magic, line_cell_magic


@magics_class
class MatlabMagic(Magics):
    """Call this magic using %%matlab

    All variables assigned within the cell will be available in
    Python.
    
    All transplantable variables assingned in Python will be 
    available in this cell.

    If you need to restart matlab, use %restart_matlab

    """

    def __init__(self, shell):
        super(MatlabMagic, self).__init__(shell)
        import transplant
        self.m = transplant.Matlab()

    def _shell_user_globals_to_matlab_base_workspace(self):
        for name, value in self.shell.user_global_ns.items():
            if not name.startswith('_'):
                try:
                    setattr(self.m, name, value)
                except TypeError:
                    pass
        
    def _matlab_base_workspace_to_shell_user_globals(self):
        vars = self.m.evalin('base', 'who()', nargout=1)
        for var in vars:
            varname = str(var)
            value = getattr(self.m, varname)
            self.shell.user_global_ns[varname] = value

    @line_cell_magic
    def matlab(self, line, cell=None):
        self._shell_user_globals_to_matlab_base_workspace()    
        res = self.m.evalin('base', line or cell)
        self.m.drawnow('update')
        self._matlab_base_workspace_to_shell_user_globals()
        return res

    @line_magic
    def restart_matlab(self, line):
        import transplant
        self.m = transplant.Matlab()


def load_ipython_extension(ipython):
    """
    Load this magic by running %load_ext transplant_magic
    """
    ipython.register_magics(MatlabMagic)
