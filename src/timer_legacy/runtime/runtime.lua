local timerApi = ...
local timerCore = timerApi.core
local timerOverlay = timerApi.overlay
local timerBatch = timerApi.batch
local timerSplits = timerApi.splits

local SpeedrunTimer = {}

function SpeedrunTimer:new()
    local o = {}
    o.Running = false
    o.RtaTimer = timerCore.RtaTimer:new()
    o.LrtTimer = timerCore.LrtTimer:new({ withRtaTimer = o.RtaTimer })
    o.IgtTimer = timerCore.IgtTimer:new()
    setmetatable(o, self)
    self.__index = self
    return o
end

function SpeedrunTimer:start()
    self.Running = true
    self.RtaTimer:start()
    self.LrtTimer:start()
end

function SpeedrunTimer:stop()
    self.Running = false
    self.RtaTimer:stop()
    self.LrtTimer:stop()
end

function SpeedrunTimer:update()
    self.RtaTimer:update()
    self.LrtTimer:update()
end

function SpeedrunTimer:getRealTime()
    return self.RtaTimer:getTime()
end

function SpeedrunTimer:getLoadRemovedTime()
    return self.LrtTimer:getTime()
end

function SpeedrunTimer:getInGameTime()
    return self.IgtTimer:getTime()
end

local TIMER_REFRESH_INTERVAL = 0.05
local OVERLAY_REGION = timerOverlay.region
local MODE_ALIASES = {
    igt = "ShowIGT",
    rta = "ShowRTA",
    lrt = "ShowLrT",
}
local DEFAULT_MODE_VISIBILITY = {
    igt = true,
    rta = false,
    lrt = false,
}
local DEFAULT_SETTING_VALUES = {
    ShowLiveTimers = true,
    ShowSplitTable = true,
    RecordingMode = "single",
}

function timerApi.FormatTimestamp(timestamp)
    return timerCore.formatTimestamp(timestamp)
end

local activeTimer = nil
local overlayContext = nil
local runFinalized = false
local showCompletedRun = false
local displaySettings = {
    initialized = false,
}
local timerSnapshot = {
    igt = 0,
    rta = 0,
    lrt = 0,
    centiseconds = {
        igt = -1,
        rta = -1,
        lrt = -1,
    },
    formatted = {
        igt = "00:00.00",
        rta = "00:00.00",
        lrt = "00:00.00",
    },
}

local function UpdateSnapshotValue(key, value)
    value = value or 0
    timerSnapshot[key] = value

    local centiseconds = timerCore.toCentiseconds(value)
    if timerSnapshot.centiseconds[key] ~= centiseconds then
        timerSnapshot.centiseconds[key] = centiseconds
        timerSnapshot.formatted[key] = timerCore.formatCentiseconds(centiseconds)
    end
end

local function UpdateTimerSnapshot()
    UpdateSnapshotValue("igt", activeTimer and activeTimer:getInGameTime() or 0)
    UpdateSnapshotValue("rta", activeTimer and activeTimer:getRealTime() or 0)
    UpdateSnapshotValue("lrt", activeTimer and activeTimer:getLoadRemovedTime() or 0)
end

local function GetTimerSnapshot()
    return timerSnapshot
end

local function IsModuleEnabled()
    return timerApi.host and timerApi.host.isEnabled()
end

local function ReadSetting(alias)
    local store = timerApi.store
    if store and type(store.read) == "function" then
        local value = store.read(alias)
        if value ~= nil then
            return value
        end
    end
    return DEFAULT_SETTING_VALUES[alias]
end

local function IsLiveTimerRowsEnabled()
    if displaySettings.initialized then
        return displaySettings.showLiveTimers == true
    end
    return ReadSetting("ShowLiveTimers") == true
end

local function IsSplitTableEnabled()
    if displaySettings.initialized then
        return displaySettings.showSplitTable == true
    end
    return ReadSetting("ShowSplitTable") == true
end

local function IsTimerOverlayVisible()
    local hasCurrentRunDisplay = activeTimer and (activeTimer.Running or showCompletedRun)
    local hasBatchDisplay = timerBatch.IsBatchVisible()
    return IsModuleEnabled() and IsLiveTimerRowsEnabled() and (hasCurrentRunDisplay or hasBatchDisplay)
end

local function ReadTimerMode(mode)
    local alias = MODE_ALIASES[mode]
    local store = timerApi.store
    if alias and store and type(store.read) == "function" then
        return store.read(alias)
    end
    return nil
end

local function ReadTimerModeVisibility(mode)
    local value = ReadTimerMode(mode)
    if value ~= nil then
        return value == true
    end
    return DEFAULT_MODE_VISIBILITY[mode] == true
end

local function IsTimerModeVisible(mode)
    if displaySettings.initialized then
        if mode == "igt" then
            return displaySettings.showIgt == true
        end
        if mode == "rta" then
            return displaySettings.showRta == true
        end
        if mode == "lrt" then
            return displaySettings.showLrt == true
        end
    end

    return ReadTimerModeVisibility(mode)
end

