local deps = ... or {}
local singleRun = deps.singleRun
local recording = deps.recording
local splits = deps.splits
local batch = deps.batch
local isEnabled = deps.isEnabled
local getCurrentRun = deps.getCurrentRun
local refreshStructure = deps.refreshStructure
local refreshText = deps.refreshText

local runLoop = {}

local function activeTimer()
    return singleRun.getActiveTimer()
end

local function snapshot()
    return singleRun.getSnapshot()
end

local function updateLiveRecordingRows(timer, run, timerSnapshot)
    if timer then
        splits.recordCompletedBiomes(timer, run, timerSnapshot)
        splits.updateLiveRows(timer, run, timerSnapshot)
    end
end

function runLoop.updateTick()
    if not isEnabled() then
        runLoop.cleanup()
        return false
    end

    local timer = singleRun.updateTick()
    batch.updateTimer()
    updateLiveRecordingRows(timer, getCurrentRun(), snapshot())
    refreshText()
    return true
end

function runLoop.hasActiveDisplayLoop()
    return singleRun.hasCurrentRunDisplay() or batch.isActive()
end

function runLoop.ensureDisplayLoop()
    if not isEnabled() then
        runLoop.cleanup()
        return false
    end

    if singleRun.startDisplayLoop() then
        refreshStructure()
    end

    if runLoop.hasActiveDisplayLoop() then
        refreshText()
        return true
    end
    return false
end

function runLoop.cleanup()
    singleRun.clear()
    recording.stop()
    refreshStructure()
end

function runLoop.installHooks(hooks)
    singleRun.installHooks(hooks, {
        isEnabled = isEnabled,
        getCurrentRun = getCurrentRun,
        onRunStarted = function(run, timer, timerSnapshot)
            recording.onRunStarted(run, timer, timerSnapshot)
            refreshStructure()
        end,
        onDisplayLoopStarted = function()
            refreshStructure()
        end,
        onLoadEvent = function(isLoading, timer, timerSnapshot)
            recording.onLoadEvent(isLoading, timer, timerSnapshot)
            refreshText()
        end,
        onRunFinalized = function(run, timer, timerSnapshot)
            recording.onRunFinalized(timer, run, timerSnapshot)
            refreshStructure()
        end,
        onDisplayChanged = function(timerSnapshot)
            updateLiveRecordingRows(activeTimer(), getCurrentRun(), timerSnapshot)
            refreshText()
        end,
    })
end

return runLoop
