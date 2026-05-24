local deps = ... or {}
local singleRun = deps.singleRun
local overlay = deps.overlay
local isModeVisible = deps.isModeVisible or function()
    return true
end
local isTimerDisplayVisible = deps.isTimerDisplayVisible or function()
    return singleRun.hasCurrentRunDisplay()
end
local getDisplayTime = deps.getDisplayTime

local liveOverlay = {}
local REGION = overlay.region
local LINES = {
    {
        name = "summary.igt",
        label = "IGT",
        mode = "igt",
        orderOffset = 0,
    },
    {
        name = "summary.rta",
        label = "RTA",
        mode = "rta",
        orderOffset = 1,
    },
    {
        name = "summary.lrt",
        label = "LrT",
        mode = "lrt",
        orderOffset = 2,
    },
}
local lineValues = {
    igt = { label = "IGT:", time = "00:00.00" },
    rta = { label = "RTA:", time = "00:00.00" },
    lrt = { label = "LrT:", time = "00:00.00" },
}

local function isLineVisible(mode)
    return isTimerDisplayVisible() == true
        and isModeVisible(mode) == true
end

local function updateLine(mode)
    local line = lineValues[mode]
    local snapshot = singleRun.getSnapshot()
    line.time = getDisplayTime and getDisplayTime(mode) or snapshot.formatted[mode]
    return line
end

function liveOverlay.register(overlays, order)
    for _, line in ipairs(LINES) do
        overlays.createLine(line.name, {
            componentName = "SpeedrunTimer_" .. line.label,
            region = REGION,
            order = order + line.orderOffset,
            columnGap = 20,
            columns = overlay.buildSummaryColumns(),
            visible = function()
                return isLineVisible(line.mode)
            end,
        })
    end
end

function liveOverlay.project(ctx)
    ctx.setLine("summary.igt", updateLine("igt"))
    ctx.setLine("summary.rta", updateLine("rta"))
    ctx.setLine("summary.lrt", updateLine("lrt"))
end

function liveOverlay.region()
    return REGION
end

return liveOverlay
