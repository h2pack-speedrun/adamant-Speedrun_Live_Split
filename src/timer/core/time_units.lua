local timeUnits = {}

function timeUnits.toCentiseconds(timestamp)
    if not timestamp then
        return 0
    end
    return math.floor((timestamp * 100) + 0.0000001)
end

return timeUnits
