# SmartAudio VTX Channel Switcher Lua Script

Changes the band/channel — and therefore the broadcast frequency — of a
SmartAudio video transmitter (VTX) from an RC switch or rotary knob.

## How it works

ArduPilot already contains a complete SmartAudio driver (`AP_VideoTX` +
`AP_SmartAudio`). That driver continuously compares the *configured* VTX
parameters (`VTX_BAND`, `VTX_CHANNEL`, `VTX_FREQ`) with the state the VTX
reports, and whenever they differ it sends the matching SmartAudio
`SET_CHANNEL` command over the wire — handling framing, CRC, autobaud, the
SmartAudio protocol version and pit-mode safety for you.

This script therefore does only one small thing: it reads an RC channel and
writes `VTX_BAND` / `VTX_CHANNEL` for the selected preset. The built-in driver
does the rest. Because control is purely through the standard VTX parameters,
the same script also works when the build is using the Tramp or CRSF VTX
backend instead of SmartAudio.

This is different from the companion `SmartAudio.lua` script, which speaks the
SmartAudio protocol *directly* over a scripting serial port (and only changes
*power*). This script changes *channel/frequency* and relies on the native
driver, so it is set up against `SERIALx_PROTOCOL = 37` (SmartAudio), not the
scripting protocol.

## Wiring and parameters

1. Connect the VTX SmartAudio pad to a free autopilot UART **TX** line and
   configure that serial port:

   | Parameter          | Value | Meaning              |
   |--------------------|-------|----------------------|
   | `SERIALx_PROTOCOL` | `37`  | SmartAudio           |
   | `SERIALx_OPTIONS`  | `4`   | Half-duplex          |

2. Enable the VTX subsystem and scripting, then reboot:

   | Parameter    | Value | Meaning            |
   |--------------|-------|--------------------|
   | `VTX_ENABLE` | `1`   | Enable VTX         |
   | `SCR_ENABLE` | `1`   | Enable Lua scripts |

3. Choose an RC channel for selection and set its option to **Scripting1**:

   | Parameter    | Value | Meaning                       |
   |--------------|-------|-------------------------------|
   | `RCx_OPTION` | `300` | Scripting1 (read by the script)|

4. Copy `SmartAudio_Channels.lua` to the autopilot's `APM/scripts` directory
   (or `./scripts` for SITL) and reboot.

## Selecting a channel

The position of the RC channel is mapped across the list of presets, from the
low end of the channel to the high end:

* A **rotary knob / pot** gives smooth access to *every* preset.
* A **6-position switch** reaches 6 of the presets.
* A **2/3-position switch** reaches the ends / middle.

Each time the selection changes, the new band/channel/frequency is written to
the VTX parameters and a Ground Control Station message confirms it, e.g.:

```
VTX: R5  5806 MHz
```

## Choosing the presets

Edit the `PRESETS` table at the top of the script. Each entry is
`{ band, channel }`:

* `band`: `0:A 1:B 2:E 3:F(Airwave) 4:R(RaceBand) 5:L(LowRace) 6:1G3_A
  7:1G3_B 8:X 9:3G3_A 10:3G3_B` (same values as `VTX_BAND`)
* `channel`: `0..7` (same values as `VTX_CHANNEL`)

The default presets are the eight RaceBand channels R1–R8 (5658–5917 MHz).

```lua
local PRESETS = {
    { 4, 0 }, -- R1  5658 MHz
    { 4, 1 }, -- R2  5695 MHz
    ...
    { 4, 7 }, -- R8  5917 MHz
}
```

## Notes

* Setting `VTX_ENABLE = 0` leaves the parameters changeable but nothing will be
  transmitted to the VTX; the script warns once at start-up in that case.
* On real hardware the driver only applies a change after the VTX has answered
  the initial settings request, so the VTX must be powered and wired correctly.
* In SITL there is no physical VTX, so the script's effect is observed through
  the `VTX_BAND` / `VTX_CHANNEL` / `VTX_FREQ` parameters and the GCS messages it
  emits — useful for validating switch mapping and presets before flashing.
