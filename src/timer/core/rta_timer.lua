-- Real-Time Attack timer. Tracks wall-clock time via socket.gettime().

local deps = ...
local Timer = deps and deps.Timer or import('timer/core/base_timer.lua')
local getTime = deps and deps.getTime or GetTime

if getTime == nil then
    local socket = require('socket')
    getTime = function(_)
        return socket.gettime()
    end
end

local RtaTimer = {}

function RtaTimer:new(args)
    args = args or {}
    local o = Timer:new(args)
    o.StartingSystemTime = nil
    o.Cycle = nil
    o.PreviousWorldTime = nil
    setmetatable(o, self)
    self.__index = self
    return o
end

function RtaTimer:init()
    self.Cycle = 0
    self.PreviousWorldTime = _worldTime
    self.StartingSystemTime = getTime({})
end

function RtaTimer:start(startingOffset)
    self:init()
    Timer.start(self, startingOffset)
end

function RtaTimer:getTime()
    return Timer.getTime(self)
end

function RtaTimer:setTime(time)
    Timer.setTime(self, time)
    if self.Running then
        self.PreviousWorldTime = _worldTime
    end
end

function RtaTimer:pause()
    Timer.pause(self)
end

function RtaTimer:resume()
    Timer.resume(self)
end

function RtaTimer:stop()
    Timer.stop(self)
end

function RtaTimer:reset()
    Timer.reset(self)
    self.StartingSystemTime = nil
    self.Cycle = nil
    self.PreviousWorldTime = nil
end

function RtaTimer:update()
    if not self.Running or self.Paused then return end

    if self.Cycle < 30 then
        self.Cycle = self.Cycle + 1
        self:processWorldTime()
        return
    end

    self.Cycle = 0
    self:trueUp()
end

function RtaTimer:processWorldTime()
    local elapsed = _worldTime - self.PreviousWorldTime
    self:setTime(self.ElapsedTime + elapsed)
    self.PreviousWorldTime = _worldTime
end

function RtaTimer:trueUp()
    self.PreviousWorldTime = _worldTime
    self.ElapsedTime = getTime({}) - self.StartingSystemTime
end

return RtaTimer
