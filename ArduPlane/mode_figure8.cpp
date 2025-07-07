#include "mode.h"
#include "Plane.h"

bool ModeFigure8::_enter()
{
    _state = 0;
    plane.loiter_angle_reset();
    uint16_t radius = (abs(plane.aparm.loiter_radius) <= 1) ? LOITER_RADIUS_DEFAULT : abs(plane.aparm.loiter_radius);
    _center1 = plane.current_loc;
    _center1.offset(0, radius);
    _center2 = plane.current_loc;
    _center2.offset(0, -radius);
    plane.next_WP_loc = _center1;
    plane.prev_WP_loc = plane.current_loc;
    return true;
}

void ModeFigure8::update()
{
    plane.calc_nav_roll();
    plane.calc_nav_pitch();
    plane.calc_throttle();
}

void ModeFigure8::navigate()
{
    const Location &center = (_state == 0) ? _center1 : _center2;
    const int8_t direction = (_state == 0) ? 1 : -1;
    plane.nav_controller->update_loiter(center, abs(plane.aparm.loiter_radius) <= 1 ? LOITER_RADIUS_DEFAULT : abs(plane.aparm.loiter_radius), direction);
    plane.loiter_angle_update();
    if (labs(plane.loiter.sum_cd) >= 36000) {
        plane.loiter_angle_reset();
        _state ^= 1;
    }
}
