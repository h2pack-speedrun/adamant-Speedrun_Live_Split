local deps = ... or {}
local splits = deps.splits
local batch = deps.batch
local readSetting = deps.readSetting
local refreshDisplay = deps.refreshDisplay
local persistentCache = deps.persistentCache

local recording = {}
local currentMode = nil
local recordingReadyRef = persistentCache.create("RecordingReady", {
    default = false,
})

local function normalizeMode(mode)
    if mode == "single" or mode == "multi" then
        return mode
    end
    return "single"
end

local function readRecordingMode()
    return normalizeMode(readSetting("RecordingMode"))
end

local function readTargetRuns()
    return readSetting("BatchTargetRuns")
end

local function isRecordingReady()
    return recordingReadyRef:get() == true
end

local function setRecordingReady(value)
    recordingReadyRef:set(value == true)
end

local function clearSingleRecording(keepReady)
    splits.clear(keepReady == true)
end

local function clearBatchRecording(targetRuns)
    batch.clear(targetRuns)
end

local function startBatchRecording(targetRuns)
    batch.start(targetRuns)
end

local function stopBatchRecording()
    batch.stop()
end

function recording.getMode()
    return currentMode or "single"
end

function recording.isSingleRunMode()
    return recording.getMode() == "single"
end

function recording.isMultiRunMode()
    return recording.getMode() == "multi"
end

function recording.syncMode()
    local previousMode = currentMode
    local nextMode = readRecordingMode()
    currentMode = nextMode

    if previousMode and previousMode ~= nextMode then
        clearSingleRecording(isRecordingReady())
        clearBatchRecording(readTargetRuns())
        if nextMode == "multi" and isRecordingReady() then
            startBatchRecording(readTargetRuns())
        end
    end

    if nextMode == "single" and isRecordingReady() and not splits.isStarted() then
        clearSingleRecording(true)
    end
end

function recording.isSplitOverlayVisible()
    return splits.isVisible()
end

function recording.status()
    if recording.isMultiRunMode() then
        return batch.status()
    end
    return splits.status()
end

function recording.start(targetRuns)
    setRecordingReady(true)
    currentMode = readRecordingMode()
    if recording.isMultiRunMode() then
        clearSingleRecording(true)
        startBatchRecording(targetRuns)
    else
        clearBatchRecording(targetRuns)
        clearSingleRecording(true)
    end
    refreshDisplay()
end

function recording.clear(targetRuns)
    clearBatchRecording(targetRuns)
    clearSingleRecording(isRecordingReady())
    refreshDisplay()
end

function recording.stop()
    setRecordingReady(false)
    stopBatchRecording()
    clearSingleRecording(false)
    refreshDisplay()
end

function recording.applyAction(action)
    if type(action) ~= "table" then
        return false
    end

    if action.kind == "start" then
        recording.start(readTargetRuns())
        return true
    end
    if action.kind == "clear" then
        recording.clear(readTargetRuns())
        return true
    end
    if action.kind == "stop" then
        recording.stop()
        return true
    end
    return false
end

function recording.onRunStarted(run)
    if isRecordingReady() then
        splits.startRun(run)
    end
    if recording.isMultiRunMode() then
        batch.startRun()
    end
end

function recording.onLoadEvent(isLoading)
    if recording.isMultiRunMode() then
        batch.processLoadEvent(isLoading)
    end
end

function recording.onRunFinalized(timer, run, snapshot)
    if recording.isMultiRunMode() then
        batch.finalizeRun(timer, run)
    else
        splits.finalizeRun(timer, run, snapshot)
    end
end

function recording.initialize()
    recordingReadyRef:refresh()
    currentMode = readRecordingMode()

    if currentMode == "multi" and isRecordingReady() then
        startBatchRecording(readTargetRuns())
    elseif currentMode == "single" then
        clearSingleRecording(isRecordingReady())
    end
end

return recording
