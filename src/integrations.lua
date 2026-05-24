local integrations = {}

local INTEGRATION_ID = "speedrun.timer"
local PROVIDER_ID = "SpeedrunTimer"

function integrations.register(host, logic)
    host.integrations.provide(INTEGRATION_ID, {
        providerId = PROVIDER_ID,
        methods = {
            getRealTime = {
                handler = function()
                    return logic.getRealTime()
                end,
            },
            getLoadRemovedTime = {
                handler = function()
                    return logic.getLoadRemovedTime()
                end,
            },
            getInGameTime = {
                handler = function()
                    return logic.getInGameTime()
                end,
            },
            getTimes = {
                handler = function()
                    return {
                        realTime = logic.getRealTime(),
                        loadRemovedTime = logic.getLoadRemovedTime(),
                        inGameTime = logic.getInGameTime(),
                    }
                end,
            },
        },
    })
end

return integrations
