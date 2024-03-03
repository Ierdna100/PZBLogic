--- Developed using LifeBoatAPI - Stormworks Lua plugin for VSCode - https://code.visualstudio.com/download (search "Stormworks Lua with LifeboatAPI" extension)
--- If you have any issues, please report them here: https://github.com/nameouschangey/STORMWORKS_VSCodeExtension/issues - by Nameous Changey


--[====[ HOTKEYS ]====]
-- Press F6 to simulate this file
-- Press F7 to build the project, copy the output from /_build/out/ into the game to use
-- Remember to set your Author name etc. in the settings: CTRL+COMMA


--[====[ EDITABLE SIMULATOR CONFIG - *automatically removed from the F7 build output ]====]
---@section __LB_SIMULATOR_ONLY__
do
    ---@type Simulator -- Set properties and screen sizes here - will run once when the script is loaded
    simulator = simulator

    simulator:setScreen(1, "9x5")

    -- Runs every tick just before onTick; allows you to simulate the inputs changing
    ---@param simulator Simulator Use simulator:<function>() to set inputs etc.
    ---@param ticks     number Number of ticks since simulator started
    function onLBSimulatorTick(simulator, ticks)
        simulator:setInputBool(1, simulator:getIsClicked(1)) -- magnet 1000
        simulator:setInputBool(2, simulator:getIsClicked(2)) -- magnet 500
        simulator:setInputBool(3, simulator:getIsClicked(3)) -- magnet 2000
        simulator:setInputBool(4, simulator:getIsToggled(4)) -- override
        simulator:setInputBool(5, simulator:getIsClicked(5)) -- release
        simulator:setInputBool(6, simulator:getIsClicked(6)) -- acknowledge
        simulator:setInputBool(7, simulator:getIsClicked(7)) -- releaseBrake
        simulator:setInputBool(8, simulator:getIsClicked(8)) -- setBhr
        simulator:setInputBool(9, simulator:getIsToggled(9)) -- reverserNeutral

        simulator:setInputBool(15, simulator:getSlider(10) == 1) -- Tick

        simulator:setInputNumber(1, simulator:getSlider(1) * 165 / 3.6) -- speed
        simulator:setInputNumber(2, simulator:getSlider(2) * 120) -- new BHR
    end;
end
---@endsection


--[====[ IN-GAME CODE ]====]

-- try require("Folder.Filename") to include code from another file in this, so you can store code in libraries
-- the "LifeBoatAPI" is included by default in /_build/libs/ - you can use require("LifeBoatAPI") to get this, and use all the LifeBoatAPI.<functions>!

speedLimit = 105
eBrakes = false
-- spd = 0

lights = {
    mode55 = false,
    mode70 = false,
    mode85 = false,
    command40 = false,
    magnet500 = false,
    magnet1000 = false,
    setAllLights = function (self, modeLight, b40, magnet500, magnet1000)
        self.mode55 = false
        self.mode70 = false
        self.mode85 = false

        self[mode.mode] = modeLight
        self.command40 = b40
        self.magnet500 = magnet500
        self.magnet1000 = magnet1000
    end
}

mode = {
    ---@type "mode55" | "mode70" | "mode85"
    mode = "mode55",
    index = 1,
    ---@generic T
    ---@param ... T
    ---@return T
    getValueByMode = function (self, ...)
        return ({...})[self.index]
    end,
    ---@param newMode "mode55" | "mode70" | "mode85"
    setMode = function (self, newMode)
        self.mode = newMode
        self.index = self.modes[newMode]
    end,
    modes = {
        mode55 = 3,
        mode70 = 2,
        mode85 = 1
    }
}

states = {
    unrestricted = 1,
    under1000Hz = 2,
    under500Hz = 3,
    underB40 = 4,
    under1000HzRestrictive = 5,
    under500HzRestrictive = 6,
    unknown = 7,
    eStop = 8,
    awaitAck = 9,
    awaitRelFrom1000 = 10,
    awaitRelRestrictedFrom1000 = 11,
    awaitRelFrom500 = 12,
    awaitRelRestrictedFrom500 = 13
}

state = states.unknown

tick = 0
tickrate = 60
blinkerFreq = 40

blinker = false

validReverserPositions = {
    F = 1,
    R = 2
}
lastValidReverser = validReverserPositions.F

