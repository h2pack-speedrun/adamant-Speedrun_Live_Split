local deps = ... or {}
local splits = deps.splits
local overlay = deps.overlay
local isVisible = deps.isVisible
local isModeVisible = deps.isModeVisible

local splitOverlay = {}
local projectionRows = {}
local projectionHeaderRow = { key = "header", label = "", igt = "", rta = "", lrt = "" }
local projectionBiomeRows = {
    { key = "biome1", label = "", igt = "", rta = "", lrt = "" },
    { key = "biome2", label = "", igt = "", rta = "", lrt = "" },
    { key = "biome3", label = "", igt = "", rta = "", lrt = "" },
    { key = "biome4", label = "", igt = "", rta = "", lrt = "" },
}
local projectionTotalRow = { key = "total", label = "", igt = "", rta = "", lrt = "" }
local projectionCount = 0

local function splitVisible()
    return isVisible() == true and splits.isVisible() == true
end

local function appendProjectionRow(source, projection)
    if source.label == nil or source.label == "" then
        return
    end

    projection.label = source.label
    projection.igt = source.igt
    projection.rta = source.rta
    projection.lrt = source.lrt

    projectionCount = projectionCount + 1
    projectionRows[projectionCount] = projection
end

local function trimProjectionRows(previousCount)
    for index = projectionCount + 1, previousCount do
        projectionRows[index] = nil
    end
end

function splitOverlay.register(overlays, order)
    overlays.createTable("splits", {
        componentName = "SpeedrunTimer_Split",
        region = overlay.region,
        order = order,
        maxRows = 6,
        columnGap = 20,
        columns = overlay.buildTimerTableColumns(isModeVisible),
        visible = splitVisible,
    })
end

function splitOverlay.buildRows(timer, run, snapshot, liveOnly)
    local previousCount = projectionCount
    projectionCount = 0
    if not splitVisible() then
        trimProjectionRows(previousCount)
        return projectionRows
    end

    if liveOnly then
        splits.updateLiveRows(timer, run, snapshot)
    else
        splits.updateRows(timer, run, snapshot)
    end

    local rows = splits.rows()
    appendProjectionRow(rows.header, projectionHeaderRow)
    for index = 1, 4 do
        appendProjectionRow(rows.biomes[index], projectionBiomeRows[index])
    end
    appendProjectionRow(rows.total, projectionTotalRow)
    trimProjectionRows(previousCount)
    return projectionRows
end

function splitOverlay.project(ctx, timer, run, snapshot, liveOnly)
    ctx.setTable("splits", splitOverlay.buildRows(timer, run, snapshot, liveOnly))
end

return splitOverlay
