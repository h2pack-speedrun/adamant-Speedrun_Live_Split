local actions = {}

local function call(controller, methodName)
    return function(host, runtime)
        return controller[methodName](host, runtime)
    end
end

function actions.build(controller)
    return {
        recordingStart = call(controller, "startRecording"),
        recordingStop = call(controller, "stopRecording"),
        recordingClear = call(controller, "clearRecording"),
    }
end

function actions.attach(module, controller)
    module.actions.define(actions.build(controller))
end

return actions
