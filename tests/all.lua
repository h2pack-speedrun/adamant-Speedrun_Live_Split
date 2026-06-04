local fakeTime = 0
_worldTime = 0

local function assertEqual(actual, expected)
    if actual ~= expected then
        error(string.format("expected %q, got %q", expected, actual), 2)
    end
end

local function setTime(value)
    fakeTime = value
    _worldTime = value
end

local function currentRun()
    return CurrentRun
end

local function newRuntimeState(backing)
    backing = backing or {}
    local function aliasFromArgs(first, second)
        return second or first
    end
    return {
        read = function(first, second)
            local alias = aliasFromArgs(first, second)
            local value = backing[alias]
            if value == nil then
                return false
            end
            return value
        end,
        write = function(first, second, third)
            local alias = first
            local value = second
            if third ~= nil then
                alias = second
                value = third
            end
            backing[alias] = value
            return true
        end,
        reset = function(first, second)
            local alias = aliasFromArgs(first, second)
            local hadValue = backing[alias] ~= nil
            backing[alias] = nil
            return hadValue
        end,
    }
end

local function withImport(callback)
    local previousImport = _G.import
    _G.import = function(path, _, deps)
        return assert(loadfile("src/" .. path))(deps)
    end
    local ok, result = pcall(callback)
    _G.import = previousImport
    if not ok then
        error(result, 2)
    end
    return result
end

local core = withImport(function()
    return assert(loadfile("src/timer/core/00_init.lua"))({
        getTime = function()
            return fakeTime
        end,
        getCurrentRun = currentRun,
    })
end)
local formatCache = assert(loadfile("src/display/format_cache.lua"))({
    formatCentiseconds = core.formatCentiseconds,
})
local formatCallCount = 0
local countedFormatCache = assert(loadfile("src/display/format_cache.lua"))({
    formatCentiseconds = function(value)
        formatCallCount = formatCallCount + 1
        return core.formatCentiseconds(value)
    end,
})
local countedFormatRow = {}
assertEqual(countedFormatCache.cell(countedFormatRow, "igt", 1234), "00:12.34")
assertEqual(countedFormatCache.cell(countedFormatRow, "igt", 1234), "00:12.34")
assertEqual(formatCallCount, 1)
assertEqual(countedFormatCache.cell(countedFormatRow, "igt", nil), "")
assertEqual(countedFormatCache.cell(countedFormatRow, "igt", nil), "")
assertEqual(formatCallCount, 1)
local overlay = withImport(function()
    return assert(loadfile("src/display/overlay_rows.lua"))()
end)

local singleRun = assert(loadfile("src/timer/single_run/single_run.lua"))({
    core = core,
    isMultiRunMode = function()
        return false
    end,
})
setTime(0)
_G.CurrentRun = {
    GameplayTime = 0,
}
singleRun.beginRun()
assertEqual(singleRun.getSnapshot().igtCs, 0)
assertEqual(singleRun.startDisplayLoop(), true)
setTime(12.34)
_G.CurrentRun.GameplayTime = 10.5
singleRun.updateTick()
assertEqual(singleRun.getSnapshot().rtaCs, 1234)
assertEqual(singleRun.getSnapshot().igtCs, 1050)
singleRun.processLoadEvent(true)
setTime(14.34)
singleRun.processLoadEvent(false)
singleRun.updateTick()
assertEqual(singleRun.getSnapshot().lrtCs, 1234)
local finalized, finalizedTimer = singleRun.finalizeRun()
assertEqual(finalized, true)
assert(finalizedTimer ~= nil, "expected finalized timer")
assertEqual(singleRun.hasSummary(), true)
singleRun.clear()
assertEqual(singleRun.hasSummary(), false)
setTime(0)
_G.CurrentRun = nil

