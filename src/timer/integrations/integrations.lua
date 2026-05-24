local deps = ... or {}
local timer = deps.timer

local integrations = {}

local INTEGRATION_ID = "speedrun.timer"
local PROVIDER_ID = "SpeedrunTimer"

function integrations.register(registry)
    registry.provide(INTEGRATION_ID, {
        providerId = PROVIDER_ID,
        methods = {
            getRealTime = {
                handler = function()
                    return timer.getRealTime()
                end,
            },
            getLoadRemovedTime = {
                handler = function()
                    return timer.getLoadRemovedTime()
                end,
            },
            getInGameTime = {
                handler = function()
                    return timer.getInGameTime()
                end,
            },
            getTimes = {
                handler = function()
                    return {
                        realTime = timer.getRealTime(),
                        loadRemovedTime = timer.getLoadRemovedTime(),
                        inGameTime = timer.getInGameTime(),
                    }
                end,
            },
        },
    })
end

return integrations
