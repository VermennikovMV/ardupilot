SCRIPT_NAME = "VTX CRSF Menu"

MAV_SEVERITY = { EMERGENCY = 0, ALERT = 1, CRITICAL = 2, ERROR = 3,
                 WARNING = 4, NOTICE = 5, INFO = 6, DEBUG = 7 }

CRSF_EVENT = { PARAMETER_READ = 1, PARAMETER_WRITE = 2 }

CRSF_PARAM_TYPE = { TEXT_SELECTION = 9, INFO = 12 }

local BANDS_OPTIONS = "A;B;E;F;Race;LowRace;1G3A;1G3B;X;3G3A;3G3B"
local CHAN_OPTIONS  = "1;2;3;4;5;6;7;8"
local PWR_OPTIONS   = "25;100;200;400;800"
local PWR_MW        = { 25, 100, 200, 400, 800 }

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function create_text_entry(name, options, value, min, max, default, unit)
    return string.pack(">BzzBBBBz", CRSF_PARAM_TYPE.TEXT_SELECTION,
        name, options, value, min, max, default, unit or "")
end

local function pwr_index_from_mw(mw)
    local idx = 0
    for i = 1, #PWR_MW do
        if mw >= PWR_MW[i] then idx = i - 1 end
    end
    return idx
end

local cur_band = math.floor((param:get('VTX_BAND') or 0) + 0.5)
local cur_chan = math.floor((param:get('VTX_CHANNEL') or 0) + 0.5)
local cur_pwr  = pwr_index_from_mw(math.floor((param:get('VTX_POWER') or 25) + 0.5))

local band_item, chan_item, pwr_item

local menu = crsf:add_menu("VTX")
if menu ~= nil then
    band_item = menu:add_parameter(create_text_entry("Band",    BANDS_OPTIONS, clamp(cur_band, 0, 10), 0, 10, 0, ""))
    chan_item = menu:add_parameter(create_text_entry("Channel", CHAN_OPTIONS,  clamp(cur_chan, 0, 7),  0, 7,  0, ""))
    pwr_item  = menu:add_parameter(create_text_entry("Power",   PWR_OPTIONS,   clamp(cur_pwr, 0, 4),   0, 4,  4, "mW"))
    gcs:send_text(MAV_SEVERITY.INFO, "VTX CRSF menu ready")
else
    gcs:send_text(MAV_SEVERITY.WARNING, "VTX CRSF menu: CRSF telem not active")
end

local function handle_write()
    local param_id, payload, events = crsf:get_menu_event(CRSF_EVENT.PARAMETER_WRITE)
    if (events & CRSF_EVENT.PARAMETER_WRITE) == 0 then
        return
    end

    local sel = string.unpack(">B", payload)

    if band_item ~= nil and param_id == band_item:id() then
        param:set_and_save('VTX_BAND', sel)
        crsf:send_write_response(payload)
        gcs:send_text(MAV_SEVERITY.INFO, string.format("VTX: band -> %d", sel))
    elseif chan_item ~= nil and param_id == chan_item:id() then
        param:set_and_save('VTX_CHANNEL', sel)
        crsf:send_write_response(payload)
        gcs:send_text(MAV_SEVERITY.INFO, string.format("VTX: channel -> %d", sel + 1))
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
