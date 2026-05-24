local deps = ... or {}
local splits = import('timer/splits/splits.lua', nil, deps)
local overlay = nil
if deps.overlay then
    overlay = import('timer/splits/overlay.lua', nil, {
        splits = splits,
        overlay = deps.overlay,
        isVisible = deps.isVisible,
        isModeVisible = deps.isModeVisible,
    })
end

splits.overlay = overlay

return splits
