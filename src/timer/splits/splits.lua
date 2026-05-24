local deps = ... or {}
local formatTimestamp = deps.formatTimestamp
local isRunSuccess = deps.isRunSuccess or function(run)
    return run and run.Cleared == true
end

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

local EMPTY_ROUTE = {}
local EMPTY_SNAPSHOT = {}
local splits = {}
local state = {
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
local rows = {
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

local function cloneRoute(route)
    local cloned = {}
    for index, biome in ipairs(route or {}) do
        cloned[index] = biome
    end
    return cloned
end

local function clearRow(row)
    row.label = ""
    row.igt = ""
    row.rta = ""
    row.lrt = ""
end

local function clearRows()
    rows.header.label = "Biome"
    rows.header.igt = "IGT"
    rows.header.rta = "RTA"
    rows.header.lrt = "LrT"
    for _, row in ipairs(rows.biomes) do
        clearRow(row)
    end
    rows.total.label = "Total"
    rows.total.igt = "00:00.00"
    rows.total.rta = "00:00.00"
    rows.total.lrt = "00:00.00"
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

local function formatTime(value)
    if value == nil then
        return ""
    end
    return formatTimestamp(value)
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

local function snapshotValue(snapshot, timer, mode)
    snapshot = snapshot or EMPTY_SNAPSHOT
    if snapshot[mode] ~= nil then
        return snapshot[mode]
    end
    return captureTime(timer, mode)
end

local function getCurrentBiome(run)
    return run and run.CurrentRoom and run.CurrentRoom.RoomSetName
end

local function getRoute(run)
    if state.routeType == nil then
        splits.startRun(run)
    end
    if state.routeType == "dream" then
        return run and run.BiomeVisitOrder or EMPTY_ROUTE
    end
    return state.route or EMPTY_ROUTE
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

local function setSnapshotRow(row, label, snapshot, timer)
    local formatted = snapshot and snapshot.formatted
    if formatted then
        return setRow(row, label, formatted.igt, formatted.rta, formatted.lrt)
    end

    return setRow(row, label,
        formatTime(snapshotValue(snapshot, timer, "igt")),
        formatTime(snapshotValue(snapshot, timer, "rta")),
        formatTime(snapshotValue(snapshot, timer, "lrt")))
end

local function setCapturedRow(row, label, captured)
    local formatted = captured and captured.formatted
    if formatted then
        return setRow(row, label, formatted.igt, formatted.rta, formatted.lrt)
    end

    return setRow(row, label,
        formatTime(captured and captured.igt),
        formatTime(captured and captured.rta),
        formatTime(captured and captured.lrt))
end

local function updateBiomeRow(row, index, timer, run, route, snapshot)
    local biome = route[index]
    if not biome then
        return setRow(row, "", "", "", "")
    end

    local label = BIOME_LABELS[biome] or biome
    local captured = state.captured[biome]
    if captured then
        return setCapturedRow(row, label, captured)
    end
    if isCurrentBiome(run, route, index, biome) then
        return setSnapshotRow(row, label, snapshot, timer)
    end
    return setRow(row, label, "", "", "")
end

function splits.startRun(run)
    if not state.started then
        return false
    end

    local routeType, route = detectRoute(run)
    if routeType == nil then
        return false
    end

    state.active = true
    state.failed = false
    state.completed = false
    state.routeType = routeType
    state.route = route
    state.captured = {}
    state.currentIndex = nil
    state.currentBiome = nil
    clearRows()
    return true
end

function splits.recordCompletedBiomes(timer, run, snapshot)
    if not state.active then
        return false
    end
    if not (timer and run and run.BiomeVisitOrder) then
        return false
    end

    local changed = false
    for _, biome in ipairs(run.BiomeVisitOrder) do
        local biomeGameplayTime = run.BiomeGameplayTimes and run.BiomeGameplayTimes[biome]
        if biomeGameplayTime ~= nil and state.captured[biome] == nil then
            local rta = snapshotValue(snapshot, timer, "rta")
            local lrt = snapshotValue(snapshot, timer, "lrt")
            state.captured[biome] = {
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

function splits.updateRows(timer, run, snapshot)
    local route = getRoute(run)
    snapshot = snapshot or EMPTY_SNAPSHOT
    for index = 1, 4 do
        updateBiomeRow(rows.biomes[index], index, timer, run, route, snapshot)
    end
    setSnapshotRow(rows.total, "Total", snapshot, timer)
    state.currentIndex, state.currentBiome = getCurrentRouteIndex(run, route)
end

function splits.updateLiveRows(timer, run, snapshot)
    local route = getRoute(run)
    local currentIndex, currentBiome = getCurrentRouteIndex(run, route)
    if currentIndex ~= state.currentIndex or currentBiome ~= state.currentBiome then
        splits.updateRows(timer, run, snapshot)
        return true
    end

    if currentIndex then
        updateBiomeRow(rows.biomes[currentIndex], currentIndex, timer, run, route, snapshot)
    end
    setSnapshotRow(rows.total, "Total", snapshot, timer)
    return false
end

function splits.finalizeRun(timer, run, snapshot)
    if not state.active then
        return false
    end

    splits.recordCompletedBiomes(timer, run, snapshot)
    splits.updateRows(timer, run, snapshot)
    state.active = false
    state.completed = isRunSuccess(run) == true
    state.failed = not state.completed
    return true
end

function splits.clear(keepStarted)
    state.started = keepStarted == true
    state.active = false
    state.failed = false
    state.completed = false
    state.routeType = nil
    state.route = nil
    state.captured = {}
    state.currentIndex = nil
    state.currentBiome = nil
    clearRows()
end

function splits.status()
    if state.active then
        return {
            kind = "active",
            text = "Recording current run",
        }
    end
    if state.failed then
        return {
            kind = "failed",
            text = "Recording failed",
        }
    end
    if state.completed then
        return {
            kind = "recorded",
            text = "Recording complete",
        }
    end
    if state.started then
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

function splits.isVisible()
    return state.started and (state.active or state.completed or state.failed)
end

function splits.isStarted()
    return state.started == true
end

function splits.rows()
    return rows
end

function splits.row(index, timer, run, snapshot)
    local route = getRoute(run)
    local row = rows.biomes[index]
    if not row then
        return nil
    end

    updateBiomeRow(row, index, timer, run, route, snapshot)
    if row.label == "" then
        return nil
    end
    return row
end

function splits.totalRow(timer, snapshot)
    setSnapshotRow(rows.total, "Total", snapshot, timer)
    return rows.total
end

return splits
