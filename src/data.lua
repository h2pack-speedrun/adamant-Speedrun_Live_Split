local internal = SpeedrunTimerInternal

function internal.BuildStorage()
    return {
        {
            type = "bool",
            alias = "ShowIGT",
            default = true,
        },
        {
            type = "bool",
            alias = "ShowRTA",
        },
        {
            type = "bool",
            alias = "ShowLrT",
        },
        {
            type = "bool",
            alias = "ShowLiveTimers",
            default = true,
        },
        {
            type = "bool",
            alias = "ShowSplitTable",
            default = true,
        },
        {
            type = "string",
            alias = "RecordingMode",
            default = "single",
            maxLen = 16,
        },
        {
            type = "int",
            alias = "BatchTargetRuns",
            default = 3,
            min = 1,
            max = 15,
        },
        {
            type = "bool",
            alias = "RecordingReady",
            default = false,
            persist = true,
            stage = false,
            hash = false,
        },
    }
end

import("timer/RtaTimer.lua")
import("timer/LrtTimer.lua")
import("timer/IgtTimer.lua")

return internal
