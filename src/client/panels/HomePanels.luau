local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local UIEffects = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("util"):WaitForChild("UIEffects"))
local CoinCounter = require(script.Parent.Parent.ui.CoinCounter)
local GuiMotion = require(script.Parent.Parent.ui.GuiMotion)

local HomePanels = {}

local state = {
	player = nil,
	playerData = nil,
	frames = nil,
	UIManager = nil,
	RemoteRegistry = nil,
	MonetizationConfig = nil,
	MarketplaceService = nil,
	TweenService = nil,
	dayStampNow = nil,
	formatHMS = nil,
	setHomeNotificationFlag = nil,
	onCoinsUpdated = nil,
	rewardsFrame = nil,
	shopFrame = nil,
	achievementsFrame = nil,
	settingsFrame = nil,
	profileFrame = nil,
	generalInfoFrame = nil,
	rewardsRefreshThreadId = 0,
	profilePlaytimeThreadId = 0,
	shopPulseThreadId = 0,
	profileRows = {},
	profileLastValues = {},
	generalInfoState = {
		onAccept = nil,
		onClose = nil,
	},
	lastAchievementUnlockedSeen = nil,
	cachedDailyRewardInfo = nil,
	cachedAchievementsBoard = nil,
	originalSfxVolumes = nil,
}

local MUSIC_SOUND_IDS = {
	"rbxassetid://98673697584976",
	"rbxassetid://113059501528347",
	"rbxassetid://101394825740085",
}

local musicState = {
	sound = nil,
	playlistThread = 0,
}

local function silenceLegacyWorkspaceMusic()
	local scriptsFolder = Workspace:FindFirstChild("Scripts")
	local legacySound = scriptsFolder and scriptsFolder:FindFirstChild("PlayerVolume")
	if legacySound and legacySound:IsA("Sound") then
		legacySound.Volume = 0
	end
end

local function ensureMusicSound()
	if musicState.sound and musicState.sound.Parent then
		return musicState.sound
	end
	local existing = SoundService:FindFirstChild("PlayerVolume")
	if existing and existing:IsA("Sound") then
		musicState.sound = existing
	else
		local sound = Instance.new("Sound")
		sound.Name = "PlayerVolume"
		sound.Archivable = false
		sound.Parent = SoundService
		sound.Looped = false
		sound.PlaybackSpeed = 0.95
		sound.Volume = 0.4
		musicState.sound = sound
	end
	return musicState.sound
end

local function ensureMusicLoop()
	local sound = ensureMusicSound()
	if not sound then
		return
	end
	if musicState.playlistThread ~= 0 then
		return
	end
	musicState.playlistThread = 1
	task.spawn(function()
		local token = musicState.playlistThread
		local index = 1
		while musicState.playlistThread == token do
			if state.playerData and state.playerData.musicEnabled == false then
				task.wait(0.25)
				continue
			end
			local liveSound = ensureMusicSound()
			if not liveSound then
				task.wait(1)
				continue
			end
			liveSound.SoundId = MUSIC_SOUND_IDS[index]
			if state.playerData and state.playerData.musicEnabled == false then
				liveSound.Volume = 0
			else
				liveSound.Volume = 0.4
			end
			liveSound:Play()
			local finished = false
			local conn
			conn = liveSound.Ended:Connect(function()
				finished = true
			end)
			local timeoutAt = os.clock() + 360
			while musicState.playlistThread == token and liveSound.Parent and liveSound.IsPlaying and not finished and os.clock() < timeoutAt do
				task.wait(0.25)
			end
			if conn then
				conn:Disconnect()
			end
			if musicState.playlistThread ~= token then
				break
			end
			if state.playerData and state.playerData.musicEnabled == false then
				task.wait(0.25)
				continue
			end
			index += 1
			if index > #MUSIC_SOUND_IDS then
				index = 1
			end
			task.wait(0.05)
		end
	end)
end

local function ensureOriginalSfxVolumes()
	if state.originalSfxVolumes then
		return
	end
	state.originalSfxVolumes = {}
	local sfxFolder = SoundService:FindFirstChild("SFX")
	if not sfxFolder then
		return
	end
	for _, descendant in ipairs(sfxFolder:GetDescendants()) do
		if descendant:IsA("Sound") then
			state.originalSfxVolumes[descendant] = descendant.Volume
		end
	end
end

local function applySfxEnabled(enabled)
	ensureOriginalSfxVolumes()
	local sfxFolder = SoundService:FindFirstChild("SFX")
	if not sfxFolder then
		return
	end
	for _, descendant in ipairs(sfxFolder:GetDescendants()) do
		if descendant:IsA("Sound") then
			if state.originalSfxVolumes[descendant] == nil then
				state.originalSfxVolumes[descendant] = descendant.Volume
			end
			descendant.Volume = enabled and (state.originalSfxVolumes[descendant] or descendant.Volume) or 0
		end
	end
end

local function applyMusicEnabled(enabled)
	silenceLegacyWorkspaceMusic()
	local sound = ensureMusicSound()
	if sound then
		sound.Volume = enabled and 0.4 or 0
		if enabled and not sound.IsPlaying then
			sound:Play()
		elseif not enabled and sound.IsPlaying then
			sound:Pause()
		end
	end
	if enabled then
		ensureMusicLoop()
	end
end

local function ensureFrame(cacheKey, frameName, fallbackName)
	local frames = state.frames
	if not frames then
		return nil
	end
	if not state[cacheKey] then
		state[cacheKey] = frames:FindFirstChild(frameName) or (fallbackName and frames:FindFirstChild(fallbackName))
	end
	local frame = state[cacheKey]
	if frame and frame:IsA("Frame") then
		return frame
	end
	return nil
