local function configureLiveSplitEnv(env)
    env._worldTime = 0
    env.GetTime = function()
        return 0
    end
    env.CurrentRun = {
        GameplayTime = 0,
    }
end

return {
    expectedPackId = "speedrun",
    expectedModuleId = "LiveSplit",
    configureEnv = configureLiveSplitEnv,
}
