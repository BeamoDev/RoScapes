-- InputState.luau
-- Simple client input lock.


local InputState = {}

local inputEnabled = true

function InputState:SetEnabled(enabled)
	inputEnabled = enabled == true
end

function InputState:IsEnabled()
	return inputEnabled
end

return InputState
