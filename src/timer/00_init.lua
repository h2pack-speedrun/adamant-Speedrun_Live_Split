local deps = ... or {}
local host = deps.host
local store = deps.store

local timer = {}

local function defaultCurrentRun()
    return rom and rom.game and rom.game.CurrentRun or CurrentRun
end

local function defaultRunSuccess(run)
    if type(WasRunSuccess) == "function" and run and run.RunResult ~= nil then
        return WasRunSuccess(run) == true
    end
    return run and run.Cleared == true
end

local game = deps.game or {}
if game.getCurrentRun == nil then
    game.getCurrentRun = defaultCurrentRun
end
if game.isRunSuccess == nil then
    game.isRunSuccess = defaultRunSuccess
end

local settings = deps.settings or {}
if settings.read == nil then
    settings.read = function(alias)
        return store.read(alias)
    end
end

local module = deps.module or {}
if module.isEnabled == nil then
    module.isEnabled = function()
        return host.isEnabled() == true
    end
end

local recordingDeps = deps.recording or {}
if recordingDeps.persistentCache == nil then
    recordingDeps.persistentCache = host.cache.persistent
end

timer.core = deps.core or import('timer/core/00_init.lua', nil, {
    getTime = game.getTime,
    getCurrentRun = game.getCurrentRun,
})
timer.overlay = deps.overlay or import('timer/overlay/00_init.lua')
timer.display = import('timer/display/00_init.lua', nil, {
    timer = timer,
    game = game,
    settings = settings,
    module = module,
})

local display = deps.display or timer.display.services
timer.singleRun = import('timer/single_run/00_init.lua', nil, {
    core = timer.core,
    isMultiRunMode = function()
        return timer.recording.isMultiRunMode()
    end,
    overlay = timer.overlay,
    isModeVisible = display.isModeVisible,
    isTimerDisplayVisible = display.isTimerDisplayVisible,
    getDisplayTime = display.getDisplayTime,
})
timer.splits = import('timer/splits/00_init.lua', nil, {
    formatTimestamp = timer.core.formatTimestamp,
    isRunSuccess = game.isRunSuccess,
    overlay = timer.overlay,
    isVisible = display.isRecordingTableVisible,
    isModeVisible = display.isModeVisible,
})
timer.batch = import('timer/batch/00_init.lua', nil, {
    core = timer.core,
    formatTimestamp = timer.core.formatTimestamp,
    isRunSuccess = game.isRunSuccess,
    overlay = timer.overlay,
    isVisible = display.isBatchVisible,
    isModeVisible = display.isModeVisible,
})
timer.recording = import('timer/recording/00_init.lua', nil, {
    splits = timer.splits,
    batch = timer.batch,
    readSetting = settings.read,
    refreshDisplay = display.refreshStructure,
    persistentCache = recordingDeps.persistentCache,
})
timer.runLoop = import('timer/run_loop/00_init.lua', nil, {
    singleRun = timer.singleRun,
    recording = timer.recording,
    splits = timer.splits,
    batch = timer.batch,
    isEnabled = module.isEnabled,
    getCurrentRun = game.getCurrentRun,
    refreshStructure = display.refreshStructure,
    refreshText = display.refreshText,
})
timer.integrations = import('timer/integrations/00_init.lua', nil, {
    timer = timer,
})

function timer.initialize()
    timer.recording.initialize()
end

function timer.registerHooks()
    timer.runLoop.installHooks(host.hooks)
end

function timer.registerOverlays()
    timer.display.registerOverlays(host.overlays)
end

function timer.registerIntegrations()
    timer.integrations.register(host.integrations)
end

function timer.onSettingsCommitted(_, _, commit)
    if not module.isEnabled() then
        timer.runLoop.cleanup()
        return
    end

    local recordingRef = commit.actions.get("recording")
    local recordingAction = recordingRef:has() and recordingRef:read() or nil
    if recordingAction then
        timer.recording.applyAction(recordingAction)
    end
    timer.recording.syncMode()
    timer.display.refreshStructure()
    timer.runLoop.ensureDisplayLoop()
end

function timer.getRealTime()
    return timer.singleRun.getSnapshot().formatted.rta
end

function timer.getLoadRemovedTime()
    return timer.singleRun.getSnapshot().formatted.lrt
end

function timer.getInGameTime()
    return timer.singleRun.getSnapshot().formatted.igt
end

function timer.getRecordingStatus()
    return timer.recording.status()
end

return timer
