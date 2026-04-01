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
 * Driver for the ST LSM6DSV16X 6-axis IMU
 *
 * Register definitions and init sequence based on the BetaFlight driver:
 *   src/main/drivers/accgyro/accgyro_spi_lsm6dsv16x.c
 * Adapted to the ArduPilot AP_InertialSensor_Backend interface.
 *
 * Datasheet: https://www.st.com/resource/en/datasheet/lsm6dsv16x.pdf
 */

#include <utility>

#include <AP_HAL/AP_HAL.h>
#include <AP_Math/AP_Math.h>

#include "AP_InertialSensor_LSM6DSV16X.h"

/*
 * LSM6DSV16X register map (relevant subset)
 */

// Interface configuration register (R/W)
#define LSM6DSV_IF_CFG                      0x03
#define LSM6DSV_IF_CFG_I2C_I3C_DISABLE                  0x01

// WHO_AM_I register (R)
#define LSM6DSV_WHO_AM_I                    0x0F
#define LSM6DSV16X_WHO_AM_I_CONST           0x70

// INT1 pin control register (R/W)
#define LSM6DSV_INT1_CTRL                   0x0D
#define LSM6DSV_INT1_CTRL_INT1_DRDY_G                   0x02

// Accelerometer control register 1 (R/W)
#define LSM6DSV_CTRL1                       0x10

// Gyroscope control register 2 (R/W)
#define LSM6DSV_CTRL2                       0x11

// Control register 3 (R/W)
#define LSM6DSV_CTRL3                       0x12
#define LSM6DSV_CTRL3_BDU                               0x40
#define LSM6DSV_CTRL3_IF_INC                            0x04
#define LSM6DSV_CTRL3_SW_RESET                          0x01

// Control register 4 (R/W)
#define LSM6DSV_CTRL4                       0x13
#define LSM6DSV_CTRL4_DRDY_PULSED                       0x02

// Control register 6 (R/W) - gyro full-scale and LPF1 bandwidth
#define LSM6DSV_CTRL6                       0x15
#define LSM6DSV_CTRL6_LPF1_G_BW_MASK                    0x70
#define LSM6DSV_CTRL6_LPF1_G_BW_SHIFT                   4
#define LSM6DSV_CTRL6_FS_G_MASK                         0x0f
#define LSM6DSV_CTRL6_FS_G_SHIFT                        0
#define LSM6DSV_CTRL6_FS_G_2000DPS                      0x04

// Gyro LPF1 bandwidth selection at ODR = 7.68 kHz
// Values advised by ST tech support, used by BetaFlight
#define LSM6DSV_CTRL6_FS_G_BW_288HZ                     0

// Control register 7 (R/W)
#define LSM6DSV_CTRL7                       0x16
#define LSM6DSV_CTRL7_LPF1_G_EN                         0x01

// Control register 8 (R/W) - accel full-scale
#define LSM6DSV_CTRL8                       0x17
#define LSM6DSV_CTRL8_FS_XL_MASK                        0x03
#define LSM6DSV_CTRL8_FS_XL_SHIFT                       0
#define LSM6DSV_CTRL8_FS_XL_16G                         3

// Control register 9 (R/W)
#define LSM6DSV_CTRL9                       0x18
#define LSM6DSV_CTRL9_LPF2_XL_EN                        0x08

// Temperature data output register (R)
#define LSM6DSV_OUT_TEMP_L                  0x20

// Gyroscope output registers (R)
#define LSM6DSV_OUTX_L_G                    0x22

// Accelerometer output registers (R)
#define LSM6DSV_OUTX_L_A                    0x28

// HAODR data rate configuration register (R/W)
#define LSM6DSV_HAODR_CFG                   0x62
#define LSM6DSV_HAODR_CFG_HAODR_SEL_MASK                0x03
#define LSM6DSV_HAODR_CFG_HAODR_SEL_SHIFT               0
// HAODR mode 1 selects 15.625/31.25/.../8000 Hz ODR set
#define LSM6DSV_HAODR_MODE1                              1

// STATUS register
#define LSM6DSV_STATUS_REG                  0x1E
#define LSM6DSV_STATUS_REG_GDA                          0x02
#define LSM6DSV_STATUS_REG_XLDA                         0x01

/*
 * ODR values in high-accuracy mode 1 (HAODR_SEL = 01)
 * Encoded in CTRL1 bits [3:0] and CTRL2 bits [3:0]
 */
