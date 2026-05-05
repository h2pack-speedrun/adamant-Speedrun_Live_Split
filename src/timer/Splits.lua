SpeedrunTimerInternal = SpeedrunTimerInternal or {}
local internal = SpeedrunTimerInternal

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
    routeType = nil,
    route = nil,
    captured = {},
    currentIndex = nil,
    currentBiome = nil,
}

local overlayConfig = nil
local splitOverlays = {}
local liveSplitKeys = {}
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

function internal.StartSplitRun(run)
    local routeType, route = detectRoute(run or getCurrentRun())
    splitState.routeType = routeType
    splitState.route = route
    splitState.captured = {}
    splitState.currentIndex = nil
    splitState.currentBiome = nil
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
    return internal.FormatTimestamp(value)
end

function internal.RecordCompletedBiomeSplits(timer, run)
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

local function getRoute(run)
    if splitState.routeType == nil then
        internal.StartSplitRun(run)
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

local function markChangedRow(key, row, previousLabel, previousIgt, previousRta, previousLrt)
    if row.label ~= "" and (
        row.igt ~= previousIgt
        or row.rta ~= previousRta
        or row.lrt ~= previousLrt
        or previousLabel ~= row.label) then

        liveSplitKeys[key] = true
    end
end

local function updateTrackedSplitRow(index, timer, run, route, snapshot)
    local row = splitRows.biomes[index]
    if not row then
        return
    end
    local previousLabel = row.label
    local previousIgt = row.igt
    local previousRta = row.rta
    local previousLrt = row.lrt
    updateSplitDisplayRow(row, index, timer, run, route, snapshot)
    markChangedRow("biome" .. index, row, previousLabel, previousIgt, previousRta, previousLrt)
end

function internal.UpdateSplitDisplayRows(timer, run)
    run = run or getCurrentRun()
    local route = getRoute(run)
    local snapshot = getSnapshot()

    liveSplitKeys.total = true
    for index = 1, 4 do
        updateTrackedSplitRow(index, timer, run, route, snapshot)
    end
    updateTotalRow(timer, snapshot)
    splitState.currentIndex, splitState.currentBiome = getCurrentRouteIndex(run, route)
end

function internal.UpdateLiveSplitDisplayRows(timer, run)
    run = run or getCurrentRun()
    local route = getRoute(run)
    local currentIndex, currentBiome = getCurrentRouteIndex(run, route)
    if currentIndex ~= splitState.currentIndex or currentBiome ~= splitState.currentBiome then
        internal.UpdateSplitDisplayRows(timer, run)
        return true
    end

    local snapshot = getSnapshot()
    liveSplitKeys.total = true
    if currentIndex then
        updateTrackedSplitRow(currentIndex, timer, run, route, snapshot)
    end
    updateTotalRow(timer, snapshot)
    return false
end

function internal.GetSplitDisplayRow(index, timer, run)
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

function internal.GetSplitTotalRow(timer)
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

local function registerSplitRow(key, orderOffset, row)
    return internal.TimerOverlay.registerTableRow(splitOverlays, key, {
        idPrefix = "speedrun.timer.split.",
        componentPrefix = "SpeedrunTimer_Split_",
        order = overlayConfig.order + orderOffset,
        row = row,
        modeVisible = modeVisible,
        visible = function()
            return splitVisible() and row.label ~= nil and row.label ~= ""
        end,
    })
end

function internal.ConfigureSplitOverlays(config)
    overlayConfig = config
end

function internal.EnsureSplitOverlays()
    if not overlayConfig then
        return
    end

    registerSplitRow("header", 0, splitRows.header)

    for index = 1, 4 do
        registerSplitRow("biome" .. index, index, splitRows.biomes[index])
    end

    registerSplitRow("total", 5, splitRows.total)
end

function internal.RefreshSplitDisplay()
    if overlayConfig then
        internal.UpdateSplitDisplayRows(overlayConfig.getTimer())
    end
    internal.EnsureSplitOverlays()
    lib.overlays.refreshStackedText(internal.TimerOverlay.region)
end

function internal.RefreshSplitText(timer)
    local needsStructureRefresh = internal.UpdateLiveSplitDisplayRows(timer)
    if needsStructureRefresh then
        internal.EnsureSplitOverlays()
        lib.overlays.refreshStackedText(internal.TimerOverlay.region)
        liveSplitKeys = {}
        return
    end
    for key in pairs(liveSplitKeys) do
        local handle = splitOverlays[key]
        if handle and handle.refreshText then
            handle.refreshText()
        end
    end
    liveSplitKeys = {}
end

return internal
