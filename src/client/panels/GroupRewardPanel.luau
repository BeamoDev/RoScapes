local TweenService = game:GetService("TweenService")
local GroupService = game:GetService("GroupService")
local GuiMotion = require(script.Parent.Parent.ui.GuiMotion)

local GroupRewardPanel = {}

local state = {
	player = nil,
	playerData = nil,
	frames = nil,
	UIManager = nil,
	RemoteRegistry = nil,
	groupId = 34241464,
	claimed = false,
	shown = false,
	shakeToken = 0,
	promptBound = false,
	onCoinsUpdated = nil,
	closeOtherPanels = nil,
	isTutorialActive = nil,
	joinPollToken = 0,
}

local function ensurePanel()
	local frames = state.frames
	if not frames then
		return nil
	end
	local panel = frames:FindFirstChild("GroupReward")
	if panel and panel:IsA("Frame") then
		return panel
	end
	return nil
end

local function hidePanel(panel)
	local inner = panel and panel:FindFirstChild("Frame")
	GuiMotion.Hide(panel, (inner and inner:IsA("GuiObject")) and inner or panel)
end

local function showPanel(panel)
	local inner = panel and panel:FindFirstChild("Frame")
	GuiMotion.Show(panel, (inner and inner:IsA("GuiObject")) and inner or panel)
end

local function isClaimed()
	return state.claimed or (state.playerData and state.playerData.groupRewardClaimed) == true
end

local function isPlayerInGroup()
	if not state.player then
		return false
	end
	local ok, inGroup = pcall(function()
		return state.player:IsInGroup(state.groupId)
	end)
	return ok and inGroup == true
end

local function startGiftShake(giftBox)
	state.shakeToken += 1
	local token = state.shakeToken
	if not giftBox or not giftBox:IsA("GuiObject") then
		return
	end
	giftBox.Rotation = 0
	task.spawn(function()
		while state.shakeToken == token and giftBox.Parent and giftBox.Visible do
			task.wait(math.random(55, 95) / 100)
			if not (state.shakeToken == token and giftBox.Parent and giftBox.Visible) then
				break
			end
			for _, angle in ipairs({ -7, 7, -5, 5, 0 }) do
				if not (state.shakeToken == token and giftBox.Parent and giftBox.Visible) then
					break
				end
				local tween = TweenService:Create(giftBox, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Rotation = angle,
				})
				tween:Play()
				tween.Completed:Wait()
			end
		end
		if giftBox and giftBox.Parent then
			giftBox.Rotation = 0
		end
	end)
end

local function tryClaim(joinedViaPrompt)
	local resp = state.RemoteRegistry:GetFunction("ClaimGroupReward"):InvokeServer(joinedViaPrompt == true)
	if resp and resp.success then
		state.playerData.groupRewardClaimed = true
		state.claimed = true
		if state.onCoinsUpdated then
			state.onCoinsUpdated(resp.coins or 0)
		end
		state.playerData.hints = tonumber(resp.hints) or state.playerData.hints or 0
		local panel = ensurePanel()
		if panel then
			hidePanel(panel)
			state.shakeToken += 1
		end
		state.UIManager:ShowAlert("Group reward given", "success")
		return true
	end
	return false
end

local function startGroupJoinVerificationPoll()
	state.joinPollToken += 1
	local token = state.joinPollToken
	task.spawn(function()
		for _ = 1, 8 do
			if state.joinPollToken ~= token or state.playerData.groupRewardClaimed then
				return
			end
			local ok, inGroup = pcall(function()
				return state.player and state.player:IsInGroup(state.groupId)
			end)
			if ok and inGroup then
				tryClaim(true)
				return
			end
			task.wait(1)
		end
	end)
end

function GroupRewardPanel.Init(options)
	state.player = options.player
	state.playerData = options.playerData
	state.frames = options.frames
	state.UIManager = options.UIManager
	state.RemoteRegistry = options.RemoteRegistry
	state.groupId = tonumber(options.groupId) or 34241464
	state.claimed = options.playerData and options.playerData.groupRewardClaimed == true
	state.shown = false
	state.shakeToken = 0
	state.promptBound = false
	state.onCoinsUpdated = options.onCoinsUpdated
	state.closeOtherPanels = options.closeOtherPanels
	state.isTutorialActive = options.isTutorialActive
	state.joinPollToken = 0
end

function GroupRewardPanel.Open(forceShow)
	if (not forceShow) and isClaimed() then
		return
	end
	local panel = ensurePanel()
	if not panel then
		return
	end
	if state.closeOtherPanels then
		state.closeOtherPanels(panel)
	end
	local frame = panel:FindFirstChild("Frame") or panel
	local giftBox = frame:FindFirstChild("GiftBox", true)
	local claimBtn = frame:FindFirstChild("Claim", true)
	local closeBtn = frame:FindFirstChild("Close", true)

	if not panel:GetAttribute("Wired") then
		panel:SetAttribute("Wired", true)
		if closeBtn and closeBtn:IsA("GuiButton") then
			closeBtn.MouseButton1Click:Connect(function()
				hidePanel(panel)
				state.shakeToken += 1
			end)
		end
		if claimBtn and claimBtn:IsA("GuiButton") then
			claimBtn.MouseButton1Click:Connect(function()
				if not state.promptBound then
					state.promptBound = true
					pcall(function()
						GroupService.PromptJoinCompleted:Connect(function(groupId, success, membershipStatus)
							if tonumber(groupId) ~= tonumber(state.groupId) then
								return
							end
							local joined = success == true
							if not joined then
								local statusText = string.lower(tostring(membershipStatus or ""))
								joined = statusText:find("ingroup", 1, true) ~= nil
							end
							if joined then
								tryClaim(true)
							end
						end)
					end)
				end

				local usedShowJoinPrompt = pcall(function()
					GroupService:ShowJoinPrompt(state.groupId)
				end)
				if not usedShowJoinPrompt then
					task.spawn(function()
						local ok, membershipStatus = pcall(function()
							return GroupService:PromptJoinAsync(state.groupId)
						end)
						if ok then
							local statusText = string.lower(tostring(membershipStatus or ""))
							if statusText:find("ingroup", 1, true) ~= nil then
								tryClaim(true)
							end
						end
					end)
				else
					startGroupJoinVerificationPoll()
				end
			end)
		end
	end

	showPanel(panel)
	if frame ~= panel and frame:IsA("GuiObject") then
		frame.Visible = true
	end
	startGiftShake(giftBox)
end

function GroupRewardPanel.Schedule(delaySeconds, forceShow)
	if (not forceShow) and (state.shown or isClaimed() or isPlayerInGroup()) then
		return
	end
	state.shown = true

	local function tryOpen()
		if (not forceShow) and (isClaimed() or isPlayerInGroup()) then
			return
		end
		if state.isTutorialActive and state.isTutorialActive() then
			task.delay(1.5, tryOpen)
			return
		end
		GroupRewardPanel.Open(forceShow)
	end

	task.delay(math.max(0, tonumber(delaySeconds) or 0), tryOpen)
end

return GroupRewardPanel
