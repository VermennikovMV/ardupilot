--[[
   Switch the band / channel (and therefore the frequency) of a SmartAudio
   video transmitter from an RC switch or knob.

   How it works
   ------------
   ArduPilot already has a complete SmartAudio driver (AP_VideoTX +
   AP_SmartAudio). That driver continuously compares the *configured* VTX
   parameters (VTX_BAND / VTX_CHANNEL / VTX_FREQ) against the state the VTX
   reports, and whenever they differ it sends the matching SmartAudio
   SET_CHANNEL / SET_FREQUENCY command over the wire. See
   AP_SmartAudio::loop() -> have_params_changed() -> update_vtx_params().

   So to "change channel" all this script has to do is write VTX_BAND and
   VTX_CHANNEL - the C++ driver does the protocol work (framing, CRC, autobaud,
   protocol-version handling, pit-mode safety, etc). This keeps the script tiny
   and reuses ArduPilot's tested implementation, and it works for any backend
   the build supports (SmartAudio, Tramp, CRSF), not just SmartAudio.

   Setup
   -----
   1. Connect the VTX SmartAudio pad to a free UART TX and set:
         SERIALx_PROTOCOL = 37   (SmartAudio)
         SERIALx_OPTIONS  = 4    (half-duplex)
         VTX_ENABLE       = 1
   2. Enable scripting and reboot:
         SCR_ENABLE       = 1
   3. Pick an RC channel for selection and set its option to "Scripting1":
         RCx_OPTION       = 300
      A rotary knob gives smooth access to every preset; a 6-position switch
      reaches 6 of them; a 2/3-position switch reaches the ends/middle.
   4. Copy this file to the autopilot's APM/scripts directory (or ./scripts in
      SITL) and reboot.

   Edit the PRESETS table below to choose which band/channel each switch
   position selects.
]] --

-- ------------------------- user configuration ----------------------------

-- RC aux-function used to select the channel. 300 == "Scripting1".
local SELECT_RC_OPTION = 300

-- How often to poll the switch, in milliseconds.
local RUN_INTERVAL_MS = 250

-- The presets the switch/knob selects between, in order from the low end of
-- the channel to the high end. Each entry is { band, channel } where:
--   band    : 0:A 1:B 2:E 3:F(Airwave) 4:R(RaceBand) 5:L(LowRace)
--             6:1G3_A 7:1G3_B 8:X 9:3G3_A 10:3G3_B   (matches VTX_BAND)
--   channel : 0..7                                    (matches VTX_CHANNEL)
-- The comment shows the resulting frequency for convenience.
local PRESETS = {
    { 4, 0 }, -- R1  5658 MHz
    { 4, 1 }, -- R2  5695 MHz
    { 4, 2 }, -- R3  5732 MHz
    { 4, 3 }, -- R4  5769 MHz
    { 4, 4 }, -- R5  5806 MHz
    { 4, 5 }, -- R6  5843 MHz
    { 4, 6 }, -- R7  5880 MHz
    { 4, 7 }, -- R8  5917 MHz
}

-- -------------------------------------------------------------------------

local MAV_SEVERITY = { EMERGENCY = 0, ALERT = 1, CRITICAL = 2, ERROR = 3,
                       WARNING = 4, NOTICE = 5, INFO = 6, DEBUG = 7 }

-- Band/channel -> frequency (MHz). Mirrors AP_VideoTX::VIDEO_CHANNELS exactly
-- so the GCS/OSD shows the correct frequency even before the VTX confirms it.
-- Keys are 0-based band numbers; the inner array is indexed channel+1.
local FREQ = {
    [0]  = { 5865, 5845, 5825, 5805, 5785, 5765, 5745, 5725 }, -- A
    [1]  = { 5733, 5752, 5771, 5790, 5809, 5828, 5847, 5866 }, -- B
    [2]  = { 5705, 5685, 5665, 5645, 5885, 5905, 5925, 5945 }, -- E
    [3]  = { 5740, 5760, 5780, 5800, 5820, 5840, 5860, 5880 }, -- F (Airwave)
    [4]  = { 5658, 5695, 5732, 5769, 5806, 5843, 5880, 5917 }, -- R (RaceBand)
    [5]  = { 5362, 5399, 5436, 5473, 5510, 5547, 5584, 5621 }, -- L (Low Race)
    [6]  = { 1080, 1120, 1160, 1200, 1240, 1280, 1320, 1360 }, -- 1G3 A
    [7]  = { 1080, 1120, 1160, 1200, 1258, 1280, 1320, 1360 }, -- 1G3 B
    [8]  = { 4990, 5020, 5050, 5080, 5110, 5140, 5170, 5200 }, -- X
    [9]  = { 3330, 3350, 3370, 3390, 3410, 3430, 3450, 3470 }, -- 3G3 A
    [10] = { 3170, 3190, 3210, 3230, 3250, 3270, 3290, 3310 }, -- 3G3 B
}

