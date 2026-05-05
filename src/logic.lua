local internal = SpeedrunTimerInternal

import("timer/OverlayRows.lua")
import("timer/Splits.lua")
import("timer/Batch.lua")
import("timer/Runtime.lua")

function internal.RegisterPublicApi()
    public.getRealTime = function()
        if internal.GetRealTime then
            return internal.GetRealTime()
        end
    end

    public.getLoadRemovedTime = function()
        if internal.GetLoadRemovedTime then
            return internal.GetLoadRemovedTime()
        end
    end

    public.getInGameTime = function()
        if internal.GetInGameTime then
            return internal.GetInGameTime()
        end
    end
end

return internal
