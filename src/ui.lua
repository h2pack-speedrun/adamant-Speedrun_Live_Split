local module = {}
local timer = nil

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
local SHOW_RAW_TIMERS_OPTS = {
    label = "Show raw timer rows",
    tooltip = "Show compact IGT/RTA/LrT rows while recording is active.",
}
local SHOW_RECORDING_TABLE_OPTS = {
    label = "Show recording table",
    tooltip = "Show split or batch rows while recording.",
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
local RESTART_RECORDING_OPTS = {
    id = "recording_restart",
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

local function drawRecordingActions(draw, actions, statusKind)
    local imgui = draw.imgui
    local recordingAction = actions.get("recording")

    if statusKind == "ready" or statusKind == "active" then
        draw.widgets.button("Stop", withAction(STOP_RECORDING_OPTS, recordingAction))
        imgui.SameLine()
        draw.widgets.button("Clear", withAction(CLEAR_RECORDING_OPTS, recordingAction))
        return
    end

    if statusKind == "recorded" or statusKind == "failed" then
        draw.widgets.button("Start New", withAction(RESTART_RECORDING_OPTS, recordingAction))
        imgui.SameLine()
        draw.widgets.button("Clear", withAction(CLEAR_RECORDING_OPTS, recordingAction))
        return
    end

    draw.widgets.button("Start", withAction(START_RECORDING_OPTS, recordingAction))
end

local function getRecordingStatus()
    local status = timer.getRecordingStatus()
    local statusText = status and status.text or "Not recording"
    local statusKind = status and status.kind or "idle"
    return statusKind, statusText
end

local function drawRecordingControls(draw, state, actions, recordingMode, statusKind)
    if recordingMode == "multi" then
        draw.widgets.stepper(state.get("BatchTargetRuns"), BATCH_TARGET_RUNS_OPTS)
    end

    drawRecordingActions(draw, actions, statusKind)
end

local function drawRecordingSection(draw, state, actions, showRecordingTable, showRawTimers)
    drawSection(draw, "Recording")
    local statusKind, statusText = getRecordingStatus()
    draw.widgets.text("Status: " .. statusText, {
        color = STATUS_TEXT_COLORS[statusKind] or MUTED_TEXT_COLOR,
    })
    draw.widgets.radio(state.get("RecordingMode"), RECORDING_MODE_OPTS)

    local recordingMode = readRecordingMode(state)
    drawRecordingControls(draw, state, actions, recordingMode, statusKind)

    if statusKind == "active" and not showRecordingTable and not showRawTimers then
        draw.widgets.text(
            "Recording is active, but no timer output is visible.",
            WARNING_TEXT_OPTS)
    elseif statusKind ~= "idle" and not showRecordingTable then
        draw.widgets.text(
            "Recording table is hidden, so recorded rows will not be visible.",
            WARNING_TEXT_OPTS)
    end
end

local function drawDisplaySection(draw, state, includeColumns)
    drawSection(draw, "Display During Recording")
    draw.widgets.checkbox(state.get("ShowRecordingTable"), SHOW_RECORDING_TABLE_OPTS)
    draw.widgets.checkbox(state.get("ShowRawTimers"), SHOW_RAW_TIMERS_OPTS)

    if includeColumns then
        draw.widgets.text("Timer columns", MUTED_TEXT_OPTS)
        for _, option in ipairs(TIMER_MODE_OPTIONS) do
            draw.widgets.checkbox(state.get(option.alias), TIMER_MODE_OPTS[option.alias])
        end
        enforceVisibleTimerMode(state)
    end
end

function module.drawTab(draw, state, actions)
    local showRecordingTable = readBool(state, "ShowRecordingTable", true)
    local showRawTimers = readBool(state, "ShowRawTimers", false)
    drawRecordingSection(draw, state, actions, showRecordingTable, showRawTimers)
    drawDisplaySection(draw, state, true)
end

function module.drawQuickContent(draw, state, actions)
    local showRecordingTable = readBool(state, "ShowRecordingTable", true)
    local showRawTimers = readBool(state, "ShowRawTimers", false)
    drawRecordingSection(draw, state, actions, showRecordingTable, showRawTimers)
    drawDisplaySection(draw, state, false)
end

function module.bind(timerApi)
    timer = timerApi
    return module
end

return module
