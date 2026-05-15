local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods['SGG_Modding-ModUtil']
---@module "adamant-ModpackLib"
---@type AdamantModpackLib
lib = mods['adamant-ModpackLib']
local chalk = mods['SGG_Modding-Chalk']
local reload = mods['SGG_Modding-ReLoad']
local config = chalk.auto('config.lua')

local PACK_ID = "speedrun"
local MODULE_ID = "SpeedrunTimer"
local PLUGIN_GUID = _PLUGIN.guid

---@class SpeedrunTimerModuleAnchor
---@field standaloneUi StandaloneRuntime|nil
MODULE_ANCHOR = MODULE_ANCHOR or {}
---@type SpeedrunTimerModuleAnchor
local moduleAnchor = MODULE_ANCHOR

moduleAnchor.standaloneUi = nil

local loader = reload.auto_single()

local function registerGui()
    rom.gui.add_imgui(function()
        if moduleAnchor.standaloneUi and moduleAnchor.standaloneUi.renderWindow then
            moduleAnchor.standaloneUi.renderWindow()
        end
    end)

    rom.gui.add_to_menu_bar(function()
        if moduleAnchor.standaloneUi and moduleAnchor.standaloneUi.addMenuBar then
            moduleAnchor.standaloneUi.addMenuBar()
        end
    end)
end

local function init()
    import_as_fallback(rom.game)
    local data = import("data.lua")
    local logic = import("logic.lua").bind()
    local ui = import("ui.lua").bind(logic)

    local host, store = lib.tryCreateModule({
        owner = moduleAnchor,
        pluginGuid = PLUGIN_GUID,
        config = config,
        definition = {
            id = MODULE_ID,
            name = "Speedrun Timer",
            tooltip = "Displays selected timer modes on screen during runs.",
            modpack = PACK_ID,
            storage = data.buildStorage(),
        },
        onSettingsCommitted = logic.onSettingsCommitted,
        registerHooks = logic.registerHooks,
        registerOverlays = logic.registerOverlays,
        drawTab = ui.drawTab,
        drawQuickContent = ui.drawQuickContent,
    })
    if not host then
        return
    end

    logic.initialize(host, store)

    local ok = host.tryActivate()
    if not ok then
        return
    end

    moduleAnchor.standaloneUi = lib.standaloneHost(PLUGIN_GUID)
end

modutil.once_loaded.game(function()
    loader.load(registerGui, init)
end)
