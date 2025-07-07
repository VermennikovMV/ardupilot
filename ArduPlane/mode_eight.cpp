#include "mode.h"
#include "Plane.h"

bool ModeEight::_enter()
{
    // maintain altitude at entry
    plane.next_WP_loc.alt = plane.current_loc.alt;
    direction = 1;
    last_switch_ms = AP_HAL::millis();
    return true;
}

void ModeEight::update()
{
    const uint32_t now = AP_HAL::millis();
    if (now - last_switch_ms > switch_period_ms) {
        direction = -direction;
        last_switch_ms = now;
    }

    plane.nav_roll_cd = direction * plane.roll_limit_cd / 3;
    plane.update_load_factor();
    plane.calc_nav_pitch();
    plane.calc_throttle();
}
