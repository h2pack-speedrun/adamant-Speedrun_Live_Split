local deps = ... or {}
local timer = deps.timer
local settings = deps.settings
local module = deps.module
local game = deps.game

local TIMER_REFRESH_INTERVAL = 0.05
local MODE_ALIASES = {
    igt = "ShowIGT",
    rta = "ShowRTA",
    lrt = "ShowLrT",
}
local DEFAULTS = {
    ShowRawTimers = false,
    ShowRecordingTable = true,
    ShowIGT = true,
    ShowRTA = false,
    ShowLrT = false,
}

local display = {
    services = {},
}
local overlayContext = nil

local function readSetting(alias)
    local value = settings.read(alias)
    if value ~= nil then
        return value
    end
    return DEFAULTS[alias]
end

local function activeTimer()
    return timer.singleRun.getActiveTimer()
end

local function snapshot()
    return timer.singleRun.getSnapshot()
end

local function currentRun()
    return game.getCurrentRun()
end

function display.services.isRawTimerRowsEnabled()
    return module.isEnabled() == true
        and readSetting("ShowRawTimers") == true
        and timer.recording.status().kind == "active"
end

function display.services.isRecordingTableVisible()
    return module.isEnabled() == true and readSetting("ShowRecordingTable") == true
end

function display.services.isBatchVisible()
    return display.services.isRecordingTableVisible()
        and timer.recording.isMultiRunMode() == true
end

function display.services.isModeVisible(mode)
    local alias = MODE_ALIASES[mode]
    if not alias then
        return true
    end
    return readSetting(alias) == true
end

function display.services.isTimerDisplayVisible()
    local hasSingleRunDisplay = timer.singleRun.hasCurrentRunDisplay() == true
    local hasBatchDisplay = timer.batch.isVisible() == true
    return display.services.isRawTimerRowsEnabled() == true
        and (hasSingleRunDisplay or hasBatchDisplay)
end

function display.services.getDisplayTime(mode)
    local batchTime = timer.batch.displayTime(mode, activeTimer())
    if batchTime ~= nil then
        return batchTime
    end
    local timerSnapshot = snapshot()
    return timerSnapshot.formatted[mode]
end

function display.project(ctx, opts)
    ctx = ctx or overlayContext
    if not ctx then
        return
    end

    overlayContext = ctx
    opts = opts or {}
    timer.singleRun.overlay.project(ctx)
    timer.batch.overlay.project(ctx)
    timer.splits.overlay.project(ctx, activeTimer(), currentRun(), snapshot(), opts.liveOnly == true)
    ctx.refreshRegion(timer.overlay.region)
end

function display.refreshStructure()
    display.project(nil, {
        liveOnly = false,
    })
end

function display.refreshText()
    display.project(nil, {
        liveOnly = true,
    })
end

display.services.refreshStructure = display.refreshStructure
display.services.refreshText = display.refreshText

function display.registerOverlays(overlays)
    local timerOverlayOrder = overlays.order.module + 10
    local batchOverlayOrder = timerOverlayOrder + 10
    local splitOverlayOrder = batchOverlayOrder + 20

    timer.singleRun.overlay.register(overlays, timerOverlayOrder)
    timer.batch.overlay.register(overlays, batchOverlayOrder)
    timer.splits.overlay.register(overlays, splitOverlayOrder)

    overlays.onCommit(function(ctx)
        display.project(ctx)
        if timer.runLoop.hasActiveDisplayLoop() then
            timer.runLoop.updateTick()
        end
    end)

    overlays.onInterval("timer", TIMER_REFRESH_INTERVAL, function(ctx)
        overlayContext = ctx
        timer.runLoop.updateTick()
    end, {
        when = timer.runLoop.hasActiveDisplayLoop,
    })
end

return display
