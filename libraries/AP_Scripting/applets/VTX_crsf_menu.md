# VTX CRSF Menu Lua Script

Gives a Betaflight-style **VTX menu inside the radio handset**: open the
Crossfire/ELRS (CRSF) device menu on the transmitter and change the video
transmitter **Band / Channel / Power** from there — no sticks, no goggles.

ArduPilot has no built-in VTX menu for the radio (unlike Betaflight), but the
CRSF menu system is scriptable. This applet registers a `VTX` menu over CRSF
and, when you change an item on the radio, writes the corresponding
`VTX_BAND` / `VTX_CHANNEL` / `VTX_POWER` parameter. The native VTX backend
(SmartAudio, **IRC Tramp** or CRSF) then applies it to the transmitter.

## Requirements

* RC link is **CRSF** (TBS Crossfire or ExpressLRS). The menu travels over the
  CRSF link, so this does not work on SBUS/PPM/PWM/etc.
* `SCR_ENABLE = 1` (scripting) and `VTX_ENABLE = 1`.
* The VTX is wired and its backend configured, e.g. for IRC Tramp:
  `SERIALx_PROTOCOL = 44`, `SERIALx_OPTIONS = 4`.

## Setup

1. Set up CRSF RC input as usual: `SERIALy_PROTOCOL = 23`, `RSSI_TYPE = 3`
   (ELRS: also `RC_OPTIONS` bit 13 / +8192 for 420 kBaud, DMA-capable UART).
2. `SCR_ENABLE = 1`, `VTX_ENABLE = 1`, reboot.
3. Copy `VTX_crsf_menu.lua` to the autopilot's `APM/scripts` directory
   (or `./scripts` in SITL) and reboot.
4. On boot you should see the GCS message `VTX CRSF menu ready`.

## Using it on the radio

On an EdgeTX/OpenTX handset open the CRSF/ExpressLRS settings (the radio's
"ExpressLRS"/"Crossfire" Lua, or the model's CRSF page), select the **flight
controller** device, and you will find a **`VTX`** menu with:

* **Band** – A, B, E, F, Race, LowRace, 1G3A, 1G3B, X, 3G3A, 3G3B
* **Channel** – 1…8
* **Power** – 25 / 100 / 200 / 400 / 800 mW

Changing an item writes the matching `VTX_*` parameter and the VTX follows.

## Notes

* Power values map to the standard SmartAudio/Tramp levels; the VTX rounds to
  the nearest level it actually supports.
* The menu's initial values are read from the current `VTX_*` parameters on
  boot.
* In SITL the menu registers (`VTX CRSF menu ready`) but cannot be rendered —
  there is no CRSF handset — so the on-radio menu must be confirmed on real
  hardware.
