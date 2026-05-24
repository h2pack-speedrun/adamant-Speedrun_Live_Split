local timerApi = ...

local ROUTES = {
    underworld = { "F", "G", "H", "I" },
    surface = { "N", "O", "P", "Q" },
}

local BIOME_LABELS = {
    F = "Erebus",
    G = "Oceanus",
    H = "Fields",
    I = "Tartarus",
    N = "Ephyra",
    O = "Thessaly",
    P = "Olympus",
    Q = "Summit",
}

local splitState = {
    started = false,
    active = false,
    failed = false,
    completed = false,
    routeType = nil,
    route = nil,
    captured = {},
    currentIndex = nil,
    currentBiome = nil,
}

local overlayConfig = nil
local EMPTY_ROUTE = {}
local EMPTY_SNAPSHOT = {}
local splitRows = {
    header = {
        label = "Biome",
        igt = "IGT",
        rta = "RTA",
        lrt = "LrT",
    },
    biomes = {
        { label = "", igt = "", rta = "", lrt = "" },
        { label = "", igt = "", rta = "", lrt = "" },
        { label = "", igt = "", rta = "", lrt = "" },
        { label = "", igt = "", rta = "", lrt = "" },
    },
    total = {
        label = "Total",
        igt = "00:00.00",
        rta = "00:00.00",
        lrt = "00:00.00",
    },
}

local function clearRow(row)
    row.label = ""
    row.igt = ""
    row.rta = ""
    row.lrt = ""
end

local function clearSplitRows()
    clearRow(splitRows.header)
    splitRows.header.label = "Biome"
    splitRows.header.igt = "IGT"
    splitRows.header.rta = "RTA"
    splitRows.header.lrt = "LrT"
    for _, row in ipairs(splitRows.biomes) do
        clearRow(row)
    end
    clearRow(splitRows.total)
end

local function getCurrentRun()
    return rom and rom.game and rom.game.CurrentRun or CurrentRun
end

local function cloneRoute(route)
    local cloned = {}
    for index, biome in ipairs(route or {}) do
        cloned[index] = biome
    end
    return cloned
end

local function detectRoute(run)
    if not run then
        return nil, nil
    end
    if run.IsDreamRun then
        return "dream", {}
    end

    local currentRoomSet = run.CurrentRoom and run.CurrentRoom.RoomSetName
    if currentRoomSet == "N" or currentRoomSet == "O" or currentRoomSet == "P" or currentRoomSet == "Q"
        or run.BiomesReached and run.BiomesReached.N then

        return "surface", cloneRoute(ROUTES.surface)
    end

    return "underworld", cloneRoute(ROUTES.underworld)
end

function timerApi.StartSplitRun(run)
    if not splitState.started then
        return
    end

    run = run or getCurrentRun()
    local routeType, route = detectRoute(run)
    if routeType == nil then
        return
    end

    splitState.active = true
    splitState.failed = false
    splitState.completed = false
    splitState.routeType = routeType
    splitState.route = route
    splitState.captured = {}
    splitState.currentIndex = nil
    splitState.currentBiome = nil
    clearSplitRows()
end

local function captureTime(timer, mode)
    if not timer then
        return 0
    end
    if mode == "igt" then
        return timer:getInGameTime()
    end
    if mode == "rta" then
        return timer:getRealTime()
    end
    if mode == "lrt" then
        return timer:getLoadRemovedTime()
    end
    return 0
end

local function getSnapshot()
    if overlayConfig and overlayConfig.getSnapshot then
        return overlayConfig.getSnapshot() or EMPTY_SNAPSHOT
    end
    return EMPTY_SNAPSHOT
end

local function captureSnapshotValue(timer, mode)
    local snapshot = getSnapshot()
    if snapshot[mode] ~= nil then
        return snapshot[mode]
    end
    return captureTime(timer, mode)
end

local function formatTime(value)
    if value == nil then
        return ""
    end
    return timerApi.FormatTimestamp(value)
end

