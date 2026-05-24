local deps = ... or {}
local batch = import('timer/batch/batch.lua', nil, deps)

batch.overlay = import('timer/batch/overlay.lua', nil, {
    batch = batch,
    overlay = deps.overlay,
    isVisible = deps.isVisible,
    isModeVisible = deps.isModeVisible,
})

return batch
