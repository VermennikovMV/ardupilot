#include "mode.h"
#include "Plane.h"

bool ModeEight::_enter()
{
    plane.next_WP_loc = plane.current_loc;
    direction = 1;
    last_heading_cd = ahrs.yaw_sensor;
    return true;
}

void ModeEight::update()
{
    plane.nav_roll_cd  = plane.roll_limit_cd / 3 * direction;
    plane.update_load_factor();
    plane.calc_nav_pitch();
    plane.calc_throttle();

    int32_t heading_diff = wrap_180_cd(ahrs.yaw_sensor - last_heading_cd);
    if (labs(heading_diff) >= 18000) {
        direction = -direction;
        last_heading_cd = ahrs.yaw_sensor;
    }
}
