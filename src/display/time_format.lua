local timeFormat = {}

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

return timeFormat
