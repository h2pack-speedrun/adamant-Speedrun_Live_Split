local timeFormat = {}

function timeFormat.toCentiseconds(timestamp)
    if not timestamp then
        return 0
    end
    return math.floor((timestamp * 100) + 0.0000001)
end

function timeFormat.formatCentiseconds(totalCentiseconds)
    local centiseconds = totalCentiseconds % 100
    local totalSeconds = math.floor(totalCentiseconds / 100)
    local seconds = totalSeconds % 60
    local totalMinutes = math.floor(totalSeconds / 60)
    local minutes = totalMinutes % 60
    local hours = math.floor(totalMinutes / 60)

    if hours == 0 then
        return string.format("%02d:%02d.%02d", minutes, seconds, centiseconds)
    end
    return string.format("%02d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
end

function timeFormat.formatTimestamp(timestamp)
    return timeFormat.formatCentiseconds(timeFormat.toCentiseconds(timestamp))
end

return timeFormat
