SCRIPT_NAME = "VTX CRSF Menu"

MAV_SEVERITY = { EMERGENCY = 0, ALERT = 1, CRITICAL = 2, ERROR = 3,
                 WARNING = 4, NOTICE = 5, INFO = 6, DEBUG = 7 }

CRSF_EVENT = { PARAMETER_READ = 1, PARAMETER_WRITE = 2 }

CRSF_PARAM_TYPE = { TEXT_SELECTION = 9, INFO = 12 }

-- Betaflight-style VTX menu: Band / Channel / Power.
local BAND_OPTIONS = "A;B;E;F;Race;LowRace;1G3A;1G3B;X;3G3A;3G3B"
local BAND_NAME = { [0] = "A", [1] = "B", [2] = "E", [3] = "F", [4] = "Race",
                    [5] = "LowRace", [6] = "1G3A", [7] = "1G3B", [8] = "X",
                    [9] = "3G3A", [10] = "3G3B" }

local CHAN_OPTIONS = "1;2;3;4;5;6;7;8"

local PWR_OPTIONS = "25;100;200;400;800"
local PWR_MW      = { 25, 100, 200, 400, 800 }

-- band -> channel frequency (MHz), mirrors AP_VideoTX::VIDEO_CHANNELS
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

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function freq_mhz(band, chan)
    local t = FREQ[band]
    if t ~= nil and t[chan + 1] ~= nil then return t[chan + 1] end
    return 0
end

local function create_text_entry(name, options, value, min, max, default, unit)
    return string.pack(">BzzBBBBz", CRSF_PARAM_TYPE.TEXT_SELECTION,
        name, options, value, min, max, default, unit or "")
end

-- seed the menu from the live parameters
local cur_band = clamp(math.floor((param:get('VTX_BAND') or 4) + 0.5), 0, 10)
local cur_chan = clamp(math.floor((param:get('VTX_CHANNEL') or 0) + 0.5), 0, 7)
local cur_pwr  = math.floor((param:get('VTX_POWER') or 25) + 0.5)
local cur_pwr_idx = 0
for i = 1, #PWR_MW do
    if cur_pwr >= PWR_MW[i] then cur_pwr_idx = i - 1 end
end

-- push the resulting frequency to VTX_FREQ so the OSD/GCS show it
local function update_freq()
    local f = freq_mhz(cur_band, cur_chan)
    if f > 0 then param:set_and_save('VTX_FREQ', f) end
    return f
end

local band_item, chan_item, pwr_item

local menu = crsf:add_menu("VTX")
if menu ~= nil then
    band_item = menu:add_parameter(create_text_entry("Band",    BAND_OPTIONS, cur_band, 0, 10, 4, ""))
    chan_item = menu:add_parameter(create_text_entry("Channel", CHAN_OPTIONS, cur_chan, 0, 7,  0, ""))
    pwr_item  = menu:add_parameter(create_text_entry("Power",   PWR_OPTIONS,  clamp(cur_pwr_idx, 0, 4), 0, 4, 4, "mW"))
    gcs:send_text(MAV_SEVERITY.INFO, "VTX CRSF menu ready")
else
    gcs:send_text(MAV_SEVERITY.WARNING, "VTX CRSF menu: CRSF telem not active")
end

local function announce()
    gcs:send_text(MAV_SEVERITY.INFO, string.format("VTX: %s%d  %d MHz",
        BAND_NAME[cur_band] or "?", cur_chan + 1, freq_mhz(cur_band, cur_chan)))
end

local function handle_write()
    local param_id, payload, events = crsf:get_menu_event(CRSF_EVENT.PARAMETER_WRITE)
    if (events & CRSF_EVENT.PARAMETER_WRITE) == 0 then
        return
    end

    local sel = string.unpack(">B", payload)

    if band_item ~= nil and param_id == band_item:id() then
        cur_band = clamp(sel, 0, 10)
        param:set_and_save('VTX_BAND', cur_band)
        update_freq()
        crsf:send_write_response(payload)
        announce()
    elseif chan_item ~= nil and param_id == chan_item:id() then
        cur_chan = clamp(sel, 0, 7)
        param:set_and_save('VTX_CHANNEL', cur_chan)
        update_freq()
        crsf:send_write_response(payload)
        announce()
    elseif pwr_item ~= nil and param_id == pwr_item:id() then
        local mw = PWR_MW[sel + 1] or 25
        param:set_and_save('VTX_POWER', mw)
        crsf:send_write_response(payload)
        gcs:send_text(MAV_SEVERITY.INFO, string.format("VTX: power -> %d mW", mw))
    end
end

local function update()
    if menu ~= nil then
        handle_write()
    end
    return update, 100
end

return update, 5000
