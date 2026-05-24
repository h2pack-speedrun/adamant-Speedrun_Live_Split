local singleRun = ...

local hooksAdapter = {}

local function emit(callbacks, name, ...)
    local callback = callbacks and callbacks[name] or nil
    if callback == nil then
        return nil
    end
    return callback(...)
end

local function isEnabled(callbacks)
    local callback = callbacks and callbacks.isEnabled or nil
    if callback == nil then
        return true
    end
    return callback() == true
end

local function getCurrentRun(callbacks)
    local callback = callbacks and callbacks.getCurrentRun or nil
    if callback == nil then
        return nil
    end
    return callback()
end

local function emitDisplayStarted(callbacks)
    emit(callbacks, "onDisplayLoopStarted", singleRun.getActiveTimer(), singleRun.getSnapshot())
    emit(callbacks, "onDisplayChanged", singleRun.getSnapshot())
end

function hooksAdapter.installHooks(hooks, callbacks)
    hooks.wrap("StartNewRun", function(baseFunc, prevRun, args)
        if not isEnabled(callbacks) then
            return baseFunc(prevRun, args)
        end

        local timer = singleRun.beginRun()
        local run = baseFunc(prevRun, args)
        emit(callbacks, "onRunStarted", run, timer, singleRun.getSnapshot())
        emit(callbacks, "onDisplayChanged", singleRun.getSnapshot())
        return run
    end)

    hooks.wrap("RoomEntranceMaterialize", function(baseFunc, ...)
        if not isEnabled(callbacks) then
            return baseFunc(...)
        end

        local value = baseFunc(...)
        if singleRun.startDisplayLoop() then
            emitDisplayStarted(callbacks)
        end
        return value
    end)

    hooks.wrap("RoomEntranceDreamBiomeStart", function(baseFunc, ...)
        if not isEnabled(callbacks) then
            return baseFunc(...)
        end

        local value = baseFunc(...)
        if singleRun.startDisplayLoop() then
            emitDisplayStarted(callbacks)
        end
        return value
    end)

    hooks.wrap("RecordRunStats", function(baseFunc, ...)
        if not isEnabled(callbacks) then
            return baseFunc(...)
        end

        local value = baseFunc(...)
        local finalized, timer = singleRun.finalizeRun()
        if finalized then
            emit(callbacks, "onRunFinalized", getCurrentRun(callbacks), timer, singleRun.getSnapshot())
            emit(callbacks, "onDisplayChanged", singleRun.getSnapshot())
        end
        return value
    end)

    hooks.wrap("AddTimerBlock", function(baseFunc, currRun, timerBlockName)
        local value = baseFunc(currRun, timerBlockName)
        if isEnabled(callbacks) and timerBlockName == "MapLoad" and singleRun.processLoadEvent(true) then
            emit(callbacks, "onLoadEvent", true, singleRun.getActiveTimer(), singleRun.getSnapshot())
        end
        return value
    end)

    hooks.wrap("RemoveTimerBlock", function(baseFunc, currRun, timerBlockName)
        local value = baseFunc(currRun, timerBlockName)
        if isEnabled(callbacks) and timerBlockName == "MapLoad" and singleRun.processLoadEvent(false) then
            emit(callbacks, "onLoadEvent", false, singleRun.getActiveTimer(), singleRun.getSnapshot())
        end
        return value
    end)
end

return hooksAdapter