---@class Counter
---@field start function
---@field value number
---@field done boolean
---@field onDone function[]
---@field timeBased boolean
---@field rate number
---@field stopAt number

---@type table<string, Counter>
counters = {}

-- Braking Hundreths
bhr = 0

-- 1000 Hz magnet
counters.acknowledge = {
    timeBased = true,
    start = function (self)
        self.value = 4
        self.done = false
        self.rate = -1 / 60
    end,
    value = 0,
    done = true,
    onDone = {
        function ()
            state = states.eStop
        end
    },
    rate = 0,
    stopAt = 0
}
counters.on1000 = {
    timeBased = true,
    start = function (self)
        self.value = mode:getValueByMode(165, 125, 105)
        self.rate = -mode:getValueByMode(0.97 / tickrate * 3.6, 0.53 / tickrate * 3.6, 0.36 / tickrate * 3.6)
        self.stopAt = mode:getValueByMode(85, 75, 55)
        self.done = false

        counters.release1000:start()
    end,
    value = 0,
    rate = 0,
    stopAt = 0,
    done = true,
    onDone = {}
}
counters.release1000 = {
    timeBased = false,
    start = function (self)
        self.value = 1250
        self.rate = -1
        self.done = false
    end,
    value = 0,
    rate = 0,
    stopAt = 0,
    done = true,
    onDone = {
        function ()
            if (state == states.under1000HzRestrictive) then
                state = states.awaitRelRestrictedFrom1000
            elseif (state == states.under1000Hz) then
                state = states.awaitRelFrom1000
            end
        end
    }
}

-- 500 Hz magnet
counters.on500 = {
    timeBased = false,
    start = function (self)
        self.value = mode:getValueByMode(65, 50, 40)
        self.done = false
        self.stopAt = mode:getValueByMode(45, 35, 25)
        self.rate = speedLimitCounterCurve(self.value, self.stopAt, 153)
        counters.release500:start()
    end,
    value = 0,
    done = true,
    onDone = {},
    rate = 0,
    stopAt = 0
}
counters.release500 = {
    timeBased = false,
    start = function (self)
        self.value = 250
        self.done = false
        self.rate = -1
    end,
    value = 0,
    done = true,
    onDone = {
        function ()
            if (state == states.under500HzRestrictive) then
                state = states.awaitRelRestrictedFrom500
            elseif (state == states.under500Hz) then
                state = states.awaitRelFrom500
            end
        end
    },
    rate = 0,
    stopAt = 0
}
counters.restrictive500 = {
    timeBased = false,
    start = function (self)
        self.value = 45
        self.done = false
        self.rate = speedLimitCounterCurve(45, 25, 153)
    end,
    value = 0,
    done = true,
    onDone = {},
    rate = 0,
    stopAt = 25
}

-- Restrictive mode
counters.restrictiveCalculator = {
    timeBased = true,
    start = function (self)
        self.value = 10
        self.done = false
        self.rate = -1 / 60
    end,
    value = 0,
    done = true,
    onDone = {
        function ()
            if (state == states.under1000Hz) then
                state = states.under1000HzRestrictive
            elseif (state == states.under500Hz) then
                if (mode.mode == "mode85") then
                    counters.restrictive500:start()
                end

                state = states.under500HzRestrictive
            end
        end
    },
    rate = 0,
    stopAt = 0
}

--- 2000 Hz magnet
counters.onB40 = {
    timeBased = false,
    start = function (self)
        self.value = 2000
        self.done = false
        self.rate = -1
    end,
    value = 0,
    done = true,
    onDone = {
        function ()
            if (state == states.underB40) then
                state = states.unrestricted
            end
        end
    },
    rate = 0,
    stopAt = 0
}