end

local function updateProfileRowValue(key, amountText)
	local row = state.profileRows[key]
	if not (row and row.Parent) then
		return
	end
	local nextValue = tostring(amountText)
	if state.profileLastValues[key] == nextValue then
		return
	end
	local amount = row:FindFirstChild("Amount", true)
	if amount and amount:IsA("TextLabel") then
		if key == "coins" then
			CoinCounter.Set(amount, tonumber(amountText) or 0)
		else
			amount.Text = nextValue
		end
	end
	state.profileLastValues[key] = nextValue
end

local function panelMotionTarget(panel)
	local inner = panel and panel:FindFirstChild("Frame")
	return (inner and inner:IsA("GuiObject")) and inner or panel
end

local function showPanel(panel)
	GuiMotion.Show(panel, panelMotionTarget(panel))
end

local function hidePanel(panel, onComplete)
	GuiMotion.Hide(panel, panelMotionTarget(panel), onComplete)
end

local function closeAllPanels(exceptPanel)
	local frames = state.frames
	if not frames then
		return
	end
	for _, child in ipairs(frames:GetChildren()) do
		if child ~= exceptPanel and child:IsA("GuiObject") then
			hidePanel(child)
		end
	end
end

local function stopShopCardPulseRuntime(panel)
	state.shopPulseThreadId += 1
	if not panel then
		return
	end
	for _, stroke in ipairs(panel:GetDescendants()) do
		if stroke:IsA("UIStroke") and stroke.Name == "ShopPulseStroke" then
			stroke.Transparency = 1
			stroke.Thickness = 0
		end
	end
	for _, scale in ipairs(panel:GetDescendants()) do
		if scale:IsA("UIScale") and scale.Name == "ShopPulseScale" then
			scale.Scale = 1
		end
	end
end

local function startShopCardPulseRuntime(panel, cards)
	if not panel then
		return
	end
	stopShopCardPulseRuntime(panel)
	state.shopPulseThreadId += 1
	local threadId = state.shopPulseThreadId
	local tweenService = state.TweenService or TweenService
	local tweenInfo = TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local settleInfo = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	task.spawn(function()
		while panel.Parent and panel.Visible and state.shopPulseThreadId == threadId do
			for _, entry in ipairs(cards) do
				if state.shopPulseThreadId ~= threadId or not panel.Visible then
					break
				end
				local card = entry.card
				if card and card.Parent and card:IsA("GuiObject") then
					local stroke = card:FindFirstChild("ShopPulseStroke")
					if not stroke then
						stroke = Instance.new("UIStroke")
						stroke.Name = "ShopPulseStroke"
						stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
						stroke.Thickness = 0
						stroke.Transparency = 1
						stroke.Parent = card
					end
					local scale = card:FindFirstChild("ShopPulseScale")
					if not scale then
						scale = Instance.new("UIScale")
						scale.Name = "ShopPulseScale"
						scale.Scale = 1
						scale.Parent = card
					end
					stroke.Color = entry.color
					stroke.Thickness = 0
					stroke.Transparency = 0.15
					scale.Scale = 1

					local strokeOut = tweenService:Create(stroke, tweenInfo, {
						Thickness = 8,
						Transparency = 1,
					})
					local scaleUp = tweenService:Create(scale, tweenInfo, {
						Scale = 1.025,
					})
					strokeOut:Play()
					scaleUp:Play()
					strokeOut.Completed:Wait()
					if state.shopPulseThreadId ~= threadId then
						break
					end
					local scaleDown = tweenService:Create(scale, settleInfo, {
						Scale = 1,
					})
					scaleDown:Play()
					scaleDown.Completed:Wait()
				end
				task.wait(0.08)
			end
			task.wait(0.25)
		end
	end)
end

function HomePanels.Init(options)
	for key, value in pairs(options or {}) do
		state[key] = value
	end
	local frames = state.frames
	local legacyCodesPanel = frames and (frames:FindFirstChild("Codes") or frames:FindFirstChild("CodesFrame"))
	if legacyCodesPanel and legacyCodesPanel:IsA("GuiObject") then
		legacyCodesPanel.Visible = false
	end
	silenceLegacyWorkspaceMusic()
	ensureMusicLoop()
	applyMusicEnabled(state.playerData and state.playerData.musicEnabled ~= false)
end

function HomePanels.SetLastAchievementUnlockedSeen(value)
	state.lastAchievementUnlockedSeen = value
end

function HomePanels.GetLastAchievementUnlockedSeen()
	return state.lastAchievementUnlockedSeen
end

function HomePanels.GetCachedDailyRewardInfo()
	return state.cachedDailyRewardInfo
end

function HomePanels.SetCachedDailyRewardInfo(info)
	state.cachedDailyRewardInfo = info
end

function HomePanels.GetCachedAchievementsBoard()
	return state.cachedAchievementsBoard
end

function HomePanels.SetCachedAchievementsBoard(board)
	state.cachedAchievementsBoard = board
end

