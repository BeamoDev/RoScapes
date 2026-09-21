local TweenService = game:GetService("TweenService")

local ButtonFeedback = {}
local states = setmetatable({}, { __mode = "k" })
local descendantConnection = nil

local HOVER_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function getStroke(button)
	local stroke = button:FindFirstChild("RoScapesButtonFeedback")
	if stroke and stroke:IsA("UIStroke") then
		return stroke
	end
	stroke = Instance.new("UIStroke")
	stroke.Name = "RoScapesButtonFeedback"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = button
	return stroke
end

local function tweenState(button, transparency, thickness, tweenInfo)
	local buttonState = states[button]
	if not buttonState then
		return
	end
	if buttonState.tween then
		buttonState.tween:Cancel()
	end
	buttonState.tween = TweenService:Create(buttonState.stroke, tweenInfo, {
		Transparency = transparency,
		Thickness = thickness,
	})
	buttonState.tween:Play()
end

local function refresh(button, tweenInfo)
	local buttonState = states[button]
	if not buttonState then
		return
	end
	local transparency = 1
	local thickness = 1
	local defaultInfo = RELEASE_INFO
	if button.Active and button:GetAttribute("DisableSmoothFeedback") ~= true then
		if buttonState.pressed then
			transparency = 0.3
			thickness = 2.4
			defaultInfo = PRESS_INFO
		elseif buttonState.hovered or buttonState.selected then
			transparency = 0.62
			thickness = 1.6
			defaultInfo = HOVER_INFO
		end
	end
	tweenState(button, transparency, thickness, tweenInfo or defaultInfo)
end

local function bind(button)
	if states[button] or not button:IsA("GuiButton") then
		return
	end
	states[button] = {
		stroke = getStroke(button),
		hovered = false,
		selected = false,
		pressed = false,
		tween = nil,
	}

	button.MouseEnter:Connect(function()
		local buttonState = states[button]
		if buttonState then
			buttonState.hovered = true
			refresh(button)
		end
	end)
	button.MouseLeave:Connect(function()
		local buttonState = states[button]
		if buttonState then
			buttonState.hovered = false
			buttonState.pressed = false
			refresh(button)
		end
	end)
	button.SelectionGained:Connect(function()
		local buttonState = states[button]
		if buttonState then
			buttonState.selected = true
			refresh(button)
		end
	end)
	button.SelectionLost:Connect(function()
		local buttonState = states[button]
		if buttonState then
			buttonState.selected = false
			buttonState.pressed = false
			refresh(button)
		end
	end)
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local buttonState = states[button]
		if buttonState then
			buttonState.pressed = true
			refresh(button, PRESS_INFO)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local buttonState = states[button]
		if buttonState then
			buttonState.pressed = false
			refresh(button, RELEASE_INFO)
		end
	end)
	button:GetPropertyChangedSignal("Active"):Connect(function()
		refresh(button)
	end)
	button.Destroying:Connect(function()
		local buttonState = states[button]
		if buttonState and buttonState.tween then
			buttonState.tween:Cancel()
		end
		states[button] = nil
	end)
end

function ButtonFeedback.Init(container)
	if not container then
		return
	end
	if descendantConnection then
		descendantConnection:Disconnect()
	end
	if container:IsA("GuiButton") then
		bind(container)
	end
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			bind(descendant)
		end
	end
	descendantConnection = container.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("GuiButton") then
			bind(descendant)
		end
	end)
end

return ButtonFeedback
