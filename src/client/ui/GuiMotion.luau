local TweenService = game:GetService("TweenService")

local GuiMotion = {}
local activeByRoot = setmetatable({}, { __mode = "k" })
local flowByRoot = setmetatable({}, { __mode = "k" })
local flowBaseByNode = setmetatable({}, { __mode = "k" })
local scaleBaseByTarget = setmetatable({}, { __mode = "k" })

local OPEN_INFO = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local CLOSED_SCALE = 0.9
local FLOW_DURATION = 0.42
local FLOW_STAGGER = 0.045

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
	local scale = target:FindFirstChild("RoScapesMotionScale") or target:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "RoScapesMotionScale"
		scale.Scale = 1
		scale.Parent = target
	end
	if scaleBaseByTarget[target] == nil then
		scaleBaseByTarget[target] = scale.Scale
	end
	return scale
end

local function getScaleBase(target)
	getScale(target)
	return scaleBaseByTarget[target] or 1
end

local function cancelFlow(root)
	local active = flowByRoot[root]
	if not active then
		return
	end
	active.cancelled = true
	for _, tween in ipairs(active.tweens) do
		tween:Cancel()
	end
	flowByRoot[root] = nil
end

local function isFlowBackdrop(node)
	local name = string.lower(node.Name)
	return string.find(name, "background", 1, true) ~= nil
		or string.find(name, "scenary", 1, true) ~= nil
		or string.find(name, "scenery", 1, true) ~= nil
		or string.find(name, "pattern", 1, true) ~= nil
		or node:GetAttribute("SkipScreenFlow") == true
end

local function getFlowNodes(root)
	local nodes = {}
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible and not isFlowBackdrop(child) then
			table.insert(nodes, child)
		end
	end
	table.sort(nodes, function(a, b)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		if a.Position.Y.Scale ~= b.Position.Y.Scale then
			return a.Position.Y.Scale < b.Position.Y.Scale
		end
		return a.Name < b.Name
	end)
	return nodes
end

local function getFlowBase(node)
	local base = flowBaseByNode[node]
	if base then
		return base
	end
	local scale = getScale(node)
	base = {
		position = node.Position,
		scale = scale,
		scaleValue = getScaleBase(node),
	}
	flowBaseByNode[node] = base
	return base
end

local function getFlowPose(node, base)
	local x = base.position.X.Scale
	local y = base.position.Y.Scale
	local dx = x < 0.34 and -0.1 or (x > 0.66 and 0.1 or 0)
	local dy = y < 0.4 and -0.075 or (y > 0.62 and 0.1 or 0.065)
	local scaleFactor = node:IsA("GuiButton") and 0.72 or 0.82
	return base.position + UDim2.fromScale(dx, dy), base.scaleValue * scaleFactor
end

local function flow(root, showing, onComplete)
	if not (root and root:IsA("GuiObject")) then
		if onComplete then
			onComplete()
		end
		return
	end
	cancelActive(root)
	cancelFlow(root)
	local nodes = getFlowNodes(root)
	if #nodes == 0 then
		if showing then
			GuiMotion.Show(root)
		else
			GuiMotion.Hide(root, nil, onComplete)
		end
		return
	end
	local wasVisible = root.Visible
	root.Visible = true
	local active = { tweens = {}, cancelled = false }
	flowByRoot[root] = active
	local maxDelay = 0
	for index, node in ipairs(nodes) do
		local base = getFlowBase(node)
		local hiddenPosition, hiddenScale = getFlowPose(node, base)
		if showing and not wasVisible then
			node.Position = hiddenPosition
			base.scale.Scale = hiddenScale
		end
		local order = showing and index or (#nodes - index + 1)
		local delay = (order - 1) * FLOW_STAGGER
		maxDelay = math.max(maxDelay, delay)
		local direction = showing and Enum.EasingDirection.Out or Enum.EasingDirection.In
		local positionTween = TweenService:Create(
			node,
			TweenInfo.new(FLOW_DURATION, Enum.EasingStyle.Quint, direction, 0, false, delay),
			{
				Position = showing and base.position or hiddenPosition,
			}
		)
		local scaleTween = TweenService:Create(
			base.scale,
			TweenInfo.new(FLOW_DURATION, Enum.EasingStyle.Back, direction, 0, false, delay),
			{
				Scale = showing and base.scaleValue or hiddenScale,
			}
		)
		table.insert(active.tweens, positionTween)
		table.insert(active.tweens, scaleTween)
		positionTween:Play()
		scaleTween:Play()
	end
	task.delay(FLOW_DURATION + maxDelay + 0.03, function()
		if flowByRoot[root] ~= active or active.cancelled then
			return
		end
		flowByRoot[root] = nil
		if not showing then
			root.Visible = false
			for _, node in ipairs(nodes) do
				local base = flowBaseByNode[node]
				if base and node.Parent then
					node.Position = base.position
					base.scale.Scale = base.scaleValue
				end
			end
		end
		if onComplete then
			onComplete()
		end
	end)
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
	local baseScale = getScaleBase(target)
	if not wasVisible then
		scale.Scale = baseScale * CLOSED_SCALE
		if target:IsA("CanvasGroup") then
			target.GroupTransparency = 1
		end
	end
	play(root, target, OPEN_INFO, baseScale, 0)
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
	local baseScale = getScaleBase(target)
	play(root, target, CLOSE_INFO, baseScale * CLOSED_SCALE, 1, function()
		root.Visible = false
		getScale(target).Scale = baseScale
		if target:IsA("CanvasGroup") then
			target.GroupTransparency = 0
		end
		if onComplete then
			onComplete()
		end
	end)
end

function GuiMotion.ShowFlow(root)
	flow(root, true)
end

function GuiMotion.HideFlow(root, onComplete)
	flow(root, false, onComplete)
end

return GuiMotion
