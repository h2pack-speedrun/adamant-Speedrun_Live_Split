local singleRun = import('timer/single_run/single_run.lua', nil, ...)
local hooks = import('timer/single_run/hooks.lua', nil, singleRun)
local deps = ... or {}
local overlay = nil
if deps.overlay then
    overlay = import('timer/single_run/overlay.lua', nil, {
        singleRun = singleRun,
        overlay = deps.overlay,
        isModeVisible = deps.isModeVisible,
        isTimerDisplayVisible = deps.isTimerDisplayVisible,
        getDisplayTime = deps.getDisplayTime,
    })
end

singleRun.installHooks = hooks.installHooks
singleRun.overlay = overlay

return singleRun