local hookSingleRun = assert(loadfile("src/timer/single_run/single_run.lua"))({
    core = core,
    isMultiRunMode = function()
        return false
    end,
})
local hookAdapter = assert(loadfile("src/timer/single_run/hooks.lua"))(hookSingleRun)
local hookHost = {
    isEnabled = function()
        return true
    end,
}
local hookRuntime = {}
local hookCallbacks = {}
local hookEvents = {}
hookAdapter.installHooks({
    wrap = function(name, callback)
        hookCallbacks[name] = callback
    end,
}, {
    isEnabled = function()
        return true
    end,
    onRunStarted = function()
        hookEvents[#hookEvents + 1] = "started"
        hookEvents.startedRun = CurrentRun
        hookEvents.startedTimer = hookSingleRun.getActiveTimer()
    end,
    onDisplayLoopStarted = function()
        hookEvents[#hookEvents + 1] = "display"
        hookEvents.displayTimer = hookSingleRun.getActiveTimer()
    end,
    onLoadEvent = function(_, isLoading)
        hookEvents[#hookEvents + 1] = isLoading and "loadStart" or "loadStop"
    end,
    onRunFinalized = function()
        hookEvents[#hookEvents + 1] = "finalized"
        hookEvents.finalizedRun = CurrentRun
        hookEvents.finalizedTimer = hookSingleRun.getActiveTimer()
    end,
    onDisplayChanged = function()
        hookEvents[#hookEvents + 1] = "changed"
    end,
})
assert(hookCallbacks.StartNewRun ~= nil, "expected StartNewRun hook")
assert(hookCallbacks.RoomEntranceMaterialize ~= nil, "expected RoomEntranceMaterialize hook")
assert(hookCallbacks.RoomEntranceDreamBiomeStart ~= nil, "expected RoomEntranceDreamBiomeStart hook")
assert(hookCallbacks.RecordRunStats ~= nil, "expected RecordRunStats hook")
assert(hookCallbacks.AddTimerBlock ~= nil, "expected AddTimerBlock hook")
assert(hookCallbacks.RemoveTimerBlock ~= nil, "expected RemoveTimerBlock hook")
setTime(0)
_G.CurrentRun = {
    GameplayTime = 0,
}
local startedRun = hookCallbacks.StartNewRun(hookHost, hookRuntime, function()
    return CurrentRun
end)
assertEqual(startedRun, CurrentRun)
assertEqual(hookEvents[1], "started")
assert(hookEvents.startedTimer ~= nil, "expected started timer")
hookCallbacks.RoomEntranceMaterialize(hookHost, hookRuntime, function()
    return "entered"
end)
assertEqual(hookEvents[3], "display")
hookCallbacks.AddTimerBlock(hookHost, hookRuntime, function()
    return true
end, CurrentRun, "MapLoad")
setTime(3)
hookCallbacks.RemoveTimerBlock(hookHost, hookRuntime, function()
    return true
end, CurrentRun, "MapLoad")
hookCallbacks.RecordRunStats(hookHost, hookRuntime, function()
    return "stats"
end)
assertEqual(hookEvents[#hookEvents - 1], "finalized")
assertEqual(hookEvents.finalizedRun, CurrentRun)
assertEqual(hookEvents.finalizedTimer, hookEvents.startedTimer)
setTime(0)
_G.CurrentRun = nil

local overlaySingleRun = assert(loadfile("src/timer/single_run/single_run.lua"))({
    core = core,
})
local overlaySingleRunAdapter = assert(loadfile("src/display/overlay_single_run.lua"))({
    singleRun = overlaySingleRun,
    overlay = overlay,
    isModeVisible = function(mode)
        return mode ~= "rta"
    end,
    isTimerDisplayVisible = function()
        return overlaySingleRun.hasSummary()
    end,
    getDisplayTime = function(row, mode)
        return formatCache.cell(row, "time", overlaySingleRun.getSnapshot()[mode .. "Cs"])
    end,
})
local singleRunOverlayDeclarations = {}
overlaySingleRunAdapter.register({
    createLine = function(name, spec)
        singleRunOverlayDeclarations[name] = spec
    end,
}, 100)
assert(singleRunOverlayDeclarations["summary.igt"] ~= nil, "expected IGT line declaration")
assert(singleRunOverlayDeclarations["summary.rta"] ~= nil, "expected RTA line declaration")
assert(singleRunOverlayDeclarations["summary.lrt"] ~= nil, "expected LrT line declaration")
assertEqual(singleRunOverlayDeclarations["summary.igt"].visible(), false)
setTime(0)
_G.CurrentRun = {
    GameplayTime = 0,
}
overlaySingleRun.beginRun()
overlaySingleRun.startDisplayLoop()
setTime(9.87)
_G.CurrentRun.GameplayTime = 8.76
overlaySingleRun.updateTick()
assertEqual(singleRunOverlayDeclarations["summary.igt"].visible(), true)
assertEqual(singleRunOverlayDeclarations["summary.rta"].visible(), false)
local projectedSingleRunLines = {}
overlaySingleRunAdapter.project({
    setLine = function(name, values)
        projectedSingleRunLines[name] = values
    end,
})
assertEqual(projectedSingleRunLines["summary.igt"].time, "00:08.76")
assertEqual(projectedSingleRunLines["summary.rta"].time, "")
setTime(0)
_G.CurrentRun = nil

local timerSplits = assert(loadfile("src/timer/splits.lua"))({
    toCentiseconds = core.toCentiseconds,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
timerSplits.clear(true)
local splitTimer = {
    getInGameTime = function()
        return 12.34
    end,
    getRealTime = function()
        return 13.45
    end,
    getLoadRemovedTime = function()
        return 12.89
    end,
}
local splitSnapshot = {
    igtCs = 1234,
    rtaCs = 1345,
    lrtCs = 1289,
}
timerSplits.startRun({
    CurrentRoom = { RoomSetName = "F" },
})
timerSplits.updateRows(splitTimer, {
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
}, splitSnapshot)
assertEqual(timerSplits.row(1, splitTimer, {
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
}, splitSnapshot).label, "Erebus")
assertEqual(timerSplits.row(1, splitTimer, {
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
}, splitSnapshot).igtCs, 1234)
timerSplits.startRun({
    CurrentRoom = { RoomSetName = "N" },
})
timerSplits.updateRows(splitTimer, {
    CurrentRoom = { RoomSetName = "N" },
    EnteredBiomes = 1,
}, splitSnapshot)
assertEqual(timerSplits.row(1, splitTimer, {
    CurrentRoom = { RoomSetName = "N" },
    EnteredBiomes = 1,
}, splitSnapshot).label, "Ephyra")
timerSplits.startRun({
    CurrentRoom = { RoomSetName = "F" },
})
timerSplits.recordCompletedBiomes(splitTimer, {
    BiomeVisitOrder = { "F" },
    BiomeGameplayTimes = {
        F = 65.43,
    },
}, splitSnapshot)
local completedSplitRow = timerSplits.row(1, splitTimer, {
    CurrentRoom = { RoomSetName = "G" },
    EnteredBiomes = 2,
}, splitSnapshot)
assertEqual(completedSplitRow.label, "Erebus")
assertEqual(completedSplitRow.igtCs, 6543)
timerSplits.finalizeRun(splitTimer, {
    Cleared = true,
    BiomeVisitOrder = { "F" },
    BiomeGameplayTimes = {
        F = 65.43,
    },
}, splitSnapshot)
assertEqual(timerSplits.status().kind, "recorded")
assertEqual(timerSplits.hasDetails(), true)
timerSplits.clear(false)
assertEqual(timerSplits.status().kind, "idle")

local overlaySplits = assert(loadfile("src/timer/splits.lua"))({
    toCentiseconds = core.toCentiseconds,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local splitsOverlayAdapter = assert(loadfile("src/display/overlay_splits.lua"))({
    currentRun = {
        hasDetails = overlaySplits.hasDetails,
        detailsSnapshot = function(liveOnly)
            if liveOnly then
                overlaySplits.updateLiveRows(splitTimer, {
                    CurrentRoom = { RoomSetName = "F" },
                    EnteredBiomes = 1,
                }, splitSnapshot)
            else
                overlaySplits.updateRows(splitTimer, {
                    CurrentRoom = { RoomSetName = "F" },
                    EnteredBiomes = 1,
                }, splitSnapshot)
            end
            return overlaySplits.details()
        end,
    },
    overlay = overlay,
    isVisible = function()
        return true
    end,
    isModeVisible = function(mode)
        return mode ~= "lrt"
    end,
    formatCache = formatCache,
})
local splitOverlayDeclarations = {}
splitsOverlayAdapter.register({
    createTable = function(name, spec)
        splitOverlayDeclarations[name] = spec
    end,
}, 200)
assert(splitOverlayDeclarations.splits ~= nil, "expected split table declaration")
assertEqual(splitOverlayDeclarations.splits.order, 200)
assertEqual(splitOverlayDeclarations.splits.visible(), false)
overlaySplits.clear(true)
overlaySplits.startRun({
    CurrentRoom = { RoomSetName = "F" },
})
local splitOverlayRows = splitsOverlayAdapter.buildRows(nil, false)
assertEqual(splitOverlayDeclarations.splits.visible(), true)
assertEqual(splitOverlayRows[1].key, "header")
assertEqual(splitOverlayRows[2].label, "Erebus")
assertEqual(splitOverlayRows[2].igt, "00:12.34")
local projectedSplitTables = {}
splitsOverlayAdapter.project({
    setTable = function(name, rows)
        projectedSplitTables[name] = rows
    end,
}, nil, true)
assertEqual(projectedSplitTables.splits[2].label, "Erebus")

local timerBatch = assert(loadfile("src/timer/batch.lua"))({
    core = core,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
timerBatch.start(2)
assertEqual(timerBatch.status().kind, "ready")
assertEqual(timerBatch.status().text, "Recording ready for 2 runs")
assertEqual(timerBatch.time("rta"), nil)
assertEqual(timerBatch.startRun(), true)
assertEqual(timerBatch.status().kind, "active")
assertEqual(timerBatch.currentRow().label, "Current 1/2")
setTime(100)
timerBatch.updateTimer()
timerBatch.finalizeRun({
    getInGameTime = function()
        return 80
    end,
}, {
    Cleared = true,
})
assertEqual(timerBatch.status().text, "Recording 1 / 2")
assertEqual(timerBatch.time("igt"), 8000)
assertEqual(timerBatch.time("rta"), 10000)
assertEqual(timerBatch.row(1).label, "Run 1/2")
assertEqual(timerBatch.currentRow().label, "")
assertEqual(timerBatch.startRun(), true)
assertEqual(timerBatch.currentRow().label, "Current 2/2")
setTime(190)
timerBatch.updateTimer()
timerBatch.finalizeRun({
    getInGameTime = function()
        return 70
    end,
}, {
    Cleared = true,
})
assertEqual(timerBatch.status().kind, "recorded")
assertEqual(timerBatch.status().text, "Recorded 2 / 2")
assertEqual(timerBatch.time("igt"), 15000)
assertEqual(timerBatch.row(2).label, "Run 2/2")
assertEqual(timerBatch.currentRow().label, "")

timerBatch.start(3)
assertEqual(timerBatch.startRun(), true)
setTime(12)
timerBatch.updateTimer()
timerBatch.finalizeRun({
    getInGameTime = function()
        return 9
    end,
}, {
    Cleared = false,
})
assertEqual(timerBatch.status().kind, "failed")
assertEqual(timerBatch.status().text, "Failed (0 / 3 complete)")
assertEqual(timerBatch.row(1).label, "Failed")
assertEqual(timerBatch.row(1).igtCs, 900)
assertEqual(timerBatch.time("igt"), 0)
setTime(0)
local overlayBatch = assert(loadfile("src/timer/batch.lua"))({
    core = core,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local batchOverlayAdapter = assert(loadfile("src/display/overlay_batch.lua"))({
    batch = {
        hasSession = overlayBatch.hasSession,
        session = overlayBatch.session,
    },
    overlay = overlay,
    isVisible = function()
        return true
    end,
    isModeVisible = function(mode)
        return mode ~= "rta"
    end,
    formatCache = formatCache,
})
local batchOverlayDeclarations = {}
batchOverlayAdapter.register({
    createTable = function(name, spec)
        batchOverlayDeclarations[name] = spec
    end,
}, 300)
assert(batchOverlayDeclarations.batch ~= nil, "expected batch table declaration")
assertEqual(batchOverlayDeclarations.batch.order, 300)
assertEqual(batchOverlayDeclarations.batch.visible(), false)
overlayBatch.start(2)
overlayBatch.startRun()
assertEqual(batchOverlayDeclarations.batch.visible(), true)
local batchOverlayRows = batchOverlayAdapter.buildRows(nil)
assertEqual(batchOverlayRows[1].key, "current")
assertEqual(batchOverlayRows[1].label, "Current 1/2")
assertEqual(batchOverlayRows[1].igt, "")
assertEqual(batchOverlayRows[1].rta, "")
assertEqual(batchOverlayRows[1].lrt, "")
local batchSession = overlayBatch.session({
    getInGameTime = function()
        return 7
    end,
})
assertEqual(batchSession.currentTime.igtCs, 700)
setTime(10)
overlayBatch.updateTimer()
overlayBatch.finalizeRun({
    getInGameTime = function()
        return 8
    end,
}, {
    Cleared = true,
})
local projectedBatchTables = {}
batchOverlayAdapter.project({
    setTable = function(name, rows)
        projectedBatchTables[name] = rows
    end,
})
assertEqual(projectedBatchTables.batch[1].key, "run1")
assertEqual(projectedBatchTables.batch[1].label, "Run 1/2")
assertEqual(projectedBatchTables.batch[1].igt, "00:08.00")
setTime(0)
local timerInitStoreValues = {
    ShowIGT = false,
    ShowRawTimers = false,
}
local timerInitRuntimeContext = {
    data = {
        read = function(alias)
            return timerInitStoreValues[alias]
        end,
        runtimeOwned = newRuntimeState(),
    },
}
local timerInit = withImport(function()
    return assert(loadfile("src/timer/00_init.lua"))({
        runtime = timerInitRuntimeContext,
        game = {
            getTime = function()
                return fakeTime
            end,
            getCurrentRun = currentRun,
        },
    })
end)
local timerInitDisplay = withImport(function()
    return assert(loadfile("src/display/display.lua"))({
        timer = timerInit,
    })
end)
assert(type(timerInit.currentRun.summary) == "function", "expected timer current-run summary")
assert(type(timerInit.currentRun.detailsSnapshot) == "function", "expected timer current-run details snapshot")
assert(type(timerInit.batch.session) == "function", "expected timer batch session")
assert(type(timerInit.recording.status) == "function", "expected timer recording status")
assertEqual(timerInitDisplay.settings.isModeVisible("igt", timerInitRuntimeContext), false)
assertEqual(timerInitDisplay.settings.isRawTimerRowsEnabled(timerInitRuntimeContext), false)

local recordingSettings = {
    RecordingMode = "single",
    BatchTargetRuns = 2,
}
local recordingCache = {}
local recordingRuntime = {
    data = {
        read = function(alias)
            return recordingSettings[alias]
        end,
        runtimeOwned = newRuntimeState(recordingCache),
    },
}
local recordingSplits = assert(loadfile("src/timer/splits.lua"))({
    toCentiseconds = core.toCentiseconds,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local recordingBatch = assert(loadfile("src/timer/batch.lua"))({
    core = core,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local recording = assert(loadfile("src/timer/recording.lua"))({
    splits = recordingSplits,
    batch = recordingBatch,
})
recording.initialize(recordingRuntime)
assertEqual(recording.status().kind, "idle")
recording.start(recordingRuntime)
assertEqual(recordingCache.RecordingReady, true)
assertEqual(recording.status().kind, "ready")
recording.onRunStarted({
    CurrentRoom = { RoomSetName = "F" },
})
assertEqual(recording.status().kind, "active")
recording.onRunFinalized(splitTimer, {
    Cleared = true,
    BiomeVisitOrder = { "F" },
    BiomeGameplayTimes = {
        F = 65.43,
    },
}, splitSnapshot)
assertEqual(recording.status().kind, "recorded")

recordingSettings.RecordingMode = "multi"
recording.syncMode(recordingRuntime)
assertEqual(recording.status().kind, "ready")
recording.onRunStarted({
    CurrentRoom = { RoomSetName = "F" },
})
assertEqual(recording.status().kind, "active")
setTime(20)
recordingBatch.updateTimer()
recording.onRunFinalized({
    getInGameTime = function()
        return 15
    end,
}, {
    Cleared = true,
})
assertEqual(recording.status().text, "Recording 1 / 2")
assertEqual(recordingBatch.row(1).igtCs, 1500)
recording.stop(recordingRuntime)
assertEqual(recordingCache.RecordingReady, false)
assertEqual(recording.status().kind, "idle")
setTime(0)
local bridgeSettings = {
    RecordingMode = "single",
    BatchTargetRuns = 2,
}
local bridgeSplits = assert(loadfile("src/timer/splits.lua"))({
    toCentiseconds = core.toCentiseconds,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local bridgeBatch = assert(loadfile("src/timer/batch.lua"))({
    core = core,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local bridgeRecording
local bridgeSingleRun = assert(loadfile("src/timer/single_run/single_run.lua"))({
    core = core,
    isMultiRunMode = function()
        return bridgeRecording and bridgeRecording.isMultiRunMode() or false
    end,
})
bridgeSingleRun.installHooks = assert(loadfile("src/timer/single_run/hooks.lua"))(bridgeSingleRun).installHooks
local bridgeEvents = {}
local bridgeEventNames = {
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
local function emitBridgeEvent(name)
    bridgeEvents[name] = (bridgeEvents[name] or 0) + 1
end
local bridgeHost = {
    isEnabled = function()
        return true
    end,
}
local bridgeRuntime = {
    data = {
        read = function(alias)
            return bridgeSettings[alias]
        end,
        runtimeOwned = newRuntimeState(),
    },
}
bridgeRecording = assert(loadfile("src/timer/recording.lua"))({
    splits = bridgeSplits,
    batch = bridgeBatch,
})
local runLoop = assert(loadfile("src/timer/run_loop.lua"))({
    singleRun = bridgeSingleRun,
    recording = bridgeRecording,
    splits = bridgeSplits,
    batch = bridgeBatch,
    getCurrentRun = function()
        return CurrentRun
    end,
    emit = emitBridgeEvent,
    events = bridgeEventNames,
})
local bridgeHooks = {}
runLoop.installHooks({
    wrap = function(name, callback)
        bridgeHooks[name] = callback
    end,
})
bridgeRecording.start(bridgeRuntime)
setTime(0)
_G.CurrentRun = {
    GameplayTime = 0,
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
    Cleared = true,
    BiomeVisitOrder = { "F" },
    BiomeGameplayTimes = {
        F = 6,
    },
}
bridgeHooks.StartNewRun(bridgeHost, bridgeRuntime, function()
    return CurrentRun
end)
assertEqual(bridgeRecording.status().kind, "active")
assertEqual(runLoop.ensureDisplayLoop(), true)
assertEqual(bridgeSingleRun.hasSummary(), true)
bridgeHooks.RoomEntranceMaterialize(bridgeHost, bridgeRuntime, function()
    return true
end)
setTime(7)
_G.CurrentRun.GameplayTime = 6
runLoop.updateTick()
local bridgeSplitRow = bridgeSplits.row(1, bridgeSingleRun.getActiveTimer(), CurrentRun, bridgeSingleRun.getSnapshot())
assertEqual(bridgeSplitRow.igtCs, 600)
bridgeHooks.RecordRunStats(bridgeHost, bridgeRuntime, function()
    return true
end)
assertEqual(bridgeRecording.status().kind, "recorded")
assert((bridgeEvents.currentRunStarted or 0) > 0, "expected currentRunStarted event")
assert((bridgeEvents.currentRunSummaryChanged or 0) > 0, "expected currentRunSummaryChanged event")
assert((bridgeEvents.currentRunDetailsChanged or 0) > 0, "expected currentRunDetailsChanged event")

bridgeSettings.RecordingMode = "multi"
bridgeRecording.syncMode(bridgeRuntime)
setTime(0)
local bridgeMultiRun = {
    GameplayTime = 0,
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
}
_G.CurrentRun = bridgeMultiRun
bridgeHooks.StartNewRun(bridgeHost, bridgeRuntime, function()
    return CurrentRun
end)
bridgeHooks.RoomEntranceMaterialize(bridgeHost, bridgeRuntime, function()
    return true
end)
setTime(9)
_G.CurrentRun.GameplayTime = 5
runLoop.updateTick()
bridgeHooks.RecordRunStats(bridgeHost, bridgeRuntime, function()
    bridgeMultiRun.Cleared = true
    return true
end)
assertEqual(bridgeRecording.status().text, "Recording 1 / 2")
assertEqual(bridgeBatch.row(1).igtCs, 500)
setTime(0)
_G.CurrentRun = nil

local format = core.formatTimestamp
assertEqual(format(nil), "00:00.00")
assertEqual(format(0), "00:00.00")
assertEqual(format(1.23), "00:01.23")
assertEqual(format(59.99), "00:59.99")
assertEqual(format(60), "01:00.00")
assertEqual(format(61.23), "01:01.23")
assertEqual(format(3599.99), "59:59.99")
assertEqual(format(3600), "01:00:00.00")
assertEqual(format(3661.23), "01:01:01.23")

local uiStatus = {
    kind = "idle",
    text = "Not recording",
}
local uiModule = dofile("src/ui.lua")
local uiStatusView = {
    getRecordingStatus = function()
        return uiStatus
    end,
}

local uiSessionValues = {
    ShowIGT = false,
    ShowRTA = false,
    ShowLrT = false,
    ShowRawTimers = false,
    ShowRecordingTable = true,
    RecordingMode = "single",
}
local uiSessionActions = {}
local uiButtons = {}
local uiDraw = {
    imgui = {
        SameLine = function() end,
        Spacing = function() end,
    },
    widgets = {
        text = function() end,
        separator = function() end,
        checkbox = function() return false end,
        radio = function() return false end,
        stepper = function() return false end,
        button = function(label, opts)
            uiButtons[#uiButtons + 1] = label
            opts.action:stage(opts.value)
            return true
        end,
    },
}
local drawState = {
    get = function(alias)
        return {
            alias = alias,
        }
    end,
    read = function(alias)
        return uiSessionValues[alias]
    end,
    write = function(alias, value)
        uiSessionValues[alias] = value
    end,
}
local uiActions = {
    get = function(action)
        return {
            stage = function(_, value)
                uiSessionActions[action] = value
            end,
        }
    end,
}
uiModule.drawTab({
    imgui = uiDraw.imgui,
    widgets = uiDraw.widgets,
}, drawState, uiActions, uiStatusView)
assertEqual(uiSessionValues.ShowIGT, true)
assertEqual(uiSessionActions.recordingStart, true)
assertEqual(uiButtons[1], "Start")
assertEqual(uiButtons[2], nil)

uiSessionActions = {}
uiButtons = {}
uiModule.drawQuickContent({
    imgui = uiDraw.imgui,
    widgets = uiDraw.widgets,
}, drawState, uiActions, uiStatusView)
assertEqual(uiSessionActions.recordingStart, true)
assertEqual(uiButtons[1], "Start")
assertEqual(uiButtons[2], nil)

uiStatus = {
    kind = "active",
    text = "Recording current run",
}
uiSessionActions = {}
uiButtons = {}
uiModule.drawQuickContent({
    imgui = uiDraw.imgui,
    widgets = uiDraw.widgets,
}, drawState, uiActions, uiStatusView)
assertEqual(uiSessionActions.recordingStop, true)
assertEqual(uiSessionActions.recordingClear, true)
assertEqual(uiButtons[1], "Stop")
assertEqual(uiButtons[2], "Clear")
assertEqual(uiButtons[3], nil)

local harness = dofile("../../ModpackTools/tests/module_entrypoint_harness.lua")
local boot = harness.bootModule({
    pluginGuid = "adamantSpeedrun-LiveSplit",
    moduleSrcDir = "src",
    configureEnv = function(env)
        env._worldTime = 0
        env.GetTime = function()
            return 0
        end
        env.CurrentRun = {
            GameplayTime = 0,
        }
    end,
})
assert(boot.liveModule and boot.liveModule.setEnabled(true))
boot.liveModule.drawTab()
boot.liveModule.drawQuickContent()

local consumerHost = boot.lib.createModule({
    pluginGuid = "test-SpeedrunTimerConsumer",
    config = {},
    id = "TimerConsumer",
    name = "Timer Consumer",
})
consumerHost.ui.tab(function() end)
consumerHost.shared.data.reader("TimerSnapshot", {
    id = "speedrun.timer",
    fallback = {
        realTimeCs = -1,
        loadRemovedTimeCs = -1,
        inGameTimeCs = -1,
    },
})
local consumerRuntime = nil
consumerHost.onActivate(function(_, runtime)
    consumerRuntime = runtime
end)
assert(consumerHost and consumerHost.activate())

local times = consumerRuntime.shared.read("TimerSnapshot")
assertEqual(times.realTimeCs, 0)
assertEqual(times.loadRemovedTimeCs, 0)
assertEqual(times.inGameTimeCs, 0)
assertEqual(times.recordingStatus.kind, "idle")
assertEqual(next(boot.moduleEnv.public), nil)

print("Timer tests passed")
