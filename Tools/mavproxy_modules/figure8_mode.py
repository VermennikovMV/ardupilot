from MAVProxy.modules.lib import mp_module

class Figure8ModeModule(mp_module.MPModule):
    def __init__(self, mpstate):
        super(Figure8ModeModule, self).__init__(mpstate, 'figure8_mode')
        self.add_command('figure8', self.cmd_figure8,
                         'switch to FIGURE8 flight mode')

    def cmd_figure8(self, args):
        self.mpstate.functions.process_stdin('mode FIGURE8\n')


def init(mpstate):
    return Figure8ModeModule(mpstate)