#define LSM6DSV_ODR_POWERDOWN               0
#define LSM6DSV_ODR_1000HZ                  9   // HAODR mode 1
#define LSM6DSV_ODR_2000HZ                  10  // HAODR mode 1
#define LSM6DSV_ODR_4000HZ                  11  // HAODR mode 1
#define LSM6DSV_ODR_8000HZ                  12  // HAODR mode 1

// Operating modes for CTRL1/CTRL2 bits [6:4]
#define LSM6DSV_OP_MODE_HIGH_ACCURACY       1

// Macro to encode multi-bit values (identical to BetaFlight)
#define LSM6DSV_ENCODE_BITS(val, mask, shift) ((val << shift) & mask)

/*
 * Driver constants
 */
#define LSM6DSV16X_BACKEND_SAMPLE_RATE      1600
#define LSM6DSV16X_POWERUP_DELAY_MSEC       5
#define LSM6DSV16X_HARDWARE_INIT_MAX_TRIES  5

static const uint32_t BACKEND_PERIOD_US = 1000000UL / LSM6DSV16X_BACKEND_SAMPLE_RATE;

extern const AP_HAL::HAL &hal;

AP_InertialSensor_LSM6DSV16X::AP_InertialSensor_LSM6DSV16X(AP_InertialSensor &imu,
                                                             AP_HAL::OwnPtr<AP_HAL::Device> dev,
                                                             enum Rotation rotation)
    : AP_InertialSensor_Backend(imu)
    , _dev(std::move(dev))
    , _rotation(rotation)
{
}

AP_InertialSensor_Backend *
AP_InertialSensor_LSM6DSV16X::probe(AP_InertialSensor &imu,
                                     AP_HAL::OwnPtr<AP_HAL::SPIDevice> dev,
                                     enum Rotation rotation)
{
    if (!dev) {
        return nullptr;
    }

    auto sensor = NEW_NOTHROW AP_InertialSensor_LSM6DSV16X(imu, std::move(dev), rotation);
    if (!sensor) {
        return nullptr;
    }

    if (!sensor->init()) {
        delete sensor;
        return nullptr;
    }

    return sensor;
}

void AP_InertialSensor_LSM6DSV16X::start()
{
    _dev->get_semaphore()->take_blocking();

    configure_gyro();
    configure_accel();

    _dev->get_semaphore()->give();

    if (!_imu.register_accel(accel_instance, LSM6DSV16X_BACKEND_SAMPLE_RATE,
                             _dev->get_bus_id_devtype(DEVTYPE_INS_LSM6DSV16X)) ||
        !_imu.register_gyro(gyro_instance, LSM6DSV16X_BACKEND_SAMPLE_RATE,
                            _dev->get_bus_id_devtype(DEVTYPE_INS_LSM6DSV16X))) {
        return;
    }

    set_gyro_orientation(gyro_instance, _rotation);
    set_accel_orientation(accel_instance, _rotation);

    _periodic_handle = _dev->register_periodic_callback(
        BACKEND_PERIOD_US,
        FUNCTOR_BIND_MEMBER(&AP_InertialSensor_LSM6DSV16X::read_sensor, void));
}

bool AP_InertialSensor_LSM6DSV16X::update()
{
    update_accel(accel_instance);
    update_gyro(gyro_instance);
    return true;
}

bool AP_InertialSensor_LSM6DSV16X::read_registers(uint8_t reg, uint8_t *data, uint8_t len)
{
    return _dev->read_registers(reg, data, len);
}

bool AP_InertialSensor_LSM6DSV16X::write_register(uint8_t reg, uint8_t v)
{
    return _dev->write_register(reg, v);
}

/*
 * Configure the gyroscope.
 *
 * Mirrors the BetaFlight lsm6dsv16xGyroInit() sequence:
 *  - High-accuracy ODR mode 1
 *  - 8 kHz gyro ODR (oversampled down to 1600 Hz by ArduPilot)
 *  - 2000 dps full scale
 *  - LPF1 enabled at 288 Hz bandwidth
 *  - Pulsed data-ready interrupt
 *
 * The gyro sensitivity at 2000 dps is 70 mdps/LSB (per datasheet section 4.1).
 * ArduPilot converts to rad/s: scale = radians(0.070) = 0.070 * DEG_TO_RAD.
 * Note: unlike Bosch IMUs, ST sensitivity != FS/32768 (70 mdps != 61 mdps).
 */
