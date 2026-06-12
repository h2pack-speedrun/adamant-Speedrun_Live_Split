local support = dofile("tests/support.lua")
local assertEqual = support.assertEqual

local harness = support.loadModpackToolsTest("module_entrypoint_harness.lua")
local boot = harness.bootModule({
    pluginGuid = "adamantSpeedrun-LiveSplit",
    moduleSrcDir = "src",
    configureEnv = function(env)
        env._worldTime = 0
        env.GetTime = function()
            return 0
        end
        env.CurrentRun = {
            GameplayTime = 0,
        }
    end,
})
assert(boot.liveModule and boot.liveModule.setEnabled(true))
boot.liveModule.drawTab()
boot.liveModule.drawQuickContent()

local consumerHost = boot.lib.createModule({
    pluginGuid = "test-SpeedrunTimerConsumer",
    id = "TimerConsumer",
    name = "Timer Consumer",
})
consumerHost.ui.tab(function() end)
consumerHost.shared.data.reader("TimerSnapshot", {
    id = "speedrun.timer",
    fallback = {
        realTimeCs = -1,
        loadRemovedTimeCs = -1,
        inGameTimeCs = -1,
    },
})
local consumerRuntime = nil
consumerHost.onActivate(function(_, runtime)
    consumerRuntime = runtime
end)
assert(consumerHost and consumerHost.activate())

local times = consumerRuntime.shared.read("TimerSnapshot")
assertEqual(times.realTimeCs, 0)
assertEqual(times.loadRemovedTimeCs, 0)
assertEqual(times.inGameTimeCs, 0)
assertEqual(times.recordingStatus.kind, "idle")
assertEqual(next(boot.moduleEnv.public), nil)
