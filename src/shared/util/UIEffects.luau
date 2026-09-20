-- UIEffects.luau
-- Shared UI animation helpers.

local TweenService = game:GetService("TweenService")
local UIEffects = {}

local stroke = script:FindFirstChild("OuterStroke")
if stroke then
	stroke = stroke:Clone()
end

-- Cache for original button sizes to avoid recalculating
local buttonSizeCache = {}

-- Store active strokes for cleanup
local activeStrokes = {}

-- Tween cache to reuse tween infos
local TWEEN_INFO_CACHE = {
	hover = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	click = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	shine = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

-- Sound cache
local soundCache = {
	sfx = nil,
	hover = nil,
	button = nil,
	click = nil,
	plus = nil,
	start = nil,
	notificationlow = nil,
	notificationmid = nil,
	purchase = nil,
	victory = nil,
	error = nil,
}

local function cacheSounds()
	local soundService = game:GetService("SoundService")
	local sfx = soundService:FindFirstChild("SFX")
	if sfx then
		soundCache.sfx = sfx
		soundCache.hover = sfx:FindFirstChild("Hover")
		soundCache.button = sfx:FindFirstChild("Button") or sfx:FindFirstChild("Click")
		soundCache.click = soundCache.button
		soundCache.plus = sfx:FindFirstChild("Plus")
		soundCache.start = sfx:FindFirstChild("Start")
		soundCache.notificationlow = sfx:FindFirstChild("NotificationLow")
		soundCache.notificationmid = sfx:FindFirstChild("NotificationMid")
		soundCache.purchase = sfx:FindFirstChild("Purchase")
		soundCache.victory = sfx:FindFirstChild("Victory")
		soundCache.error = sfx:FindFirstChild("Error")
	end
end

-- Initialize sound cache
task.spawn(cacheSounds)

local function playSound(soundName)
	local key = string.lower(tostring(soundName or ""))
	local sound = soundCache[key]
	if sound then
		sound:Play()
	end
end

function UIEffects.PlaySound(soundName)
	playSound(soundName)
end

local function tweenObjectSize(object, targetSize, tweenInfo)
	TweenService:Create(object, tweenInfo, { Size = targetSize }):Play()
end

local function hoverEffect(button)
	-- Cache the original size
	local originalSize = button.Size
	buttonSizeCache[button] = originalSize

	local hoverSize = UDim2.new(
		originalSize.X.Scale * 1.03,
		originalSize.X.Offset,
		originalSize.Y.Scale * 1.03,
		originalSize.Y.Offset
	)

	button.MouseEnter:Connect(function()
		playSound("Hover")

		-- Skip size animation if "Size" attribute is false
		if button:GetAttribute("Size") == false then
			return
		end

		tweenObjectSize(button, hoverSize, TWEEN_INFO_CACHE.hover)
	end)

	button.MouseLeave:Connect(function()
		if button:GetAttribute("Size") ~= false then
			-- Use cached original size
			local cachedSize = buttonSizeCache[button] or originalSize
			tweenObjectSize(button, cachedSize, TWEEN_INFO_CACHE.hover)
		end
	end)
end

local function clickEffect(button)
	local originalSize = buttonSizeCache[button] or button.Size
	local shrinkSize = UDim2.new(
		originalSize.X.Scale * 0.94,
		originalSize.X.Offset,
		originalSize.Y.Scale * 0.94,
		originalSize.Y.Offset
	)

	button.MouseButton1Click:Connect(function()
		playSound("Button")

		-- Skip size animation if "Size" attribute is false
		if button:GetAttribute("Size") == false then
			return
		end

		tweenObjectSize(button, shrinkSize, TWEEN_INFO_CACHE.click)
		task.delay(0.1, function()
			local cachedSize = buttonSizeCache[button] or originalSize
			tweenObjectSize(button, cachedSize, TWEEN_INFO_CACHE.click)
		end)
	end)
end

local function shineEffect(button)
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.Size = UDim2.new(0.2, 0, 1, 0)
	shine.BackgroundTransparency = 0.8
	shine.BorderSizePixel = 0
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.new(-0.5, 0, 0.5, 0)
	shine.ZIndex = button.ZIndex + 1
	shine.Parent = button

	local function playShine()
		-- Reset position before tweening
		shine.Position = UDim2.new(-0.5, 0, 0.5, 0)

		local tween = TweenService:Create(shine, TWEEN_INFO_CACHE.shine, { Position = UDim2.new(1.5, 0, 0.5, 0) })
		tween:Play()
	end

	button.MouseEnter:Connect(playShine)
end

local function cleanupStroke(button)
	local existingStroke = activeStrokes[button]
	if existingStroke then
		existingStroke:Destroy()
		activeStrokes[button] = nil
	end
end

local function outerEffect(button)
	if not stroke then
		warn("[UIEffects] OuterStroke template not found in script")
		return
	end

	button.MouseEnter:Connect(function()
		-- Clean up any existing stroke on this button
		cleanupStroke(button)

		-- Create new stroke
		local newStroke = stroke:Clone()
		newStroke.Transparency = 0.3
		newStroke.Parent = button

		-- Store reference for cleanup
		activeStrokes[button] = newStroke
	end)

	button.MouseLeave:Connect(function()
		-- Destroy the stroke when mouse leaves
		cleanupStroke(button)
	end)

	-- Clean up stroke if button is destroyed
	button.Destroying:Connect(function()
		cleanupStroke(button)
		buttonSizeCache[button] = nil
	end)
end

function UIEffects.Init(button)
	if not button or not button:IsA("GuiButton") then
		return
	end

	hoverEffect(button)
	clickEffect(button)

	local effectType = button:GetAttribute("EffectType")
	if effectType == "Shine" then
		shineEffect(button)
	elseif effectType == "Outer" then
		outerEffect(button)
	end
end

function UIEffects.ApplyToAll(container)
	if not container then
		warn("[UIEffects] ApplyToAll called with nil container")
		return
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			UIEffects.Init(descendant)
		end
	end
end

-- Cleanup function to remove all active strokes
function UIEffects.Cleanup()
	for button, strokeInstance in pairs(activeStrokes) do
		if strokeInstance then
			strokeInstance:Destroy()
		end
	end
	activeStrokes = {}
	buttonSizeCache = {}
end

return UIEffects
