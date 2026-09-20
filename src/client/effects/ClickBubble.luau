local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ClickBubble = {}

function ClickBubble.Init(playerGui, hud)
	local bubbleGui = Instance.new("ScreenGui")
	bubbleGui.Name = "ClickBubbleGui"
	bubbleGui.IgnoreGuiInset = true
	bubbleGui.ResetOnSpawn = false
	bubbleGui.DisplayOrder = 10000
	bubbleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	bubbleGui.Parent = playerGui

	local layer = Instance.new("Frame")
	layer.Name = "ClickBubbleLayer"
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 1000
	layer.Parent = bubbleGui

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not hud.Parent then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local position = input.Position
		local point = typeof(position) == "Vector3" and Vector2.new(position.X, position.Y) or position
		if typeof(point) ~= "Vector2" then
			return
		end
		local bubble = Instance.new("Frame")
		bubble.Name = "ClickBubble"
		bubble.AnchorPoint = Vector2.new(0.5, 0.5)
		bubble.Position = UDim2.fromOffset(point.X - layer.AbsolutePosition.X, point.Y - layer.AbsolutePosition.Y)
		bubble.Size = UDim2.fromOffset(10, 10)
		bubble.BackgroundColor3 = Color3.new(1, 1, 1)
		bubble.BackgroundTransparency = 0.45
		bubble.BorderSizePixel = 0
		bubble.ZIndex = layer.ZIndex
		bubble.Parent = layer

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = bubble
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 1
		stroke.Transparency = 0.3
		stroke.Parent = bubble

		TweenService:Create(bubble, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(24, 24),
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Thickness = 2,
		}):Play()
		task.delay(0.22, function()
			bubble:Destroy()
		end)
	end)
end

return ClickBubble
