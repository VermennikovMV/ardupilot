-- station_switches.lua
-- ============================================================
-- Станина с магнитными контактами, два тумблера:
--   Тумблер 1 (S5 / GPIO 54) — ARM / DISARM (toggle)
--   Тумблер 2 (S6 / GPIO 55) — PWM на RC6: 1100 ↔ 1500 (toggle)
--
-- Pull-up: разомкнуто = HIGH (1), замкнуто на GND = LOW (0).
-- Реагируем ТОЛЬКО на falling edge (1→0 = замыкание).
-- Rising edge (размыкание при взлёте) — полностью игнорируется.
--
-- Цикл работы:
--   1. Борт на станине, тумблер выкл → HIGH (1)
--   2. Оператор щёлкает тумблер ARM → LOW (0) → falling edge → ARM
--   3. Борт взлетает, магнитный контакт размыкается → rising edge → игнор
--   4. Борт садится, контакт замыкается → LOW (0) → falling edge → DISARM
--   5. Для повторного арма: выключить тумблер, включить снова
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

--------------------------------------------------------------------
-- СОСТОЯНИЕ
--------------------------------------------------------------------
local arm_prev           = 1       -- предыдущий уровень ARM pin (1=HIGH)
local rc_prev            = 1       -- предыдущий уровень RC pin  (1=HIGH)
local arm_edge_time      = uint32_t(0)
local rc_edge_time       = uint32_t(0)

local rc_is_on           = false   -- текущее состояние RC PWM (false = 1100)
local rc_chan            = nil     -- объект RC_Channel, инициализируется позже

--------------------------------------------------------------------
-- УТИЛИТЫ
--------------------------------------------------------------------
local function log(lvl, msg)
    gcs:send_text(lvl, "STN: " .. msg)
end

--- Детектор falling edge (1→0 = замыкание контакта).
--- Rising edge (0→1 = размыкание) обновляет состояние, но НЕ триггерит.
--- gpio:read() возвращает 0 или 1 (число), НЕ boolean.
--- Возвращает: triggered, new_prev, new_edge_time
local function falling_edge(cur, prev, edge_time, now)
    if cur == prev then
        return false, prev, edge_time
    end
    if (now - edge_time):toint() < DEBOUNCE_MS then
        return false, prev, edge_time
    end
    -- Falling edge: HIGH(1) → LOW(0) (замыкание)
    if cur == 0 and prev == 1 then
        return true, cur, now
    end
    -- Rising edge: LOW(0) → HIGH(1) (размыкание) — обновляем, не триггерим
    return false, cur, now
end

--------------------------------------------------------------------
-- ГЛАВНЫЙ ЦИКЛ
--------------------------------------------------------------------
local function update()
    local now = millis()

    local arm_now = gpio:read(ARM_PIN)
    local rc_now  = gpio:read(RC_PIN)

    if arm_now == nil or rc_now == nil then
        log(3, "GPIO read error")
        return update, POLL_INTERVAL_MS
    end

    local armed = arming:is_armed()

    -- === ТУМБЛЕР ARM / DISARM ===
    local arm_trig
    arm_trig, arm_prev, arm_edge_time = falling_edge(arm_now, arm_prev, arm_edge_time, now)

    if arm_trig then
        if not armed then
            if arming:arm() then
                log(6, "ARM (switch)")
            else
                log(4, "ARM FAILED — check pre-arm")
            end
        else
            if arming:disarm() then
                log(6, "DISARM (switch)")
            else
                log(4, "DISARM FAILED")
            end
        end
    end

    -- === ТУМБЛЕР RC PWM ===
    local rc_trig
    rc_trig, rc_prev, rc_edge_time = falling_edge(rc_now, rc_prev, rc_edge_time, now)

    if rc_trig then
        rc_is_on = not rc_is_on
        log(6, string.format("RC%d → %d", RC_CHANNEL, rc_is_on and RC_PWM_ON or RC_PWM_OFF))
    end

    -- Обновляем override КАЖДЫЙ цикл, чтобы не сбросился по таймауту
    if rc_chan then
        rc_chan:set_override(rc_is_on and RC_PWM_ON or RC_PWM_OFF)
    end

    return update, POLL_INTERVAL_MS
end

--------------------------------------------------------------------
-- ИНИЦИАЛИЗАЦИЯ
--------------------------------------------------------------------
gpio:pinMode(ARM_PIN, 0)
gpio:pinMode(RC_PIN, 0)

-- Проверяем что пины читаются
local arm_test = gpio:read(ARM_PIN)
local rc_test  = gpio:read(RC_PIN)

if arm_test == nil or rc_test == nil then
    log(3, "FAIL: GPIO read — check SERVO5/6_FUNCTION = -1")
    return
end

arm_prev = arm_test
rc_prev  = rc_test

rc_chan = rc:get_channel(RC_CHANNEL)
if not rc_chan then
    log(3, string.format("FAIL: RC channel %d not found", RC_CHANNEL))
    return
end

rc_chan:set_override(RC_PWM_OFF)

log(6, string.format(
    "Ready: ARM=GPIO%d, RC=GPIO%d→RC%d (%d/%d)",
    ARM_PIN, RC_PIN, RC_CHANNEL, RC_PWM_OFF, RC_PWM_ON
))

return update, POLL_INTERVAL_MS
