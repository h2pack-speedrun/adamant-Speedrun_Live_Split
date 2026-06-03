local OVERLAY_REGION = "middleRightStack"
local LABEL_FONT = "P22UndergroundSCMedium"
local VALUE_FONT = "NumericP22UndergroundSCMedium"

local timerOverlay = {}
timerOverlay.region = OVERLAY_REGION

local function buildModeColumn(mode, modeVisible)
    return {
        key = mode,
        minWidth = 78,
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
            minWidth = 78,
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
