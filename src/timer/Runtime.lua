SpeedrunTimerInternal = SpeedrunTimerInternal or {}
local internal = SpeedrunTimerInternal

local SpeedrunTimer = {}

function SpeedrunTimer:new()
    local o = {}
    o.Running = false
    o.RtaTimer = RtaTimer:new()
    o.LrtTimer = LrtTimer:new({ withRtaTimer = o.RtaTimer })
    o.IgtTimer = IgtTimer:new()
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

local TIMER_OVERLAY_ORDER = lib.overlays.order.module + 10
local BATCH_OVERLAY_ORDER = TIMER_OVERLAY_ORDER + 10
local SPLIT_OVERLAY_ORDER = BATCH_OVERLAY_ORDER + 20
local TIMER_REFRESH_INTERVAL = 0.05
local OVERLAY_REGION = internal.TimerOverlay.region
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
    SplitMode = "single",
}

local function ToCentiseconds(timestamp)
    if not timestamp then
        return 0
    end
    return math.floor((timestamp * 100) + 0.0000001)
end

local function FormatCentiseconds(totalCentiseconds)
    local centiseconds = totalCentiseconds % 100
    local totalSeconds = math.floor(totalCentiseconds / 100)
    local seconds = totalSeconds % 60
    local totalMinutes = math.floor(totalSeconds / 60)
    local minutes = totalMinutes % 60
    local hours = math.floor(totalMinutes / 60)

    if hours == 0 then
        return string.format("%02d:%02d.%02d", minutes, seconds, centiseconds)
    end
    return string.format("%02d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
end

function internal.FormatTimestamp(timestamp)
    return FormatCentiseconds(ToCentiseconds(timestamp))
end

local activeTimer = nil
local timerOverlays = {}
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

    local centiseconds = ToCentiseconds(value)
    if timerSnapshot.centiseconds[key] ~= centiseconds then
        timerSnapshot.centiseconds[key] = centiseconds
        timerSnapshot.formatted[key] = FormatCentiseconds(centiseconds)
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
    return lib.isModuleEnabled(internal.store, internal.PACK_ID)
end

local function ReadSetting(alias)
    local store = internal.store
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

local function IsMultiRunMode()
    if displaySettings.initialized then
        return displaySettings.splitMode == "multi"
    end
    return ReadSetting("SplitMode") == "multi"
end

local function IsCurrentRunOverlayVisible()
    return activeTimer
        and (activeTimer.Running or showCompletedRun)
        and IsModuleEnabled()
end

local function IsTimerOverlayVisible()
    local hasCurrentRunDisplay = activeTimer and (activeTimer.Running or showCompletedRun)
    local hasBatchDisplay = internal.IsBatchVisible and internal.IsBatchVisible()
    return IsModuleEnabled() and IsLiveTimerRowsEnabled() and (hasCurrentRunDisplay or hasBatchDisplay)
end

local function ReadTimerMode(mode)
    local alias = MODE_ALIASES[mode]
    local store = internal.store
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
    displaySettings.splitMode = ReadSetting("SplitMode")
    displaySettings.showIgt = ReadTimerModeVisibility("igt")
    displaySettings.showRta = ReadTimerModeVisibility("rta")
    displaySettings.showLrt = ReadTimerModeVisibility("lrt")
end

local function GetDisplayTime(mode)
    if internal.GetBatchDisplayTime then
        local batchTime = internal.GetBatchDisplayTime(mode, activeTimer)
        if batchTime ~= nil then
            return batchTime
        end
    end
    return timerSnapshot.formatted[mode]
end

local function EnsureTimerOverlay(timerName, mode, orderOffset, getTime)
    if timerOverlays[timerName] then
        return timerOverlays[timerName]
    end

    local handle = lib.overlays.registerStackedRow({
        id = "speedrun.timer." .. timerName,
        componentName = "SpeedrunTimer_" .. timerName,
        region = OVERLAY_REGION,
        order = TIMER_OVERLAY_ORDER + orderOffset,
        columnGap = 20,
        columns = {
            {
                key = "label",
                minWidth = 40,
                justify = "Left",
                text = timerName .. ":",
                textArgs = {
                    Font = "P22UndergroundSCMedium",
                },
            },
            {
                key = "time",
                minWidth = 80,
                justify = "Left",
                text = getTime,
                textArgs = {
                    Font = "NumericP22UndergroundSCMedium",
                },
            },
        },
        visible = function()
            return IsTimerModeOverlayVisible(mode)
        end,
    })
    timerOverlays[timerName] = handle
    return handle
end

local function EnsureTimerOverlays()
    EnsureTimerOverlay("IGT", "igt", 0, function()
        return GetDisplayTime("igt")
    end)
    EnsureTimerOverlay("RTA", "rta", 1, function()
        return GetDisplayTime("rta")
    end)
    EnsureTimerOverlay("LrT", "lrt", 2, function()
        return GetDisplayTime("lrt")
    end)
end

if internal.ConfigureBatchOverlays then
    internal.ConfigureBatchOverlays({
        order = BATCH_OVERLAY_ORDER,
    })
end

if internal.ConfigureSplitOverlays then
    internal.ConfigureSplitOverlays({
        order = SPLIT_OVERLAY_ORDER,
        getTimer = function()
            return activeTimer
        end,
        getSnapshot = GetTimerSnapshot,
        isVisible = function()
            return IsSplitTableEnabled() and IsCurrentRunOverlayVisible()
        end,
        isModeVisible = IsTimerModeVisible,
    })
end

if internal.ConfigureBatchMode then
    internal.ConfigureBatchMode({
        isVisible = function()
            return IsSplitTableEnabled() and IsMultiRunMode()
        end,
        isModeVisible = IsTimerModeVisible,
    })
end

local function RefreshTimerStructure()
    SyncDisplaySettings()
    EnsureTimerOverlays()
    if internal.UpdateBatchDisplayRows then
        internal.UpdateBatchDisplayRows()
    end
    if internal.UpdateSplitDisplayRows then
        internal.UpdateSplitDisplayRows(activeTimer)
    end
    if internal.EnsureBatchOverlays then
        internal.EnsureBatchOverlays()
    end
    if internal.EnsureSplitOverlays then
        internal.EnsureSplitOverlays()
    end
    lib.overlays.refreshStackedText(OVERLAY_REGION)
end

local function RefreshTimerText()
    for _, handle in pairs(timerOverlays) do
        if handle.refreshText then
            handle.refreshText()
        else
            handle.refresh()
        end
    end
    if internal.RefreshSplitText then
        internal.RefreshSplitText(activeTimer)
    end
end

local function CleanupDisplay()
    RefreshTimerStructure()
end

local updateThreadActive = false
local StopAndCleanup = nil

local function HasActiveDisplayLoop()
    local hasRunningTimer = activeTimer and activeTimer.Running
    local hasActiveBatch = internal.IsBatchActive and internal.IsBatchActive()
    return hasRunningTimer or hasActiveBatch
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

    if HasActiveDisplayLoop() and not updateThreadActive then
        updateThreadActive = true
        thread(function()
            while HasActiveDisplayLoop() do
                if not IsModuleEnabled() then
                    StopAndCleanup()
                    return
                end

                if activeTimer and activeTimer.Running then
                    activeTimer:update()
                    if internal.RecordCompletedBiomeSplits then
                        internal.RecordCompletedBiomeSplits(activeTimer)
                    end
                end
                if internal.UpdateBatchTimer then
                    internal.UpdateBatchTimer()
                end
                UpdateTimerSnapshot()

                RefreshTimerText()

                wait(TIMER_REFRESH_INTERVAL, "adamant_SpeedrunTimer", true)
            end
            updateThreadActive = false
        end)
    end
end

StopAndCleanup = function()
    ClearActiveTimer()
    if internal.StopBatch then
        internal.StopBatch()
    end
    updateThreadActive = false
    CleanupDisplay()
end

internal.RefreshTimerDisplay = RefreshTimerStructure
internal.EnsureTimerDisplayLoop = StartTimerDisplayLoop

function internal.OnSettingsCommitted()
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
    if internal.FinalizeBatchRun then
        internal.FinalizeBatchRun(activeTimer, GetCurrentRun())
    end
    activeTimer:stop()
    showCompletedRun = not IsMultiRunMode()
    UpdateTimerSnapshot()
    RefreshTimerStructure()
end

function internal.RegisterHooks()
    lib.hooks.Wrap(internal, "StartNewRun", function(baseFunc, prevRun, args)
        if not IsModuleEnabled() then return baseFunc(prevRun, args) end
        if activeTimer then
            ClearActiveTimer()
        end
        activeTimer = SpeedrunTimer:new()
        runFinalized = false
        showCompletedRun = false
        UpdateTimerSnapshot()
        local run = baseFunc(prevRun, args)
        if internal.StartSplitRun then
            internal.StartSplitRun(run)
        end
        if internal.StartBatchRun then
            internal.StartBatchRun()
        end
        RefreshTimerStructure()
        return run
    end)

    lib.hooks.Wrap(internal, "RoomEntranceMaterialize", function(baseFunc, ...)
        if not IsModuleEnabled() then return baseFunc(...) end
        local val = baseFunc(...)
        StartTimerDisplayLoop()
        return val
    end)

    lib.hooks.Wrap(internal, "RoomEntranceDreamBiomeStart", function(baseFunc, ...)
        if not IsModuleEnabled() then return baseFunc(...) end
        local val = baseFunc(...)
        StartTimerDisplayLoop()
        return val
    end)

    lib.hooks.Wrap(internal, "RecordRunStats", function(baseFunc, ...)
        if not IsModuleEnabled() then return baseFunc(...) end
        local val = baseFunc(...)
        HandleRunFinalized()
        return val
    end)

    lib.hooks.Wrap(internal, "AddTimerBlock", function(baseFunc, currRun, timerBlockName)
        local val = baseFunc(currRun, timerBlockName)
        local shouldRecordLoad = IsModuleEnabled() and timerBlockName == "MapLoad"
        if shouldRecordLoad and activeTimer and activeTimer.Running then
            activeTimer.LrtTimer:processLoadEvent(true)
        end
        if shouldRecordLoad and internal.ProcessBatchLoadEvent then
            internal.ProcessBatchLoadEvent(true)
        end
        return val
    end)

    lib.hooks.Wrap(internal, "RemoveTimerBlock", function(baseFunc, currRun, timerBlockName)
        local val = baseFunc(currRun, timerBlockName)
        local shouldRecordLoad = IsModuleEnabled() and timerBlockName == "MapLoad"
        if shouldRecordLoad and activeTimer and activeTimer.Running then
            activeTimer.LrtTimer:processLoadEvent(false)
        end
        if shouldRecordLoad and internal.ProcessBatchLoadEvent then
            internal.ProcessBatchLoadEvent(false)
        end
        return val
    end)
end

function internal.GetRealTime()
    return timerSnapshot.formatted.rta
end

function internal.GetLoadRemovedTime()
    return timerSnapshot.formatted.lrt
end

function internal.GetInGameTime()
    return timerSnapshot.formatted.igt
end
