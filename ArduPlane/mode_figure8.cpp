#include "mode.h"
#include "Plane.h"

bool ModeFigure8::_enter()
{
    plane.do_loiter_at_location();
    plane.setup_terrain_target_alt(plane.next_WP_loc);

    center1 = plane.next_WP_loc;
    center2 = center1;
    const float radius = fabsf(plane.aparm.loiter_radius);
    const float use_radius = radius <= 1 ? LOITER_RADIUS_DEFAULT : radius;
    center2.offset_bearing(90, use_radius * 2);

    current_center = 0;
    plane.loiter.direction = 1;
    plane.loiter_angle_reset();
    return true;
}

void ModeFigure8::update()
{
    plane.calc_nav_roll();
    plane.calc_nav_pitch();
    plane.calc_throttle();
    plane.update_loiter(0);
    if (fabsf(plane.loiter.sum_cd) >= 36000) {
        plane.loiter_angle_reset();
        current_center ^= 1;
        plane.next_WP_loc = (current_center == 0) ? center1 : center2;
        plane.loiter.direction *= -1;
    }
}
