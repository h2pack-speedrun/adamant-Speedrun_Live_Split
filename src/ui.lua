local module = {}
local logic = nil

local TIMER_MODE_OPTIONS = {
    {
        alias = "ShowIGT",
        label = "In-Game Time",
        tooltip = "Show gameplay time from CurrentRun.GameplayTime.",
    },
    {
        alias = "ShowRTA",
        label = "Real Time",
        tooltip = "Show wall-clock time.",
    },
    {
        alias = "ShowLrT",
        label = "Load-Removed Time",
        tooltip = "Show real time with map-load time removed.",
    },
}
local RECORDING_MODE_VALUES = { "single", "multi" }
local RECORDING_MODE_LABELS = {
    single = "Single run",
    multi = "Multi-run batch",
}
local MUTED_TEXT_COLOR = { 0.65, 0.65, 0.65, 1.0 }
local WARNING_TEXT_COLOR = { 1.0, 0.78, 0.35, 1.0 }
local STATUS_TEXT_COLORS = {
    active = { 0.45, 0.85, 1.0, 1.0 },
    ready = { 0.55, 0.95, 0.55, 1.0 },
    failed = WARNING_TEXT_COLOR,
    recorded = { 0.80, 0.82, 0.88, 1.0 },
    idle = MUTED_TEXT_COLOR,
}
local MUTED_TEXT_OPTS = { color = MUTED_TEXT_COLOR }
local WARNING_TEXT_OPTS = { color = WARNING_TEXT_COLOR }
local TIMER_MODE_OPTS = {}
local SHOW_LIVE_TIMERS_OPTS = {
    label = "Show live timer rows",
    tooltip = "Show the compact IGT/RTA/LrT rows above the split table.",
}
local SHOW_SPLIT_TABLE_OPTS = {
    label = "Show split table",
    tooltip = "Show biome split rows for single-run or multi-run tracking.",
}
local RECORDING_MODE_OPTS = {
    values = RECORDING_MODE_VALUES,
    default = "single",
    displayValues = RECORDING_MODE_LABELS,
    optionsPerLine = 2,
}
local BATCH_TARGET_RUNS_OPTS = {
    label = "Runs to record",
    min = 1,
    max = 10,
    default = 3,
}
local START_RECORDING_OPTS = {
    id = "recording_start",
    value = { kind = "start" },
}
local CLEAR_RECORDING_OPTS = {
    id = "recording_clear",
    value = { kind = "clear" },
}
local STOP_RECORDING_OPTS = {
    id = "recording_stop",
    value = { kind = "stop" },
}

for _, option in ipairs(TIMER_MODE_OPTIONS) do
    TIMER_MODE_OPTS[option.alias] = {
        label = option.label,
        tooltip = option.tooltip,
    }
end

local function drawSection(draw, title, helpText)
    local imgui = draw.imgui
    if imgui.Spacing then
        imgui.Spacing()
    end
    draw.widgets.text(title)
    draw.widgets.separator()
    if helpText then
        draw.widgets.text(helpText, MUTED_TEXT_OPTS)
    end
end

local function enforceVisibleTimerMode(state)
    if state.read("ShowIGT") or state.read("ShowRTA") or state.read("ShowLrT") then
        return
    end
    state.write("ShowIGT", true)
end

local function readBool(state, alias, fallback)
    local value = state.read(alias)
    if value == nil then
        return fallback == true
    end
    return value == true
end

local function readRecordingMode(state)
    local mode = state.read("RecordingMode")
    if mode == "single" or mode == "multi" then
        return mode
    end
    state.write("RecordingMode", "single")
    return "single"
end

local function withAction(opts, action)
    opts.action = action
    return opts
end

local function drawRecordingControls(draw, state, actions, recordingMode)
    local imgui = draw.imgui
    local recordingAction = actions.get("recording")
    local status = logic.getRecordingStatus()
    local statusText = status and status.text or "Not recording"
    local statusKind = status and status.kind or "idle"
    draw.widgets.text("Status: " .. statusText, {
        color = STATUS_TEXT_COLORS[statusKind] or MUTED_TEXT_COLOR,
    })

    if recordingMode == "multi" then
        draw.widgets.stepper(state.get("BatchTargetRuns"), BATCH_TARGET_RUNS_OPTS)
    end

    draw.widgets.button("Start Recording", withAction(START_RECORDING_OPTS, recordingAction))
    imgui.SameLine()
    draw.widgets.button("Clear Results", withAction(CLEAR_RECORDING_OPTS, recordingAction))
    imgui.SameLine()
    draw.widgets.button("Stop Recording", withAction(STOP_RECORDING_OPTS, recordingAction))
    draw.widgets.text("Recording stays ready until stopped or the module is disabled.", MUTED_TEXT_OPTS)
end

function module.drawTab(draw, state, actions)
    drawSection(draw, "Timer Columns", "Choose which timer values are shown in timer rows and split tables.")
    draw.widgets.text("At least one timer column is always shown.", MUTED_TEXT_OPTS)

    for _, option in ipairs(TIMER_MODE_OPTIONS) do
        draw.widgets.checkbox(state.get(option.alias), TIMER_MODE_OPTS[option.alias])
    end
    enforceVisibleTimerMode(state)

    drawSection(draw, "Overlay Sections")
    draw.widgets.checkbox(state.get("ShowLiveTimers"), SHOW_LIVE_TIMERS_OPTS)
    draw.widgets.checkbox(state.get("ShowSplitTable"), SHOW_SPLIT_TABLE_OPTS)

    local showLiveTimers = readBool(state, "ShowLiveTimers", true)
    local showSplitTable = readBool(state, "ShowSplitTable", true)
    if not showLiveTimers and not showSplitTable then
        draw.widgets.text("No overlay sections selected.", WARNING_TEXT_OPTS)
    end

    if showSplitTable then
        drawSection(draw, "Recording Mode")
        draw.widgets.radio(state.get("RecordingMode"), RECORDING_MODE_OPTS)

        local recordingMode = readRecordingMode(state)
        drawSection(draw, "Recording")
        drawRecordingControls(draw, state, actions, recordingMode)
        local status = logic.getRecordingStatus()
        if not status or status.kind == "idle" then
            draw.widgets.text(
                "Split table is enabled, but recording is not started. Press Start Recording to begin tracking runs.",
                WARNING_TEXT_OPTS)
        end
    end
end

function module.drawQuickContent(draw, state)
    draw.widgets.checkbox(state.get("ShowLiveTimers"), SHOW_LIVE_TIMERS_OPTS)
    draw.widgets.checkbox(state.get("ShowSplitTable"), SHOW_SPLIT_TABLE_OPTS)

end

function module.bind(moduleLogic)
    logic = moduleLogic
    return module
end

return module
