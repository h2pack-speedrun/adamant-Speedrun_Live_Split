local internal = SpeedrunTimerInternal

function internal.BuildStorage()
    return {
        {
            type = "bool",
            alias = "ShowIGT",
            configKey = "ShowIGT",
        },
        {
            type = "bool",
            alias = "ShowRTA",
            configKey = "ShowRTA",
        },
        {
            type = "bool",
            alias = "ShowLrT",
            configKey = "ShowLrT",
        },
        {
            type = "bool",
            alias = "ShowLiveTimers",
            configKey = "ShowLiveTimers",
            default = true,
        },
        {
            type = "bool",
            alias = "ShowSplitTable",
            configKey = "ShowSplitTable",
            default = true,
        },
        {
            type = "string",
            alias = "RecordingMode",
            configKey = "RecordingMode",
            default = "single",
            maxLen = 16,
        },
        {
            type = "int",
            alias = "BatchTargetRuns",
            configKey = "BatchTargetRuns",
            default = 3,
            min = 1,
            max = 15,
        },
        {
            type = "bool",
            alias = "RecordingReady",
            configKey = "RecordingReady",
            default = false,
            runtime = true,
        },
    }
end

import("timer/RtaTimer.lua")
import("timer/LrtTimer.lua")
import("timer/IgtTimer.lua")

return internal
