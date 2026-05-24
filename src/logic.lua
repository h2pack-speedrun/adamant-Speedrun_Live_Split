local module = {}
local timer = {}

import("timer/RtaTimer.lua")
import("timer/LrtTimer.lua")
import("timer/IgtTimer.lua")

local function bindTimerFile(path)
    import(path, nil, timer)
end

bindTimerFile("timer/OverlayRows.lua")
bindTimerFile("timer/Splits.lua")
bindTimerFile("timer/Batch.lua")
bindTimerFile("timer/Recorder.lua")
bindTimerFile("timer/Runtime.lua")

function module.initialize(host, store)
    timer.host = host
    timer.store = store
    if timer.InitializeBatchState then
        timer.InitializeBatchState()
    end
    if timer.InitializeRecordingState then
        timer.InitializeRecordingState()
    end
end

function module.registerHooks(host, store)
    timer.host = host
    timer.store = store
    timer.RegisterHooks(host, store)
end

function module.registerOverlays(host, store)
    timer.host = host
    timer.store = store
    timer.RegisterOverlays(host.overlays, host, store)
end

function module.onSettingsCommitted(host, store, commit)
    timer.host = host
    timer.store = store
    timer.OnSettingsCommitted(host, store, commit)
end

function module.getRealTime()
    if timer.GetRealTime then
        return timer.GetRealTime()
    end
end

function module.getLoadRemovedTime()
    if timer.GetLoadRemovedTime then
        return timer.GetLoadRemovedTime()
    end
end

function module.getInGameTime()
    if timer.GetInGameTime then
        return timer.GetInGameTime()
    end
end

function module.getRecordingStatus()
    if timer.GetRecordingStatus then
        return timer.GetRecordingStatus()
    end
end

function module.startRecording(targetRuns)
    if timer.StartRecording then
        timer.StartRecording(targetRuns)
    end
end

function module.clearRecording(targetRuns)
    if timer.ClearRecording then
        timer.ClearRecording(targetRuns)
    end
end

function module.stopRecording()
    if timer.StopRecording then
        timer.StopRecording()
    end
end

function module.bind()
    return module
end

return module
