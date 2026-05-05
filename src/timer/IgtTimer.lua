-- In-Game Time timer. Thin wrapper around the engine's _worldTime global.

IgtTimer = {}

function IgtTimer:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function IgtTimer:getTime()  --luacheck: ignore 212
    local currentRun = rom and rom.game and rom.game.CurrentRun or CurrentRun
    if not currentRun or currentRun.GameplayTime == nil then
        return 0
    end
    return currentRun.GameplayTime
end
