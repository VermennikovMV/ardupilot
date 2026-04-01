/*
 * This file is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This file is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Driver for the ST LSM6DSV16X IMU
 * Datasheet: https://www.st.com/resource/en/datasheet/lsm6dsv16x.pdf
 */
#pragma once

#include <AP_HAL/AP_HAL.h>
#include <AP_HAL/SPIDevice.h>

#include "AP_InertialSensor.h"
#include "AP_InertialSensor_Backend.h"

#ifndef LSM6DSV16X_DEFAULT_ROTATION
#define LSM6DSV16X_DEFAULT_ROTATION ROTATION_NONE
#endif

class AP_InertialSensor_LSM6DSV16X : public AP_InertialSensor_Backend {
public:
    static AP_InertialSensor_Backend *probe(AP_InertialSensor &imu,
                                            AP_HAL::OwnPtr<AP_HAL::SPIDevice> dev,
                                            enum Rotation rotation=LSM6DSV16X_DEFAULT_ROTATION);

    void start() override;
    bool update() override;

private:
    AP_InertialSensor_LSM6DSV16X(AP_InertialSensor &imu,
                                  AP_HAL::OwnPtr<AP_HAL::Device> dev,
                                  enum Rotation rotation);

    bool init();
    bool hardware_init();

    void configure_accel();
    void configure_gyro();

    void read_sensor();

    bool read_registers(uint8_t reg, uint8_t *data, uint8_t len);
    bool write_register(uint8_t reg, uint8_t v);

    AP_HAL::OwnPtr<AP_HAL::Device> _dev;
    AP_HAL::Device::PeriodicHandle _periodic_handle;

    enum Rotation _rotation;

    uint8_t _temperature_counter;
};
