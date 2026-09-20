local TweenService = game:GetService("TweenService")

local GuiMotion = {}
local activeByRoot = setmetatable({}, { __mode = "k" })

local OPEN_INFO = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local CLOSED_SCALE = 0.9

local function cancelActive(root)
	local active = activeByRoot[root]
	if not active then
		return
	end
	for _, tween in ipairs(active) do
		tween:Cancel()
	end
	activeByRoot[root] = nil
end

local function getScale(target)
	local scale = target:FindFirstChild("RoScapesMotionScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "RoScapesMotionScale"
		scale.Scale = 1
		scale.Parent = target
	end
	return scale
end

local function play(root, target, info, scaleValue, transparencyValue, onComplete)
	cancelActive(root)
	local tweens = {}
	local scaleTween = TweenService:Create(getScale(target), info, { Scale = scaleValue })
	table.insert(tweens, scaleTween)
	if target:IsA("CanvasGroup") then
		local fadeTween = TweenService:Create(target, info, { GroupTransparency = transparencyValue })
		table.insert(tweens, fadeTween)
	end
	activeByRoot[root] = tweens
	for _, tween in ipairs(tweens) do
		tween:Play()
	end
	scaleTween.Completed:Connect(function(playbackState)
		if activeByRoot[root] ~= tweens then
			return
		end
		activeByRoot[root] = nil
		if playbackState == Enum.PlaybackState.Completed and onComplete then
			onComplete()
		end
	end)
end

function GuiMotion.Show(root, target)
	if not (root and root:IsA("GuiObject")) then
		return
	end
	target = (target and target:IsA("GuiObject")) and target or root
	local wasVisible = root.Visible
	root.Visible = true
	target.Visible = true
	local scale = getScale(target)
	if not wasVisible then
		scale.Scale = CLOSED_SCALE
		if target:IsA("CanvasGroup") then
			target.GroupTransparency = 1
		end
	end
	play(root, target, OPEN_INFO, 1, 0)
end

function GuiMotion.Hide(root, target, onComplete)
	if not (root and root:IsA("GuiObject")) then
		if onComplete then
			onComplete()
		end
		return
	end
	if not root.Visible then
		if onComplete then
			onComplete()
		end
		return
	end
	target = (target and target:IsA("GuiObject")) and target or root
	play(root, target, CLOSE_INFO, CLOSED_SCALE, 1, function()
		root.Visible = false
		getScale(target).Scale = 1
		if target:IsA("CanvasGroup") then
			target.GroupTransparency = 0
		end
		if onComplete then
			onComplete()
		end
	end)
end

return GuiMotion