void AP_InertialSensor_LSM6DSV16X::configure_gyro()
{
    // Select high-accuracy ODR mode 1 (gives 1000/2000/4000/8000 Hz options)
    write_register(LSM6DSV_HAODR_CFG,
                   LSM6DSV_ENCODE_BITS(LSM6DSV_HAODR_MODE1,
                                       LSM6DSV_HAODR_CFG_HAODR_SEL_MASK,
                                       LSM6DSV_HAODR_CFG_HAODR_SEL_SHIFT));

    // Enable gyro in high-accuracy mode at 8 kHz ODR
    write_register(LSM6DSV_CTRL2,
                   LSM6DSV_ENCODE_BITS(LSM6DSV_OP_MODE_HIGH_ACCURACY, 0x70, 4) |
                   LSM6DSV_ENCODE_BITS(LSM6DSV_ODR_8000HZ, 0x0f, 0));

    // Set gyro full scale to 2000 dps and LPF1 bandwidth to 288 Hz
    write_register(LSM6DSV_CTRL6,
                   LSM6DSV_ENCODE_BITS(LSM6DSV_CTRL6_FS_G_BW_288HZ,
                                       LSM6DSV_CTRL6_LPF1_G_BW_MASK,
                                       LSM6DSV_CTRL6_LPF1_G_BW_SHIFT) |
                   LSM6DSV_ENCODE_BITS(LSM6DSV_CTRL6_FS_G_2000DPS,
                                       LSM6DSV_CTRL6_FS_G_MASK,
                                       LSM6DSV_CTRL6_FS_G_SHIFT));

    // Enable gyro digital LPF1 filter
    write_register(LSM6DSV_CTRL7, LSM6DSV_CTRL7_LPF1_G_EN);

    // Generate pulsed interrupt (not latched)
    write_register(LSM6DSV_CTRL4, LSM6DSV_CTRL4_DRDY_PULSED);
}

/*
 * Configure the accelerometer.
 *
 * Mirrors BetaFlight:
 *  - High-accuracy mode at 1 kHz ODR
 *  - 16 G full scale
 *  - LPF2 enabled
 *
 * Accel sensitivity at 16 G: 0.488 mg/LSB → acc_1G = 2048.
 * ArduPilot scale: (1/32768) * GRAVITY_MSS * 16.
 */
void AP_InertialSensor_LSM6DSV16X::configure_accel()
{
    // Enable accel in high-accuracy mode at 1 kHz ODR
    write_register(LSM6DSV_CTRL1,
                   LSM6DSV_ENCODE_BITS(LSM6DSV_OP_MODE_HIGH_ACCURACY, 0x70, 4) |
                   LSM6DSV_ENCODE_BITS(LSM6DSV_ODR_1000HZ, 0x0f, 0));

    // Set accel full scale to 16 G
    write_register(LSM6DSV_CTRL8,
                   LSM6DSV_ENCODE_BITS(LSM6DSV_CTRL8_FS_XL_16G,
                                       LSM6DSV_CTRL8_FS_XL_MASK,
                                       LSM6DSV_CTRL8_FS_XL_SHIFT));

    // Enable accel digital LPF2 filter
    write_register(LSM6DSV_CTRL9, LSM6DSV_CTRL9_LPF2_XL_EN);
}

/*
 * Read gyro and accel data from output registers.
 *
 * The LSM6DSV16X stores gyro data at 0x22..0x27 and accel data at 0x28..0x2D.
 * With IF_INC enabled we can burst-read all 12 bytes starting from OUTX_L_G.
 *
 * Data format: 16-bit signed little-endian per axis (X, Y, Z).
 *
 * Gyro scale: 70 mdps/LSB at 2000 dps FS → rad/s = raw * radians(0.070)
 * Accel scale: 0.488 mg/LSB at 16 G FS → m/s² = raw * 0.000488 * GRAVITY_MSS
 */