function HomePanels.OpenGeneralInfo(titleText, subtitleText, options)
	local panel = ensureFrame("generalInfoFrame", "GeneralInfo")
	if not panel then
		state.UIManager:ShowAlert(tostring(subtitleText or titleText or ""), "bonus")
		return
	end
	closeAllPanels(panel)
	local frame = panel:FindFirstChild("Frame")
	if not frame or not frame:IsA("Frame") then
		state.UIManager:ShowAlert(tostring(subtitleText or titleText or ""), "bonus")
		return
	end
	local title = frame:FindFirstChild("Title")
	local subtitle = frame:FindFirstChild("Subtitle")
	local closeBtn = frame:FindFirstChild("Close")
	local acceptBtn = frame:FindFirstChild("Accept")
	local acceptLabel = acceptBtn and acceptBtn:FindFirstChild("Label")
	options = options or {}

	if title and title:IsA("TextLabel") then
		title.Text = tostring(titleText or "")
	end
	if subtitle and subtitle:IsA("TextLabel") then
		subtitle.Text = tostring(subtitleText or "")
	end
	if acceptBtn and acceptBtn:IsA("GuiButton") then
		acceptBtn.Visible = options.showAccept == true
		acceptBtn.Active = options.showAccept == true
		acceptBtn.AutoButtonColor = options.showAccept == true
		if options.acceptText then
			if acceptLabel and acceptLabel:IsA("TextLabel") then
				acceptLabel.Text = tostring(options.acceptText)
			else
				acceptBtn.Text = tostring(options.acceptText)
			end
		end
	end

	state.generalInfoState.onAccept = options.onAccept
	state.generalInfoState.onClose = options.onClose

	if not panel:GetAttribute("Wired") then
		panel:SetAttribute("Wired", true)
		if closeBtn and closeBtn:IsA("GuiButton") then
			closeBtn.MouseButton1Click:Connect(function()
				hidePanel(panel)
				local cb = state.generalInfoState.onClose
				state.generalInfoState.onClose = nil
				state.generalInfoState.onAccept = nil
				if cb then
					cb()
				end
			end)
		end
		if acceptBtn and acceptBtn:IsA("GuiButton") then
			acceptBtn.MouseButton1Click:Connect(function()
				hidePanel(panel)
				local cb = state.generalInfoState.onAccept
				state.generalInfoState.onClose = nil
				state.generalInfoState.onAccept = nil
				if cb then
					cb()
				end
			end)
		end
	end

	showPanel(panel)
end

function HomePanels.UpdateProfileRowValue(key, amountText)
	updateProfileRowValue(key, amountText)
end

function HomePanels.OpenDailyRewards()
	if state.setHomeNotificationFlag then
		state.setHomeNotificationFlag("daily", false)
	end
	local panel = ensureFrame("rewardsFrame", "DailyRewards", "DailyLoginFrame")
	if not panel then
		return
	end
	closeAllPanels(panel)
	local frame = panel:FindFirstChild("Frame")
	local status = frame and frame:FindFirstChild("Status")
	local nextReward = frame and frame:FindFirstChild("NextReward")
	local title = frame and frame:FindFirstChild("Title")
	local claim = frame and frame:FindFirstChild("Claim")
	local claimLabel = claim and claim:FindFirstChild("Label")
	local closeBtn = frame and frame:FindFirstChild("Close")
	local latestInfo = nil

local function stopTimedRewardPulse(button)
	if not button or not button:IsA("GuiButton") then
		return
	end
	button:SetAttribute("RewardPulseToken", nil)
	local stroke = button:FindFirstChild("TimedRewardPulseStroke")
	if stroke then
		stroke:Destroy()
	end
end

local function startTimedRewardPulse(button)
	if not button or not button:IsA("GuiButton") or button:GetAttribute("RewardPulseToken") then
		return
	end
	local token = tostring(os.clock()) .. "_" .. tostring(math.random(1000, 9999))
	button:SetAttribute("RewardPulseToken", token)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "TimedRewardPulseStroke"
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 0
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	task.spawn(function()
		local infoTween = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		while button.Parent and button:GetAttribute("RewardPulseToken") == token do
			local pulse = TweenService:Create(stroke, infoTween, {
				Thickness = 6,
				Transparency = 1,
			})
			pulse:Play()
			pulse.Completed:Wait()
			if button:GetAttribute("RewardPulseToken") ~= token then
				break
			end
			stroke.Thickness = 0
			stroke.Transparency = 0
			task.wait(0.2)
		end
		if stroke and stroke.Parent then
			stroke:Destroy()
		end
	end)
end

local function stopShopCardPulse(panel)
	state.shopPulseThreadId += 1
	if not panel then
		return
	end
	for _, stroke in ipairs(panel:GetDescendants()) do
		if stroke:IsA("UIStroke") and stroke.Name == "ShopPulseStroke" then
			stroke.Transparency = 1
			stroke.Thickness = 0
		end
	end
	for _, scale in ipairs(panel:GetDescendants()) do
		if scale:IsA("UIScale") and scale.Name == "ShopPulseScale" then
			scale.Scale = 1
		end
	end
end

local function startShopCardPulse(panel, cards)
	if not panel then
		return
	end
	stopShopCardPulse(panel)
	state.shopPulseThreadId += 1
	local threadId = state.shopPulseThreadId
	local tweenService = state.TweenService or TweenService
	local tweenInfo = TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local settleInfo = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	task.spawn(function()
		while panel.Parent and panel.Visible and state.shopPulseThreadId == threadId do
			for _, entry in ipairs(cards) do
				if state.shopPulseThreadId ~= threadId or not panel.Visible then
					break
				end
				local card = entry.card
				if card and card.Parent and card:IsA("GuiObject") then
					local stroke = card:FindFirstChild("ShopPulseStroke")
					if not stroke then
						stroke = Instance.new("UIStroke")
						stroke.Name = "ShopPulseStroke"
						stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
						stroke.Thickness = 0
						stroke.Transparency = 1
						stroke.Parent = card
					end
					local scale = card:FindFirstChild("ShopPulseScale")
					if not scale then
						scale = Instance.new("UIScale")
						scale.Name = "ShopPulseScale"
						scale.Scale = 1
						scale.Parent = card
					end
					stroke.Color = entry.color
					stroke.Thickness = 0
					stroke.Transparency = 0.15
					scale.Scale = 1

					local strokeOut = tweenService:Create(stroke, tweenInfo, {
						Thickness = 8,
						Transparency = 1,
					})
					local scaleUp = tweenService:Create(scale, tweenInfo, {
						Scale = 1.025,
					})
					strokeOut:Play()
					scaleUp:Play()
					strokeOut.Completed:Wait()
					if state.shopPulseThreadId ~= threadId then
						break
					end
					local scaleDown = tweenService:Create(scale, settleInfo, {
						Scale = 1,
					})
					scaleDown:Play()
					scaleDown.Completed:Wait()
				end
				task.wait(0.08)
			end
			task.wait(0.25)
		end
	end)
