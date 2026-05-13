SpeedrunTimerInternal = {}
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
function LrtTimer:update()
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
function IgtTimer:getTime()
    return CurrentRun and CurrentRun.GameplayTime or 0
end

lib = {
    overlays = {
        order = {
            module = 1000,
        },
        registerStackedText = function()
            return {
                setText = function() end,
                setVisible = function() end,
                refresh = function() end,
            }
        end,
        registerStackedRow = function()
            return {
                setColumnText = function() return true end,
                setVisible = function() end,
                refresh = function() end,
            }
        end,
        refreshStackedText = function() end,
    },
    isModuleEnabled = function()
        return true
    end,
}

dofile("src/timer/OverlayRows.lua")
dofile("src/timer/Splits.lua")
dofile("src/timer/Batch.lua")
dofile("src/timer/Recorder.lua")
dofile("src/timer/Runtime.lua")
SpeedrunTimerInternal.EnsureTimerDisplayLoop = function() end
SpeedrunTimerInternal.store = {
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
    writeUnstaged = function(alias, value)
        runtimeValues[alias] = value
    end,
}

local function assertEqual(actual, expected)
    if actual ~= expected then
        error(string.format("expected %q, got %q", expected, actual), 2)
    end
end

local function assertBatchStatusText(expected)
    assertEqual(SpeedrunTimerInternal.GetBatchStatus().text, expected)
end

local format = SpeedrunTimerInternal.FormatTimestamp

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

