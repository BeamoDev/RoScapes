local TweenService = game:GetService("TweenService")

local IntroLoader = {}

local function waitForGuiObject(parent, childName, timeoutSeconds)
	local deadline = tick() + math.max(0.1, tonumber(timeoutSeconds) or 10)
	local found = parent and parent:FindFirstChild(childName)
	while not found and tick() < deadline do
		task.wait(0.1)
		found = parent and parent:FindFirstChild(childName)
	end
	return found
end

function IntroLoader.Create(guiParent)
	local groupIntro = waitForGuiObject(guiParent, "GroupIntro", 8)
	if not groupIntro then
		return {
			BeginLoading = function() end,
			SetProgress = function() end,
			Finish = function() end,
			WaitForSequence = function() end,
		}
	end

	local frame = waitForGuiObject(groupIntro, "Frame", 5)
	if not frame then
		return {
			BeginLoading = function() end,
			SetProgress = function() end,
			Finish = function()
				if groupIntro:IsA("ScreenGui") then
					groupIntro.Enabled = false
				elseif groupIntro:IsA("GuiObject") then
					groupIntro.Visible = false
				end
			end,
			WaitForSequence = function() end,
		}
	end

	local barTrack = waitForGuiObject(frame, "Frame", 5)
	local fillBar = barTrack and waitForGuiObject(barTrack, "Fill", 5)
	local status = waitForGuiObject(frame, "Status", 5)
	if not (barTrack and fillBar and status) then
		return {
			BeginLoading = function() end,
			SetProgress = function(_, _, text)
				if status and text then
					status.Text = text
				end
			end,
			Finish = function()
				if groupIntro:IsA("ScreenGui") then
					groupIntro.Enabled = false
				elseif groupIntro:IsA("GuiObject") then
					groupIntro.Visible = false
				end
			end,
			WaitForSequence = function() end,
		}
	end
	local icon = frame:FindFirstChild("Icon")
	local roScapesIcon = frame:FindFirstChild("RoScapesIcon")
	local groupIcon = frame:FindFirstChild("GroupIcon")
	local started = false
	local hasShownGroupIcon = false
	local sequenceReadyAt = 0
	local ROSCAPES_HOLD_TIME = 0.55
	local GROUP_HOLD_TIME = 0.72
	local BAR_FADE_IN_DELAY = 0.7

	local function playIconBounce(iconObject, fadeTo, autoPlay)
		if not iconObject or not iconObject:IsA("ImageLabel") then
			return nil
		end
		local baseSize = iconObject.Size
		local growSize = UDim2.new(
			baseSize.X.Scale,
			baseSize.X.Offset + 12,
			baseSize.Y.Scale,
			baseSize.Y.Offset + 12
		)
		local shrinkSize = UDim2.new(
			baseSize.X.Scale,
			math.max(0, baseSize.X.Offset - 4),
			baseSize.Y.Scale,
			math.max(0, baseSize.Y.Offset - 4)
		)
		iconObject.Size = shrinkSize
		local bounceOut = TweenService:Create(iconObject, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = growSize,
			ImageTransparency = fadeTo,
		})
		local settle = TweenService:Create(iconObject, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = baseSize,
		})
		if autoPlay ~= false then
			bounceOut:Play()
		end
		bounceOut.Completed:Connect(function()
			if iconObject and iconObject.Parent then
				settle:Play()
			end
		end)
		return bounceOut
	end

	local function swapIcons(showRoScapes)
		if showRoScapes then
			if groupIcon and groupIcon:IsA("ImageLabel") then
				playIconBounce(groupIcon, 1)
			end
			if roScapesIcon and roScapesIcon:IsA("ImageLabel") then
				playIconBounce(roScapesIcon, 0)
			end
		else
			hasShownGroupIcon = true
			if roScapesIcon and roScapesIcon:IsA("ImageLabel") then
				playIconBounce(roScapesIcon, 1)
			end
			if groupIcon and groupIcon:IsA("ImageLabel") then
				playIconBounce(groupIcon, 0)
			end
		end
	end

	if groupIntro:IsA("ScreenGui") then
		groupIntro.Enabled = true
	end
	if groupIntro:IsA("GuiObject") then
		groupIntro.Visible = true
	end

	fillBar.Size = UDim2.new(0, 0, fillBar.Size.Y.Scale, fillBar.Size.Y.Offset)
	barTrack.BackgroundTransparency = 1
	fillBar.BackgroundTransparency = 1
	status.TextTransparency = 1
	status.Text = "Starting..."
	if icon and icon:IsA("ImageLabel") then
		icon.ImageTransparency = 0
	end
	if roScapesIcon and roScapesIcon:IsA("ImageLabel") then
		roScapesIcon.ImageTransparency = 0
	end
	if groupIcon and groupIcon:IsA("ImageLabel") then
		groupIcon.ImageTransparency = 1
	end

	local currentProgress = 0

	local function beginLoading()
		if started then
			return
		end
		started = true
		sequenceReadyAt = os.clock() + ROSCAPES_HOLD_TIME + GROUP_HOLD_TIME + 0.4

		task.delay(ROSCAPES_HOLD_TIME, function()
			if not frame.Parent or not started then
				return
			end
			swapIcons(false)
		end)

		task.delay(BAR_FADE_IN_DELAY, function()
			if not frame.Parent then
				return
			end
			TweenService:Create(barTrack, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				BackgroundTransparency = 0,
			}):Play()
			TweenService:Create(fillBar, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				BackgroundTransparency = 0,
			}):Play()
			TweenService:Create(status, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				TextTransparency = 0,
			}):Play()
		end)

		task.delay(ROSCAPES_HOLD_TIME + GROUP_HOLD_TIME, function()
			if not frame.Parent or not started then
				return
			end
			swapIcons(true)
		end)
	end

	local function setProgress(value, text)
		if not started then
			beginLoading()
		end
		local target = math.clamp(value, 0, 1)
		if target < currentProgress then
			target = currentProgress
		end
		currentProgress = target
		if text then
			status.Text = text
		end

		TweenService:Create(fillBar, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(target, 0, fillBar.Size.Y.Scale, fillBar.Size.Y.Offset),
		}):Play()
	end

	local function playFadeOut()
		local fadeTweens = {
			TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 1,
			}),
			TweenService:Create(barTrack, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 1,
			}),
			TweenService:Create(fillBar, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 1,
			}),
			TweenService:Create(status, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				TextTransparency = 1,
			}),
		}
		if groupIntro:IsA("GuiObject") then
			table.insert(fadeTweens, TweenService:Create(groupIntro, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 1,
			}))
		end
		if icon and icon:IsA("ImageLabel") then
			table.insert(fadeTweens, TweenService:Create(icon, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				ImageTransparency = 1,
			}))
		end
		if roScapesIcon and roScapesIcon:IsA("ImageLabel") then
			local tween = playIconBounce(roScapesIcon, 1, false)
			if tween then
				table.insert(fadeTweens, tween)
			end
		end
		if groupIcon and groupIcon:IsA("ImageLabel") then
			local tween = playIconBounce(groupIcon, 1, false)
			if tween then
				table.insert(fadeTweens, tween)
			end
		end

		for _, tw in ipairs(fadeTweens) do
			tw:Play()
		end

		task.delay(0.4, function()
			if groupIntro:IsA("ScreenGui") then
				groupIntro.Enabled = false
			elseif groupIntro:IsA("GuiObject") then
				groupIntro.Visible = false
			end
		end)
	end

	local function finish()
		if started and not hasShownGroupIcon and frame.Parent then
			swapIcons(false)
			task.delay(0.16, function()
				if not frame.Parent then
					return
				end
				swapIcons(true)
				task.delay(0.16, function()
					if frame.Parent then
						playFadeOut()
					end
				end)
			end)
			return
		end

		playFadeOut()
	end

	return {
		BeginLoading = beginLoading,
		SetProgress = setProgress,
		Finish = finish,
		WaitForSequence = function()
			local remaining = sequenceReadyAt - os.clock()
			if remaining > 0 then
				task.wait(remaining)
			end
		end,
	}
end

return IntroLoader