end

local function updateNextRewardText(info)
		if not nextReward or not nextReward:IsA("TextLabel") then
			return
		end
		if not info then
			nextReward.Text = "Next reward in: --:--:--"
			return
		end
		if info.canClaim then
			nextReward.Text = "Next reward in: Available now"
			return
		end
		local lastClaimDay = tonumber(info.lastClaimDay) or state.dayStampNow()
		local nextClaimUnix = (lastClaimDay + 1) * 86400
		local remaining = math.max(0, nextClaimUnix - os.time())
		nextReward.Text = "Next reward in: " .. state.formatHMS(remaining)
	end

	local function refreshRewards()
		local info = state.cachedDailyRewardInfo
		if not info then
			info = state.RemoteRegistry:GetFunction("GetDailyLoginReward"):InvokeServer()
			state.cachedDailyRewardInfo = info
		end
		latestInfo = info
		if title and title:IsA("TextLabel") then
			title.Text = "Daily Rewards"
		end
		if status and status:IsA("TextLabel") then
			status.Text = string.format(
				"You're on a %s-day streak. Today's reward is %s coins. %s",
				tostring(info.streak or 0),
				tostring(info.reward or 0),
				(info.canClaim and "Ready to claim." or "Already claimed today.")
			)
		end
		if claim and claim:IsA("TextButton") then
			claim.Active = info.canClaim == true
			claim.AutoButtonColor = info.canClaim == true
			claim.BackgroundColor3 = info.canClaim and Color3.fromRGB(35, 255, 79) or Color3.fromRGB(83, 95, 130)
			if info.canClaim then
				startTimedRewardPulse(claim)
			else
				stopTimedRewardPulse(claim)
			end
		end
		if claimLabel and claimLabel:IsA("TextLabel") then
			claimLabel.Text = info.canClaim and "Claim" or "Claimed"
		elseif claim and claim:IsA("TextButton") then
			claim.Text = info.canClaim and "Claim" or "Claimed"
		end
		updateNextRewardText(info)
	end

	if not panel:GetAttribute("Wired") then
		panel:SetAttribute("Wired", true)
		if closeBtn and closeBtn:IsA("GuiButton") then
			closeBtn.MouseButton1Click:Connect(function()
				hidePanel(panel)
				state.rewardsRefreshThreadId += 1
			end)
		end
		if claim and claim:IsA("GuiButton") then
			claim.MouseButton1Click:Connect(function()
				local resp = state.RemoteRegistry:GetFunction("ClaimDailyLoginReward"):InvokeServer()
				if resp and resp.success then
					UIEffects.PlaySound("Victory")
					state.cachedDailyRewardInfo = resp.state
					if state.onCoinsUpdated then
						state.onCoinsUpdated((resp.state and resp.state.coins) or 0)
					end
					state.UIManager:ShowAlert("Daily reward +" .. tostring(resp.reward or 0) .. " coins", "coin")
				else
					UIEffects.PlaySound("Error")
					state.UIManager:ShowAlert((resp and resp.message) or "Already claimed", "error")
				end
				if resp and resp.state then
					state.cachedDailyRewardInfo = resp.state
				end
				refreshRewards()
			end)
		end
	end

	refreshRewards()
	showPanel(panel)
	state.rewardsRefreshThreadId += 1
	local threadId = state.rewardsRefreshThreadId
	task.spawn(function()
		local secondsSincePoll = 0
		while panel and panel.Parent and panel.Visible and threadId == state.rewardsRefreshThreadId do
			task.wait(1)
			if not panel.Visible then
				break
			end
			secondsSincePoll += 1
			updateNextRewardText(latestInfo)
			if latestInfo and latestInfo.canClaim ~= true then
				local lastClaimDay = tonumber(latestInfo.lastClaimDay) or state.dayStampNow()
				local nextClaimUnix = (lastClaimDay + 1) * 86400
				if os.time() >= nextClaimUnix then
					state.cachedDailyRewardInfo = nil
					refreshRewards()
					secondsSincePoll = 0
				end
			end
		end
	end)
end

