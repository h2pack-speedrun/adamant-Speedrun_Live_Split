local OVERLAY_REGION = "middleRightStack"
local LABEL_FONT = "P22UndergroundSCMedium"
local VALUE_FONT = "NumericP22UndergroundSCMedium"
local TIMER_TABLE_LABEL_WIDTH = 112
local TIMER_TABLE_VALUE_WIDTH = 78

local timerOverlay = {}
timerOverlay.region = OVERLAY_REGION
timerOverlay.timerTableColumnGap = 28

local function buildModeColumn(mode, modeVisible)
    return {
        key = mode,
        minWidth = TIMER_TABLE_VALUE_WIDTH,
        justify = "Left",
        visible = function(_, runtime)
            return modeVisible(mode, runtime) == true
        end,
        textArgs = {
            Font = VALUE_FONT,
        },
    }
end

function timerOverlay.buildSummaryColumns()
    return {
        {
            key = "label",
            minWidth = 40,
            justify = "Left",
            textArgs = {
                Font = LABEL_FONT,
            },
        },
        {
            key = "time",
            minWidth = 80,
            justify = "Left",
            textArgs = {
                Font = VALUE_FONT,
            },
        },
    }
end

function timerOverlay.buildTimerTableColumns(modeVisible)
    return {
        {
            key = "label",
            minWidth = TIMER_TABLE_LABEL_WIDTH,
            justify = "Left",
            textArgs = {
                Font = LABEL_FONT,
            },
        },
        buildModeColumn("igt", modeVisible),
        buildModeColumn("rta", modeVisible),
        buildModeColumn("lrt", modeVisible),
    }
end

return timerOverlay
