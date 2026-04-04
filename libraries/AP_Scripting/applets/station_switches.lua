-- station_switches.lua
-- ============================================================
-- Станина с магнитными контактами, два тумблера:
--   Тумблер 1 (S5 / GPIO 54) — ARM / DISARM (по уровню)
--   Тумблер 2 (S6 / GPIO 55) — PWM на RC6: 1100 ↔ 1500 (toggle)
--
-- Pull-up: разомкнуто = HIGH (true), замкнуто на GND = LOW (false).
--
-- Тумблер ARM — привязка к уровню:
--   HIGH (тумблер выкл / контакт разомкнут) → ARM
--   LOW  (тумблер вкл  / контакт замкнут)   → DISARM
--   Rising edge  (LOW→HIGH) → ARM
--   Falling edge (HIGH→LOW) → DISARM
--
-- При входе в режим GUIDED_NOGPS (mode 20) тумблеры блокируются —
-- скрипт продолжает обновлять prev-состояния пинов, но не выполняет
-- ARM/DISARM и не переключает RC. Это предотвращает ложные
-- срабатывания при сходе со станины.
--
-- Тумблер RC — toggle: каждое замыкание (falling edge)
-- переключает PWM на RC6 между 1100 и 1500.
--
-- ============================================================
-- ТРЕБОВАНИЯ (параметры ArduPilot):
--   SCR_ENABLE       = 1
--   SERVO5_FUNCTION  = -1          (GPIO для тумблера ARM)
--   SERVO6_FUNCTION  = -1          (GPIO для тумблера RC)
-- ============================================================

--------------------------------------------------------------------
-- НАСТРОЙКИ
--------------------------------------------------------------------
local ARM_PIN           = 54       -- GPIO тумблера ARM   (S5)
local RC_PIN            = 55       -- GPIO тумблера RC    (S6)

local RC_CHANNEL        = 6        -- RC-канал для PWM
local RC_PWM_OFF        = 1100     -- PWM при выключенном состоянии
local RC_PWM_ON         = 1500     -- PWM при включённом состоянии

local DEBOUNCE_MS       = 100      -- Антидребезг, мс
local POLL_INTERVAL_MS  = 50       -- Период опроса, мс

local MODE_GUIDED_NOGPS = 20       -- Copter GUIDED_NOGPS mode number

--------------------------------------------------------------------
-- СОСТОЯНИЕ
--------------------------------------------------------------------
local arm_prev           = true    -- предыдущий уровень ARM pin (true=HIGH)
local rc_prev            = true    -- предыдущий уровень RC pin
local arm_edge_time      = uint32_t(0)
local rc_edge_time       = uint32_t(0)

local rc_is_on           = false   -- текущее состояние RC PWM (false = 1100)

--------------------------------------------------------------------
-- RC-канал (получаем объект один раз)
--------------------------------------------------------------------
local rc_chan = nil

--------------------------------------------------------------------
-- УТИЛИТЫ
--------------------------------------------------------------------
local function log(lvl, msg)
    gcs:send_text(lvl, "STN: " .. msg)
end

--- gpio:read() возвращает boolean: true = HIGH, false = LOW
local function read_pin(pin)
    return gpio:read(pin)
end

--- Детектор фронтов с антидребезгом.
--- Возвращает: edge ("rising"/"falling"/nil), new_prev, new_edge_time
local function detect_edge(cur, prev, edge_time, now)
    if cur == prev then
        return nil, prev, edge_time
    end
    if (now - edge_time) < DEBOUNCE_MS then
        return nil, prev, edge_time
    end
    if prev == true and cur == false then
        return "falling", cur, now
    end
    if prev == false and cur == true then
        return "rising", cur, now
    end
    return nil, cur, now
end

--------------------------------------------------------------------
-- ГЛАВНЫЙ ЦИКЛ
--------------------------------------------------------------------
local function update()
    local now = millis()

    local arm_now = read_pin(ARM_PIN)
    local rc_now  = read_pin(RC_PIN)

    if arm_now == nil or rc_now == nil then
        log(3, "GPIO read error")
        return update, POLL_INTERVAL_MS
    end

    -- Edge detection работает ВСЕГДА (чтобы prev не рассинхронизировался)
    local arm_edge
    arm_edge, arm_prev, arm_edge_time = detect_edge(arm_now, arm_prev, arm_edge_time, now)

    local rc_edge
    rc_edge, rc_prev, rc_edge_time = detect_edge(rc_now, rc_prev, rc_edge_time, now)

    -- Блокировка тумблеров в режиме GUIDED_NOGPS
    local mode = vehicle:get_mode()
    if mode == MODE_GUIDED_NOGPS then
        return update, POLL_INTERVAL_MS
    end

    -- === ТУМБЛЕР ARM / DISARM (по уровню) ===
    -- Rising edge  (LOW→HIGH, тумблер выкл) → ARM
    -- Falling edge (HIGH→LOW, тумблер вкл)  → DISARM
    if arm_edge == "rising" then
        if not arming:is_armed() then
            if arming:arm() then
                log(6, "ARM (switch OFF / undocked)")
            else
                log(4, "ARM FAILED — check pre-arm")
            end
        end
    elseif arm_edge == "falling" then
        if arming:is_armed() then
            if arming:disarm() then
                log(6, "DISARM (switch ON)")
            else
                log(4, "DISARM FAILED")
            end
        end
    end

    -- === ТУМБЛЕР RC PWM (toggle по falling edge) ===
    if rc_edge == "falling" then
        rc_is_on = not rc_is_on
        log(6, string.format("RC%d -> %d", RC_CHANNEL, rc_is_on and RC_PWM_ON or RC_PWM_OFF))
    end

    -- Обновляем override КАЖДЫЙ цикл, чтобы не сбросился по таймауту
    if rc_chan then
        if rc_is_on then
            rc_chan:set_override(RC_PWM_ON)
        else
            rc_chan:set_override(RC_PWM_OFF)
        end
    end

    return update, POLL_INTERVAL_MS
end

--------------------------------------------------------------------
-- ИНИЦИАЛИЗАЦИЯ
--------------------------------------------------------------------

-- pinMode возвращает void — проверяем работоспособность через пробное чтение
gpio:pinMode(ARM_PIN, 0)
gpio:pinMode(RC_PIN, 0)

local arm_test = read_pin(ARM_PIN)
local rc_test  = read_pin(RC_PIN)

if arm_test == nil then
    log(3, string.format("FAIL: cannot read GPIO %d", ARM_PIN))
    return
end

if rc_test == nil then
    log(3, string.format("FAIL: cannot read GPIO %d", RC_PIN))
    return
end

rc_chan = rc:get_channel(RC_CHANNEL)
if rc_chan == nil then
    log(3, string.format("FAIL: cannot get RC channel %d", RC_CHANNEL))
    return
end

-- Инициализируем prev-состояния реальными значениями с пинов
arm_prev = arm_test
rc_prev  = rc_test
arm_edge_time = millis()
rc_edge_time  = millis()

rc_chan:set_override(RC_PWM_OFF)

log(6, string.format(
    "Ready: ARM=GPIO%d, RC=GPIO%d->RC%d (%d/%d)",
    ARM_PIN, RC_PIN, RC_CHANNEL, RC_PWM_OFF, RC_PWM_ON
))

return update, POLL_INTERVAL_MS