function timerApi.RecordCompletedBiomeSplits(timer, run)
    if not splitState.active then
        return false
    end

    run = run or getCurrentRun()
    if not (timer and run and run.BiomeVisitOrder) then
        return false
    end

    local changed = false
    for _, biome in ipairs(run.BiomeVisitOrder) do
        local biomeGameplayTime = run.BiomeGameplayTimes and run.BiomeGameplayTimes[biome]
        if biomeGameplayTime ~= nil and splitState.captured[biome] == nil then
            local rta = captureSnapshotValue(timer, "rta")
            local lrt = captureSnapshotValue(timer, "lrt")
            splitState.captured[biome] = {
                igt = biomeGameplayTime,
                rta = rta,
                lrt = lrt,
                formatted = {
                    igt = formatTime(biomeGameplayTime),
                    rta = formatTime(rta),
                    lrt = formatTime(lrt),
                },
            }
            changed = true
        end
    end
    return changed
end

local function isSuccessRun(run)
    if not run then
        return false
    end
    if type(WasRunSuccess) == "function" and run.RunResult ~= nil then
        return WasRunSuccess(run) == true
    end
    return run.Cleared == true
end

function timerApi.IsSingleRecordingVisible()
    return splitState.started
        and (splitState.active or splitState.completed or splitState.failed)
end

function timerApi.IsSingleRecordingStarted()
    return splitState.started == true
end

function timerApi.GetSingleRecordingStatus()
    if splitState.active then
        return {
            kind = "active",
            text = "Recording current run",
        }
    end
    if splitState.failed then
        return {
            kind = "failed",
            text = "Recording failed",
        }
    end
    if splitState.completed then
        return {
            kind = "recorded",
            text = "Recording complete",
        }
    end
    if splitState.started then
        return {
            kind = "ready",
            text = "Recording ready",
        }
    end
    return {
        kind = "idle",
        text = "Not recording",
    }
end

function timerApi.ClearSingleRecording(keepStarted)
    splitState.started = keepStarted == true
    splitState.active = false
    splitState.failed = false
    splitState.completed = false
    splitState.routeType = nil
    splitState.route = nil
    splitState.captured = {}
    splitState.currentIndex = nil
    splitState.currentBiome = nil
    clearSplitRows()
end

function timerApi.FinalizeSingleRecording(timer, run)
    if not splitState.active then
        return
    end

    run = run or getCurrentRun()
    timerApi.RecordCompletedBiomeSplits(timer, run)
    timerApi.UpdateSplitDisplayRows(timer, run)
    splitState.active = false
    splitState.completed = isSuccessRun(run)
    splitState.failed = not splitState.completed
end

local function getRoute(run)
    if splitState.routeType == nil then
        timerApi.StartSplitRun(run)
    end
    if splitState.routeType == "dream" then
        return run and run.BiomeVisitOrder or EMPTY_ROUTE
    end
    return splitState.route or EMPTY_ROUTE
end

local function getCurrentBiome(run)
    return run and run.CurrentRoom and run.CurrentRoom.RoomSetName
end

local function isCurrentBiome(run, route, index, biome)
    if getCurrentBiome(run) == biome then
        return true
    end
    return route[index] == biome and run and run.EnteredBiomes == index
end

local function getCurrentRouteIndex(run, route)
    local currentBiome = getCurrentBiome(run)
    for index, biome in ipairs(route or EMPTY_ROUTE) do
        if currentBiome == biome or route[index] == biome and run and run.EnteredBiomes == index then
            return index, biome
        end
    end
    return nil, currentBiome
end

local function setRow(row, label, igt, rta, lrt)
    row.label = label or ""
    row.igt = igt or ""
    row.rta = rta or ""
    row.lrt = lrt or ""
    return row
end

local function setFormattedSnapshotRow(row, label, snapshot, timer)
    local formatted = snapshot.formatted
    if formatted then
        return setRow(row, label, formatted.igt, formatted.rta, formatted.lrt)
    end

    return setRow(row, label,
        formatTime(snapshot.igt ~= nil and snapshot.igt or captureTime(timer, "igt")),
        formatTime(snapshot.rta ~= nil and snapshot.rta or captureTime(timer, "rta")),
        formatTime(snapshot.lrt ~= nil and snapshot.lrt or captureTime(timer, "lrt")))
end

local function setCompletedRow(row, label, captured)
    local formatted = captured and captured.formatted
    if formatted then
        return setRow(row, label, formatted.igt, formatted.rta, formatted.lrt)
    end

    return setRow(row, label,
        formatTime(captured and captured.igt),
        formatTime(captured and captured.rta),
        formatTime(captured and captured.lrt))
end