-- Worst state machine known to human-kind
function onTick()
    if (tick == 0) then
        setMode()
        state = states.unknown
    end

    if (tick % blinkerFreq == 0) then
        blinker = not blinker
    end

    local inputs = getInputs()

    if (inputs.setBhr and inputs.speed < 0.1 and inputs.reverser < 0.05 and inputs.reverser > -0.05) then
        bhr = inputs.newBhr
        setMode()
    end

    local currReverser = 0
    if (inputs.reverser >= 0) then
        currReverser = validReverserPositions.F
    else
        currReverser = validReverserPositions.R
    end

    if (inputs.magnet1000) then
        lastValidReverser = currReverser
        counters.acknowledge:start()
        state = states.awaitAck
    end

    if (state == states.awaitAck) then
        if (counters.acknowledge == 1) then
            state = states.eStop
        elseif (inputs.acknowledge) then
            counters.acknowledge.done = true
            counters.on1000:start()
            state = states.under1000Hz
        end
    end

    if (inputs.magnet500) then
        lastValidReverser = currReverser
        if (state == states.unrestricted or state == states.awaitAck) then
            state = states.eStop
        else
            if (state == states.under1000HzRestrictive) then
                state = states.under500HzRestrictive
            else
                state = states.under500Hz
            end

            counters.on500:start()
        end
    end

    if (inputs.magnet2000) then
        lastValidReverser = currReverser
        if (inputs.override and inputs.speed < 40 / 3.6) then
            state = states.underB40
            counters.onB40:start()
        else
            state = states.eStop
        end
    end

    if (inputs.speed < 10 / 3.6 and (state == states.under1000Hz or state == states.under500Hz) and counters.restrictiveCalculator.done) then
        counters.restrictiveCalculator:start()
    elseif (not counters.restrictiveCalculator.done and inputs.speed > 10 / 3.6) then
        counters.restrictiveCalculator.done = true
    end

    if (inputs.speed < 0.1 and (state == states.under1000Hz or state == states.under500Hz)) then
        for _, f in ipairs(counters.restrictiveCalculator.onDone) do
            f()
        end
    end

    if (state == states.awaitRelFrom1000
    or state == states.awaitRelFrom500
    or state == states.awaitRelRestrictedFrom1000
    or state == states.awaitRelRestrictedFrom500) then
        if (inputs.release) then
            state = states.unrestricted
        end
    end

    if (state == states.eStop) then
        if (inputs.releaseEBrake and inputs.speed < 0.1) then
            counters.on1000:start()
            state = states.under1000Hz
        end
    end

    -- counters doing counter things
    for k, v in pairs(counters) do
        if (v.done) then
            goto continue
        end

        if (v.timeBased) then
            v.value = v.value + v.rate
        else
            v.value = v.value + (v.rate * (inputs.speed / tickrate))
        end

        if (v.value < v.stopAt) then
            v.value = v.stopAt
            v.rate = 0
            v.done = true
            for _, f in ipairs(v.onDone) do
                f()
            end
        end
        ::continue::
    end

    if (inputs.speed * 3.6 > speedLimit + 5) then
        state = states.eStop
    end

    if (currReverser ~= lastValidReverser) then
        state = states.unknown
    end

    if (state == states.awaitAck or state == states.unrestricted) then
        speedLimit = mode:getValueByMode(165, 125, 105)
        lights:setAllLights(true, false, false, false)
    elseif (state == states.under1000Hz) then
        speedLimit = counters.on1000.value
        lights:setAllLights(blinker, false, false, true)
    elseif (state == states.under1000HzRestrictive) then
        speedLimit = 45
        lights:setAllLights(false, false, false, true)
        lights.mode85 = blinker
        lights.mode70 = not blinker
    elseif (state == states.under500Hz) then
        speedLimit = counters.on500.value
        lights:setAllLights(blinker, false, true, false)
    elseif (state == states.under500HzRestrictive) then
        speedLimit = mode:getValueByMode(counters.restrictive500.value, 25, 25)
        lights:setAllLights(false, false, true, false)
        lights.mode85 = blinker
        lights.mode70 = not blinker
    elseif (state == states.underB40) then
        speedLimit = 40
        lights:setAllLights(blinker, true, false, false)
    elseif (state == states.eStop) then
        speedLimit = 0
        lights:setAllLights(false, false, false, false)
        lights.mode85 = blinker
        lights.mode70 = not blinker
    elseif (state == states.unknown) then
        speedLimit = 50
        lights:setAllLights(false, false, false, false)
    elseif (state == states.awaitRelFrom500) then
        speedLimit = mode:getValueByMode(45, 35, 25)
        lights:setAllLights(blinker, false, false, false)
    elseif (state == states.awaitRelRestrictedFrom500) then
        speedLimit = mode:getValueByMode(counters.restrictive500, 25, 25)
        lights:setAllLights(false, false, false, false)
        lights.mode85 = blinker
        lights.mode70 = not blinker
    elseif (state == states.awaitRelFrom1000) then
        speedLimit = mode:getValueByMode(85, 70, 55)
        lights:setAllLights(blinker, false, false, false)
    elseif (state == states.awaitRelRestrictedFrom1000) then
        speedLimit = 45
        lights:setAllLights(false, false, false, false)
        lights.mode85 = blinker
        lights.mode70 = not blinker
    end

    tick = tick + 1
    out()
