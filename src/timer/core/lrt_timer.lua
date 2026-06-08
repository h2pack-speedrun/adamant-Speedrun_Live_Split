-- Load-Removed Time timer. LRT = RealTime - LoadTime.

local deps = ...
local getTime = deps and deps.getTime or GetTime

local LrtTimer = {}

function LrtTimer:new(args)
    args = args or {}
    local o = {
        Running = false,
        Loading = false,
        WasReset = false,
        LoadStartSystemTime = nil,
        LoadTime = 0,
        RealTimer = args.rtaTimer,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function LrtTimer:init()
    self.Loading = false
    self.LoadStartSystemTime = nil
    self.LoadTime = 0
    self.WasReset = false
end

function LrtTimer:start()
    self:init()
    self.Running = true
end

function LrtTimer:stop()
    if self.Loading then
        self:stopLoad()
    end
    self.Running = false
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
    self.LoadTime = self.LoadTime + timeThisLoad
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
    self.LoadStartSystemTime = nil
    self.LoadTime = 0
    self.WasReset = true
end

function LrtTimer:getLoadTime()
    if self.Loading and self.LoadStartSystemTime ~= nil then
        return self.LoadTime + getTime({}) - self.LoadStartSystemTime
    end
    return self.LoadTime
end

function LrtTimer:getTime()
    return self.RealTimer:getTime() - self:getLoadTime()
end

return LrtTimer
