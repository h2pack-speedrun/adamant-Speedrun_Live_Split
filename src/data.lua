local data = {}

function data.buildStorage()
    return {
        {
            type = "bool",
            alias = "ShowIGT",
            default = true,
            hash = false,
        },
        {
            type = "bool",
            alias = "ShowRTA",
            default = false,
            hash = false,
        },
        {
            type = "bool",
            alias = "ShowLrT",
            default = false,
            hash = false,
        },
        {
            type = "bool",
            alias = "ShowRawTimers",
            default = false,
            hash = false,
        },
        {
            type = "bool",
            alias = "ShowRecordingTable",
            default = true,
            hash = false,
        },
        {
            type = "string",
            alias = "RecordingMode",
            default = "single",
            maxLen = 16,
            hash = false,
        },
        {
            type = "int",
            alias = "BatchTargetRuns",
            default = 3,
            min = 1,
            max = 10,
            hash = false,
        },
        {
            type = "bool",
            alias = "RecordingReady",
            mode = "runtime",
            persist = true,
            hash = false,
            default = false,
        },
    }
end

return data
