from IPython.core.magic import Magics, magics_class
from IPython.core.magic import line_magic, cell_magic


@magics_class
class MatlabMagic(Magics):
    """Call this magic using %%matlab

    All variables assigned within the cell will be available in
    Python.

    If you need to restart matlab, use %restart_matlab

    """

    def __init__(self, shell):
        super(MatlabMagic, self).__init__(shell)
        import transplant
        self.m = transplant.Matlab()

    @cell_magic
    def matlab(self, line, cell):
        res = self.m.evalin('base', cell)
        vars = self.m.evalin('base', 'who()', nargout=1)
        for var in vars:
            varname = str(var)
            value = getattr(self.m, varname)
            self.shell.user_global_ns[varname] = value

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
