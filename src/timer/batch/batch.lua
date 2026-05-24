local deps = ... or {}
local core = deps.core
local formatTimestamp = deps.formatTimestamp
local isRunSuccess = deps.isRunSuccess or function(run)
    return run and run.Cleared == true
end

local MAX_BATCH_RUNS = 10
local batch = {}
local rows = {
    runs = {},
    current = { label = "", igt = "", rta = "", lrt = "" },
}
for index = 1, MAX_BATCH_RUNS do
    rows.runs[index] = { label = "", igt = "", rta = "", lrt = "" }
end

local state = {
    ready = false,
    active = false,
    failed = false,
    targetRuns = 0,
    completedRuns = 0,
    completedIgt = 0,
    runRows = {},
    timer = nil,
    currentRunActive = false,
}
local displayCache = {
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

local BatchTimer = {}

function BatchTimer:new()
    local o = {}
    o.Running = false
    o.RtaTimer = core.RtaTimer:new()
    o.LrtTimer = core.LrtTimer:new({ withRtaTimer = o.RtaTimer })
    setmetatable(o, self)
    self.__index = self
    return o
end

function BatchTimer:start()
    self.Running = true
    self.RtaTimer:start()
    self.LrtTimer:start()
end

function BatchTimer:stop()
    self.Running = false
    self.RtaTimer:stop()
    self.LrtTimer:stop()
end

function BatchTimer:update()
    if not self.Running then
        return
    end
    self.RtaTimer:update()
    self.LrtTimer:update()
end

function BatchTimer:getRealTime()
    return self.RtaTimer:getTime()
end

function BatchTimer:getLoadRemovedTime()
    return self.LrtTimer:getTime()
end

function BatchTimer:processLoadEvent(isLoading)
    if self.Running then
        self.LrtTimer:processLoadEvent(isLoading)
    end
end

local function clampTargetRuns(value)
    value = math.floor(tonumber(value) or 3)
    if value < 1 then
        return 1
    end
    if value > MAX_BATCH_RUNS then
        return MAX_BATCH_RUNS
    end
    return value
end

local function setRow(row, label, igt, rta, lrt)
    row.label = label or ""
    row.igt = igt or ""
    row.rta = rta or ""
    row.lrt = lrt or ""
    return row
end

local function getRunLabel(prefix, runIndex)
    return ("%s %d/%d"):format(prefix, runIndex, state.targetRuns)
end

local function getCurrentRunLabel()
    local runIndex = state.completedRuns + 1
    if state.targetRuns > 0 and runIndex > state.targetRuns then
        runIndex = state.targetRuns
    end
    return getRunLabel("Current", runIndex)
end

local function formatTime(value)
    return formatTimestamp(value)
end

local function formatLiveTime(mode, value)
    local centiseconds = core.toCentiseconds(value)
    if displayCache.centiseconds[mode] ~= centiseconds then
        displayCache.centiseconds[mode] = centiseconds
        displayCache.formatted[mode] = formatTime(value)
    end
    return displayCache.formatted[mode]
end

local function getActiveRunIgt(activeTimer)
    if activeTimer and activeTimer.getInGameTime then
        return activeTimer:getInGameTime()
    end
    return 0
end

local function getBatchRta()
    return state.timer and state.timer:getRealTime() or 0
end

local function getBatchLrt()
    return state.timer and state.timer:getLoadRemovedTime() or 0
end

local function stopTimer()
    if state.timer and state.timer.Running then
        state.timer:stop()
    end
end

local function resetCurrentBatch(clearTimer)
    state.active = false
    state.failed = false
    state.completedRuns = 0
    state.completedIgt = 0
    state.runRows = {}
    state.currentRunActive = false
    if clearTimer ~= false then
        stopTimer()
        state.timer = nil
    end
end

local function finishCurrentBatch()
    state.active = false
    state.currentRunActive = false
    stopTimer()
end

function batch.start(targetRuns)
    state.ready = true
    state.targetRuns = clampTargetRuns(targetRuns)
    resetCurrentBatch(true)
end

function batch.stop()
    state.ready = false
    resetCurrentBatch(true)
end

function batch.clear(targetRuns)
    if targetRuns ~= nil then
        state.targetRuns = clampTargetRuns(targetRuns)
    end
    resetCurrentBatch(true)
end

function batch.startRun()
    if not state.ready then
        return false
    end
    if not state.active then
        resetCurrentBatch(true)
        if state.targetRuns <= 0 then
            state.targetRuns = clampTargetRuns()
        end
        state.active = true
    end
    if not state.timer then
        state.timer = BatchTimer:new()
        state.timer:start()
    end
    state.currentRunActive = true
    return true
end

function batch.updateTimer()
    if state.active and state.timer then
        state.timer:update()
    end
end

function batch.processLoadEvent(isLoading)
    if state.active and state.timer then
        state.timer:processLoadEvent(isLoading)
        return true
    end
    return false
end

function batch.displayTime(mode, activeTimer)
    if not batch.isVisible() then
        return nil
    end
    if mode == "igt" then
        local activeIgt = state.currentRunActive and getActiveRunIgt(activeTimer) or 0
        return formatLiveTime("igt", state.completedIgt + activeIgt)
    end
    if mode == "rta" then
        return formatLiveTime("rta", getBatchRta())
    end
    if mode == "lrt" then
        return formatLiveTime("lrt", getBatchLrt())
    end
    return nil
end

function batch.finalizeRun(activeTimer, run)
    if not state.active then
        return false
    end

    local runIgt = getActiveRunIgt(activeTimer)
    if isRunSuccess(run) then
        state.completedIgt = state.completedIgt + runIgt
        state.completedRuns = state.completedRuns + 1
        state.runRows[#state.runRows + 1] = {
            label = getRunLabel("Run", state.completedRuns),
            igt = formatTime(state.completedIgt),
            rta = formatTime(getBatchRta()),
            lrt = formatTime(getBatchLrt()),
        }
        state.currentRunActive = false
        if state.completedRuns >= state.targetRuns then
            finishCurrentBatch()
        end
        return true
    end

    state.failed = true
    state.currentRunActive = false
    state.runRows[#state.runRows + 1] = {
        label = "Failed",
        igt = formatTime(state.completedIgt + runIgt),
        rta = formatTime(getBatchRta()),
        lrt = formatTime(getBatchLrt()),
    }
    finishCurrentBatch()
    return true
end

function batch.updateRows()
    for index = 1, MAX_BATCH_RUNS do
        local source = state.runRows[index]
        if source then
            setRow(rows.runs[index], source.label, source.igt, source.rta, source.lrt)
        else
            setRow(rows.runs[index], "", "", "", "")
        end
    end

    if state.active and state.currentRunActive then
        setRow(rows.current, getCurrentRunLabel(), "", "", "")
    else
        setRow(rows.current, "", "", "", "")
    end
end

function batch.status()
    if state.active then
        return {
            kind = "active",
            text = ("Recording %d / %d"):format(state.completedRuns, state.targetRuns),
        }
    end
    if state.failed then
        return {
            kind = "failed",
            text = ("Failed (%d / %d complete)"):format(state.completedRuns, state.targetRuns),
        }
    end
    if #state.runRows > 0 then
        return {
            kind = "recorded",
            text = ("Recorded %d / %d"):format(state.completedRuns, state.targetRuns),
        }
    end
    if state.ready then
        return {
            kind = "ready",
            text = ("Recording ready for %d runs"):format(state.targetRuns),
        }
    end
    return {
        kind = "idle",
        text = "Not recording",
    }
end

function batch.isActive()
    return state.active == true
end

function batch.isVisible()
    return state.timer ~= nil or state.failed == true or state.completedRuns > 0
end

function batch.row(index)
    batch.updateRows()
    return rows.runs[index]
end

function batch.currentRow()
    batch.updateRows()
    return rows.current
end

function batch.rows()
    batch.updateRows()
    return rows
end

batch.BatchTimer = BatchTimer

return batch