local function IsTimerModeOverlayVisible(mode)
    return IsTimerOverlayVisible() and IsTimerModeVisible(mode)
end

local function SyncDisplaySettings()
    displaySettings.initialized = true
    displaySettings.showLiveTimers = ReadSetting("ShowLiveTimers")
    displaySettings.showSplitTable = ReadSetting("ShowSplitTable")
    displaySettings.showIgt = ReadTimerModeVisibility("igt")
    displaySettings.showRta = ReadTimerModeVisibility("rta")
    displaySettings.showLrt = ReadTimerModeVisibility("lrt")
    if timerApi.SyncRecordingMode then
        timerApi.SyncRecordingMode()
    end
end

local function GetDisplayTime(mode)
    local batchTime = timerBatch.GetBatchDisplayTime(mode, activeTimer)
    if batchTime ~= nil then
        return batchTime
    end
    return timerSnapshot.formatted[mode]
end

local timerLines = {
    igt = {
        label = "IGT:",
        time = "00:00.00",
    },
    rta = {
        label = "RTA:",
        time = "00:00.00",
    },
    lrt = {
        label = "LrT:",
        time = "00:00.00",
    },
}

local function updateTimerLine(mode)
    local line = timerLines[mode]
    line.time = GetDisplayTime(mode)
    return line
end

local function projectTimerOverlay(ctx, opts)
    ctx = ctx or overlayContext
    if not ctx then
        return
    end

    overlayContext = ctx
    opts = opts or {}
    if opts.syncSettings == true then
        SyncDisplaySettings()
    end

    ctx.setLine("summary.igt", updateTimerLine("igt"))
    ctx.setLine("summary.rta", updateTimerLine("rta"))
    ctx.setLine("summary.lrt", updateTimerLine("lrt"))

    ctx.setTable("batch", timerBatch.BuildBatchOverlayRows())
    ctx.setTable("splits", timerSplits.BuildSplitOverlayRows(activeTimer, nil, opts.liveOnly == true))

    ctx.refreshRegion(OVERLAY_REGION)
end

local function RefreshTimerStructure()
    projectTimerOverlay(nil, {
        syncSettings = true,
    })
end

timerSplits.ConfigureSplitOverlays({
    getTimer = function()
        return activeTimer
    end,
    getSnapshot = GetTimerSnapshot,
    isVisible = function()
        return IsSplitTableEnabled()
            and timerApi.IsSplitRecordingOverlayVisible
            and timerApi.IsSplitRecordingOverlayVisible()
    end,
    isModeVisible = IsTimerModeVisible,
})

timerBatch.ConfigureBatchMode({
    isVisible = function()
        return IsSplitTableEnabled() and timerApi.IsMultiRunMode and timerApi.IsMultiRunMode()
    end,
    isModeVisible = IsTimerModeVisible,
})

if timerApi.ConfigureRecorder then
    timerApi.ConfigureRecorder({
        readSetting = ReadSetting,
        refreshDisplay = function()
            RefreshTimerStructure()
        end,
    })
end

local function RefreshTimerText()
    projectTimerOverlay(nil, {
        liveOnly = true,
    })
end

local function CleanupDisplay()
    RefreshTimerStructure()
end

local StopAndCleanup = nil

local function HasActiveDisplayLoop()
    local hasRunningTimer = activeTimer and activeTimer.Running
    local hasActiveBatch = timerBatch.IsBatchActive()
    return hasRunningTimer or hasActiveBatch
end

local function updateTimerTick()
    if not IsModuleEnabled() then
        StopAndCleanup()
        return
    end

    if activeTimer and activeTimer.Running then
        activeTimer:update()
        timerSplits.RecordCompletedBiomeSplits(activeTimer)
    end
    timerBatch.UpdateBatchTimer()
    UpdateTimerSnapshot()
end

local function createTimerLine(overlays, timerOverlayOrder, name, label, mode, orderOffset)
    overlays.createLine(name, {
        componentName = "SpeedrunTimer_" .. label,
        region = OVERLAY_REGION,
        order = timerOverlayOrder + orderOffset,
        columnGap = 20,
        columns = timerOverlay.buildSummaryColumns(),
        visible = function()
            return IsTimerModeOverlayVisible(mode)
        end,
    })
end

function timerApi.RegisterOverlays(overlays)
    local timerOverlayOrder = overlays.order.module + 10
    local batchOverlayOrder = timerOverlayOrder + 10
    local splitOverlayOrder = batchOverlayOrder + 20

    timerBatch.ConfigureBatchOverlays({
        order = batchOverlayOrder,
    })
    timerSplits.ConfigureSplitOverlays({
        order = splitOverlayOrder,
    })

    createTimerLine(overlays, timerOverlayOrder, "summary.igt", "IGT", "igt", 0)
    createTimerLine(overlays, timerOverlayOrder, "summary.rta", "RTA", "rta", 1)
    createTimerLine(overlays, timerOverlayOrder, "summary.lrt", "LrT", "lrt", 2)

    timerBatch.RegisterBatchOverlay(overlays)
    timerSplits.RegisterSplitOverlay(overlays)

    overlays.onCommit(function(ctx)
        projectTimerOverlay(ctx, {
            syncSettings = true,
        })
        if HasActiveDisplayLoop() then
            updateTimerTick()
            RefreshTimerText()
        end
    end)

    overlays.onInterval("timer", TIMER_REFRESH_INTERVAL, function(ctx)
        overlayContext = ctx
        updateTimerTick()
        RefreshTimerText()
    end, {
        when = HasActiveDisplayLoop,
    })
