local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods['SGG_Modding-ModUtil']
---@module "adamant-ModpackLib"
---@type AdamantModpackLib
local lib = mods['adamant-ModpackLib']
local chalk = mods['SGG_Modding-Chalk']
local reload = mods['SGG_Modding-ReLoad']
local config = chalk.auto('config.lua')

local PACK_ID = "speedrun"
local MODULE_ID = "SpeedrunTimer"
local PLUGIN_GUID = _PLUGIN.guid

local loader = reload.auto_single()

local function init()
    import_as_fallback(rom.game)
    local data = import("data.lua")
    local timer = nil
    local timerFacade = {
        getRecordingStatus = function()
            if timer then
                return timer.getRecordingStatus()
            end
            return {
                kind = "idle",
                text = "Not recording",
            }
        end,
    }
    local ui = import("ui.lua").bind(timerFacade)

    local host, store = lib.createModule({
        pluginGuid = PLUGIN_GUID,
        config = config,
        modpack = PACK_ID,
        id = MODULE_ID,
        name = "Speedrun Timer",
        tooltip = "Displays selected timer modes on screen during runs.",
        storage = data.buildStorage(),
        cache = {
            RecordingReady = {
                domain = "persistent",
                key = "RecordingReady",
                default = false,
            },
        },
        actions = {
            recording = function() end,
        },
        onSettingsCommitted = function(...)
            if timer then
                timer.onSettingsCommitted(...)
            end
        end,
        drawTab = ui.drawTab,
        drawQuickContent = ui.drawQuickContent,
    })
    if not host then
        return
    end

    timer = import("timer/00_init.lua", nil, {
        host = host,
        store = store,
    })
    timer.initialize()
    timer.registerIntegrations()
    timer.registerHooks()
    timer.registerOverlays()

    host.fallbackUi.attachGuiOnce(function(fallbackUi)
        rom.gui.add_imgui(fallbackUi.renderWindow)
        rom.gui.add_to_menu_bar(fallbackUi.addMenuBar)
    end)

    local ok = host.activate()
    if not ok then
        return
    end
end

modutil.once_loaded.game(function()
    loader.load(nil, init)
end)
