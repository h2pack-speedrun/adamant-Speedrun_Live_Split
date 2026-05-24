local deps = ... or {}
local getTime = deps.getTime or GetTime

if getTime == nil then
    local socket = require('socket')
    getTime = function(_)
        return socket.gettime()
    end
end

local Timer = import('timer_legacy/core/base_timer.lua')
local RtaTimer = import('timer_legacy/core/rta_timer.lua', nil, {
    Timer = Timer,
    getTime = getTime,
})
local LrtTimer = import('timer_legacy/core/lrt_timer.lua', nil, {
    Timer = Timer,
    RtaTimer = RtaTimer,
    getTime = getTime,
})
local IgtTimer = import('timer_legacy/core/igt_timer.lua', nil, {
    getCurrentRun = deps.getCurrentRun,
})
local timeFormat = import('timer_legacy/core/time_format.lua')

return {
    Timer = Timer,
    RtaTimer = RtaTimer,
    LrtTimer = LrtTimer,
    IgtTimer = IgtTimer,
    formatTimestamp = timeFormat.formatTimestamp,
    formatCentiseconds = timeFormat.formatCentiseconds,
    toCentiseconds = timeFormat.toCentiseconds,
}