end

local function ClearActiveTimer()
    if activeTimer then
        activeTimer:stop()
    end
    activeTimer = nil
    showCompletedRun = false
    UpdateTimerSnapshot()
end

local function StartTimerDisplayLoop()
    local startedTimer = false
    if activeTimer and not activeTimer.Running and not runFinalized then
        activeTimer:start()
        startedTimer = true
    end

    if startedTimer then
        UpdateTimerSnapshot()
        RefreshTimerStructure()
    end

    if HasActiveDisplayLoop() then
        RefreshTimerText()
    end
end

StopAndCleanup = function()
    ClearActiveTimer()
    if timerApi.StopRecording then
        timerApi.StopRecording()
    end
    CleanupDisplay()
end

timerApi.RefreshTimerDisplay = RefreshTimerStructure
timerApi.EnsureTimerDisplayLoop = StartTimerDisplayLoop

function timerApi.OnSettingsCommitted(_, _, commit)
    if not IsModuleEnabled() then
        StopAndCleanup()
        return
    end
    local recordingRef = commit and commit.actions and commit.actions.get("recording") or nil
    local recordingAction = recordingRef and recordingRef:has() and recordingRef:read() or nil
    if recordingAction and timerApi.ApplyRecordingAction then
        timerApi.ApplyRecordingAction(recordingAction)
    end
    RefreshTimerStructure()
    StartTimerDisplayLoop()
end

local function GetCurrentRun()
    return rom and rom.game and rom.game.CurrentRun or CurrentRun
end

local function HandleRunFinalized()
    if runFinalized or not activeTimer then
        return
    end
    runFinalized = true
    if timerApi.OnRecordingRunFinalized then
        timerApi.OnRecordingRunFinalized(activeTimer, GetCurrentRun())
    end
    activeTimer:stop()
    showCompletedRun = not (timerApi.IsMultiRunMode and timerApi.IsMultiRunMode())
    UpdateTimerSnapshot()
    RefreshTimerStructure()
end

function timerApi.RegisterHooks()
    timerApi.host.hooks.wrap("StartNewRun", function(baseFunc, prevRun, args)
        if not IsModuleEnabled() then return baseFunc(prevRun, args) end
        if activeTimer then
            ClearActiveTimer()
        end
        activeTimer = SpeedrunTimer:new()
        runFinalized = false
        showCompletedRun = false
        UpdateTimerSnapshot()
        local run = baseFunc(prevRun, args)
        if timerApi.OnRecordingRunStarted then
            timerApi.OnRecordingRunStarted(run)
        end
        RefreshTimerStructure()
        return run
    end)

    timerApi.host.hooks.wrap("RoomEntranceMaterialize", function(baseFunc, ...)
        if not IsModuleEnabled() then return baseFunc(...) end
        local val = baseFunc(...)
        StartTimerDisplayLoop()
        return val
    end)

    timerApi.host.hooks.wrap("RoomEntranceDreamBiomeStart", function(baseFunc, ...)
        if not IsModuleEnabled() then return baseFunc(...) end
        local val = baseFunc(...)
        StartTimerDisplayLoop()
        return val
    end)

    timerApi.host.hooks.wrap("RecordRunStats", function(baseFunc, ...)
        if not IsModuleEnabled() then return baseFunc(...) end
        local val = baseFunc(...)
        HandleRunFinalized()
        return val
    end)

    timerApi.host.hooks.wrap("AddTimerBlock", function(baseFunc, currRun, timerBlockName)
        local val = baseFunc(currRun, timerBlockName)
        local shouldRecordLoad = IsModuleEnabled() and timerBlockName == "MapLoad"
        if shouldRecordLoad and activeTimer and activeTimer.Running then
            activeTimer.LrtTimer:processLoadEvent(true)
        end
        if shouldRecordLoad then
            timerBatch.ProcessBatchLoadEvent(true)
        end
        return val
    end)

    timerApi.host.hooks.wrap("RemoveTimerBlock", function(baseFunc, currRun, timerBlockName)
        local val = baseFunc(currRun, timerBlockName)
        local shouldRecordLoad = IsModuleEnabled() and timerBlockName == "MapLoad"
        if shouldRecordLoad and activeTimer and activeTimer.Running then
            activeTimer.LrtTimer:processLoadEvent(false)
        end
        if shouldRecordLoad then
            timerBatch.ProcessBatchLoadEvent(false)
        end
        return val
    end)
end

function timerApi.GetRealTime()
    return timerSnapshot.formatted.rta
end

function timerApi.GetLoadRemovedTime()
    return timerSnapshot.formatted.lrt
end

function timerApi.GetInGameTime()
    return timerSnapshot.formatted.igt
end
