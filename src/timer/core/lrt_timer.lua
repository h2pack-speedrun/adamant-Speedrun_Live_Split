-- Load-Removed Time timer. LRT = RealTime - LoadTime.

local deps = ...
local Timer = deps and deps.Timer or import('timer/core/base_timer.lua')
local RtaTimer = deps and deps.RtaTimer or import('timer/core/rta_timer.lua', nil, {
    Timer = Timer,
})
local getTime = deps and deps.getTime or GetTime

local LrtTimer = {}

function LrtTimer:new(args)
    args = args or {}
    local o = {
        Running = false,
        Loading = false,
        WasReset = false,
        LoadStartSystemTime = nil,
        RealTimer = args.withRtaTimer or RtaTimer:new(),
        LoadTimer = Timer:new(),
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function LrtTimer:init()
    self.RealTimer:init()
    self.LoadTimer:init()
    self.WasReset = false
end

function LrtTimer:start()
    self:init()
    self.Running = true
    self.RealTimer:start()
    self.LoadTimer:start()
    self.LoadTimer:pause()
end

function LrtTimer:stop()
    self.Running = false
    self.RealTimer:stop()
    self.LoadTimer:stop()
end

function LrtTimer:startLoad()
    if self.Loading then return end
    self.Loading = true
    self.LoadStartSystemTime = getTime({})
end

function LrtTimer:stopLoad()
    if not self.Loading then return end
    self.Loading = false

    local now = getTime({})
    local timeThisLoad = now - self.LoadStartSystemTime
    self.LoadTimer:setTime(self.LoadTimer:getTime() + timeThisLoad)
    self.LoadStartSystemTime = nil
end

function LrtTimer:processLoadEvent(isLoading)
    if not self.Running then return end
    if isLoading then
        self:startLoad()
    else
        self:stopLoad()
    end
end

function LrtTimer:reset()
    self.Running = false
    self.Loading = false
    self.RealTimer:reset()
    self.LoadTimer:reset()
    self.WasReset = true
end

function LrtTimer:update()
    self.RealTimer:update()
end

function LrtTimer:trueUp()
    self.RealTimer:trueUp()
end

function LrtTimer:getTime()
    return self.RealTimer:getTime() - self.LoadTimer:getTime()
end

return LrtTimer