function HomePanels.OpenShop()
	local panel = ensureFrame("shopFrame", "Shop", "EffectShopFrame")
	if not panel then
		return
	end
	closeAllPanels(panel)
	local frame = panel:FindFirstChild("Frame") or panel
	local closeBtn = frame:FindFirstChild("Close", true)
	local legacyCodesButton = frame:FindFirstChild("Codes", true)
	local currencyHints = frame:FindFirstChild("CurreencyHints", true) or frame:FindFirstChild("CurrencyHints", true)

	local function resolvePurchaseButton(root)
		if not root or not root:IsA("GuiObject") then
			return nil
		end
		if root:IsA("GuiButton") and string.lower(root.Name) == "purchase" then
			return root
		end
		return root:FindFirstChild("Purchase", true)
	end

	local function findPurchaseButton(...)
		for index = 1, select("#", ...) do
			local rootName = select(index, ...)
			local root = frame:FindFirstChild(rootName, true)
			local button = resolvePurchaseButton(root)
			if button then
				return button
			end
		end
		return nil
	end

	local function promptProduct(productId)
		local resolvedId = tonumber(productId) or 0
		if resolvedId <= 0 then
			state.UIManager:ShowAlert("Set product id first", "error")
			return
		end
		state.MarketplaceService:PromptProductPurchase(state.player, resolvedId)
	end

	if legacyCodesButton and legacyCodesButton:IsA("GuiObject") then
		legacyCodesButton.Visible = false
	end
	if currencyHints and currencyHints:IsA("GuiObject") then
		currencyHints.Visible = false
	end

	local legacyHintPacks = frame:FindFirstChild("HintPacks", true)
	local quickRescueCard = frame:FindFirstChild("QuickRescue", true) or frame:FindFirstChild("CoinsSmall", true)
	local megaHintsCard = frame:FindFirstChild("MegaHints", true) or (legacyHintPacks and legacyHintPacks:FindFirstChild("Small", true))
	local superBundleCard = frame:FindFirstChild("SuperBundle", true)
	local quickRescuePurchase = findPurchaseButton("QuickRescue", "CoinsSmall")
	local megaHintsPurchase = findPurchaseButton("MegaHints")
		or resolvePurchaseButton(legacyHintPacks and legacyHintPacks:FindFirstChild("Small", true))
	local superBundlePurchase = findPurchaseButton("SuperBundle")

	if not panel:GetAttribute("Wired") then
		panel:SetAttribute("Wired", true)
		if closeBtn and closeBtn:IsA("GuiButton") then
			closeBtn.MouseButton1Click:Connect(function()
				stopShopCardPulseRuntime(panel)
				hidePanel(panel)
			end)
		end
		if quickRescuePurchase and quickRescuePurchase:IsA("GuiButton") then
			quickRescuePurchase.MouseButton1Click:Connect(function()
				promptProduct(state.MonetizationConfig.HintProducts.quickRescue and state.MonetizationConfig.HintProducts.quickRescue.id)
			end)
		end
		if megaHintsPurchase and megaHintsPurchase:IsA("GuiButton") then
			megaHintsPurchase.MouseButton1Click:Connect(function()
				promptProduct(state.MonetizationConfig.HintProducts.hints10 and state.MonetizationConfig.HintProducts.hints10.id)
			end)
		end
		if superBundlePurchase and superBundlePurchase:IsA("GuiButton") then
			superBundlePurchase.MouseButton1Click:Connect(function()
				promptProduct(state.MonetizationConfig.HintProducts.superBundle and state.MonetizationConfig.HintProducts.superBundle.id)
			end)
		end
	end

	showPanel(panel)
	if frame ~= panel and frame:IsA("GuiObject") then
		frame.Visible = true
	end
	startShopCardPulseRuntime(panel, {
		{ card = quickRescueCard, color = Color3.fromRGB(255, 92, 92) },
		{ card = megaHintsCard, color = Color3.fromRGB(111, 255, 138) },
		{ card = superBundleCard, color = Color3.fromRGB(186, 126, 255) },
	})
end

function HomePanels.OpenSettings()
	local panel = ensureFrame("settingsFrame", "Settings")
	if not panel then
		return
	end
	closeAllPanels(panel)
	local frame = panel:FindFirstChild("Frame") or panel
	local content = frame:FindFirstChild("Scroll")
	local closeBtn = frame:FindFirstChild("Close", true)
	local saveBtn = frame:FindFirstChild("Save", true)
	if not content or not content:IsA("GuiObject") then
		return
	end

	local musicRow = content:FindFirstChild("Music")
	local sfxRow = content:FindFirstChild("SFX")
	local musicToggle = musicRow and (musicRow:FindFirstChild("Togglebutton") or musicRow:FindFirstChild("Toggle"))
	local sfxToggle = sfxRow and (sfxRow:FindFirstChild("Togglebutton") or sfxRow:FindFirstChild("Toggle"))

	local function paintToggle(btn, on)
		if not btn or not btn:IsA("GuiButton") then
			return
		end
		local label = btn:FindFirstChild("Label")
		local targetColor = on and Color3.fromRGB(0, 255, 60) or Color3.fromRGB(255, 90, 90)
		local targetText = on and "On" or "Off"
		if label and label:IsA("TextLabel") then
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextTransparency = 0
			label.Text = targetText
		else
			pcall(function()
				btn.TextColor3 = Color3.fromRGB(255, 255, 255)
				btn.Text = targetText
			end)
		end
		state.TweenService:Create(btn, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = targetColor,
		}):Play()
	end

	if not panel:GetAttribute("Wired") then
		panel:SetAttribute("Wired", true)
		if closeBtn and closeBtn:IsA("GuiButton") then
			closeBtn.MouseButton1Click:Connect(function()
				hidePanel(panel)
			end)
		end
		if musicToggle and musicToggle:IsA("GuiButton") then
			musicToggle.MouseButton1Click:Connect(function()
				state.playerData.musicEnabled = not (state.playerData.musicEnabled ~= false)
				applyMusicEnabled(state.playerData.musicEnabled ~= false)
				paintToggle(musicToggle, state.playerData.musicEnabled ~= false)
			end)
		end
		if sfxToggle and sfxToggle:IsA("GuiButton") then
			sfxToggle.MouseButton1Click:Connect(function()
				state.playerData.sfxEnabled = not (state.playerData.sfxEnabled ~= false)
				applySfxEnabled(state.playerData.sfxEnabled ~= false)
				paintToggle(sfxToggle, state.playerData.sfxEnabled ~= false)
			end)
		end
	end

	if saveBtn and saveBtn:IsA("GuiObject") then
		saveBtn.Visible = false
	end
	applyMusicEnabled(state.playerData.musicEnabled ~= false)
	applySfxEnabled(state.playerData.sfxEnabled ~= false)
	paintToggle(musicToggle, state.playerData.musicEnabled ~= false)
	paintToggle(sfxToggle, state.playerData.sfxEnabled ~= false)
	showPanel(panel)
	if frame ~= panel and frame:IsA("GuiObject") then
		frame.Visible = true
	end
