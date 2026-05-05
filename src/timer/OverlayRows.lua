SpeedrunTimerInternal = SpeedrunTimerInternal or {}
local internal = SpeedrunTimerInternal

local OVERLAY_REGION = "middleRightStack"
local LABEL_FONT = "P22UndergroundSCMedium"
local VALUE_FONT = "NumericP22UndergroundSCMedium"

internal.TimerOverlay = internal.TimerOverlay or {}
local timerOverlay = internal.TimerOverlay

timerOverlay.region = OVERLAY_REGION

local function buildTimeColumn(row, mode, modeVisible)
    return {
        key = mode,
        minWidth = 78,
        justify = "Left",
        text = function()
            return row[mode]
        end,
        visible = function()
            return modeVisible(mode) == true
        end,
        textArgs = {
            Font = VALUE_FONT,
        },
    }
end

function timerOverlay.buildTimerTableColumns(row, modeVisible)
    return {
        {
            key = "label",
            minWidth = 96,
            justify = "Left",
            text = function()
                return row.label
            end,
            textArgs = {
                Font = LABEL_FONT,
            },
        },
        buildTimeColumn(row, "igt", modeVisible),
        buildTimeColumn(row, "rta", modeVisible),
        buildTimeColumn(row, "lrt", modeVisible),
    }
end

function timerOverlay.registerTableRow(cache, key, opts)
    if cache[key] then
        return cache[key]
    end

    local modeVisible = opts.modeVisible or function()
        return true
    end
    local visible = opts.visible or function()
        return true
    end

    local handle = lib.overlays.registerStackedRow({
        id = opts.idPrefix .. key,
        componentName = opts.componentPrefix .. key,
        owner = internal.PLUGIN_GUID,
        region = opts.region or OVERLAY_REGION,
        order = opts.order,
        columnGap = opts.columnGap or 10,
        columns = timerOverlay.buildTimerTableColumns(opts.row, modeVisible),
        visible = function()
            return visible(opts.row) == true
        end,
    })
    cache[key] = handle
    return handle
end

return timerOverlay
