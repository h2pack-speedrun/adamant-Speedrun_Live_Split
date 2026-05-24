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

local function newPersistentCache(backing)
    backing = backing or {}
    return {
        read = function(alias, fallback)
            local value = backing[alias]
            if value == nil then
                return fallback
            end
            return value
        end,
        write = function(alias, value)
            backing[alias] = value
            return true
        end,
        clear = function(alias)
            local hadValue = backing[alias] ~= nil
            backing[alias] = nil
            return hadValue
        end,
        has = function(alias)
            return backing[alias] ~= nil
        end,
        create = function(alias, opts)
            opts = opts or {}
            local fallback = opts.default
            local snapshot = backing[alias]
            if snapshot == nil then
                snapshot = fallback
            end
            local ref = {}
            ref.get = function()
                return snapshot
            end
            ref.set = function(selfOrValue, maybeValue)
                local value = maybeValue
                if value == nil and selfOrValue ~= ref then
                    value = selfOrValue
                end
                backing[alias] = value
                snapshot = value
                return true
            end
            ref.clear = function()
                local hadValue = backing[alias] ~= nil
                backing[alias] = nil
                snapshot = fallback
                return hadValue
            end
            ref.has = function()
                return backing[alias] ~= nil
            end
            ref.refresh = function()
                snapshot = backing[alias]
                if snapshot == nil then
                    snapshot = fallback
                end
                return snapshot
            end
            return ref
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
local overlay = withImport(function()
    return assert(loadfile("src/timer/overlay/00_init.lua"))()
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
assertEqual(singleRun.getSnapshot().formatted.igt, "00:00.00")
assertEqual(singleRun.startDisplayLoop(), true)
setTime(12.34)
_G.CurrentRun.GameplayTime = 10.5
singleRun.updateTick()
assertEqual(singleRun.getSnapshot().formatted.rta, "00:12.34")
assertEqual(singleRun.getSnapshot().formatted.igt, "00:10.50")
singleRun.processLoadEvent(true)
setTime(14.34)
singleRun.processLoadEvent(false)
singleRun.updateTick()
assertEqual(singleRun.getSnapshot().formatted.lrt, "00:12.34")
local finalized, finalizedTimer = singleRun.finalizeRun()
assertEqual(finalized, true)
assert(finalizedTimer ~= nil, "expected finalized timer")
assertEqual(singleRun.hasCurrentRunDisplay(), true)
singleRun.clear()
assertEqual(singleRun.hasCurrentRunDisplay(), false)
setTime(0)
_G.CurrentRun = nil

local hookSingleRun = assert(loadfile("src/timer/single_run/single_run.lua"))({
    core = core,
    isMultiRunMode = function()
        return false
    end,
})
local hookAdapter = assert(loadfile("src/timer/single_run/hooks.lua"))(hookSingleRun)
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
    getCurrentRun = function()
        return CurrentRun
    end,
    onRunStarted = function(run, timer)
        hookEvents[#hookEvents + 1] = "started"
        hookEvents.startedRun = run
        hookEvents.startedTimer = timer
    end,
    onDisplayLoopStarted = function(timer)
        hookEvents[#hookEvents + 1] = "display"
        hookEvents.displayTimer = timer
    end,
    onLoadEvent = function(isLoading)
        hookEvents[#hookEvents + 1] = isLoading and "loadStart" or "loadStop"
    end,
    onRunFinalized = function(run, timer)
        hookEvents[#hookEvents + 1] = "finalized"
        hookEvents.finalizedRun = run
        hookEvents.finalizedTimer = timer
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
local startedRun = hookCallbacks.StartNewRun(function()
    return CurrentRun
end)
assertEqual(startedRun, CurrentRun)
assertEqual(hookEvents[1], "started")
assert(hookEvents.startedTimer ~= nil, "expected started timer")
hookCallbacks.RoomEntranceMaterialize(function()
    return "entered"
end)
assertEqual(hookEvents[3], "display")
hookCallbacks.AddTimerBlock(function()
    return true
end, CurrentRun, "MapLoad")
setTime(3)
hookCallbacks.RemoveTimerBlock(function()
    return true
end, CurrentRun, "MapLoad")
hookCallbacks.RecordRunStats(function()
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
local overlaySingleRunAdapter = assert(loadfile("src/timer/single_run/overlay.lua"))({
    singleRun = overlaySingleRun,
    overlay = overlay,
    isModeVisible = function(mode)
        return mode ~= "rta"
    end,
    isTimerDisplayVisible = function()
        return overlaySingleRun.hasCurrentRunDisplay()
    end,
    getDisplayTime = function(mode)
        return overlaySingleRun.getSnapshot().formatted[mode]
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
assertEqual(projectedSingleRunLines["summary.rta"].time, "00:09.87")
setTime(0)
_G.CurrentRun = nil

local timerSplits = assert(loadfile("src/timer/splits/splits.lua"))({
    formatTimestamp = core.formatTimestamp,
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
    igt = 12.34,
    rta = 13.45,
    lrt = 12.89,
    formatted = {
        igt = "00:12.34",
        rta = "00:13.45",
        lrt = "00:12.89",
    },
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
}, splitSnapshot).igt, "00:12.34")
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
assertEqual(completedSplitRow.igt, "01:05.43")
timerSplits.finalizeRun(splitTimer, {
    Cleared = true,
    BiomeVisitOrder = { "F" },
    BiomeGameplayTimes = {
        F = 65.43,
    },
}, splitSnapshot)
assertEqual(timerSplits.status().kind, "recorded")
assertEqual(timerSplits.isVisible(), true)
timerSplits.clear(false)
assertEqual(timerSplits.status().kind, "idle")

local overlaySplits = assert(loadfile("src/timer/splits/splits.lua"))({
    formatTimestamp = core.formatTimestamp,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local splitsOverlayAdapter = assert(loadfile("src/timer/splits/overlay.lua"))({
    splits = overlaySplits,
    overlay = overlay,
    isVisible = function()
        return true
    end,
    isModeVisible = function(mode)
        return mode ~= "lrt"
    end,
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
local splitOverlayRows = splitsOverlayAdapter.buildRows(splitTimer, {
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
}, splitSnapshot, false)
assertEqual(splitOverlayDeclarations.splits.visible(), true)
assertEqual(splitOverlayRows[1].key, "header")
assertEqual(splitOverlayRows[2].label, "Erebus")
assertEqual(splitOverlayRows[2].igt, "00:12.34")
local projectedSplitTables = {}
splitsOverlayAdapter.project({
    setTable = function(name, rows)
        projectedSplitTables[name] = rows
    end,
}, splitTimer, {
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
}, splitSnapshot, true)
assertEqual(projectedSplitTables.splits[2].label, "Erebus")

local timerBatch = assert(loadfile("src/timer/batch/batch.lua"))({
    core = core,
    formatTimestamp = core.formatTimestamp,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
timerBatch.start(2)
assertEqual(timerBatch.status().kind, "ready")
assertEqual(timerBatch.status().text, "Recording ready for 2 runs")
assertEqual(timerBatch.displayTime("rta"), nil)
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
assertEqual(timerBatch.displayTime("igt"), "01:20.00")
assertEqual(timerBatch.displayTime("rta"), "01:40.00")
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
assertEqual(timerBatch.displayTime("igt"), "02:30.00")
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
assertEqual(timerBatch.row(1).igt, "00:09.00")
assertEqual(timerBatch.displayTime("igt"), "00:00.00")
setTime(0)
local overlayBatch = assert(loadfile("src/timer/batch/batch.lua"))({
    core = core,
    formatTimestamp = core.formatTimestamp,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local batchOverlayAdapter = assert(loadfile("src/timer/batch/overlay.lua"))({
    batch = overlayBatch,
    overlay = overlay,
    isVisible = function()
        return true
    end,
    isModeVisible = function(mode)
        return mode ~= "rta"
    end,
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
local batchOverlayRows = batchOverlayAdapter.buildRows()
assertEqual(batchOverlayRows[1].key, "current")
assertEqual(batchOverlayRows[1].label, "Current 1/2")
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
local timerInit = withImport(function()
    return assert(loadfile("src/timer/00_init.lua"))({
        host = {
            isEnabled = function()
                return true
            end,
            cache = {
                persistent = newPersistentCache(),
            },
        },
        store = {
            read = function(alias)
                return timerInitStoreValues[alias]
            end,
        },
        game = {
            getTime = function()
                return fakeTime
            end,
            getCurrentRun = currentRun,
        },
    })
end)
assert(timerInit.core.RtaTimer ~= nil, "expected timer core timers")
assert(timerInit.overlay.buildSummaryColumns ~= nil, "expected timer overlay helpers")
assert(timerInit.singleRun.overlay ~= nil, "expected timer single-run overlay")
assert(timerInit.splits.overlay ~= nil, "expected timer splits overlay")
assert(timerInit.batch.overlay ~= nil, "expected timer batch overlay")
assert(timerInit.recording ~= nil, "expected timer recording")
assert(timerInit.runLoop ~= nil, "expected timer run loop")
assertEqual(timerInit.display.services.isModeVisible("igt"), false)
assertEqual(timerInit.display.services.isRawTimerRowsEnabled(), false)

local recordingSettings = {
    RecordingMode = "single",
    BatchTargetRuns = 2,
}
local recordingCache = {}
local recordingSplits = assert(loadfile("src/timer/splits/splits.lua"))({
    formatTimestamp = core.formatTimestamp,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local recordingBatch = assert(loadfile("src/timer/batch/batch.lua"))({
    core = core,
    formatTimestamp = core.formatTimestamp,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local recordingRefreshCount = 0
local recording = assert(loadfile("src/timer/recording/recording.lua"))({
    splits = recordingSplits,
    batch = recordingBatch,
    readSetting = function(alias)
        return recordingSettings[alias]
    end,
    refreshDisplay = function()
        recordingRefreshCount = recordingRefreshCount + 1
    end,
    persistentCache = newPersistentCache(recordingCache),
})
recording.initialize()
assertEqual(recording.status().kind, "idle")
recording.start(2)
assertEqual(recordingRefreshCount, 1)
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
recording.syncMode()
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
assertEqual(recordingBatch.row(1).igt, "00:15.00")
recording.applyAction({ kind = "stop" })
assertEqual(recordingCache.RecordingReady, false)
assertEqual(recording.status().kind, "idle")
setTime(0)
local bridgeSettings = {
    RecordingMode = "single",
    BatchTargetRuns = 2,
}
local bridgeSplits = assert(loadfile("src/timer/splits/splits.lua"))({
    formatTimestamp = core.formatTimestamp,
    isRunSuccess = function(run)
        return run and run.Cleared == true
    end,
})
local bridgeBatch = assert(loadfile("src/timer/batch/batch.lua"))({
    core = core,
    formatTimestamp = core.formatTimestamp,
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
local bridgeRefresh = {
    structure = 0,
    text = 0,
}
bridgeRecording = assert(loadfile("src/timer/recording/recording.lua"))({
    splits = bridgeSplits,
    batch = bridgeBatch,
    readSetting = function(alias)
        return bridgeSettings[alias]
    end,
    refreshDisplay = function() end,
    persistentCache = newPersistentCache(),
})
local runLoop = assert(loadfile("src/timer/run_loop/run_loop.lua"))({
    singleRun = bridgeSingleRun,
    recording = bridgeRecording,
    splits = bridgeSplits,
    batch = bridgeBatch,
    isEnabled = function()
        return true
    end,
    getCurrentRun = function()
        return CurrentRun
    end,
    refreshStructure = function()
        bridgeRefresh.structure = bridgeRefresh.structure + 1
    end,
    refreshText = function()
        bridgeRefresh.text = bridgeRefresh.text + 1
    end,
})
local bridgeHooks = {}
runLoop.installHooks({
    wrap = function(name, callback)
        bridgeHooks[name] = callback
    end,
})
bridgeRecording.start(2)
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
bridgeHooks.StartNewRun(function()
    return CurrentRun
end)
assertEqual(bridgeRecording.status().kind, "active")
assertEqual(runLoop.ensureDisplayLoop(), true)
assertEqual(bridgeSingleRun.hasCurrentRunDisplay(), true)
bridgeHooks.RoomEntranceMaterialize(function()
    return true
end)
setTime(7)
_G.CurrentRun.GameplayTime = 6
runLoop.updateTick()
local bridgeSplitRow = bridgeSplits.row(1, bridgeSingleRun.getActiveTimer(), CurrentRun, bridgeSingleRun.getSnapshot())
assertEqual(bridgeSplitRow.igt, "00:06.00")
bridgeHooks.RecordRunStats(function()
    return true
end)
assertEqual(bridgeRecording.status().kind, "recorded")
assert(bridgeRefresh.structure > 0, "expected bridge structure refresh")
assert(bridgeRefresh.text > 0, "expected bridge text refresh")

bridgeSettings.RecordingMode = "multi"
bridgeRecording.syncMode()
setTime(0)
local bridgeMultiRun = {
    GameplayTime = 0,
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
}
_G.CurrentRun = bridgeMultiRun
bridgeHooks.StartNewRun(function()
    return CurrentRun
end)
bridgeHooks.RoomEntranceMaterialize(function()
    return true
end)
setTime(9)
_G.CurrentRun.GameplayTime = 5
runLoop.updateTick()
bridgeHooks.RecordRunStats(function()
    bridgeMultiRun.Cleared = true
    return true
end)
assertEqual(bridgeRecording.status().text, "Recording 1 / 2")
assertEqual(bridgeBatch.row(1).igt, "00:05.00")
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
local uiModule = dofile("src/ui.lua").bind({
    getRecordingStatus = function()
        return uiStatus
    end,
})

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
}, drawState, uiActions)
assertEqual(uiSessionValues.ShowIGT, true)
assertEqual(uiSessionActions.recording.kind, "start")
assertEqual(uiButtons[1], "Start")
assertEqual(uiButtons[2], nil)

uiSessionActions = {}
uiButtons = {}
uiModule.drawQuickContent({
    imgui = uiDraw.imgui,
    widgets = uiDraw.widgets,
}, drawState, uiActions)
assertEqual(uiSessionActions.recording.kind, "start")
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
}, drawState, uiActions)
assertEqual(uiSessionActions.recording.kind, "clear")
assertEqual(uiButtons[1], "Stop")
assertEqual(uiButtons[2], "Clear")
assertEqual(uiButtons[3], nil)

local harness = dofile("../../Setup/tests/module_entrypoint_harness.lua")
local boot = harness.bootModule({
    pluginGuid = "adamant-Speedrun_Timer",
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
assert(boot.host and boot.host.setEnabled(true))
boot.host.drawTab()
boot.host.drawQuickContent()

local consumerHost = boot.lib.createModule({
    pluginGuid = "test-SpeedrunTimerConsumer",
    config = {},
    id = "TimerConsumer",
    name = "Timer Consumer",
    drawTab = function() end,
})
assert(consumerHost and consumerHost.activate())

assertEqual(consumerHost.integrations.poll("speedrun.timer", "getRealTime", "missing"), "00:00.00")
assertEqual(consumerHost.integrations.poll("speedrun.timer", "getLoadRemovedTime", "missing"), "00:00.00")
assertEqual(consumerHost.integrations.poll("speedrun.timer", "getInGameTime", "missing"), "00:00.00")
local times = consumerHost.integrations.poll("speedrun.timer", "getTimes", nil)
assertEqual(times.realTime, "00:00.00")
assertEqual(times.loadRemovedTime, "00:00.00")
assertEqual(times.inGameTime, "00:00.00")
assertEqual(next(boot.moduleEnv.public), nil)

print("Timer tests passed")