local BAND_NAME = { [0] = "A", [1] = "B", [2] = "E", [3] = "F", [4] = "R",
                    [5] = "L", [6] = "1G3A", [7] = "1G3B", [8] = "X",
                    [9] = "3G3A", [10] = "3G3B" }

local function band_name(b) return BAND_NAME[b] or "?" end

local function freq_mhz(band, chan)
    local t = FREQ[band]
    if t ~= nil and t[chan + 1] ~= nil then
        return t[chan + 1]
    end
    return 0
end

-- runtime state
local last_index = -1     -- last preset index we applied (-1 == none yet)
local warned_no_rc = false -- so we only nag about a missing RC option once

-- Map the switch/knob position (-1 .. +1) to a preset index (1 .. N).
-- Works for a knob (continuous) and for 2/3/6-position switches.
local function index_from_switch(ch)
    local n = #PRESETS
    if n <= 1 then
        return 1
    end
    local norm = ch:norm_input_ignore_trim() -- -1.0 .. +1.0
    local idx = math.floor((norm + 1.0) * 0.5 * (n - 1) + 0.5) + 1
    if idx < 1 then idx = 1 end
    if idx > n then idx = n end
    return idx
end

-- Apply a preset by writing the VTX_* parameters. The native VTX driver picks
-- the change up and transmits it to the VTX.
local function apply_preset(idx)
    local band = PRESETS[idx][1]
    local chan = PRESETS[idx][2]

    local ok = param:set('VTX_BAND', band)
    ok = param:set('VTX_CHANNEL', chan) and ok
    if not ok then
        gcs:send_text(MAV_SEVERITY.ERROR,
            "VTX: VTX_* params not found - is AP_VideoTX enabled?")
        return false
    end

    -- Keep VTX_FREQ in step so the GCS/OSD report the right frequency. This is
    -- exactly the value the driver derives from band+channel, so it never
    -- fights the driver; it just makes the selection visible immediately.
    local freq = freq_mhz(band, chan)
    if freq > 0 then
        param:set('VTX_FREQ', freq)
    end

    gcs:send_text(MAV_SEVERITY.INFO,
        string.format("VTX: %s%d  %d MHz", band_name(band), chan + 1, freq))
    return true
end

local function update()
    local ch = rc:find_channel_for_option(SELECT_RC_OPTION)
    if ch == nil then
        if not warned_no_rc then
            gcs:send_text(MAV_SEVERITY.WARNING,
                string.format("VTX: no RC channel has RCx_OPTION = %d", SELECT_RC_OPTION))
            warned_no_rc = true
        end
        return
    end
    warned_no_rc = false

    local idx = index_from_switch(ch)
    if idx ~= last_index then
        if apply_preset(idx) then
            last_index = idx
        end
    end
end

-- Protected wrapper: a runtime error in update() is reported but never stops
-- the script from running.
local function protected_update()
    local ok, err = pcall(update)
    if not ok then
        gcs:send_text(MAV_SEVERITY.ERROR, "VTX: " .. tostring(err))
    end
    return protected_update, RUN_INTERVAL_MS
end

-- one-off startup checks / banner
if param:get('VTX_ENABLE') == nil then
    gcs:send_text(MAV_SEVERITY.ERROR,
        "VTX: AP_VideoTX not available in this firmware - script idle")
    return -- stop: nothing to do
end
if param:get('VTX_ENABLE') == 0 then
    gcs:send_text(MAV_SEVERITY.WARNING,
        "VTX: VTX_ENABLE is 0 - set it to 1 for the change to reach the VTX")
end
gcs:send_text(MAV_SEVERITY.INFO,
    string.format("VTX: SmartAudio channel switcher ready (%d presets)", #PRESETS))

-- give RC a couple of seconds to come good before the first read
return protected_update, 2000
