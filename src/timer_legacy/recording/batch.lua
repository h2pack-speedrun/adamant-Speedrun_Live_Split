local deps = ... or {}
local batch = {}
local timerCore = deps.core
local timerOverlay = deps.overlay
local formatTimestamp = deps.formatTimestamp or function(value)
    return tostring(value or 0)
end
local readSetting = deps.readSetting or function()
    return nil
end
local refreshDisplay = deps.refreshDisplay or function() end
local isRunSuccess = deps.isRunSuccess or function(run)
    if type(WasRunSuccess) == "function" and run and run.RunResult ~= nil then
        return WasRunSuccess(run) == true
    end
    return run and run.Cleared == true
end

local MAX_BATCH_RUNS = 10

local overlayConfig = nil
local modeConfig = nil
local batchRows = {
    runs = {},
    current = { label = "", igt = "", rta = "", lrt = "" },
}
local batchProjectionRows = {}
local batchProjectionRunRows = {}
local batchProjectionCurrentRow = { key = "current", label = "", igt = "", rta = "", lrt = "" }
local batchProjectionCount = 0

for index = 1, MAX_BATCH_RUNS do
    batchRows.runs[index] = { label = "", igt = "", rta = "", lrt = "" }
    batchProjectionRunRows[index] = { key = "run" .. index, label = "", igt = "", rta = "", lrt = "" }
end

local batchState = {
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
    o.RtaTimer = timerCore.RtaTimer:new()
    o.LrtTimer = timerCore.LrtTimer:new({ withRtaTimer = o.RtaTimer })
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
    return formatTimestamp(value)
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
    return isRunSuccess(run) == true
end

local function readStore(alias)
    return readSetting(alias)
end

function batch.IsBatchActive()
    return batchState.active == true
end

function batch.IsBatchVisible()
    local modeVisible = not (modeConfig and modeConfig.isVisible) or modeConfig.isVisible() == true
    return modeVisible and (batchState.timer ~= nil or batchState.failed == true or batchState.completedRuns > 0)
end

function batch.GetBatchStatus()
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
    if batchState.ready then
        return {
            kind = "ready",
            text = ("Recording ready for %d runs"):format(batchState.targetRuns),
        }
    end
    return {
        kind = "idle",
        text = "Not recording",
    }
end

local function refreshBatchDisplay()
    refreshDisplay()
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
        refreshBatchDisplay()
    end
end

function batch.StartBatch(targetRuns)
    batchState.ready = true
    batchState.targetRuns = clampTargetRuns(targetRuns)
    clearBatchDisplay(false)
    refreshBatchDisplay()
end

function batch.StopBatch()
    batchState.ready = false
    clearBatchDisplay(true)
end

function batch.ClearBatch(targetRuns, refresh)
    if targetRuns ~= nil then
        batchState.targetRuns = clampTargetRuns(targetRuns)
    end
    clearBatchDisplay(false)
    if refresh ~= false then
        refreshBatchDisplay()
    end
end

function batch.StartBatchRun()
    if not batchState.ready then
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
end

function batch.UpdateBatchTimer()
    if batchState.active and batchState.timer then
        batchState.timer:update()
    end
end

function batch.ProcessBatchLoadEvent(isLoading)
    if batchState.active and batchState.timer then
        batchState.timer:processLoadEvent(isLoading)
    end
end

function batch.GetBatchDisplayTime(mode, activeTimer)
    if not batch.IsBatchVisible() then
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

function batch.FinalizeBatchRun(activeTimer, run)
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
end

function batch.Initialize()
    batchState.ready = false
    batchState.targetRuns = clampTargetRuns(readStore("BatchTargetRuns"))
    resetCurrentBatch(true)
    refreshBatchDisplay()
end

function batch.UpdateBatchDisplayRows()
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

function batch.GetBatchDisplayRow(index)
    batch.UpdateBatchDisplayRows()
    return batchRows.runs[index]
end

function batch.GetBatchCurrentDisplayRow()
    batch.UpdateBatchDisplayRows()
    return batchRows.current
end

local function batchRowVisible(row)
    return batch.IsBatchVisible() and row.label ~= nil and row.label ~= ""
end

local function appendProjectionRow(source, projection)
    if not batchRowVisible(source) then
        return
    end

    projection.label = source.label
    projection.igt = source.igt
    projection.rta = source.rta
    projection.lrt = source.lrt

    batchProjectionCount = batchProjectionCount + 1
    batchProjectionRows[batchProjectionCount] = projection
end

local function modeVisible(mode)
    if modeConfig and modeConfig.isModeVisible then
        return modeConfig.isModeVisible(mode) == true
    end
    return true
end

function batch.ConfigureBatchOverlays(config)
    overlayConfig = config
end

function batch.ConfigureBatchMode(config)
    modeConfig = config
end

function batch.RegisterBatchOverlay(overlays)
    if not overlayConfig then
        return
    end

    overlays.createTable("batch", {
        componentName = "SpeedrunTimer_Batch",
        region = timerOverlay.region,
        order = overlayConfig.order,
        maxRows = MAX_BATCH_RUNS + 1,
        columnGap = 20,
        columns = timerOverlay.buildTimerTableColumns(modeVisible),
        visible = function()
            return batch.IsBatchVisible()
        end,
    })
end

function batch.BuildBatchOverlayRows()
    local previousCount = batchProjectionCount
    batchProjectionCount = 0
    batch.UpdateBatchDisplayRows()
    if not batch.IsBatchVisible() then
        for index = 1, previousCount do
            batchProjectionRows[index] = nil
        end
        return batchProjectionRows
    end

    for index = 1, MAX_BATCH_RUNS do
        appendProjectionRow(batchRows.runs[index], batchProjectionRunRows[index])
    end

    appendProjectionRow(batchRows.current, batchProjectionCurrentRow)

    for index = batchProjectionCount + 1, previousCount do
        batchProjectionRows[index] = nil
    end
    return batchProjectionRows
end

return batch
