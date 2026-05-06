local internal = SpeedrunTimerInternal

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

local function drawSection(ui, title, helpText)
    if ui.Spacing then
        ui.Spacing()
    end
    lib.widgets.text(ui, title)
    lib.widgets.separator(ui)
    if helpText then
        lib.widgets.text(ui, helpText, {
            color = MUTED_TEXT_COLOR,
        })
    end
end

local function enforceVisibleTimerMode(session)
    if session.read("ShowIGT") or session.read("ShowRTA") or session.read("ShowLrT") then
        return
    end
    session.write("ShowIGT", true)
end

local function readBool(session, alias, fallback)
    local value = session.read(alias)
    if value == nil then
        return fallback == true
    end
    return value == true
end

local function readRecordingMode(session)
    local mode = session.read("RecordingMode")
    if mode == "single" or mode == "multi" then
        return mode
    end
    session.write("RecordingMode", "single")
    return "single"
end

local function drawRecordingControls(ui, session, recordingMode)
    local status = internal.GetRecordingStatus and internal.GetRecordingStatus() or nil
    local statusText = status and status.text or "Not recording"
    local statusKind = status and status.kind or "idle"
    lib.widgets.text(ui, "Status: " .. statusText, {
        color = STATUS_TEXT_COLORS[statusKind] or MUTED_TEXT_COLOR,
    })

    if recordingMode == "multi" then
        lib.widgets.stepper(ui, session, "BatchTargetRuns", {
            label = "Runs to record",
            min = 1,
            max = 10,
            default = 3,
        })
    end

    local targetRuns = session.read("BatchTargetRuns") or 3
    lib.widgets.button(ui, "Start Recording", {
        id = "recording_start",
        onClick = function()
            if internal.StartRecording then
                internal.StartRecording(targetRuns)
            end
        end,
    })
    ui.SameLine()
    lib.widgets.button(ui, "Clear Results", {
        id = "recording_clear",
        onClick = function()
            if internal.ClearRecording then
                internal.ClearRecording(targetRuns)
            end
        end,
    })
    ui.SameLine()
    lib.widgets.button(ui, "Stop Recording", {
        id = "recording_stop",
        onClick = function()
            if internal.StopRecording then
                internal.StopRecording()
            end
        end,
    })
    lib.widgets.text(ui, "Recording stays ready until stopped or the module is disabled.", {
        color = MUTED_TEXT_COLOR,
    })
end

function internal.DrawTab(ui, session)
    drawSection(ui, "Timer Columns", "Choose which timer values are shown in timer rows and split tables.")
    lib.widgets.text(ui, "At least one timer column is always shown.", {
        color = MUTED_TEXT_COLOR,
    })

    for _, option in ipairs(TIMER_MODE_OPTIONS) do
        lib.widgets.checkbox(ui, session, option.alias, {
            label = option.label,
            tooltip = option.tooltip,
        })
    end
    enforceVisibleTimerMode(session)

    drawSection(ui, "Overlay Sections")
    lib.widgets.checkbox(ui, session, "ShowLiveTimers", {
        label = "Show live timer rows",
        tooltip = "Show the compact IGT/RTA/LrT rows above the split table.",
    })
    lib.widgets.checkbox(ui, session, "ShowSplitTable", {
        label = "Show split table",
        tooltip = "Show biome split rows for single-run or multi-run tracking.",
    })

    local showLiveTimers = readBool(session, "ShowLiveTimers", true)
    local showSplitTable = readBool(session, "ShowSplitTable", true)
    if not showLiveTimers and not showSplitTable then
        lib.widgets.text(ui, "No overlay sections selected.", {
            color = WARNING_TEXT_COLOR,
        })
    end

    if showSplitTable then
        drawSection(ui, "Recording Mode")
        lib.widgets.radio(ui, session, "RecordingMode", {
            values = RECORDING_MODE_VALUES,
            default = "single",
            displayValues = RECORDING_MODE_LABELS,
            optionsPerLine = 2,
        })

        local recordingMode = readRecordingMode(session)
        drawSection(ui, "Recording")
        drawRecordingControls(ui, session, recordingMode)
        local status = internal.GetRecordingStatus and internal.GetRecordingStatus() or nil
        if not status or status.kind == "idle" then
            lib.widgets.text(ui,
                "Split table is enabled, but recording is not started. Press Start Recording to begin tracking runs.",
                { color = WARNING_TEXT_COLOR })
        end
    end
end

function internal.DrawQuickContent(ui, session)
    lib.widgets.checkbox(ui, session, "ShowLiveTimers", {
        label = "Show live timer rows",
        tooltip = "Show the compact IGT/RTA/LrT rows above the split table.",
    })
    lib.widgets.checkbox(ui, session, "ShowSplitTable", {
        label = "Show split table",
        tooltip = "Show biome split rows for single-run or multi-run tracking.",
    })

end

return internal
