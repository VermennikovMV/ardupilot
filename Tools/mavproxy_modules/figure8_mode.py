from MAVProxy.modules.lib import mp_module
from pymavlink import mavutil

class Figure8ModeModule(mp_module.MPModule):
    def __init__(self, mpstate):
        super(Figure8ModeModule, self).__init__(mpstate, 'figure8_mode')
        self.add_command('figure8', self.cmd_figure8,
                         'switch to FIGURE8 flight mode')

    def cmd_figure8(self, args):
        mapping = self.mpstate.master.mode_mapping()
        if mapping and 'FIGURE8' in mapping:
            mode_num = mapping['FIGURE8']
        else:
            mode_num = 27
        self.mpstate.master.mav.command_long_send(
            self.mpstate.master.target_system,
            self.mpstate.master.target_component,
            mavutil.mavlink.MAV_CMD_DO_SET_MODE,
            0,
            mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
            mode_num,
            0, 0, 0, 0, 0)


def init(mpstate):
    return Figure8ModeModule(mpstate)
