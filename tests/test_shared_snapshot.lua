local support = dofile("tests/support.lua")
local assertEqual = support.assertEqual

local currentSummary = {
    rtaCs = 12,
    lrtCs = 10,
    igtCs = 8,
}
local currentStatus = {
    kind = "idle",
}
local registeredEvents = {}

local sharedSnapshot = assert(loadfile("src/shared_snapshot.lua"))({
    timer = {
        currentRun = {
            summary = function()
                return currentSummary
            end,
        },
        recording = {
            status = function()
                return currentStatus
            end,
        },
        events = {
            names = {
                currentRunSummaryChanged = "currentRunSummaryChanged",
                recordingStatusChanged = "recordingStatusChanged",
            },
            on = function(eventName, callback)
                registeredEvents[eventName] = callback
            end,
        },
    },
})

local ownerCalls = {}
local sharedWrites = {}
local shared = {
    data = {
        owner = function(name, opts)
            ownerCalls[#ownerCalls + 1] = {
                name = name,
                opts = opts,
            }
        end,
    },
    set = function(name, value)
        sharedWrites[#sharedWrites + 1] = {
            name = name,
            value = value,
        }
        return true
    end,
}

local function assertSnapshot(snapshot, expectedRta, expectedLrt, expectedIgt, expectedStatus)
    assertEqual(snapshot.realTimeCs, expectedRta)
    assertEqual(snapshot.loadRemovedTimeCs, expectedLrt)
    assertEqual(snapshot.inGameTimeCs, expectedIgt)
    assertEqual(snapshot.recordingStatus, expectedStatus)
end

sharedSnapshot.register(shared)

assertEqual(#ownerCalls, 1)
assertEqual(ownerCalls[1].name, "TimerSnapshot")
assertEqual(ownerCalls[1].opts.id, "speedrun.timer")
assertSnapshot(ownerCalls[1].opts.default, 12, 10, 8, currentStatus)

currentSummary = {
    rtaCs = 30,
    lrtCs = 24,
    igtCs = 18,
}
currentStatus = {
    kind = "recording",
}

assert(sharedSnapshot.publish(shared))
assertEqual(#sharedWrites, 1)
assertEqual(sharedWrites[1].name, "TimerSnapshot")
assertSnapshot(sharedWrites[1].value, 30, 24, 18, currentStatus)

sharedSnapshot.attach({
    events = {
        names = {
            currentRunSummaryChanged = "currentRunSummaryChanged",
            recordingStatusChanged = "recordingStatusChanged",
        },
        on = function(eventName, callback)
            registeredEvents[eventName] = callback
        end,
    },
})

assert(registeredEvents.currentRunSummaryChanged)
assert(registeredEvents.recordingStatusChanged)

currentSummary = {
    rtaCs = 44,
    lrtCs = 33,
    igtCs = 22,
}
currentStatus = {
    kind = "stopped",
}

registeredEvents.currentRunSummaryChanged(nil, {
    shared = shared,
})

assertEqual(#sharedWrites, 2)
assertEqual(sharedWrites[2].name, "TimerSnapshot")
assertSnapshot(sharedWrites[2].value, 44, 33, 22, currentStatus)
