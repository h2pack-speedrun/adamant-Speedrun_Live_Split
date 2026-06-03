local deps = ... or {}
local timer = deps.timer
local controller = {}

function controller.startRecording(host, runtime)
    if host.isEnabled() then
        timer.recording.start(runtime)
    end
end

function controller.stopRecording(host, runtime)
    if host.isEnabled() then
        timer.recording.stop(runtime)
    end
end

function controller.clearRecording(host, runtime)
    if host.isEnabled() then
        timer.recording.clear(runtime)
    end
end

controller.overlayEvents = {
    onCommit = function(host, runtime, ctx, overlayDisplay)
        local liveOnly = false
        if host.isEnabled() and timer.hasActiveDisplayLoop() then
            liveOnly = timer.updateTick(runtime) == true
        end
        overlayDisplay.project(ctx, {
            runtime = runtime,
            liveOnly = liveOnly,
        })
    end,
    onInterval = function(host, runtime, ctx, overlayDisplay)
        if not host.isEnabled() then
            timer.cleanup(runtime)
            overlayDisplay.project(ctx, {
                runtime = runtime,
                liveOnly = false,
            })
            return false
        end
        local liveOnly = timer.updateTick(runtime) == true
        overlayDisplay.project(ctx, {
            runtime = runtime,
            liveOnly = liveOnly,
        })
    end,
    whenActive = function(host)
        return host.isEnabled() and timer.hasActiveDisplayLoop()
    end,
}

function controller.onCommit(host, runtime)
    if not host.isEnabled() then
        timer.cleanup(runtime)
        return
    end

    timer.recording.syncSettings(runtime)
    timer.ensureDisplayLoop()
end

function controller.onActivate(_, runtime)
    timer.initialize(runtime)
end

return controller
