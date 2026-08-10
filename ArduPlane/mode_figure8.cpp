#include "mode.h"
#include "Plane.h"

bool ModeFigureEight::_enter()
{
    // use current location as starting point and compute two circle centers
    const float radius = (fabsf(plane.aparm.loiter_radius) <= 1) ? LOITER_RADIUS_DEFAULT : fabsf(plane.aparm.loiter_radius);
    const float heading_deg = plane.ahrs.get_yaw_deg();

    center1 = plane.current_loc;
    center1.offset_bearing(heading_deg + 90.0f, radius);

    center2 = plane.current_loc;
    center2.offset_bearing(heading_deg - 90.0f, radius);

    plane.prev_WP_loc = plane.current_loc;
    plane.next_WP_loc = center1;
    plane.loiter.direction = 1;
    on_second_circle = false;

    plane.loiter_angle_reset();
    plane.setup_terrain_target_alt(plane.next_WP_loc);
    return true;
}

void ModeFigureEight::update()
{
    plane.calc_nav_roll();
    plane.calc_nav_pitch();
    plane.calc_throttle();

    const float radius = (fabsf(plane.aparm.loiter_radius) <= 1) ? LOITER_RADIUS_DEFAULT : fabsf(plane.aparm.loiter_radius);
    plane.update_loiter(radius);

    if (fabsf(plane.loiter.sum_cd) >= 36000) {
        plane.loiter_angle_reset();
        plane.prev_WP_loc = plane.current_loc;
        if (on_second_circle) {
            plane.next_WP_loc = center1;
        } else {
            plane.next_WP_loc = center2;
        }
        plane.loiter.direction = -plane.loiter.direction;
        on_second_circle = !on_second_circle;
    }
}