end

function HomePanels.OpenProfile()
	local panel = ensureFrame("profileFrame", "Profile")
	if not panel then
		return
	end
	closeAllPanels(panel)
	local frame = panel:FindFirstChild("Frame") or panel
	local status = frame:FindFirstChild("Progress", true) or frame:FindFirstChild("Status", true)
	local closeBtn = frame:FindFirstChild("Close", true)
	local refreshBtn = frame:FindFirstChild("Refresh", true)
	local scroll = frame:FindFirstChild("Scroll", true)
	local statTemplate = frame:FindFirstChild("StatTemplate", true)
	local separatorTemplate = frame:FindFirstChild("Seperator", true)
	if statTemplate and statTemplate:IsA("GuiObject") then
		statTemplate.Visible = false
		statTemplate.LayoutOrder = -1000
		if statTemplate.Parent == scroll then
			statTemplate.Parent = frame
		end
	end
	if separatorTemplate and separatorTemplate:IsA("GuiObject") then
		separatorTemplate.Visible = false
		separatorTemplate.LayoutOrder = -999
		if separatorTemplate.Parent == scroll then
			separatorTemplate.Parent = frame
		end
	end

	local sectionColors = {
		core = Color3.fromRGB(88, 146, 255),
		economy = Color3.fromRGB(255, 196, 92),
		daily = Color3.fromRGB(94, 214, 140),
		pvp = Color3.fromRGB(232, 108, 108),
		hardcore = Color3.fromRGB(190, 116, 255),
	}

	local function addProfileStat(key, layoutOrder, titleText, amountText, color)
		if not scroll or not statTemplate then
			return
		end
		local row = state.profileRows[key]
		if not row or not row.Parent then
			row = statTemplate:Clone()
			row.Name = "Stat_" .. tostring(key)
			row.Visible = true
			row.Parent = scroll
			state.profileRows[key] = row
		end
		row.LayoutOrder = layoutOrder
		row.Visible = true

		local title = row:FindFirstChild("Title", true)
		local amount = row:FindFirstChild("Amount", true)
		local highlight = row:FindFirstChild("Highlight", true)
		local nextValue = tostring(amountText)

		if title and title:IsA("TextLabel") then
			title.Text = tostring(titleText)
		end
		if amount and amount:IsA("TextLabel") and state.profileLastValues[key] ~= nextValue then
			if key == "coins" then
				CoinCounter.Set(amount, tonumber(amountText) or 0)
			else
				amount.Text = nextValue
			end
		end
		if highlight and highlight:IsA("GuiObject") then
			highlight.BackgroundColor3 = color
		end
		state.profileLastValues[key] = nextValue
	end

	local function addProfileSeparator(key, layoutOrder, titleText)
		if not scroll or not separatorTemplate then
			return
		end
		local separator = state.profileRows[key]
		if not separator or not separator.Parent then
			separator = separatorTemplate:Clone()
			separator.Name = "Separator_" .. tostring(key)
			separator.Visible = true
			separator.Parent = scroll
			state.profileRows[key] = separator
		end
		separator.Visible = true
		separator.LayoutOrder = layoutOrder
		local title = separator:FindFirstChild("Title", true)
		if title and title:IsA("TextLabel") then
			title.Text = tostring(titleText or "")
		end
	end

	local function hideUnusedProfileRows(activeKeys)
		for key, row in pairs(state.profileRows) do
			if row and row.Parent then
				row.Visible = activeKeys[key] == true
			end
		end
	end

	local function refreshProfile()
		local pStats = state.RemoteRegistry:GetFunction("GetPlayerStats"):InvokeServer() or {}
		local stats = pStats.stats or {}
		local rank = pStats.rank or {}
		local skill = pStats.skill or {}
		local activeKeys = {}
		if status and status:IsA("TextLabel") then
			status.Text = string.format(
				"Rank: %s | Skill: %d/5",
				tostring(rank.name or "Bronze 1"),
				math.clamp(math.floor(tonumber(skill.level) or tonumber(stats.skillLevel) or 1), 1, 5)
			)
		end

		local order = 1
		local function stat(key, titleText, amountText, sectionKey)
			activeKeys[key] = true
			addProfileStat(key, order, titleText, amountText, sectionColors[sectionKey] or sectionColors.core)
			order += 1
		end
		local function separator(key, titleText)
			activeKeys[key] = true
			addProfileSeparator(key, order, titleText)
			order += 1
		end

		stat("coins", "Coins", tostring(pStats.coins or 0), "economy")
		stat("hints", "Hints", tostring(pStats.hints or 0), "economy")
		separator("sep_econ_skill", "Skill")
		stat("skill_level", "Skill Level", string.format("%d / 5", math.clamp(math.floor(tonumber(skill.level) or tonumber(stats.skillLevel) or 1), 1, 5)), "core")
		stat("skill_score", "Skill Score", string.format("%.2f / 100", tonumber(skill.score) or tonumber(stats.skillScore) or 0), "core")
		stat("skill_recent_levels", "Recent Levels Rated", tostring(tonumber(skill.recentLevelsTracked) or 0), "core")
		stat("avg_solve_time", "Avg Solve Time", string.format("%.2fs", tonumber(stats.averageSolveTimeSeconds) or 0), "core")
		stat("avg_guesses", "Avg Guesses", string.format("%.2f", tonumber(stats.averageGuessesPerLevel) or 0), "core")
		stat("avg_wrong_guesses", "Avg Wrong Guesses", string.format("%.2f", tonumber(stats.averageWrongGuessesPerLevel) or 0), "core")
		stat("avg_bonus_words", "Avg Bonus Words", string.format("%.2f", tonumber(stats.averageBonusWordsPerLevel) or 0), "core")
		separator("sep_skill_core", "Core")
		stat("playtime", "Playtime", state.formatHMS(tonumber(stats.totalPlaytimeSeconds) or 0), "core")
		stat("levels_solved", "Levels Solved", tostring(pStats.solved or 0), "core")
		stat("levels_completed", "Levels Completed", tostring(stats.totalLevelsCompleted or 0), "core")
		stat("fastest_solve", "Fastest Solve", string.format("%.2fs", tonumber(stats.fastestSolveSeconds) or 0), "core")
		stat("words_found", "Words Found", tostring(stats.totalWordsFound or 0), "core")
		stat("bonus_words", "Bonus Words", tostring(stats.totalBonusWords or 0), "core")
		stat("total_guesses", "Total Guesses", tostring(stats.totalGuessesTaken or 0), "core")
		stat("total_wrong_guesses", "Total Wrong Guesses", tostring(stats.totalWrongGuesses or 0), "core")
		stat("best_freeplay_streak", "Best Freeplay Streak", tostring(stats.highestFreeplayStreak or 0), "core")
		stat("perfect_clears", "Perfect Clears", tostring(stats.perfectClearCount or 0), "core")
		separator("sep_core_timed", "Timed")
		stat("timed_played", "Timed Modes Played", tostring(stats.timedModesPlayed or 0), "daily")
		stat("timed_high_score", "Highest Timed Score", tostring(stats.highestTimedScore or 0), "daily")
		separator("sep_timed_pvp", "1v1")
		stat("wins", "Wins", tostring(stats.pvpWins or 0), "pvp")
		stat("losses", "Losses", tostring(stats.pvpLosses or 0), "pvp")
		stat("matches", "Matches", tostring(stats.pvpMatchesPlayed or 0), "pvp")
		stat("current_pvp_streak", "Current PvP Streak", tostring(stats.pvpCurrentStreak or 0), "pvp")
		stat("best_pvp_streak", "Best PvP Streak", tostring(stats.pvpBestStreak or 0), "pvp")
		separator("sep_pvp_hardcore", "Hardcore")
		stat("hardcore_best", "Hardcore Best", tostring(stats.hardcoreBestStreak or 0), "hardcore")
		stat("hardcore_runs", "Hardcore Runs", tostring(stats.hardcoreRuns or 0), "hardcore")
		separator("sep_hardcore_econ", "Economy")
		stat("hints_used", "Hints Used", tostring(stats.totalHintsUsed or 0), "economy")
		stat("coins_earned", "Coins Earned", tostring(stats.totalCoinsEarned or 0), "economy")
		stat("coins_spent", "Coins Spent", tostring(stats.totalCoinsSpent or 0), "economy")
		hideUnusedProfileRows(activeKeys)

		local playtimeBase = tonumber(stats.totalPlaytimeSeconds) or 0
		state.profilePlaytimeThreadId += 1
		local playtimeThreadId = state.profilePlaytimeThreadId
		local openedAt = os.clock()
		task.spawn(function()
			while panel and panel.Parent and panel.Visible and playtimeThreadId == state.profilePlaytimeThreadId do
				local elapsed = math.max(0, math.floor(os.clock() - openedAt))
				updateProfileRowValue("playtime", state.formatHMS(playtimeBase + elapsed))
				task.wait(1)
			end
		end)
	end

	if refreshBtn and refreshBtn:IsA("GuiObject") then
		refreshBtn.Visible = false
	end
	if not panel:GetAttribute("Wired") then
		panel:SetAttribute("Wired", true)
		if closeBtn and closeBtn:IsA("GuiButton") then
			closeBtn.MouseButton1Click:Connect(function()
				state.profilePlaytimeThreadId += 1
				hidePanel(panel)
			end)
		end
	end

	showPanel(panel)
	refreshProfile()