SpeedrunTimerInternal.ConfigureSplitOverlays({
    order = lib.overlays.order.module + 20,
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

SpeedrunTimerInternal.ClearSingleRecording(true)
SpeedrunTimerInternal.StartSplitRun({
    CurrentRoom = { RoomSetName = "F" },
})
local row = SpeedrunTimerInternal.GetSplitDisplayRow(1, timer, {
    CurrentRoom = { RoomSetName = "F" },
    EnteredBiomes = 1,
})
assertEqual(row.label, "Erebus")
assertEqual(row.igt, "00:12.34")
assertEqual(row.rta, "00:13.45")
assertEqual(row.lrt, "00:12.89")

SpeedrunTimerInternal.StartSplitRun({
    CurrentRoom = { RoomSetName = "N" },
})
row = SpeedrunTimerInternal.GetSplitDisplayRow(1, timer, {
    CurrentRoom = { RoomSetName = "N" },
    EnteredBiomes = 1,
})
assertEqual(row.label, "Ephyra")

SpeedrunTimerInternal.StartSplitRun({
    IsDreamRun = true,
})
row = SpeedrunTimerInternal.GetSplitDisplayRow(2, timer, {
    IsDreamRun = true,
    CurrentRoom = { RoomSetName = "P" },
    EnteredBiomes = 2,
    BiomeVisitOrder = { "G", "P" },
})
assertEqual(row.label, "Olympus")
assertEqual(row.igt, "00:12.34")

SpeedrunTimerInternal.StartSplitRun({
    CurrentRoom = { RoomSetName = "F" },
})
SpeedrunTimerInternal.RecordCompletedBiomeSplits(timer, {
    BiomeVisitOrder = { "F" },
    BiomeGameplayTimes = {
        F = 65.43,
    },
})
row = SpeedrunTimerInternal.GetSplitDisplayRow(1, timer, {
    CurrentRoom = { RoomSetName = "G" },
    EnteredBiomes = 2,
    BiomeGameplayTimes = {
        F = 65.43,
    },
})
assertEqual(row.label, "Erebus")
assertEqual(row.igt, "01:05.43")
assertEqual(row.rta, "00:13.45")

SpeedrunTimerInternal.StartRecording(2)
assertBatchStatusText("Recording ready for 2 runs")
assertEqual(SpeedrunTimerInternal.GetBatchStatus().kind, "ready")
assertEqual(runtimeValues.RecordingReady, true)
assertEqual(SpeedrunTimerInternal.GetBatchDisplayTime("rta"), nil)
SpeedrunTimerInternal.StartBatchRun()
assertEqual(SpeedrunTimerInternal.GetBatchStatus().kind, "active")
SpeedrunTimerInternal.UpdateBatchDisplayRows()
assertEqual(SpeedrunTimerInternal.GetBatchCurrentDisplayRow().label, "Current 1/2")
fakeTime = 100
SpeedrunTimerInternal.UpdateBatchTimer()
SpeedrunTimerInternal.FinalizeBatchRun({
    getInGameTime = function()
        return 80
    end,
}, {
    Cleared = true,
})
assertBatchStatusText("Recording 1 / 2")
assertEqual(SpeedrunTimerInternal.GetBatchDisplayTime("igt"), "01:20.00")
assertEqual(SpeedrunTimerInternal.GetBatchDisplayTime("igt", {
    getInGameTime = function()
        return 80
    end,
}), "01:20.00")
assertEqual(SpeedrunTimerInternal.GetBatchDisplayTime("rta"), "01:40.00")
SpeedrunTimerInternal.UpdateBatchDisplayRows()
assertEqual(SpeedrunTimerInternal.GetBatchDisplayRow(1).label, "Run 1/2")
assertEqual(SpeedrunTimerInternal.GetBatchCurrentDisplayRow().label, "")

fakeTime = 190
SpeedrunTimerInternal.UpdateBatchTimer()
SpeedrunTimerInternal.FinalizeBatchRun({
    getInGameTime = function()
        return 70
    end,
}, {
    Cleared = true,
})
assertBatchStatusText("Recorded 2 / 2")
assertEqual(SpeedrunTimerInternal.GetBatchStatus().kind, "recorded")
assertEqual(SpeedrunTimerInternal.GetBatchDisplayTime("igt"), "02:30.00")
SpeedrunTimerInternal.UpdateBatchDisplayRows()
assertEqual(SpeedrunTimerInternal.GetBatchDisplayRow(2).label, "Run 2/2")
SpeedrunTimerInternal.StartBatchRun()
SpeedrunTimerInternal.UpdateBatchDisplayRows()
assertEqual(SpeedrunTimerInternal.GetBatchDisplayRow(1).label, "")
assertEqual(SpeedrunTimerInternal.GetBatchCurrentDisplayRow().label, "Current 1/2")

SpeedrunTimerInternal.StartRecording(3)
SpeedrunTimerInternal.StartBatchRun()
fakeTime = 240
SpeedrunTimerInternal.UpdateBatchTimer()
SpeedrunTimerInternal.FinalizeBatchRun({
    getInGameTime = function()
        return 10
    end,
}, {
    Cleared = false,
})
assertBatchStatusText("Failed (0 / 3 complete)")
assertEqual(SpeedrunTimerInternal.GetBatchStatus().kind, "failed")
assertEqual(runtimeValues.RecordingReady, true)
SpeedrunTimerInternal.StartBatchRun()
SpeedrunTimerInternal.UpdateBatchDisplayRows()
assertEqual(SpeedrunTimerInternal.GetBatchDisplayRow(1).label, "")
assertEqual(SpeedrunTimerInternal.GetBatchCurrentDisplayRow().label, "Current 1/3")

runtimeValues.RecordingReady = true
SpeedrunTimerInternal.store.read = function(alias)
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
SpeedrunTimerInternal.InitializeBatchState()
SpeedrunTimerInternal.InitializeRecordingState()
assertBatchStatusText("Recording ready for 4 runs")
assertEqual(runtimeValues.RecordingReady, true)
SpeedrunTimerInternal.OnRecordingRunStarted({
    CurrentRoom = { RoomSetName = "N" },
})
assertEqual(SpeedrunTimerInternal.GetBatchStatus().kind, "active")
assertEqual(SpeedrunTimerInternal.IsSplitRecordingOverlayVisible(), true)
row = SpeedrunTimerInternal.GetSplitDisplayRow(1, timer, {
    CurrentRoom = { RoomSetName = "N" },
    EnteredBiomes = 1,
})
assertEqual(row.label, "Ephyra")

SpeedrunTimerInternal.store.read = function(alias)
    if alias == "RecordingMode" then
        return "single"
    end
    if alias == "BatchTargetRuns" then
        return 4
    end
    return nil
end
SpeedrunTimerInternal.SyncRecordingMode()
assertEqual(SpeedrunTimerInternal.GetRecordingStatus().kind, "ready")
SpeedrunTimerInternal.StopRecording()
assertEqual(runtimeValues.RecordingReady, false)
assertEqual(SpeedrunTimerInternal.GetRecordingStatus().kind, "idle")

lib.widgets = {
    text = function() end,
    separator = function() end,
    checkbox = function() return false end,
    radio = function() return false end,
    stepper = function() return false end,
    button = function() return false end,
}
dofile("src/ui.lua")

local uiSessionValues = {
    ShowIGT = false,
    ShowRTA = false,
    ShowLrT = false,
    ShowLiveTimers = true,
    ShowSplitTable = true,
    RecordingMode = "single",
}
SpeedrunTimerInternal.DrawTab({
    SameLine = function() end,
    Spacing = function() end,
}, {
    read = function(alias)
        return uiSessionValues[alias]
    end,
    write = function(alias, value)
        uiSessionValues[alias] = value
    end,
})
assertEqual(uiSessionValues.ShowIGT, true)

print("Timer tests passed")
