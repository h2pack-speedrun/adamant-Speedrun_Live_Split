local timerApi = ...

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

local function readUnstaged(alias)
    local store = timerApi.store
    return store and store.read and store.read(alias) or nil
end

local function writeUnstaged(alias, value)
    local store = timerApi.store
    if store and store.writeUnstaged then
        store.writeUnstaged(alias, value)
    end
end

local function persistRecordingReady()
    writeUnstaged("RecordingReady", recordingReady == true)
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
    if timerApi.ClearSingleRecording then
        timerApi.ClearSingleRecording(keepReady == true)
    end
end

local function clearBatchRecording(targetRuns)
    if timerApi.ClearBatch then
        timerApi.ClearBatch(targetRuns, false)
    end
end

local function startBatchRecording(targetRuns)
    if timerApi.StartBatch then
        timerApi.StartBatch(targetRuns)
    end
end

local function stopBatchRecording()
    if timerApi.StopBatch then
        timerApi.StopBatch()
    end
end

function timerApi.ConfigureRecorder(opts)
    config = opts or {}
end

function timerApi.GetRecordingMode()
    return readRecordingMode()
end

function timerApi.IsSingleRunMode()
    return timerApi.GetRecordingMode() == "single"
end

function timerApi.IsMultiRunMode()
    return timerApi.GetRecordingMode() == "multi"
end

local function isRecordingReady()
    return recordingReady == true
end

local function setRecordingReady(started)
    recordingReady = started == true
    persistRecordingReady()
end

function timerApi.SyncRecordingMode()
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
        and timerApi.IsSingleRecordingStarted
        and not timerApi.IsSingleRecordingStarted() then

        clearSingleRecording(true)
    end
end

function timerApi.IsSplitRecordingOverlayVisible()
    return timerApi.IsSingleRecordingVisible
        and timerApi.IsSingleRecordingVisible()
end

function timerApi.GetRecordingStatus()
    if timerApi.IsMultiRunMode() and timerApi.GetBatchStatus then
        return timerApi.GetBatchStatus()
    end
    if timerApi.GetSingleRecordingStatus then
        return timerApi.GetSingleRecordingStatus()
    end
    return {
        kind = "idle",
        text = "Not recording",
    }
end

function timerApi.StartRecording(targetRuns)
    setRecordingReady(true)
    if timerApi.IsMultiRunMode() then
        clearSingleRecording(true)
        startBatchRecording(targetRuns)
    else
        clearBatchRecording(targetRuns)
        clearSingleRecording(true)
    end
    refreshDisplay()
end

function timerApi.ClearRecording(targetRuns)
    clearBatchRecording(targetRuns)
    clearSingleRecording(isRecordingReady())
    refreshDisplay()
end

function timerApi.StopRecording()
    setRecordingReady(false)
    stopBatchRecording()
    clearSingleRecording(false)
    refreshDisplay()
end

function timerApi.ApplyRecordingAction(action)
    if type(action) ~= "table" then
        return false
    end

    local kind = action.kind
    if kind == "start" then
        timerApi.StartRecording(readTargetRuns())
        return true
    end
    if kind == "clear" then
        timerApi.ClearRecording(readTargetRuns())
        return true
    end
    if kind == "stop" then
        timerApi.StopRecording()
        return true
    end
    return false
end

function timerApi.OnRecordingRunStarted(run)
    if isRecordingReady() and timerApi.StartSplitRun then
        timerApi.StartSplitRun(run)
    end
    if timerApi.IsMultiRunMode() and timerApi.StartBatchRun then
        timerApi.StartBatchRun()
    end
end

function timerApi.OnRecordingRunFinalized(timer, run)
    if timerApi.IsMultiRunMode() then
        if timerApi.FinalizeBatchRun then
            timerApi.FinalizeBatchRun(timer, run)
        end
    elseif timerApi.FinalizeSingleRecording then
        timerApi.FinalizeSingleRecording(timer, run)
    end
end

function timerApi.InitializeRecordingState()
    recordingReady = readUnstaged("RecordingReady") == true
    currentMode = readRecordingMode()

    if currentMode == "multi" and isRecordingReady() then
        startBatchRecording(readTargetRuns())
    elseif currentMode == "single" then
        clearSingleRecording(isRecordingReady())
    end
    persistRecordingReady()
end

return timerApi
