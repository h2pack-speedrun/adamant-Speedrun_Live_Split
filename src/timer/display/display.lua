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
    ShowLiveTimers = true,
    ShowSplitTable = true,
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
    return timer.singleRun and timer.singleRun.getActiveTimer() or nil
end

local function snapshot()
    return timer.singleRun and timer.singleRun.getSnapshot() or nil
end

local function currentRun()
    return game.getCurrentRun()
end

function display.services.isLiveRowsEnabled()
    return module.isEnabled() == true and readSetting("ShowLiveTimers") == true
end

function display.services.isSplitTableVisible()
    return module.isEnabled() == true and readSetting("ShowSplitTable") == true
end

function display.services.isBatchVisible()
    return display.services.isSplitTableVisible()
        and timer.recording
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
    local hasSingleRunDisplay = timer.singleRun and timer.singleRun.hasCurrentRunDisplay() == true
    local hasBatchDisplay = timer.batch and timer.batch.isVisible() == true
    return display.services.isLiveRowsEnabled() == true
        and (hasSingleRunDisplay or hasBatchDisplay)
end

function display.services.getDisplayTime(mode)
    local batchTime = timer.batch and timer.batch.displayTime(mode, activeTimer()) or nil
    if batchTime ~= nil then
        return batchTime
    end
    local timerSnapshot = snapshot()
    return timerSnapshot and timerSnapshot.formatted[mode] or "00:00.00"
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
            display.refreshText()
        end
    end)

    overlays.onInterval("timer", TIMER_REFRESH_INTERVAL, function(ctx)
        overlayContext = ctx
        timer.runLoop.updateTick()
        display.refreshText()
    end, {
        when = timer.runLoop.hasActiveDisplayLoop,
    })
end

return display