end

function HomePanels.OpenAchievements()
	if state.setHomeNotificationFlag then
		state.setHomeNotificationFlag("achievements", false)
	end
	local panel = ensureFrame("achievementsFrame", "Achievements")
	if not panel then
		return
	end
	closeAllPanels(panel)
	local frame = panel:FindFirstChild("Frame")
	if not frame or not frame:IsA("GuiObject") then
		return
	end
	local status = frame:FindFirstChild("Progress", true) or frame:FindFirstChild("Status", true)
	local scroll = frame:FindFirstChild("Scroll", true)
	local content = scroll and (scroll:FindFirstChild("Content") or scroll)
	local template = frame:FindFirstChild("AchievementTemplate", true)
	local closeBtn = frame:FindFirstChild("Close", true)
	if not content or not content:IsA("GuiObject") or not template then
		return
	end
	if template:IsA("GuiObject") then
		template.Visible = false
		template.LayoutOrder = -1000
	end
	if not panel:GetAttribute("Wired") then
		panel:SetAttribute("Wired", true)
		if closeBtn and closeBtn:IsA("GuiButton") then
			closeBtn.MouseButton1Click:Connect(function()
				hidePanel(panel)
			end)
		end
	end
	for _, child in ipairs(content:GetChildren()) do
		if child ~= template and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	if status and status:IsA("TextLabel") then
		status.Text = "Loading achievements..."
	end
	local board = state.cachedAchievementsBoard or state.RemoteRegistry:GetFunction("GetAchievements"):InvokeServer() or {}
	state.cachedAchievementsBoard = board
	state.lastAchievementUnlockedSeen = tonumber(board.unlocked) or state.lastAchievementUnlockedSeen
	local items = board.achievements or {}
	local unlocked = tonumber(board.unlocked or 0) or 0
	local total = tonumber(board.total or #items) or #items
	if status and status:IsA("TextLabel") then
		status.Text = string.format("%s/%s complete", tostring(unlocked), tostring(total))
	end

	local function getAchievementLayoutOrder(ach, index)
		if ach.claimed then
			return 300000 + index
		end
		if ach.unlocked then
			return index
		end
		local ratio = math.clamp((tonumber(ach.progress) or 0) / math.max(1, tonumber(ach.target) or 1), 0, 1)
		return 100000 + math.floor((1 - ratio) * 10000) + index
	end

	local function applyAchievementRow(row, ach, index)
		row.LayoutOrder = getAchievementLayoutOrder(ach, index)
		row.Visible = true
		local title = row:FindFirstChild("Title", true)
		local explanation = row:FindFirstChild("Explanation", true)
		local progressLabel = row:FindFirstChild("Progress", true)
		local rewardLabel = row:FindFirstChild("CoinReward", true)
		local completedBadge = row:FindFirstChild("Completed", true)
		local barBg = row:FindFirstChild("BarBg", true)
		local fill = barBg and barBg:FindFirstChild("Fill")
		local claimBtn = row:FindFirstChild("Claim", true)
		local claimLabel = claimBtn and (claimBtn:FindFirstChild("Label") or claimBtn:FindFirstChildWhichIsA("TextLabel"))

		if title and title:IsA("TextLabel") then
			title.Text = tostring(ach.title or "Achievement")
		end
		if explanation and explanation:IsA("TextLabel") then
			explanation.Text = tostring(ach.desc or "")
		end
		if progressLabel and progressLabel:IsA("TextLabel") then
			progressLabel.Text = tostring(ach.progress or 0) .. "/" .. tostring(ach.target or 0)
		end
		if rewardLabel and rewardLabel:IsA("TextLabel") then
			rewardLabel.Text = tostring(ach.reward or 0)
		end
		if completedBadge and completedBadge:IsA("GuiObject") then
			completedBadge.Visible = ach.claimed == true
		end
		if fill and fill:IsA("GuiObject") then
			local ratio = math.clamp((tonumber(ach.progress) or 0) / math.max(1, tonumber(ach.target) or 1), 0, 1)
			local visualRatio = 0.1 + (ratio * 0.9)
			fill.Size = UDim2.new(math.clamp(visualRatio, 0.1, 1), 0, 1, 0)
			if ach.claimed then
				fill.BackgroundColor3 = Color3.fromRGB(92, 148, 106)
			else
				fill.BackgroundColor3 = Color3.fromRGB(35, 255, 79)
			end
		end
		local claimText = ach.claimed and "Claimed" or (ach.unlocked and "Claim" or "Locked")
		if claimBtn and claimBtn:IsA("GuiButton") then
			if ach.claimed then
				claimBtn.Active = false
				claimBtn.AutoButtonColor = false
				claimBtn.BackgroundColor3 = Color3.fromRGB(83, 98, 126)
			elseif ach.unlocked then
				claimBtn.Active = true
				claimBtn.AutoButtonColor = true
				claimBtn.BackgroundColor3 = Color3.fromRGB(35, 255, 79)
			else
				claimBtn.Active = false
				claimBtn.AutoButtonColor = false
				claimBtn.BackgroundColor3 = Color3.fromRGB(58, 64, 78)
			end
		end
		if claimLabel and claimLabel:IsA("TextLabel") then
			claimLabel.Text = claimText
		elseif claimBtn and claimBtn:IsA("GuiButton") then
			claimBtn.Text = claimText
		end
	end

	for i, ach in ipairs(items) do
		local row = template:Clone()
		row.Name = "Achievement_" .. tostring(ach.id or i)
		row.Parent = content
		applyAchievementRow(row, ach, i)
		local claimBtn = row:FindFirstChild("Claim", true)
		if claimBtn and claimBtn:IsA("GuiButton") and ach.unlocked and not ach.claimed then
			claimBtn.MouseButton1Click:Connect(function()
				local resp = state.RemoteRegistry:GetFunction("ClaimAchievementReward"):InvokeServer(ach.id)
				if resp and resp.success then
					UIEffects.PlaySound("Victory")
					state.cachedAchievementsBoard = resp.board or state.cachedAchievementsBoard
					if state.onCoinsUpdated then
						state.onCoinsUpdated(resp.coins or 0)
					end
					state.UIManager:ShowAlert("Achievement reward +" .. tostring(resp.reward or 0) .. " coins", "coin")
					ach.claimed = true
					applyAchievementRow(row, ach, i)
					if status and status:IsA("TextLabel") then
						status.Text = string.format("%s/%s complete", tostring(unlocked), tostring(total))
					end
				else
					UIEffects.PlaySound("Error")
					state.UIManager:ShowAlert((resp and resp.message) or "Claim failed", "error")
				end
			end)
		end
	end
	showPanel(panel)
	if frame ~= panel and frame:IsA("GuiObject") then
		frame.Visible = true
	end
end

function HomePanels.GetShopFrame()
	return ensureFrame("shopFrame", "Shop", "EffectShopFrame")
end

function HomePanels.CloseAllPanels(exceptPanel)
	closeAllPanels(exceptPanel)
end

return HomePanels
