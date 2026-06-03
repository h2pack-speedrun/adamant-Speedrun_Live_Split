local deps = ... or {}
local timer = deps.timer

local sharedSnapshot = {}

local SHARED_TIMER_SNAPSHOT = "speedrun.timer"
local SHARED_DECLARATION = "TimerSnapshot"

local function buildSnapshot()
    local snapshot = timer.currentRun.summary()
    return {
        realTimeCs = snapshot.rtaCs,
        loadRemovedTimeCs = snapshot.lrtCs,
        inGameTimeCs = snapshot.igtCs,
        recordingStatus = timer.recording.status(),
    }
end

function sharedSnapshot.register(shared)
    shared.data.owner(SHARED_DECLARATION, {
        id = SHARED_TIMER_SNAPSHOT,
        default = buildSnapshot(),
    })
end

function sharedSnapshot.publish(shared)
    return shared.set(SHARED_DECLARATION, buildSnapshot())
end

function sharedSnapshot.attach(timerSource)
    local events = timerSource.events.names
    local publishEvents = {
        events.currentRunSummaryChanged,
        events.recordingStatusChanged,
    }
    local function publish(_, runtime)
        if runtime then
            sharedSnapshot.publish(runtime.shared)
        end
    end

    for _, eventName in ipairs(publishEvents) do
        timerSource.events.on(eventName, publish)
    end
end

return sharedSnapshot
