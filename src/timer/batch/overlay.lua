local deps = ... or {}
local batch = deps.batch
local overlay = deps.overlay
local isVisible = deps.isVisible or function()
    return true
end
local isModeVisible = deps.isModeVisible or function()
    return true
end

local MAX_BATCH_RUNS = 10

local batchOverlay = {}
local projectionRows = {}
local projectionRunRows = {}
local projectionCurrentRow = { key = "current", label = "", igt = "", rta = "", lrt = "" }
local projectionCount = 0

for index = 1, MAX_BATCH_RUNS do
    projectionRunRows[index] = { key = "run" .. index, label = "", igt = "", rta = "", lrt = "" }
end

local function batchVisible()
    return isVisible() == true and batch.isVisible() == true
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

function batchOverlay.register(overlays, order)
    overlays.createTable("batch", {
        componentName = "SpeedrunTimer_Batch",
        region = overlay.region,
        order = order,
        maxRows = MAX_BATCH_RUNS + 1,
        columnGap = 20,
        columns = overlay.buildTimerTableColumns(isModeVisible),
        visible = batchVisible,
    })
end

function batchOverlay.buildRows()
    local previousCount = projectionCount
    projectionCount = 0
    if not batchVisible() then
        trimProjectionRows(previousCount)
        return projectionRows
    end

    local rows = batch.rows()
    for index = 1, MAX_BATCH_RUNS do
        appendProjectionRow(rows.runs[index], projectionRunRows[index])
    end
    appendProjectionRow(rows.current, projectionCurrentRow)
    trimProjectionRows(previousCount)
    return projectionRows
end

function batchOverlay.project(ctx)
    ctx.setTable("batch", batchOverlay.buildRows())
end

return batchOverlay
