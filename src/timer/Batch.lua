SpeedrunTimerInternal = SpeedrunTimerInternal or {}
local internal = SpeedrunTimerInternal

local MAX_BATCH_RUNS = 10

local overlayConfig = nil
local modeConfig = nil
local batchOverlays = {}
local batchRows = {
    runs = {},
    current = { label = "", igt = "", rta = "", lrt = "" },
}

for index = 1, MAX_BATCH_RUNS do
    batchRows.runs[index] = { label = "", igt = "", rta = "", lrt = "" }
end

local batchState = {
    armed = false,
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
    o.RtaTimer = RtaTimer:new()
    o.LrtTimer = LrtTimer:new({ withRtaTimer = o.RtaTimer })
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
    return ("%s %d/%d"):format(prefix, runIndex, batchState.targetRuns)
end

local function getCurrentRunLabel()
    local runIndex = batchState.completedRuns + 1
    if batchState.targetRuns > 0 and runIndex > batchState.targetRuns then
        runIndex = batchState.targetRuns
    end
    return getRunLabel("Current", runIndex)
end

local function formatTime(value)
    return internal.FormatTimestamp and internal.FormatTimestamp(value) or tostring(value or 0)
end

local function toCentiseconds(value)
    return math.floor(((value or 0) * 100) + 0.0000001)
end

local function formatLiveTime(mode, value)
    local centiseconds = toCentiseconds(value)
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
    return batchState.timer and batchState.timer:getRealTime() or 0
end

local function getBatchLrt()
    return batchState.timer and batchState.timer:getLoadRemovedTime() or 0
end

local function isSuccessRun(run)
    if not run then
        return false
    end
    if type(WasRunSuccess) == "function" and run.RunResult ~= nil then
        return WasRunSuccess(run) == true
    end
    return run.Cleared == true
end

local function readStore(alias)
    local store = internal.store
    if store and store.read then
        return store.read(alias)
    end
    return nil
end

local function getRuntimeState()
    local store = internal.store
    if store and store.getRuntimeState then
        return store.getRuntimeState()
    end
    return nil
end

local function readRuntime(alias)
    local runtime = getRuntimeState()
    return runtime and runtime.read(alias) or nil
end

local function writeRuntime(alias, value)
    local runtime = getRuntimeState()
    if runtime then
        runtime.write(alias, value)
    end
end

local function persistRecordingState()
    writeRuntime("BatchRecordingArmed", batchState.armed == true)
    writeRuntime("BatchRunInProgress", batchState.active == true and batchState.currentRunActive == true)
end

function internal.IsBatchActive()
    return batchState.active == true
end

function internal.IsBatchVisible()
    local modeVisible = not (modeConfig and modeConfig.isVisible) or modeConfig.isVisible() == true
    return modeVisible and (batchState.timer ~= nil or batchState.failed == true or batchState.completedRuns > 0)
end

function internal.IsBatchForcingTimerModes()
    return false
end

function internal.GetBatchStatus()
    if batchState.active then
        return {
            kind = "active",
            text = ("Recording %d / %d"):format(batchState.completedRuns, batchState.targetRuns),
        }
    end
    if batchState.failed then
        return {
            kind = "failed",
            text = ("Failed (%d / %d complete)"):format(batchState.completedRuns, batchState.targetRuns),
        }
    end
    if #batchState.runRows > 0 then
        return {
            kind = "recorded",
            text = ("Recorded %d / %d"):format(batchState.completedRuns, batchState.targetRuns),
        }
    end
    if batchState.armed then
        return {
            kind = "armed",
            text = ("Armed for %d runs"):format(batchState.targetRuns),
        }
    end
    return {
        kind = "idle",
        text = "Not recording",
    }
end

function internal.GetBatchStatusText()
    return internal.GetBatchStatus().text
end

local function refreshDisplay()
    if internal.RefreshTimerDisplay then
        internal.RefreshTimerDisplay()
    end
end

local function stopTimer()
    if batchState.timer and batchState.timer.Running then
        batchState.timer:stop()
    end
end

local function resetCurrentBatch(clearTimer)
    batchState.active = false
    batchState.failed = false
    batchState.completedRuns = 0
    batchState.completedIgt = 0
    batchState.runRows = {}
    batchState.currentRunActive = false
    if clearTimer ~= false then
        stopTimer()
        batchState.timer = nil
    end
end

local function finishCurrentBatch()
    batchState.active = false
    batchState.currentRunActive = false
    stopTimer()
end

local function clearBatchDisplay(refresh)
    resetCurrentBatch(true)
    if refresh ~= false then
        refreshDisplay()
    end
end

function internal.StartBatch(targetRuns)
    batchState.armed = true
    batchState.targetRuns = clampTargetRuns(targetRuns)
    clearBatchDisplay(false)
    persistRecordingState()
    refreshDisplay()
end

function internal.StopBatch()
    batchState.armed = false
    clearBatchDisplay(true)
    persistRecordingState()
end

function internal.ClearBatch(targetRuns)
    if targetRuns ~= nil then
        batchState.targetRuns = clampTargetRuns(targetRuns)
    end
    clearBatchDisplay(false)
    persistRecordingState()
    refreshDisplay()
end

function internal.StartBatchRun()
    if not batchState.armed then
        return
    end
    if not batchState.active then
        resetCurrentBatch(true)
        if batchState.targetRuns <= 0 then
            batchState.targetRuns = clampTargetRuns()
        end
        batchState.active = true
    end
    if not batchState.timer then
        batchState.timer = BatchTimer:new()
        batchState.timer:start()
    end
    batchState.currentRunActive = true
    persistRecordingState()
end

function internal.UpdateBatchTimer()
    if batchState.active and batchState.timer then
        batchState.timer:update()
    end
end

function internal.ProcessBatchLoadEvent(isLoading)
    if batchState.active and batchState.timer then
        batchState.timer:processLoadEvent(isLoading)
    end
end

function internal.GetBatchDisplayTime(mode, activeTimer)
    if not internal.IsBatchVisible() then
        return nil
    end
    if mode == "igt" then
        local activeIgt = batchState.currentRunActive and getActiveRunIgt(activeTimer) or 0
        return formatLiveTime("igt", batchState.completedIgt + activeIgt)
    end
    if mode == "rta" then
        return formatLiveTime("rta", getBatchRta())
    end
    if mode == "lrt" then
        return formatLiveTime("lrt", getBatchLrt())
    end
    return nil
end

function internal.FinalizeBatchRun(activeTimer, run)
    if not batchState.active then
        return
    end

    local runIgt = getActiveRunIgt(activeTimer)
    if isSuccessRun(run) then
        batchState.completedIgt = batchState.completedIgt + runIgt
        batchState.completedRuns = batchState.completedRuns + 1
        batchState.runRows[#batchState.runRows + 1] = {
            label = getRunLabel("Run", batchState.completedRuns),
            igt = formatTime(batchState.completedIgt),
            rta = formatTime(getBatchRta()),
            lrt = formatTime(getBatchLrt()),
        }
        batchState.currentRunActive = false
        if batchState.completedRuns >= batchState.targetRuns then
            finishCurrentBatch()
        end
        persistRecordingState()
        return
    end

    batchState.failed = true
    batchState.currentRunActive = false
    batchState.runRows[#batchState.runRows + 1] = {
        label = "Failed",
        igt = formatTime(batchState.completedIgt + runIgt),
        rta = formatTime(getBatchRta()),
        lrt = formatTime(getBatchLrt()),
    }
    finishCurrentBatch()
    persistRecordingState()
end

function internal.InitializeBatchState()
    local wasArmed = readRuntime("BatchRecordingArmed") == true
    batchState.armed = wasArmed
    batchState.targetRuns = clampTargetRuns(readStore("BatchTargetRuns"))
    resetCurrentBatch(true)
    persistRecordingState()
    refreshDisplay()
end

function internal.UpdateBatchDisplayRows()
    for index = 1, MAX_BATCH_RUNS do
        local source = batchState.runRows[index]
        if source then
            setRow(batchRows.runs[index], source.label, source.igt, source.rta, source.lrt)
        else
            setRow(batchRows.runs[index], "", "", "", "")
        end
    end

    if batchState.active and batchState.currentRunActive then
        setRow(batchRows.current, getCurrentRunLabel(), "", "", "")
    else
        setRow(batchRows.current, "", "", "", "")
    end
end

function internal.GetBatchDisplayRow(index)
    internal.UpdateBatchDisplayRows()
    return batchRows.runs[index]
end

function internal.GetBatchCurrentDisplayRow()
    internal.UpdateBatchDisplayRows()
    return batchRows.current
end

local function batchRowVisible(row)
    return internal.IsBatchVisible() and row.label ~= nil and row.label ~= ""
end

local function modeVisible(mode)
    if modeConfig and modeConfig.isModeVisible then
        return modeConfig.isModeVisible(mode) == true
    end
    return true
end

local function registerBatchRow(key, orderOffset, row)
    return internal.TimerOverlay.registerTableRow(batchOverlays, key, {
        idPrefix = "speedrun.timer.batch.",
        componentPrefix = "SpeedrunTimer_Batch_",
        order = overlayConfig.order + orderOffset,
        row = row,
        modeVisible = modeVisible,
        visible = function()
            return batchRowVisible(row)
        end,
    })
end

function internal.ConfigureBatchOverlays(config)
    overlayConfig = config
end

function internal.ConfigureBatchMode(config)
    modeConfig = config
end

function internal.EnsureBatchOverlays()
    if not overlayConfig then
        return
    end
    for index = 1, MAX_BATCH_RUNS do
        registerBatchRow("run" .. index, index, batchRows.runs[index])
    end
    registerBatchRow("current", MAX_BATCH_RUNS + 1, batchRows.current)
end

return internal
