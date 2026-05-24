local timer = {}

timer.core = import('timer_legacy/core/00_init.lua', nil, {
    getTime = GetTime,
    getCurrentRun = function()
        return rom and rom.game and rom.game.CurrentRun or CurrentRun
    end,
})
timer.overlay = import('timer_legacy/overlay/00_init.lua')
timer.splits = import('timer_legacy/recording/splits.lua', nil, {
    overlay = timer.overlay,
    formatTimestamp = timer.core.formatTimestamp,
    getCurrentRun = function()
        return rom and rom.game and rom.game.CurrentRun or CurrentRun
    end,
    refreshDisplay = function()
        if timer.RefreshTimerDisplay then
            timer.RefreshTimerDisplay()
        end
    end,
    isRunSuccess = function(run)
        if type(WasRunSuccess) == "function" and run and run.RunResult ~= nil then
            return WasRunSuccess(run) == true
        end
        return run and run.Cleared == true
    end,
})
timer.batch = import('timer_legacy/recording/batch.lua', nil, {
    core = timer.core,
    overlay = timer.overlay,
    formatTimestamp = timer.core.formatTimestamp,
    readSetting = function(alias)
        local store = timer.store
        if store and store.read then
            return store.read(alias)
        end
        return nil
    end,
    refreshDisplay = function()
        if timer.RefreshTimerDisplay then
            timer.RefreshTimerDisplay()
        end
    end,
    isRunSuccess = function(run)
        if type(WasRunSuccess) == "function" and run and run.RunResult ~= nil then
            return WasRunSuccess(run) == true
        end
        return run and run.Cleared == true
    end,
})

-- Compatibility shim while the timer subsystem is migrated off legacy globals.
-- Delete this once all runtime/recording files consume explicit dependencies.
Timer = timer.core.Timer
RtaTimer = timer.core.RtaTimer
LrtTimer = timer.core.LrtTimer
IgtTimer = timer.core.IgtTimer
timer.TimerOverlay = timer.overlay
timer.IsBatchActive = timer.batch.IsBatchActive
timer.IsBatchVisible = timer.batch.IsBatchVisible
timer.GetBatchStatus = timer.batch.GetBatchStatus
timer.StartBatch = timer.batch.StartBatch
timer.StopBatch = timer.batch.StopBatch
timer.ClearBatch = timer.batch.ClearBatch
timer.StartBatchRun = timer.batch.StartBatchRun
timer.UpdateBatchTimer = timer.batch.UpdateBatchTimer
timer.ProcessBatchLoadEvent = timer.batch.ProcessBatchLoadEvent
timer.GetBatchDisplayTime = timer.batch.GetBatchDisplayTime
timer.FinalizeBatchRun = timer.batch.FinalizeBatchRun
timer.InitializeBatchState = timer.batch.Initialize
timer.UpdateBatchDisplayRows = timer.batch.UpdateBatchDisplayRows
timer.GetBatchDisplayRow = timer.batch.GetBatchDisplayRow
timer.GetBatchCurrentDisplayRow = timer.batch.GetBatchCurrentDisplayRow
timer.ConfigureBatchOverlays = timer.batch.ConfigureBatchOverlays
timer.ConfigureBatchMode = timer.batch.ConfigureBatchMode
timer.RegisterBatchOverlay = timer.batch.RegisterBatchOverlay
timer.BuildBatchOverlayRows = timer.batch.BuildBatchOverlayRows
timer.StartSplitRun = timer.splits.StartSplitRun
timer.RecordCompletedBiomeSplits = timer.splits.RecordCompletedBiomeSplits
timer.IsSingleRecordingVisible = timer.splits.IsSingleRecordingVisible
timer.IsSingleRecordingStarted = timer.splits.IsSingleRecordingStarted
timer.GetSingleRecordingStatus = timer.splits.GetSingleRecordingStatus
timer.ClearSingleRecording = timer.splits.ClearSingleRecording
timer.FinalizeSingleRecording = timer.splits.FinalizeSingleRecording
timer.UpdateSplitDisplayRows = timer.splits.UpdateSplitDisplayRows
timer.UpdateLiveSplitDisplayRows = timer.splits.UpdateLiveSplitDisplayRows
timer.GetSplitDisplayRow = timer.splits.GetSplitDisplayRow
timer.GetSplitTotalRow = timer.splits.GetSplitTotalRow
timer.ConfigureSplitOverlays = timer.splits.ConfigureSplitOverlays
timer.RegisterSplitOverlay = timer.splits.RegisterSplitOverlay
timer.BuildSplitOverlayRows = timer.splits.BuildSplitOverlayRows
timer.RefreshSplitDisplay = timer.splits.RefreshSplitDisplay
timer.RefreshSplitText = timer.splits.RefreshSplitText

return timer
