#include "mode.h"
#include "Plane.h"

bool ModeEight::_enter()
{
    plane.do_loiter_at_location();
    plane.setup_terrain_target_alt(plane.next_WP_loc);
    plane.loiter_angle_reset();

    radius_m = (fabsf(plane.aparm.loiter_radius) <= 1) ? LOITER_RADIUS_DEFAULT : fabsf(plane.aparm.loiter_radius);

    cross_alt_cm = plane.target_altitude.amsl_cm;

    cross_loc = plane.next_WP_loc;
    cross_loc.set_alt_cm(cross_alt_cm, Location::AltFrame::ABSOLUTE);

    const float yaw_rad = radians(ahrs.yaw_sensor * 0.01f);
    Vector2f ofs(radius_m, 0);
    ofs.rotate(yaw_rad + M_PI_2);

    right_loc = cross_loc;
    right_loc.offset(ofs.x, ofs.y);
    right_loc.set_alt_cm(cross_alt_cm, Location::AltFrame::ABSOLUTE);

    left_loc = cross_loc;
    left_loc.offset(-ofs.x, -ofs.y);
    left_loc.set_alt_cm(cross_alt_cm, Location::AltFrame::ABSOLUTE);

    direction = 1;
    plane.next_WP_loc = right_loc;
    plane.next_WP_loc.loiter_ccw = 0;
    plane.loiter.direction = direction;

    return true;
}

void ModeEight::update()
{
    plane.calc_nav_roll();
    plane.calc_nav_pitch();
    plane.calc_throttle();

    plane.update_loiter(0);

    if (labs(plane.loiter.sum_cd) >= 18000) {
        direction = -direction;

        if (direction > 0) {
            plane.next_WP_loc = right_loc;
            plane.next_WP_loc.loiter_ccw = 0;
        } else {
            plane.next_WP_loc = left_loc;
            plane.next_WP_loc.loiter_ccw = 1;
        }
        plane.next_WP_loc.set_alt_cm(cross_alt_cm, Location::AltFrame::ABSOLUTE);
        plane.loiter.direction = direction;
        plane.loiter_angle_reset();
    }
}