void AP_InertialSensor_LSM6DSV16X::read_sensor()
{
    uint8_t data[12];
    if (!read_registers(LSM6DSV_OUTX_L_G, data, 12)) {
        _inc_accel_error_count(accel_instance);
        _inc_gyro_error_count(gyro_instance);
        return;
    }

    // Parse gyro (first 6 bytes)
    {
        // Datasheet: 70 mdps/LSB at FS=±2000 dps (NOT 2000/32768!)
        const float gyro_scale = radians(0.070f);
        int16_t raw[3];
        raw[0] = int16_t(uint16_t(data[0] | (data[1] << 8)));
        raw[1] = int16_t(uint16_t(data[2] | (data[3] << 8)));
        raw[2] = int16_t(uint16_t(data[4] | (data[5] << 8)));

        Vector3f gyro(float(raw[0]), float(raw[1]), float(raw[2]));
        gyro *= gyro_scale;

        _rotate_and_correct_gyro(gyro_instance, gyro);
        _notify_new_gyro_raw_sample(gyro_instance, gyro);
    }

    // Parse accel (next 6 bytes)
    {
        // Datasheet: 0.488 mg/LSB at FS=±16G
        const float accel_scale = 0.000488f * GRAVITY_MSS;
        int16_t raw[3];
        raw[0] = int16_t(uint16_t(data[6] | (data[7] << 8)));
        raw[1] = int16_t(uint16_t(data[8] | (data[9] << 8)));
        raw[2] = int16_t(uint16_t(data[10] | (data[11] << 8)));

        Vector3f accel(float(raw[0]), float(raw[1]), float(raw[2]));
        accel *= accel_scale;

        _rotate_and_correct_accel(accel_instance, accel);
        _notify_new_accel_raw_sample(accel_instance, accel);
    }

    // Temperature: read every ~160 calls (~100 ms at 1600 Hz)
    if (_temperature_counter++ >= 160) {
        _temperature_counter = 0;
        uint8_t tbuf[2];
        if (read_registers(LSM6DSV_OUT_TEMP_L, tbuf, 2)) {
            int16_t raw_temp = int16_t(uint16_t(tbuf[0] | (tbuf[1] << 8)));
            // LSM6DSV16X temperature: sensitivity 256 LSB/degC, offset 25 degC
            float temp_degc = (float(raw_temp) / 256.0f) + 25.0f;
            _publish_temperature(accel_instance, temp_degc);
        }
    }
}

/*
 * Hardware initialisation.
 *
 * Follows the BetaFlight sequence:
 *  1. Software reset via CTRL3
 *  2. Wait for reset to complete
 *  3. Verify WHO_AM_I == 0x70
 *  4. Enable auto-increment and BDU
 *  5. Disable I2C/I3C to reduce noise in SPI mode
 */
bool AP_InertialSensor_LSM6DSV16X::hardware_init()
{
    hal.scheduler->delay(LSM6DSV16X_POWERUP_DELAY_MSEC);

    WITH_SEMAPHORE(_dev->get_semaphore());

    _dev->set_speed(AP_HAL::Device::SPEED_LOW);

    for (unsigned i = 0; i < LSM6DSV16X_HARDWARE_INIT_MAX_TRIES; i++) {
        // Software reset
        write_register(LSM6DSV_CTRL3, LSM6DSV_CTRL3_SW_RESET);
        hal.scheduler->delay(10);

        // Wait for reset to complete (SW_RESET bit clears itself)
        uint8_t ctrl3 = 0;
        for (uint8_t wait = 0; wait < 100; wait++) {
            read_registers(LSM6DSV_CTRL3, &ctrl3, 1);
            if ((ctrl3 & LSM6DSV_CTRL3_SW_RESET) == 0) {
                break;
            }
            hal.scheduler->delay(1);
        }
        if (ctrl3 & LSM6DSV_CTRL3_SW_RESET) {
            continue;
        }

        // Read and verify WHO_AM_I
        uint8_t whoami = 0;
        read_registers(LSM6DSV_WHO_AM_I, &whoami, 1);
        if (whoami != LSM6DSV16X_WHO_AM_I_CONST) {
            continue;
        }

        // Enable auto-increment and block data update
        write_register(LSM6DSV_CTRL3, LSM6DSV_CTRL3_IF_INC | LSM6DSV_CTRL3_BDU);

        // Disable I2C/I3C interface (SPI-only mode reduces noise)
        write_register(LSM6DSV_IF_CFG, LSM6DSV_IF_CFG_I2C_I3C_DISABLE);

        _dev->set_speed(AP_HAL::Device::SPEED_HIGH);

        DEV_PRINTF("LSM6DSV16X initialized after %d retries\n", i + 1);
        return true;
    }

    _dev->set_speed(AP_HAL::Device::SPEED_HIGH);
    return false;
}

bool AP_InertialSensor_LSM6DSV16X::init()
{
    _dev->set_read_flag(0x80);
    return hardware_init();
}
