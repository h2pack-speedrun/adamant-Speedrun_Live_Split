SpeedrunTimerInternal = SpeedrunTimerInternal or {}
local internal = SpeedrunTimerInternal

local config = nil
local currentMode = nil
local recordingReady = false

local function readSetting(alias)
    if config and config.readSetting then
        return config.readSetting(alias)
    end
    return nil
end

local function refreshDisplay()
    if config and config.refreshDisplay then
        config.refreshDisplay()
    end
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

local function persistRecordingReady()
    writeRuntime("RecordingReady", recordingReady == true)
end

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

local function clearSingleRecording(keepReady)
    if internal.ClearSingleRecording then
        internal.ClearSingleRecording(keepReady == true)
    end
end

local function clearBatchRecording(targetRuns)
    if internal.ClearBatch then
        internal.ClearBatch(targetRuns, false)
    end
end

local function startBatchRecording(targetRuns)
    if internal.StartBatch then
        internal.StartBatch(targetRuns)
    end
end

local function stopBatchRecording()
    if internal.StopBatch then
        internal.StopBatch()
    end
end

function internal.ConfigureRecorder(opts)
    config = opts or {}
end

function internal.GetRecordingMode()
    return readRecordingMode()
end

function internal.IsSingleRunMode()
    return internal.GetRecordingMode() == "single"
end

function internal.IsMultiRunMode()
    return internal.GetRecordingMode() == "multi"
end

local function isRecordingReady()
    return recordingReady == true
end

local function setRecordingReady(started)
    recordingReady = started == true
    persistRecordingReady()
end

function internal.SyncRecordingMode()
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

    if nextMode == "single"
        and isRecordingReady()
        and internal.IsSingleRecordingStarted
        and not internal.IsSingleRecordingStarted() then

        clearSingleRecording(true)
    end
end

function internal.IsSplitRecordingOverlayVisible()
    return internal.IsSingleRecordingVisible
        and internal.IsSingleRecordingVisible()
end

function internal.GetRecordingStatus()
    if internal.IsMultiRunMode() and internal.GetBatchStatus then
        return internal.GetBatchStatus()
    end
    if internal.GetSingleRecordingStatus then
        return internal.GetSingleRecordingStatus()
    end
    return {
        kind = "idle",
        text = "Not recording",
    }
end

function internal.StartRecording(targetRuns)
    setRecordingReady(true)
    if internal.IsMultiRunMode() then
        clearSingleRecording(true)
        startBatchRecording(targetRuns)
    else
        clearBatchRecording(targetRuns)
        clearSingleRecording(true)
    end
    refreshDisplay()
end

function internal.ClearRecording(targetRuns)
    clearBatchRecording(targetRuns)
    clearSingleRecording(isRecordingReady())
    refreshDisplay()
end

function internal.StopRecording()
    setRecordingReady(false)
    stopBatchRecording()
    clearSingleRecording(false)
    refreshDisplay()
end

function internal.OnRecordingRunStarted(run)
    if isRecordingReady() and internal.StartSplitRun then
        internal.StartSplitRun(run)
    end
    if internal.IsMultiRunMode() and internal.StartBatchRun then
        internal.StartBatchRun()
    end
end

function internal.OnRecordingRunFinalized(timer, run)
    if internal.IsMultiRunMode() then
        if internal.FinalizeBatchRun then
            internal.FinalizeBatchRun(timer, run)
        end
    elseif internal.FinalizeSingleRecording then
        internal.FinalizeSingleRecording(timer, run)
    end
end

function internal.InitializeRecordingState()
    recordingReady = readRuntime("RecordingReady") == true
    currentMode = readRecordingMode()

    if currentMode == "multi" and isRecordingReady() then
        startBatchRecording(readTargetRuns())
    elseif currentMode == "single" then
        clearSingleRecording(isRecordingReady())
    end
    persistRecordingReady()
end

return internal
