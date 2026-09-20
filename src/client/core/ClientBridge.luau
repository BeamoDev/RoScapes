local ClientBridge = {}

local callbacks = {}
local state = {}

function ClientBridge.SetCallback(name, fn)
	if typeof(name) ~= "string" or name == "" then
		return
	end
	if typeof(fn) == "function" then
		callbacks[name] = fn
	else
		callbacks[name] = nil
	end
end

function ClientBridge.Call(name, ...)
	local fn = callbacks[name]
	if fn then
		return fn(...)
	end
	return nil
end

function ClientBridge.SetState(name, value)
	if typeof(name) ~= "string" or name == "" then
		return
	end
	state[name] = value
end

function ClientBridge.GetState(name)
	return state[name]
end

return ClientBridge
