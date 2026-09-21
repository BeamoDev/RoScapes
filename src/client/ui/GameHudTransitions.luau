local TweenService = game:GetService("TweenService")

local GameHudTransitions = {}
local state = {
	gameScreen = nil,
	gameButtons = nil,
	inGameBar = nil,
	LetterWheel = nil,
	targets = nil,
	positions = {},
	sizes = {},
	setExitPending = nil,
	slowdown = 1.45,
	transitionToken = 0,
	activeTweens = {},
}

local function beginTransition()
	state.transitionToken += 1
	for _, tween in ipairs(state.activeTweens) do
		tween:Cancel()
	end
	state.activeTweens = {}
	return state.transitionToken
end

local function playTween(instance, tweenInfo, goals)
	local tween = TweenService:Create(instance, tweenInfo, goals)
	table.insert(state.activeTweens, tween)
	tween:Play()
	return tween
end

local function targets()
	if state.targets then
		return state.targets
	end
	local wheel = state.gameScreen and state.gameScreen:FindFirstChild("WheelRoot")
	local buttons = state.gameButtons
	local bar = state.inGameBar
	state.targets = {
		wheelRoot = wheel,
		arrow = (buttons and buttons:FindFirstChild("Arrow")) or (wheel and wheel:FindFirstChild("Arrow")),
		hint = (buttons and (buttons:FindFirstChild("Hint") or buttons:FindFirstChild("HintButton")))
			or (bar and bar:FindFirstChild("HintButton")),
		shuffle = (buttons and buttons:FindFirstChild("Shuffle")) or (wheel and wheel:FindFirstChild("Shuffle")),
		star = (buttons and (buttons:FindFirstChild("Star") or buttons:FindFirstChild("STAR")))
			or (wheel and (wheel:FindFirstChild("Star") or wheel:FindFirstChild("STAR"))),
		returnBtn = (buttons and buttons:FindFirstChild("Return")) or (bar and bar:FindFirstChild("Return")),
		currency = (buttons and buttons:FindFirstChild("Currency"))
			or (state.gameScreen and state.gameScreen:FindFirstChild("Currency")),
		levelLabel = (state.gameScreen and state.gameScreen:FindFirstChild("LevelLabel"))
			or (bar and bar:FindFirstChild("LevelLabel")),
	}
	for key, gui in pairs(state.targets) do
		if gui and gui:IsA("GuiObject") then
			state.positions[key] = gui.Position
			state.sizes[key] = gui.Size
		end
	end
	return state.targets
end

local function hiddenPositions()
	return {
		wheelRoot = state.positions.wheelRoot,
		arrow = state.positions.arrow and state.positions.arrow + UDim2.fromScale(0.5, 0),
		hint = state.positions.hint and state.positions.hint + UDim2.fromScale(0.5, 0),
		shuffle = state.positions.shuffle and state.positions.shuffle + UDim2.fromScale(-0.5, 0),
		star = state.positions.star and state.positions.star + UDim2.fromScale(-0.5, 0),
		returnBtn = state.positions.returnBtn and state.positions.returnBtn + UDim2.fromScale(0, -0.5),
		currency = state.positions.currency,
		levelLabel = state.positions.levelLabel and state.positions.levelLabel + UDim2.fromScale(0, -0.5),
	}
end

function GameHudTransitions.Init(options)
	for key, value in pairs(options) do
		state[key] = value
	end
	targets()
end

function GameHudTransitions.SetHidden()
	beginTransition()
	local hidden = hiddenPositions()
	for key, gui in pairs(targets()) do
		if gui and gui:IsA("GuiObject") and hidden[key] then
			gui.Position = hidden[key]
		end
		if key == "wheelRoot" and gui and gui:IsA("GuiObject") then
			gui.Visible = false
			gui.Size = UDim2.fromScale(0, 0)
		end
	end
	if state.LetterWheel.SetLettersHiddenState then
		state.LetterWheel:SetLettersHiddenState()
	end
end

function GameHudTransitions.AnimateIn()
	beginTransition()
	state.setExitPending(false)
	for key, gui in pairs(targets()) do
		local position = state.positions[key]
		if gui and gui:IsA("GuiObject") and position then
			if key == "wheelRoot" then
				gui.Visible = true
				playTween(
					gui,
					TweenInfo.new(0.28 * state.slowdown, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{
						Position = position,
						Size = state.sizes[key] or gui.Size,
					}
				)
				if state.LetterWheel.AnimateLettersIn then
					state.LetterWheel:AnimateLettersIn(0.28 * state.slowdown)
				end
			else
				playTween(
					gui,
					TweenInfo.new(0.32 * state.slowdown, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
					{ Position = position }
				)
			end
		end
	end
end

function GameHudTransitions.AnimateOut(onDone)
	local token = beginTransition()
	state.setExitPending(true)
	local wheelDuration = 0.22 * state.slowdown
	local uiDuration = 0.3 * state.slowdown
	local hidden = hiddenPositions()
	for key, gui in pairs(targets()) do
		if gui and gui:IsA("GuiObject") then
			if key == "wheelRoot" then
				playTween(gui, TweenInfo.new(wheelDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
					Size = UDim2.fromScale(0, 0),
				})
				if state.LetterWheel.AnimateLettersOut then
					state.LetterWheel:AnimateLettersOut(wheelDuration, true)
				end
				task.delay(wheelDuration + 0.02, function()
					if state.transitionToken == token and gui.Parent then
						gui.Visible = false
					end
				end)
			elseif hidden[key] then
				playTween(gui, TweenInfo.new(uiDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
					Position = hidden[key],
				})
			end
		end
	end
	task.delay(math.max(wheelDuration, uiDuration) + 0.04, function()
		if state.transitionToken == token and onDone then
			onDone()
		end
	end)
end

return GameHudTransitions