local function updateSplitDisplayRow(row, index, timer, run, route, snapshot)
    local biome = route[index]
    if not biome then
        return setRow(row, "", "", "", "")
    end

    local label = BIOME_LABELS[biome] or biome
    local captured = splitState.captured[biome]
    if captured then
        return setCompletedRow(row, label, captured)
    end
    if isCurrentBiome(run, route, index, biome) then
        return setFormattedSnapshotRow(row, label, snapshot, timer)
    end
    return setRow(row, label, "", "", "")
end

local function updateTotalRow(timer, snapshot)
    return setFormattedSnapshotRow(splitRows.total, "Total", snapshot, timer)
end

local function updateTrackedSplitRow(index, timer, run, route, snapshot)
    local row = splitRows.biomes[index]
    if not row then
        return
    end
    updateSplitDisplayRow(row, index, timer, run, route, snapshot)
end

function timerApi.UpdateSplitDisplayRows(timer, run)
    run = run or getCurrentRun()
    local route = getRoute(run)
    local snapshot = getSnapshot()

    for index = 1, 4 do
        updateTrackedSplitRow(index, timer, run, route, snapshot)
    end
    updateTotalRow(timer, snapshot)
    splitState.currentIndex, splitState.currentBiome = getCurrentRouteIndex(run, route)
end

function timerApi.UpdateLiveSplitDisplayRows(timer, run)
    run = run or getCurrentRun()
    local route = getRoute(run)
    local currentIndex, currentBiome = getCurrentRouteIndex(run, route)
    if currentIndex ~= splitState.currentIndex or currentBiome ~= splitState.currentBiome then
        timerApi.UpdateSplitDisplayRows(timer, run)
        return true
    end

    local snapshot = getSnapshot()
    if currentIndex then
        updateTrackedSplitRow(currentIndex, timer, run, route, snapshot)
    end
    updateTotalRow(timer, snapshot)
    return false
end

function timerApi.GetSplitDisplayRow(index, timer, run)
    run = run or getCurrentRun()
    local route = getRoute(run)
    local row = splitRows.biomes[index]
    if not row then
        return nil
    end

    updateSplitDisplayRow(row, index, timer, run, route, getSnapshot())
    if row.label == "" then
        return nil
    end
    return row
end

function timerApi.GetSplitTotalRow(timer)
    updateTotalRow(timer, getSnapshot())
    return splitRows.total
end

local function splitVisible()
    return overlayConfig and overlayConfig.isVisible and overlayConfig.isVisible() == true
end

local function modeVisible(mode)
    if overlayConfig and overlayConfig.isModeVisible then
        return overlayConfig.isModeVisible(mode) == true
    end
    return true
end

function timerApi.ConfigureSplitOverlays(config)
    overlayConfig = overlayConfig or {}
    for key, value in pairs(config or {}) do
        overlayConfig[key] = value
    end
end

function timerApi.RegisterSplitOverlay(overlays)
    if not overlayConfig then
        return
    end

    overlays.createTable("splits", {
        componentName = "SpeedrunTimer_Split",
        region = timerApi.TimerOverlay.region,
        order = overlayConfig.order,
        maxRows = 6,
        columnGap = 20,
        columns = timerApi.TimerOverlay.buildTimerTableColumns(modeVisible),
        visible = splitVisible,
    })
end

local function appendRow(rows, key, row)
    if row.label == nil or row.label == "" then
        return
    end
    rows[#rows + 1] = {
        key = key,
        label = row.label,
        igt = row.igt,
        rta = row.rta,
        lrt = row.lrt,
    }
end

function timerApi.BuildSplitOverlayRows(timer, run, liveOnly)
    local rows = {}
    if not splitVisible() then
        return rows
    end

    if liveOnly then
        timerApi.UpdateLiveSplitDisplayRows(timer, run)
    else
        timerApi.UpdateSplitDisplayRows(timer, run)
    end

    appendRow(rows, "header", splitRows.header)
    for index = 1, 4 do
        appendRow(rows, "biome" .. index, splitRows.biomes[index])
    end
    appendRow(rows, "total", splitRows.total)
    return rows
end

function timerApi.RefreshSplitDisplay()
    if timerApi.RefreshTimerDisplay then
        timerApi.RefreshTimerDisplay()
    end
end

function timerApi.RefreshSplitText()
    if timerApi.RefreshTimerDisplay then
        timerApi.RefreshTimerDisplay()
    end
end

return timerApi
