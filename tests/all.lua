local timerModule = {}
local runtimeValues = {
    RecordingReady = false,
}
local fakeTime = 0
_worldTime = 0

RtaTimer = {}
function RtaTimer:new()
    local o = {
        Running = false,
        StartTime = 0,
        ElapsedTime = 0,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end
function RtaTimer:start()
    self.Running = true
    self.StartTime = fakeTime
    self.ElapsedTime = 0
end
function RtaTimer:stop()
    self:update()
    self.Running = false
end
function RtaTimer:update()
    if self.Running then
        self.ElapsedTime = fakeTime - self.StartTime
    end
end
function RtaTimer:getTime()
    return self.ElapsedTime
end

LrtTimer = {}
function LrtTimer:new(args)
    local o = {
        Running = false,
        Loading = false,
        LoadStartTime = 0,
        LoadTime = 0,
        RealTimer = args and args.withRtaTimer or RtaTimer:new(),
    }
    setmetatable(o, self)
    self.__index = self
    return o
end
function LrtTimer:start()
    self.Running = true
    self.Loading = false
    self.LoadTime = 0
end
function LrtTimer:stop()
    self.Running = false
end
function LrtTimer.update()
end
function LrtTimer:processLoadEvent(isLoading)
    if isLoading and not self.Loading then
        self.Loading = true
        self.LoadStartTime = fakeTime
    elseif not isLoading and self.Loading then
        self.Loading = false
        self.LoadTime = self.LoadTime + fakeTime - self.LoadStartTime
    end
end
function LrtTimer:getTime()
    return self.RealTimer:getTime() - self.LoadTime
end

IgtTimer = {}
function IgtTimer:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end
function IgtTimer.getTime()
    return CurrentRun and CurrentRun.GameplayTime or 0
end

assert(loadfile("src/timer/OverlayRows.lua"))(timerModule)
assert(loadfile("src/timer/Splits.lua"))(timerModule)
assert(loadfile("src/timer/Batch.lua"))(timerModule)
assert(loadfile("src/timer/Recorder.lua"))(timerModule)
assert(loadfile("src/timer/Runtime.lua"))(timerModule)
timerModule.EnsureTimerDisplayLoop = function() end
timerModule.host = {
    isEnabled = function()
        return true
    end,
    cache = {
        persistent = {
            read = function(alias, fallback)
                local value = runtimeValues[alias]
                if value == nil then
                    return fallback
                end
                return value
            end,
            write = function(alias, value)
                runtimeValues[alias] = value
            end,
        },
    },
}
timerModule.store = {
    read = function(alias)
        if alias == "ShowSplitTable" then
            return true
        end
        if alias == "RecordingMode" then
            return "multi"
        end
        if alias == "BatchTargetRuns" then
            return 2
        end
        return runtimeValues[alias]
    end,
}

local retained = {
    lines = {},
    tables = {},
    intervals = {},
}
timerModule.RegisterOverlays({
    order = {
        module = 1000,
    },
    createLine = function(name, spec)
        retained.lines[name] = spec
    end,
    createTable = function(name, spec)
        retained.tables[name] = spec
    end,
    onCommit = function(callback)
        retained.commit = callback
    end,
    onInterval = function(name, seconds, callback, opts)
        retained.intervals[name] = {
            seconds = seconds,
            callback = callback,
            opts = opts,
        }
    end,
})

local projection = {
    lines = {},
    tables = {},
    refreshCount = 0,
}
local projectionContext = {
    setLine = function(name, values)
        projection.lines[name] = values
        return true
    end,
    setTable = function(name, rows)
        projection.tables[name] = rows
        return true
    end,
    refreshRegion = function(region)
        projection.region = region
        projection.refreshCount = projection.refreshCount + 1
    end,
}

local function assertEqual(actual, expected)
    if actual ~= expected then
        error(string.format("expected %q, got %q", expected, actual), 2)
    end
end

local function assertBatchStatusText(expected)
    assertEqual(timerModule.GetBatchStatus().text, expected)
end

local format = timerModule.FormatTimestamp

assert(retained.lines["summary.igt"] ~= nil, "missing IGT overlay line")
assert(retained.lines["summary.rta"] ~= nil, "missing RTA overlay line")
assert(retained.lines["summary.lrt"] ~= nil, "missing LrT overlay line")
assert(retained.tables.batch ~= nil, "missing batch overlay table")
assert(retained.tables.splits ~= nil, "missing split overlay table")
assert(retained.intervals.timer ~= nil, "missing timer interval overlay event")
retained.commit(projectionContext, {})
assertEqual(projection.lines["summary.igt"].label, "IGT:")
assertEqual(projection.lines["summary.igt"].time, "00:00.00")
assertEqual(projection.region, "middleRightStack")

assertEqual(format(nil), "00:00.00")
assertEqual(format(0), "00:00.00")
assertEqual(format(1.23), "00:01.23")
assertEqual(format(59.99), "00:59.99")
assertEqual(format(60), "01:00.00")
assertEqual(format(61.23), "01:01.23")
assertEqual(format(3599.99), "59:59.99")
assertEqual(format(3600), "01:00:00.00")
assertEqual(format(3661.23), "01:01:01.23")

local timer = {
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
local snapshot = {
    igt = 12.34,
    rta = 13.45,
    lrt = 12.89,
    formatted = {
        igt = "00:12.34",
        rta = "00:13.45",
        lrt = "00:12.89",
    },
}

timerModule.ConfigureSplitOverlays({
    order = 1020,
    getTimer = function()
        return timer
    end,
    getSnapshot = function()
        return snapshot
    end,
    isVisible = function()
        return true
    end,
})

timerModule.ClearSingleRecording(true)
timerModule.StartSplitRun({
    CurrentRoom = { RoomSetName = "F" },
})
local row = timerModule.GetSplitDisplayRow(1, timer, {
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
})
assertEqual(row.label, "Erebus")
assertEqual(row.igt, "00:12.34")
assertEqual(row.rta, "00:13.45")
assertEqual(row.lrt, "00:12.89")

timerModule.StartSplitRun({
    CurrentRoom = { RoomSetName = "N" },
})
row = timerModule.GetSplitDisplayRow(1, timer, {
    CurrentRoom = { RoomSetName = "N" },
    EnteredBiomes = 1,
})
assertEqual(row.label, "Ephyra")

timerModule.StartSplitRun({
    IsDreamRun = true,
})
row = timerModule.GetSplitDisplayRow(2, timer, {
    IsDreamRun = true,
    CurrentRoom = { RoomSetName = "P" },
    EnteredBiomes = 2,
    BiomeVisitOrder = { "G", "P" },
})
assertEqual(row.label, "Olympus")
assertEqual(row.igt, "00:12.34")

timerModule.StartSplitRun({
    CurrentRoom = { RoomSetName = "F" },
})
timerModule.RecordCompletedBiomeSplits(timer, {
    BiomeVisitOrder = { "F" },
    BiomeGameplayTimes = {
        F = 65.43,
    },
})
row = timerModule.GetSplitDisplayRow(1, timer, {
    CurrentRoom = { RoomSetName = "G" },
    EnteredBiomes = 2,
    BiomeGameplayTimes = {
        F = 65.43,
    },
})
assertEqual(row.label, "Erebus")
assertEqual(row.igt, "01:05.43")
assertEqual(row.rta, "00:13.45")

timerModule.StartRecording(2)
assertBatchStatusText("Recording ready for 2 runs")
assertEqual(timerModule.GetBatchStatus().kind, "ready")
assertEqual(runtimeValues.RecordingReady, true)
assertEqual(timerModule.GetBatchDisplayTime("rta"), nil)
timerModule.StartBatchRun()
assertEqual(timerModule.GetBatchStatus().kind, "active")
timerModule.UpdateBatchDisplayRows()
assertEqual(timerModule.GetBatchCurrentDisplayRow().label, "Current 1/2")
fakeTime = 100
timerModule.UpdateBatchTimer()
timerModule.FinalizeBatchRun({
    getInGameTime = function()
        return 80
    end,
}, {
    Cleared = true,
})
assertBatchStatusText("Recording 1 / 2")
assertEqual(timerModule.GetBatchDisplayTime("igt"), "01:20.00")
assertEqual(timerModule.GetBatchDisplayTime("igt", {
    getInGameTime = function()
        return 80
    end,
}), "01:20.00")
assertEqual(timerModule.GetBatchDisplayTime("rta"), "01:40.00")
timerModule.UpdateBatchDisplayRows()
assertEqual(timerModule.GetBatchDisplayRow(1).label, "Run 1/2")
assertEqual(timerModule.GetBatchCurrentDisplayRow().label, "")

fakeTime = 190
timerModule.UpdateBatchTimer()
timerModule.FinalizeBatchRun({
    getInGameTime = function()
        return 70
    end,
}, {
    Cleared = true,
})
assertBatchStatusText("Recorded 2 / 2")
assertEqual(timerModule.GetBatchStatus().kind, "recorded")
assertEqual(timerModule.GetBatchDisplayTime("igt"), "02:30.00")
timerModule.UpdateBatchDisplayRows()
assertEqual(timerModule.GetBatchDisplayRow(2).label, "Run 2/2")
timerModule.StartBatchRun()
timerModule.UpdateBatchDisplayRows()
assertEqual(timerModule.GetBatchDisplayRow(1).label, "")
assertEqual(timerModule.GetBatchCurrentDisplayRow().label, "Current 1/2")

timerModule.StartRecording(3)
timerModule.StartBatchRun()
fakeTime = 240
timerModule.UpdateBatchTimer()
timerModule.FinalizeBatchRun({
    getInGameTime = function()
        return 10
    end,
}, {
    Cleared = false,
})
assertBatchStatusText("Failed (0 / 3 complete)")
assertEqual(timerModule.GetBatchStatus().kind, "failed")
assertEqual(runtimeValues.RecordingReady, true)
timerModule.StartBatchRun()
timerModule.UpdateBatchDisplayRows()
assertEqual(timerModule.GetBatchDisplayRow(1).label, "")
assertEqual(timerModule.GetBatchCurrentDisplayRow().label, "Current 1/3")

runtimeValues.RecordingReady = true
timerModule.store.read = function(alias)
    if alias == "BatchTargetRuns" then
        return 4
    end
    if alias == "ShowSplitTable" then
        return true
    end
    if alias == "RecordingMode" then
        return "multi"
    end
    return runtimeValues[alias]
end
timerModule.InitializeBatchState()
timerModule.InitializeRecordingState()
assertBatchStatusText("Recording ready for 4 runs")
assertEqual(runtimeValues.RecordingReady, true)
timerModule.OnRecordingRunStarted({
    CurrentRoom = { RoomSetName = "N" },
})
assertEqual(timerModule.GetBatchStatus().kind, "active")
assertEqual(timerModule.IsSplitRecordingOverlayVisible(), true)
row = timerModule.GetSplitDisplayRow(1, timer, {
    CurrentRoom = { RoomSetName = "N" },
    EnteredBiomes = 1,
})
assertEqual(row.label, "Ephyra")

timerModule.store.read = function(alias)
    if alias == "RecordingMode" then
        return "single"
    end
    if alias == "BatchTargetRuns" then
        return 4
    end
    return nil
end
timerModule.SyncRecordingMode()
assertEqual(timerModule.GetRecordingStatus().kind, "ready")
timerModule.StopRecording()
assertEqual(runtimeValues.RecordingReady, false)
assertEqual(timerModule.GetRecordingStatus().kind, "idle")

local uiModule = dofile("src/ui.lua").bind({
    getRecordingStatus = function()
        return timerModule.GetRecordingStatus()
    end,
    startRecording = function(targetRuns)
        timerModule.StartRecording(targetRuns)
    end,
    clearRecording = function(targetRuns)
        timerModule.ClearRecording(targetRuns)
    end,
    stopRecording = function()
        timerModule.StopRecording()
    end,
})

local uiSessionValues = {
    ShowIGT = false,
    ShowRTA = false,
    ShowLrT = false,
    ShowLiveTimers = true,
    ShowSplitTable = true,
    RecordingMode = "single",
}
local uiSessionActions = {}
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
        button = function(_, opts)
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
assertEqual(uiSessionActions.recording.kind, "stop")

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
