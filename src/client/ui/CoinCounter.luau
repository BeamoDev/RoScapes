local TweenService = game:GetService("TweenService")

local CoinCounter = {}
local activeByLabel = setmetatable({}, { __mode = "k" })

local function formatInteger(value)
	local number = math.max(0, math.floor((tonumber(value) or 0) + 0.5))
	local text = tostring(number)
	local formatted = text
	repeat
		formatted, number = formatted:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until number == 0
	return formatted
end

local function readDisplayedValue(label, fallback)
	local digits = tostring(label.Text or ""):gsub("[^%d%-]", "")
	return tonumber(digits) or tonumber(fallback) or 0
end

function CoinCounter.Set(label, targetValue, options)
	if not label or not label:IsA("TextLabel") then
		return
	end
	options = options or {}
	local target = math.max(0, math.floor((tonumber(targetValue) or 0) + 0.5))
	local previous = activeByLabel[label]
	local start = previous and previous.value.Value or readDisplayedValue(label, options.startValue)
	if previous then
		activeByLabel[label] = nil
		previous.tween:Cancel()
		previous.connection:Disconnect()
		previous.value:Destroy()
	end
	local prefix = tostring(options.prefix or "")
	local suffix = tostring(options.suffix or "")
	local function render(value)
		label.Text = prefix .. formatInteger(value) .. suffix
	end
	if start == target or options.instant == true then
		render(target)
		activeByLabel[label] = nil
		return
	end
	local counter = Instance.new("NumberValue")
	counter.Value = start
	local difference = math.abs(target - start)
	local duration = math.clamp(0.28 + math.log10(difference + 1) * 0.16, 0.32, 0.9)
	local connection = counter:GetPropertyChangedSignal("Value"):Connect(function()
		if label.Parent then
			render(counter.Value)
		end
	end)
	local tween =
		TweenService:Create(counter, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Value = target,
		})
	activeByLabel[label] = { value = counter, tween = tween, connection = connection }
	render(start)
	tween:Play()
	tween.Completed:Connect(function(playbackState)
		local active = activeByLabel[label]
		if not active or active.tween ~= tween or playbackState ~= Enum.PlaybackState.Completed then
			return
		end
		render(target)
		connection:Disconnect()
		counter:Destroy()
		activeByLabel[label] = nil
	end)
end

return CoinCounter
