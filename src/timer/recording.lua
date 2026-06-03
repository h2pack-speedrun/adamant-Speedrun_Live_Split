local deps = ... or {}
local splits = deps.splits
local batch = deps.batch

local recording = {}
local currentMode = nil
local recordingReady = false

local function normalizeMode(mode)
    if mode == "single" or mode == "multi" then
        return mode
    end
    return "single"
end

local function readRecordingMode(runtime)
    return normalizeMode(runtime.data.read("RecordingMode"))
end

local function readTargetRuns(runtime)
    return runtime.data.read("BatchTargetRuns")
end

local function isRecordingReady(runtime)
    if runtime == nil then
        return recordingReady == true
    end
    return runtime.data.runtimeOwned.read("RecordingReady") == true
end

local function setRecordingReady(runtime, value)
    recordingReady = value == true
    runtime.data.runtimeOwned.set("RecordingReady", recordingReady)
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

function recording.syncMode(runtime)
    local previousMode = currentMode
    local nextMode = readRecordingMode(runtime)
    currentMode = nextMode
    recordingReady = isRecordingReady(runtime)

    if previousMode and previousMode ~= nextMode then
        clearSingleRecording(isRecordingReady(runtime))
        clearBatchRecording(readTargetRuns(runtime))
        if nextMode == "multi" and isRecordingReady(runtime) then
            startBatchRecording(readTargetRuns(runtime))
        end
    end

    if nextMode == "single" and isRecordingReady(runtime) and not splits.isStarted() then
        clearSingleRecording(true)
    end
end

function recording.status()
    if recording.isMultiRunMode() then
        return batch.status()
    end
    return splits.status()
end

function recording.start(runtime)
    local targetRuns = readTargetRuns(runtime)
    setRecordingReady(runtime, true)
    currentMode = readRecordingMode(runtime)
    if recording.isMultiRunMode() then
        clearSingleRecording(true)
        startBatchRecording(targetRuns)
    else
        clearBatchRecording(targetRuns)
        clearSingleRecording(true)
    end
end

function recording.clear(runtime)
    local targetRuns = readTargetRuns(runtime)
    clearBatchRecording(targetRuns)
    clearSingleRecording(isRecordingReady(runtime))
end

function recording.stop(runtime)
    setRecordingReady(runtime, false)
    stopBatchRecording()
    clearSingleRecording(false)
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

function recording.initialize(runtime)
    currentMode = readRecordingMode(runtime)

    if currentMode == "multi" and isRecordingReady(runtime) then
        startBatchRecording(readTargetRuns(runtime))
    elseif currentMode == "single" then
        clearSingleRecording(isRecordingReady(runtime))
    end
end

return recording