end

function setMode()
    if (bhr > 110) then
        mode:setMode("mode85")
    elseif (bhr > 66) then
        mode:setMode("mode70")
    else
        mode:setMode("mode55")
    end
end

function getInputs()
    return {
        magnet1000 = input.getBool(1),
        magnet500 = input.getBool(2),
        magnet2000 = input.getBool(3),
        override = input.getBool(4),
        release = input.getBool(5),
        acknowledge = input.getBool(6),
        releaseEBrake = input.getBool(7),
        setBhr = input.getBool(8),
        speed = input.getNumber(1),
        newBhr = input.getNumber(2),
        reverser = input.getNumber(3)
    }
end

function out()
    output.setBool(1, lights.mode55)
    output.setBool(2, lights.mode70)
    output.setBool(3, lights.mode85)
    output.setBool(4, lights.magnet500)
    output.setBool(5, lights.magnet1000)
    output.setBool(6, lights.command40)
    output.setBool(7, state == states.awaitAck) -- ack buzzer
    output.setNumber(1, speedLimit)

    output.setBool(32, eBrakes)
    output.setBool(29, state == states.awaitRelRestricted or state == states.awaitRel)
    output.setBool(28, blinker)

    output.setNumber(32, mode.index)
    output.setNumber(31, counters.acknowledge.value * tickrate)
    output.setNumber(30, bhr)

    output.setNumber(29, counters.acknowledge.value)
    output.setNumber(28, counters.on1000.value)
    output.setNumber(27, counters.on500.value)
    output.setNumber(26, counters.onB40.value)
    output.setNumber(25, counters.release1000.value)
    output.setNumber(24, counters.release500.value)
    output.setNumber(23, counters.restrictive500.value)
    output.setNumber(22, counters.restrictiveCalculator.value)
end

-- function onDraw()
--     bools = {
--         { condition = lights.mode55, key = "mode55" },
--         { condition = lights.mode70, key = "mode70" },
--         { condition = lights.mode85, key = "mode85" },
--         { condition = lights.magnet500, key = "magnet500" },
--         { condition = lights.magnet1000, key = "magnet1000" },
--         { condition = lights.command40, key = "command40" },
--         { condition = state == states.awaitAck, key = "buzzer" },
--         { condition = eBrakes, key = "E-BRAKE" },
--         { condition = state == states.awaitRelRestricted or state == states.awaitRel, key = "release" },
--         --{ condition = blinker, key = "blinker" }
--     }

--     k = ""
--     for key, value in pairs(states) do
--         if (value == state) then
--             k = key
--             break
--         end
--     end

--     nums = {
--         { value = speedLimit, key = "LIMIT: " },
--         { value = mode.index, key = "INDEX: " },
--         { value = counters.acknowledge.value * tickrate, key = "ACK: " },
--         { value = k, key = "STATE: "},
--         { value = state, key = "STATE: "},
--         { value = counters.acknowledge.value, key = "ACK: " },
--         { value = counters.on1000.value, key = "1000: " },
--         { value = counters.on500.value, key = "500: " },
--         { value = counters.onB40.value, key = "B40: " },
--         { value = counters.release1000.value, key = "REL 1000: " },
--         { value = counters.release500.value, key = "REL  500: " },
--         { value = counters.restrictive500.value, key = "REST 500: " },
--         { value = counters.restrictiveCalculator.value, key = "RESTRICT: " },
--         { value = input._numbers[1] * 3.6, key = "SPEED: " },
--     }

--     j = 0
--     for i = 1, #bools, 1 do
--         v = bools[i]
--         if (v.condition) then
--             screen.setColor(0,255,0)
--         else
--             screen.setColor(255,0,0)
--         end

--         screen.drawText(0, (i - 1) * 6 + 1, v.key)
--         j = i
--     end

--     screen.setColor(70,70,0)
--     for i = 1, #nums, 1 do
--         v = nums[i]
--         screen.drawText(0, (i + j - 1) * 6 + 1, v.key .. v.value)
--     end
-- end

function speedLimitCounterCurve(startSpeed, endSpeed, distance)
    return -(startSpeed - endSpeed) / distance
end
