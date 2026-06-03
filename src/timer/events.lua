local deps = ... or {}
local source = deps.source

local events = {}
local listeners = {}

events.names = {
    currentRunSummaryChanged = "currentRunSummaryChanged",
    currentRunDetailsChanged = "currentRunDetailsChanged",
    batchSessionChanged = "batchSessionChanged",
    recordingStatusChanged = "recordingStatusChanged",
    currentRunStarted = "currentRunStarted",
    currentRunFinalized = "currentRunFinalized",
    currentRunDisplayStarted = "currentRunDisplayStarted",
    loadRemovalStarted = "loadRemovalStarted",
    loadRemovalEnded = "loadRemovalEnded",
}

function events.on(eventName, callback)
    listeners[eventName] = listeners[eventName] or {}
    listeners[eventName][#listeners[eventName] + 1] = callback
end

function events.emit(eventName, runtime)
    local eventListeners = listeners[eventName]
    if not eventListeners then
        return
    end
    for _, callback in ipairs(eventListeners) do
        callback(source, runtime)
    end
end

function events.emitCurrentRunChanged(runtime)
    events.emit(events.names.currentRunSummaryChanged, runtime)
    events.emit(events.names.currentRunDetailsChanged, runtime)
end

function events.emitRecordingOutputsChanged(runtime)
    events.emit(events.names.recordingStatusChanged, runtime)
    events.emit(events.names.currentRunDetailsChanged, runtime)
    events.emit(events.names.batchSessionChanged, runtime)
end

function events.emitRecordingStarted(runtime, isMultiRunMode)
    events.emit(events.names.recordingStatusChanged, runtime)
    if isMultiRunMode then
        events.emit(events.names.batchSessionChanged, runtime)
    else
        events.emit(events.names.currentRunDetailsChanged, runtime)
    end
end

function events.emitTick(runtime, isMultiRunMode)
    events.emitCurrentRunChanged(runtime)
    if isMultiRunMode then
        events.emit(events.names.batchSessionChanged, runtime)
    end
end

function events.emitCleanup(runtime)
    events.emit(events.names.recordingStatusChanged, runtime)
    events.emitCurrentRunChanged(runtime)
    events.emit(events.names.batchSessionChanged, runtime)
end

return events
