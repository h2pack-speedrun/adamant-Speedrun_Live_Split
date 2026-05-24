local deps = ... or {}
local core = deps.core
local isMultiRunMode = deps.isMultiRunMode

local LiveRunTimer = {}

function LiveRunTimer:new()
    local o = {}
    o.Running = false
    o.RtaTimer = core.RtaTimer:new()
    o.LrtTimer = core.LrtTimer:new({ withRtaTimer = o.RtaTimer })
    o.IgtTimer = core.IgtTimer:new()
    setmetatable(o, self)
    self.__index = self
    return o
end

function LiveRunTimer:start()
    self.Running = true
    self.RtaTimer:start()
    self.LrtTimer:start()
end

function LiveRunTimer:stop()
    self.Running = false
    self.RtaTimer:stop()
    self.LrtTimer:stop()
end

function LiveRunTimer:update()
    self.RtaTimer:update()
    self.LrtTimer:update()
end

function LiveRunTimer:getRealTime()
    return self.RtaTimer:getTime()
end

function LiveRunTimer:getLoadRemovedTime()
    return self.LrtTimer:getTime()
end

function LiveRunTimer:getInGameTime()
    return self.IgtTimer:getTime()
end

local singleRun = {}
local activeTimer = nil
local runFinalized = false
local showCompletedRun = false
local snapshot = {
    igt = 0,
    rta = 0,
    lrt = 0,
    centiseconds = {
        igt = -1,
        rta = -1,
        lrt = -1,
    },
    formatted = {
        igt = "00:00.00",
        rta = "00:00.00",
        lrt = "00:00.00",
    },
}

local function updateSnapshotValue(key, value)
    value = value or 0
    snapshot[key] = value

    local centiseconds = core.toCentiseconds(value)
    if snapshot.centiseconds[key] ~= centiseconds then
        snapshot.centiseconds[key] = centiseconds
        snapshot.formatted[key] = core.formatCentiseconds(centiseconds)
    end
end

local function updateSnapshot()
    updateSnapshotValue("igt", activeTimer and activeTimer:getInGameTime() or 0)
    updateSnapshotValue("rta", activeTimer and activeTimer:getRealTime() or 0)
    updateSnapshotValue("lrt", activeTimer and activeTimer:getLoadRemovedTime() or 0)
end

function singleRun.clear()
    if activeTimer then
        activeTimer:stop()
    end
    activeTimer = nil
    runFinalized = false
    showCompletedRun = false
    updateSnapshot()
end

function singleRun.beginRun()
    singleRun.clear()
    activeTimer = LiveRunTimer:new()
    updateSnapshot()
    return activeTimer
end

function singleRun.startDisplayLoop()
    local started = false
    if activeTimer and not activeTimer.Running and not runFinalized then
        activeTimer:start()
        started = true
    end
    if activeTimer then
        updateSnapshot()
    end
    return started
end

function singleRun.updateTick()
    if activeTimer and activeTimer.Running then
        activeTimer:update()
    end
    updateSnapshot()
    return activeTimer
end

function singleRun.finalizeRun()
    if runFinalized or not activeTimer then
        return false, nil
    end
    runFinalized = true
    activeTimer:stop()
    showCompletedRun = not isMultiRunMode()
    updateSnapshot()
    return true, activeTimer
end

function singleRun.processLoadEvent(isLoading)
    if not (activeTimer and activeTimer.Running) then
        return false
    end
    activeTimer.LrtTimer:processLoadEvent(isLoading)
    return true
end

function singleRun.hasCurrentRunDisplay()
    return activeTimer ~= nil and (activeTimer.Running == true or showCompletedRun == true)
end

function singleRun.getActiveTimer()
    return activeTimer
end

function singleRun.getSnapshot()
    return snapshot
end

singleRun.LiveRunTimer = LiveRunTimer

return singleRun
