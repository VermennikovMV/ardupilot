local SELECT_RC_OPTION = 300

local RUN_INTERVAL_MS = 250

local PRESETS = {
    { 4, 0 },
    { 4, 1 },
    { 4, 2 },
    { 4, 3 },
    { 4, 4 },
    { 4, 5 },
    { 4, 6 },
    { 4, 7 },
}

local MAV_SEVERITY = { EMERGENCY = 0, ALERT = 1, CRITICAL = 2, ERROR = 3,
                       WARNING = 4, NOTICE = 5, INFO = 6, DEBUG = 7 }

local FREQ = {
    [0]  = { 5865, 5845, 5825, 5805, 5785, 5765, 5745, 5725 },
    [1]  = { 5733, 5752, 5771, 5790, 5809, 5828, 5847, 5866 },
    [2]  = { 5705, 5685, 5665, 5645, 5885, 5905, 5925, 5945 },
    [3]  = { 5740, 5760, 5780, 5800, 5820, 5840, 5860, 5880 },
    [4]  = { 5658, 5695, 5732, 5769, 5806, 5843, 5880, 5917 },
    [5]  = { 5362, 5399, 5436, 5473, 5510, 5547, 5584, 5621 },
    [6]  = { 1080, 1120, 1160, 1200, 1240, 1280, 1320, 1360 },
    [7]  = { 1080, 1120, 1160, 1200, 1258, 1280, 1320, 1360 },
    [8]  = { 4990, 5020, 5050, 5080, 5110, 5140, 5170, 5200 },
    [9]  = { 3330, 3350, 3370, 3390, 3410, 3430, 3450, 3470 },
    [10] = { 3170, 3190, 3210, 3230, 3250, 3270, 3290, 3310 },
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

local last_index = -1
local warned_no_rc = false

local function index_from_switch(ch)
    local n = #PRESETS
    if n <= 1 then
        return 1
    end
    local norm = ch:norm_input_ignore_trim()
    local idx = math.floor((norm + 1.0) * 0.5 * (n - 1) + 0.5) + 1
    if idx < 1 then idx = 1 end
    if idx > n then idx = n end
    return idx
end

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

local function protected_update()
    local ok, err = pcall(update)
    if not ok then
        gcs:send_text(MAV_SEVERITY.ERROR, "VTX: " .. tostring(err))
    end
    return protected_update, RUN_INTERVAL_MS
end

if param:get('VTX_ENABLE') == nil then
    gcs:send_text(MAV_SEVERITY.ERROR,
        "VTX: AP_VideoTX not available in this firmware - script idle")
    return
end
if param:get('VTX_ENABLE') == 0 then
    gcs:send_text(MAV_SEVERITY.WARNING,
        "VTX: VTX_ENABLE is 0 - set it to 1 for the change to reach the VTX")
end
gcs:send_text(MAV_SEVERITY.INFO,
    string.format("VTX: SmartAudio channel switcher ready (%d presets)", #PRESETS))

return protected_update, 2000
