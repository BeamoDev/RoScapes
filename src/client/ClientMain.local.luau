-- Client main

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local AvatarEditorService = game:GetService("AvatarEditorService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteRegistry = require(ReplicatedStorage:WaitForChild("Shared").RemoteRegistry)
local TutorialConfig = require(ReplicatedStorage:WaitForChild("Shared").TutorialConfig)
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MonetizationConfig"))
local UIEffects = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("util"):WaitForChild("UIEffects"))
local IntroLoader = require(script.Parent.bootstrap.IntroLoader)
local TutorialController = require(script.Parent.controllers.TutorialController)
local QuestsPanel = require(script.Parent.panels.QuestsPanel)
local GroupRewardPanel = require(script.Parent.panels.GroupRewardPanel)
local HomePanels = require(script.Parent.panels.HomePanels)
local AdminPanel = require(script.Parent.panels.AdminPanel)
local BonusFx = require(script.Parent.effects.BonusFx)

local UIManager = require(script.Parent.ui.UIManager)
local HomeHud = require(script.Parent.ui.HomeHud)
local GameHudTransitions = require(script.Parent.ui.GameHudTransitions)
local LevelSelect = require(script.Parent.ui.LevelSelect)
local GameBoard = require(script.Parent.ui.GameBoard)
local LetterWheel = require(script.Parent.gameplay.LetterWheel)
local ModeFlows = require(script.Parent.gameplay.ModeFlows)
local InputState = require(script.Parent.core.InputState)
local ClientBridge = require(script.Parent.core.ClientBridge)

task.spawn(function()
	local RejoinSystem = require(script.Parent.core.AutoRejoin)
	RejoinSystem.Init()
end)

local hud = nil
local playerData = nil
local favoritePromptShown = false
local favoritePromptInProgress = false
local favoritePromptCompletedConnection = nil
local SYSTEM_CHAT_MESSAGES = {
	"Follow @beamozx for more puzzle games and updates.",
	"Join the group for rewards and future bonuses.",
	"Tip: bonus words are extra valid words that are not required on the board.",
	"Tip: selection hints are best saved for awkward last letters.",
	"Invite someone to 1v1 if you want a faster competitive round.",
}

local function postSystemChatMessage(message)
	local text = tostring(message or "")
	if text == "" then
		return
	end
	local richPrefix = '<font color="#AA6EFF">[SERVER]</font> '
	local plainText = "[SERVER] " .. text
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = channels and channels:FindFirstChild("RBXGeneral")
	if general and general.DisplaySystemMessage then
		pcall(function()
			general:DisplaySystemMessage(richPrefix .. text)
		end)
		return
	end
	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = plainText,
			Color = Color3.fromRGB(170, 110, 255),
			Font = Enum.Font.GothamMedium,
			FontSize = Enum.FontSize.Size18,
		})
	end)
end

local function waitForGuiObject(parent, childName, timeoutSeconds)
	local deadline = tick() + math.max(0.1, tonumber(timeoutSeconds) or 10)
	local found = parent:FindFirstChild(childName)
	while not found and tick() < deadline do
		task.wait(0.1)
		found = parent:FindFirstChild(childName)
	end
	return found
end

local function collectImagePreloadTargets(root, results, seen)
	if not root then
		return
	end
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("ImageLabel") or inst:IsA("ImageButton") or inst:IsA("Decal") or inst:IsA("Texture") then
			local image = inst:IsA("Texture") and inst.Texture or inst.Image
			if typeof(image) == "string" and image ~= "" and not seen[image] then
				seen[image] = true
				table.insert(results, image)
			end
		end
	end
end

local function maybePromptFavoriteGame()
	if favoritePromptShown or favoritePromptInProgress then
		return
	end
	favoritePromptInProgress = true
	if favoritePromptCompletedConnection then
		favoritePromptCompletedConnection:Disconnect()
		favoritePromptCompletedConnection = nil
	end
	favoritePromptCompletedConnection = AvatarEditorService.PromptSetFavoriteCompleted:Connect(function()
		favoritePromptInProgress = false
		if favoritePromptCompletedConnection then
			favoritePromptCompletedConnection:Disconnect()
			favoritePromptCompletedConnection = nil
		end
	end)
	local ok = pcall(function()
		AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
	if ok then
		favoritePromptShown = true
		playerData.favoritePromptShown = true
		RemoteRegistry:GetFunction("MarkFavoritePromptShown"):InvokeServer()
		return
	end
	favoritePromptInProgress = false
	if favoritePromptCompletedConnection then
		favoritePromptCompletedConnection:Disconnect()
		favoritePromptCompletedConnection = nil
	end
end

local introLoader = IntroLoader.Create(playerGui)
if not game:IsLoaded() then
	game.Loaded:Wait()
end
RunService.RenderStepped:Wait()
RunService.RenderStepped:Wait()
introLoader.BeginLoading()
introLoader.SetProgress(0.06, "Preparing interface...")

local PRELOAD_BACKGROUND_IDS = {
	home = {
		"85788799350525",
		"105699786679786",
		"115444761772173",
		"81376931726151",
	},
	packs = {
		"85788799350525",
		"91785141817679",
		"115444761772173",
		"81376931726151",
		"105699786679786",
		"134011177418284",
		"131694469551685",
		"88170501418837",
		"105360992331128",
		"85145996060240",
		"124778064405452",
		"84087501777142",
		"94642764712259",
		"103542522568208",
		"89331598575326",
		"93456390451733",
		"136727958546302",
		"103381099115414",
	},
}

hud = waitForGuiObject(playerGui, "HUD", 15)
if not hud then
	error("[ClientMain] HUD not found in PlayerGui after waiting")
end

local function applyMobileHudOverrides()
	local isTouchOnlyMobile = UserInputService.TouchEnabled
		and not UserInputService.KeyboardEnabled
		and not UserInputService.GamepadEnabled
	local framesRoot = hud:FindFirstChild("Frames")
	if framesRoot and framesRoot:IsA("GuiObject") then
		framesRoot.ClipsDescendants = not isTouchOnlyMobile
	end
	if not isTouchOnlyMobile then
		return
	end
	for _, screenName in ipairs({ "Game", "Home", "Levels" }) do
		local screen = hud:FindFirstChild(screenName)
		if screen and screen:IsA("GuiObject") then
			screen.ClipsDescendants = false
		end
	end
	for _, screenName in ipairs({ "Game", "Home" }) do
		local screen = hud:FindFirstChild(screenName)
		local scenary = screen and screen:FindFirstChild("Scenary", true)
		if scenary and scenary:IsA("GuiObject") then
			scenary.Size = UDim2.fromScale(1.35, 1.35)
		end
	end
end

applyMobileHudOverrides()
hud.Enabled = false
require(script.Parent.effects.ClickBubble).Init(playerGui, hud)

local preloadTargets = { hud, ReplicatedStorage:WaitForChild("Shared") }
local seenPreloadAssets = {}
collectImagePreloadTargets(playerGui, preloadTargets, seenPreloadAssets)
collectImagePreloadTargets(ReplicatedStorage:WaitForChild("Shared"), preloadTargets, seenPreloadAssets)
for _, idValue in ipairs(PRELOAD_BACKGROUND_IDS.home) do
	local assetId = "rbxassetid://" .. idValue
	if not seenPreloadAssets[assetId] then
		seenPreloadAssets[assetId] = true
		table.insert(preloadTargets, assetId)
	end
end
for _, idValue in ipairs(PRELOAD_BACKGROUND_IDS.packs) do
	local assetId = "rbxassetid://" .. idValue
	if not seenPreloadAssets[assetId] then
		seenPreloadAssets[assetId] = true
		table.insert(preloadTargets, assetId)
	end
end

introLoader.SetProgress(0.15, "Preloading images...")
local loadedCount = 0
local totalCount = math.max(1, #preloadTargets)
ContentProvider:PreloadAsync(preloadTargets, function()
	loadedCount += 1
	local assetProgress = math.clamp(loadedCount / totalCount, 0, 1)
	introLoader.SetProgress(
		0.15 + (assetProgress * 0.62),
		"Preloading images... " .. tostring(math.floor(assetProgress * 100)) .. "%"
	)
end)

introLoader.SetProgress(0.82, "Syncing player data...")
playerData = RemoteRegistry:GetFunction("GetPlayerData"):InvokeServer()
if not playerData then
	playerData = { hints = 0, progress = {}, packs = {}, skill = { level = 1, score = 0, recentLevelsTracked = 0 } }
end
playerData.premiumOwned = playerData.premiumOwned == true
playerData.groupRewardClaimed = playerData.groupRewardClaimed == true
playerData.favoritePromptShown = playerData.favoritePromptShown == true
playerData.skill = playerData.skill or { level = 1, score = 0, recentLevelsTracked = 0 }
favoritePromptShown = playerData.favoritePromptShown

introLoader.SetProgress(0.9, "Building UI...")
InputState:SetEnabled(false)

UIManager:Init(playerGui, playerData)
require(script.Parent.ui.ButtonFeedback).Init(hud)
LevelSelect:Init(UIManager, playerData, hud)
GameBoard:Init(UIManager, hud)
LetterWheel:Init(UIManager, hud)

local homeScreen = hud:FindFirstChild("Home")
local levelsScreen = hud:FindFirstChild("Levels") or hud:FindFirstChild("LevelSelect")
local gameScreen = hud:FindFirstChild("Game") or hud:WaitForChild("Game")
local gameButtons = gameScreen and gameScreen:FindFirstChild("Buttons")
local gameInGameBar = gameScreen and gameScreen:FindFirstChild("InGameBar")
local frames = hud:FindFirstChild("Frames")
local bonusWordsFrame = frames and frames:FindFirstChild("BonusWords")
local guessedBonusWords = {}
local pvpFrame = frames and (frames:FindFirstChild("PlayerList") or frames:FindFirstChild("PvPPanel"))
local pendingPvPInvites = {}
local isPvPMatch = false
local isDailyPuzzleMode = false
local isTimedMode = false
local isHardcoreMode = false
local freeplaySessionStreak = 0
local nextAutoAdvanceToken = 0
local timedMatchToken = 0
local timedModeState = nil
local timedExitPending = false
local gameExitPending = false
local hardcoreState = nil
local updateProfileRowValue = function() end
local tutorialCompleted = playerData.tutorialCompleted == true
local tutorialToken = 0
local cancelOnboardingTutorial
local stopTimedModeTimer
local finishTimedToLobby
local stopHardcoreMode
local onTutorialWordFound = function() end
local onTutorialHintUsed = function() end
local onTutorialArrowModeStarted = function() end
local playBonusCoinFly = function() end
local playBonusWordFly = function() end
local FORCE_TUTORIAL_FOR_TESTING = false
local tutorialShownThisSession = false
local tutorialSessionActive = false
ClientBridge.SetState("IsHardcoreMode", false)
local lastAchievementUnlockedSeen = nil
local uiState = {
	motion = require(script.Parent.ui.GuiMotion),
	homeNotificationCounts = {
		daily = 0,
		quests = 0,
		achievements = 0,
		oneVsOne = 0,
	},
	generalInfoState = {
		onAccept = nil,
		onClose = nil,
	},
	renderPvPPanel = nil,
	cachedDailyPuzzleInfo = nil,
}
uiState.panelMotionTarget = function(panel)
	local inner = panel and panel:FindFirstChild("Frame")
	return (inner and inner:IsA("GuiObject")) and inner or panel
end
uiState.showAnimatedPanel = function(panel)
	uiState.motion.Show(panel, uiState.panelMotionTarget(panel))
end
uiState.hideAnimatedPanel = function(panel)
	uiState.motion.Hide(panel, uiState.panelMotionTarget(panel))
end
GameHudTransitions.Init({
	gameScreen = gameScreen,
	gameButtons = gameButtons,
	inGameBar = gameInGameBar,
	LetterWheel = LetterWheel,
	setExitPending = function(value)
		gameExitPending = value == true
	end,
})
uiState.levelDataRequestToken = 0
-- Ensures only the latest level request can update the active board on the client.
uiState.requestLevelData = function(packId, levelId, fallbackPackId, fallbackLevelId, requestOptions)
	uiState.levelDataRequestToken += 1
	local requestToken = uiState.levelDataRequestToken

	local data = RemoteRegistry:GetFunction("GetLevelData"):InvokeServer(packId, levelId, requestToken, requestOptions)
	if requestToken ~= uiState.levelDataRequestToken then
		return nil, "stale"
	end

	if not data and fallbackPackId ~= nil and fallbackLevelId ~= nil then
		data = RemoteRegistry:GetFunction("GetLevelData"):InvokeServer(fallbackPackId, fallbackLevelId, requestToken, requestOptions)
		if requestToken ~= uiState.levelDataRequestToken then
			return nil, "stale"
		end
	end

	return data, "ok"
end

uiState.promptSpecialHintPurchase = function(kind, row, col)
	local prep = RemoteRegistry:GetFunction("PrepareSpecialHintPurchase"):InvokeServer(kind, row, col)
	if not (prep and prep.success) then
		UIManager:ShowAlert((prep and prep.message) or "Purchase unavailable", "error")
		return false
	end
	local productId = tonumber(prep.productId) or 0
	if productId <= 0 then
		local hintProducts = MonetizationConfig.HintProducts or {}
		local productName = "Hint"
		if kind == "pvp_row_hint" then
			productName = (hintProducts.pvpRowHint and hintProducts.pvpRowHint.label) or "1v1 Row Hint"
		elseif kind == "pvp_hint" then
			productName = (hintProducts.pvpHint and hintProducts.pvpHint.label) or "1v1 Hint"
		elseif kind == "daily_pick_hint" then
			productName = (hintProducts.dailySelectionHint and hintProducts.dailySelectionHint.label)
				or "Daily Selection Hint"
		else
			productName = (hintProducts.dailyHint and hintProducts.dailyHint.label) or "Daily Hint"
		end
		UIManager:ShowAlert("Set product id for " .. productName, "error")
		return false
	end
	MarketplaceService:PromptProductPurchase(player, productId)
	return true
end
ClientBridge.SetCallback("PromptSpecialHintPurchase", function(kind, row, col)
	return uiState.promptSpecialHintPurchase(kind, row, col)
end)
ClientBridge.SetCallback("GetSpecialArrowPurchaseKind", function()
	if isPvPMatch then
		return "pvp_row_hint"
	end
	if isDailyPuzzleMode then
		return "daily_pick_hint"
	end
	return nil
end)

-- Background asset ids
local BACKGROUND_IDS = {
	home = {
		"85788799350525",
		"105699786679786",
		"115444761772173",
		"81376931726151",
	},
	packs = {
		"85788799350525",
		"91785141817679",
		"115444761772173",
		"81376931726151",
		"105699786679786",
		"134011177418284",
		"131694469551685",
		"88170501418837",
		"105360992331128",
		"85145996060240",
		"124778064405452",
		"84087501777142",
		"94642764712259",
		"103542522568208",
		"89331598575326",
		"93456390451733",
		"136727958546302",
		"103381099115414",
	},
}

local function toAssetId(idValue)
	return "rbxassetid://" .. tostring(idValue)
end

local PACK_SCENERY_IMAGE_IDS = {}
local HOME_SCENERY_IMAGE_IDS = {}
local packList = playerData.packs or {}
local packIdsInOrder = {}
for index, packInfo in ipairs(packList) do
	local fallbackPackId = index
	local packId = tonumber(packInfo and packInfo.packId) or fallbackPackId
	table.insert(packIdsInOrder, packId)
end

if #packIdsInOrder == 0 then
	table.insert(packIdsInOrder, 1)
end

for _, idValue in ipairs(BACKGROUND_IDS.home) do
	table.insert(HOME_SCENERY_IMAGE_IDS, toAssetId(idValue))
end

local packAssetIds = {}
for _, idValue in ipairs(BACKGROUND_IDS.packs) do
	table.insert(packAssetIds, toAssetId(idValue))
end

for i, packId in ipairs(packIdsInOrder) do
	local pid = tonumber(packId) or i
	local sceneryIndex = ((math.max(1, pid) - 1) % math.max(1, #packAssetIds)) + 1
	PACK_SCENERY_IMAGE_IDS[packId] = packAssetIds[sceneryIndex]
end

local DEFAULT_SCENERY_IMAGE_ID = "rbxassetid://81376931726151"
local FIXED_HOME_SCENERY_IMAGE_ID = DEFAULT_SCENERY_IMAGE_ID
if #HOME_SCENERY_IMAGE_IDS > 0 then
	FIXED_HOME_SCENERY_IMAGE_ID = HOME_SCENERY_IMAGE_IDS[math.random(1, #HOME_SCENERY_IMAGE_IDS)]
end

local function dayStampNow()
	return math.floor(os.time() / 86400)
end

local function formatHMS(totalSeconds)
	local s = math.max(0, math.floor(totalSeconds))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	return string.format("%02d:%02d:%02d", h, m, sec)
end

local function formatQuestResetTime(totalSeconds)
	local s = math.max(0, math.floor(totalSeconds))
	local days = math.floor(s / 86400)
	local hours = math.floor((s % 86400) / 3600)
	local mins = math.floor((s % 3600) / 60)
	local secs = s % 60
	if days > 0 then
		return string.format("%dd %02dh %02dm %02ds", days, hours, mins, secs)
	end
	return string.format("%02dh %02dm %02ds", hours, mins, secs)
end

local function getPackSceneryImage(packId)
	local numericPackId = tonumber(packId) or 0
	if numericPackId == -1 then
		return "rbxassetid://74139347761646"
	end
	if numericPackId < 1 and #HOME_SCENERY_IMAGE_IDS > 0 then
		return FIXED_HOME_SCENERY_IMAGE_ID
	end
	local fallbackId = DEFAULT_SCENERY_IMAGE_ID
	local id = PACK_SCENERY_IMAGE_IDS[numericPackId]
	if typeof(id) == "string" and id ~= "" then
		return id
	end
	return fallbackId
end

local findNextPlayableLevel

local function setScreenScenaryImage(screen, imageId)
	if not screen or typeof(imageId) ~= "string" or imageId == "" then
		return
	end
	local scenary = screen:FindFirstChild("Scenary", true)
	if scenary and scenary:IsA("ImageLabel") then
		scenary.Image = imageId
	end
end

local function getScreenScenaryImage(screen)
	if not screen then
		return nil
	end
	local scenary = screen:FindFirstChild("Scenary", true)
	if scenary and scenary:IsA("ImageLabel") then
		local image = tostring(scenary.Image or "")
		if image ~= "" then
			return image
		end
	end
	return nil
end

local function syncDropBackgroundImage()
	local dropBackground = hud and hud:FindFirstChild("DropBackground")
	local bgImage = dropBackground and dropBackground:FindFirstChild("BGImage")
	if not (bgImage and bgImage:IsA("ImageLabel")) then
		return
	end

	local activeImage = nil
	if gameScreen and gameScreen.Visible then
		activeImage = getScreenScenaryImage(gameScreen)
	elseif levelsScreen and levelsScreen.Visible then
		activeImage = getScreenScenaryImage(levelsScreen)
	elseif homeScreen and homeScreen.Visible then
		activeImage = getScreenScenaryImage(homeScreen)
	end

	if typeof(activeImage) == "string" and activeImage ~= "" then
		bgImage.Image = activeImage
	end
end

local function applyLobbyScenary()
	local nextPackId = select(1, findNextPlayableLevel())
	local levelsImageId = getPackSceneryImage(nextPackId)
	setScreenScenaryImage(levelsScreen, levelsImageId)
	setScreenScenaryImage(homeScreen, FIXED_HOME_SCENERY_IMAGE_ID)
	syncDropBackgroundImage()
end

local function applyGameScenaryForPack(packId)
	setScreenScenaryImage(gameScreen, getPackSceneryImage(packId))
	syncDropBackgroundImage()
end

if LevelSelect and LevelSelect.SetPackSceneryResolver then
	LevelSelect:SetPackSceneryResolver(function(packId)
		return getPackSceneryImage(packId)
	end)
end
local function clearGuessedBonusWords()
	guessedBonusWords = {}
	ClientBridge.Call("UpdateBonusWordsCounter")
end

local function loadSavedBonusWords(words)
	guessedBonusWords = {}
	local seen = {}
	for _, word in ipairs(words or {}) do
		local upper = tostring(word or ""):upper()
		if upper ~= "" and not seen[upper] then
			seen[upper] = true
			table.insert(guessedBonusWords, upper)
		end
	end
	table.sort(guessedBonusWords)
	ClientBridge.Call("UpdateBonusWordsCounter")
	if bonusWordsFrame and bonusWordsFrame.Visible then
		ClientBridge.Call("ShowBonusWords")
	end
end

uiState.applySavedBoardProgress = function(data)
	if typeof(data) ~= "table" then
		return
	end
	if GameBoard.ApplySavedDailyProgress then
		GameBoard:ApplySavedDailyProgress(data.progressCells or {})
	end
	if GameBoard.ApplySavedHintCells then
		GameBoard:ApplySavedHintCells(data.hintedCells or {})
	end
	loadSavedBonusWords(data.progressBonus or {})
end

local function resetFreeplaySessionStreak()
	freeplaySessionStreak = 0
	updateProfileRowValue("current_freeplay_streak", "0")
end

local function issueAutoAdvanceToken()
	nextAutoAdvanceToken += 1
	ClientBridge.SetState("PendingAutoAdvanceToken", nextAutoAdvanceToken)
	return nextAutoAdvanceToken
end

local function invalidateAutoAdvanceToken()
	nextAutoAdvanceToken += 1
	ClientBridge.SetState("PendingAutoAdvanceToken", nextAutoAdvanceToken)
end

local function shakeGuiObject(guiObject, originalPosition)
	if not guiObject or not guiObject.Parent then
		return
	end
	local offsets = {
		Vector2.new(-6, 0),
		Vector2.new(5, -2),
		Vector2.new(-4, 2),
		Vector2.new(3, -1),
		Vector2.new(0, 0),
	}
	local stepDuration = 0.045
	task.spawn(function()
		for _, offset in ipairs(offsets) do
			if not guiObject.Parent then
				return
			end
			local tween = TweenService:Create(
				guiObject,
				TweenInfo.new(stepDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
				{
					Position = originalPosition + UDim2.fromOffset(offset.X, offset.Y),
				}
			)
			tween:Play()
			tween.Completed:Wait()
		end
	end)
end

local function playFreeplayStreakAnimation(streakValue, onFinished)
	if not frames then
		return 0
	end
	local streakFrame = frames:FindFirstChild("Streak")
	if not (streakFrame and streakFrame:IsA("GuiObject")) then
		return 0
	end
	local streakBackground = streakFrame:FindFirstChild("Background")
	local container = streakFrame:FindFirstChild("Container")
	local flameIcon = container and container:FindFirstChild("FlameIcon")
	local streakAmount = container and container:FindFirstChild("StreakAmount")
	if not (container and container:IsA("GuiObject")) then
		return 0
	end

	local fadeTarget = (streakBackground and streakBackground:IsA("GuiObject")) and streakBackground or streakFrame
	local baseFadeTransparency = fadeTarget.BackgroundTransparency
	local baseContainerPos = container.Position
	local hiddenContainerPos = UDim2.fromScale(0.5, 1.5)
	local shownContainerPos = UDim2.fromScale(0.5, 0.5)
	local holdDuration = 2
	local animationDuration = 2.95

	streakFrame.Visible = true
	fadeTarget.BackgroundTransparency = 1
	container.Position = hiddenContainerPos
	if streakAmount and streakAmount:IsA("TextLabel") then
		streakAmount.Text = "x" .. tostring(math.max(1, tonumber(streakValue) or 1))
	end

	local fadeIn =
		TweenService:Create(fadeTarget, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.4,
		})
	local slideIn =
		TweenService:Create(container, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = shownContainerPos,
		})
	fadeIn:Play()
	slideIn:Play()

	task.delay(0.38, function()
		shakeGuiObject(container, shownContainerPos)
		if flameIcon and flameIcon:IsA("GuiObject") then
			shakeGuiObject(flameIcon, flameIcon.Position)
		end
	end)

	task.delay(holdDuration, function()
		if not streakFrame.Parent or not container.Parent then
			return
		end
		local slideOut =
			TweenService:Create(container, TweenInfo.new(0.36, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = hiddenContainerPos,
			})
		local fadeOut =
			TweenService:Create(fadeTarget, TweenInfo.new(0.36, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 1,
			})
		slideOut:Play()
		fadeOut:Play()
		task.delay(0.4, function()
			if not streakFrame.Parent then
				return
			end
			streakFrame.Visible = false
			fadeTarget.BackgroundTransparency = baseFadeTransparency
			if container.Parent then
				container.Position = baseContainerPos
			end
			if onFinished then
				onFinished()
			end
		end)
	end)

	return animationDuration
end

local function getOrderedPacks()
	local packs = {}
	for _, pack in ipairs(playerData.packs or {}) do
		table.insert(packs, pack)
	end
	table.sort(packs, function(a, b)
		local aId = tonumber(a and a.packId) or 0
		local bId = tonumber(b and b.packId) or 0
		if aId < 1 and bId >= 1 then
			return true
		end
		if bId < 1 and aId >= 1 then
			return false
		end
		return aId < bId
	end)
	return packs
end

local function getGlobalLevelNumber(packId, levelId)
	local targetPack = tonumber(packId) or 1
	local targetLevel = math.max(1, tonumber(levelId) or 1)
	local totalBefore = 0
	for _, pack in ipairs(getOrderedPacks()) do
		local pid = tonumber(pack and pack.packId) or 0
		local count = math.max(0, tonumber(pack and pack.levelCount) or 0)
		if pid < 1 then
			continue
		end
		if pid == targetPack then
			return totalBefore + math.min(targetLevel, math.max(1, count))
		end
		totalBefore += count
	end
	-- Fallback if pack metadata is missing.
	return math.max(1, ((targetPack - 1) * 30) + targetLevel)
end

local function getAccessibleLevelCountForPack(pack)
	local packId = tonumber(pack and pack.packId) or 0
	if packId < 1 then
		return 0
	end
	if playerData.premiumOwned == true then
		return math.max(0, tonumber(pack and pack.levelCount) or 0)
	end
	if LevelSelect.GetLastAccessibleLevel then
		return math.max(0, tonumber(LevelSelect:GetLastAccessibleLevel(packId)) or 0)
	end
	return math.max(0, tonumber(pack and pack.levelCount) or 0)
end

local function findNextAdvanceLevel(currentPackId, currentLevelId)
	local orderedPacks = getOrderedPacks()
	local resolvedCurrentPackId = tonumber(currentPackId) or 0
	local resolvedCurrentLevelId = math.max(0, tonumber(currentLevelId) or 0)
	local currentPackIndex = nil

	for index, pack in ipairs(orderedPacks) do
		if (tonumber(pack and pack.packId) or 0) == resolvedCurrentPackId then
			currentPackIndex = index
			break
		end
	end

	if not currentPackIndex then
		return nil, nil
	end

	local currentPack = orderedPacks[currentPackIndex]
	local currentPackAccessibleCount = getAccessibleLevelCountForPack(currentPack)
	if currentPackAccessibleCount > 0 and resolvedCurrentLevelId < currentPackAccessibleCount then
		return resolvedCurrentPackId, resolvedCurrentLevelId + 1
	end

	for index = currentPackIndex + 1, #orderedPacks do
		local pack = orderedPacks[index]
		local packId = tonumber(pack and pack.packId) or 0
		local accessibleCount = getAccessibleLevelCountForPack(pack)
		if packId >= 1 and accessibleCount > 0 then
			return packId, 1
		end
	end

	return nil, nil
end

findNextPlayableLevel = function()
	local packs = getOrderedPacks()
	local progress = playerData.progress or {}
	for _, pack in ipairs(packs) do
		local packId = tonumber(pack and pack.packId) or 1
		if packId < 1 then
			continue
		end
		local levelCount = LevelSelect.GetLastAccessibleLevel and LevelSelect:GetLastAccessibleLevel(packId)
			or math.max(1, tonumber(pack and pack.levelCount) or 1)
		if levelCount <= 0 then
			continue
		end
		local packProgress = progress[tostring(packId)] or {}
		for levelId = 1, levelCount do
			if packProgress[tostring(levelId)] ~= true then
				return packId, levelId
			end
		end
	end
	if #packs > 0 then
		local lastPack = packs[#packs]
		local lastPackId = tonumber(lastPack and lastPack.packId) or 1
		local lastLevel = LevelSelect.GetLastAccessibleLevel and LevelSelect:GetLastAccessibleLevel(lastPackId)
			or math.max(1, tonumber(lastPack and lastPack.levelCount) or 1)
		lastLevel = math.max(1, tonumber(lastLevel) or 1)
		return lastPackId, lastLevel
	end
	return 1, 1
end

local function refreshPlayButtonLevelLabel()
	if not homeScreen then
		return
	end
	local btns = homeScreen:FindFirstChild("Buttons")
	local playBtn = btns and btns:FindFirstChild("Play")
	if not (playBtn and playBtn:IsA("GuiButton")) then
		return
	end

	local packId, levelId = findNextPlayableLevel()
	local globalLevel = getGlobalLevelNumber(packId, levelId)
	local textValue = "LEVEL " .. tostring(globalLevel)

	local label = playBtn:FindFirstChild("Label") or playBtn:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		label.Text = textValue
	else
		playBtn.Text = textValue
	end
end

local function showLoadedGameScreen()
	GameHudTransitions.SetHidden()
	UIManager:ShowScreen("GameScreen")
	GameHudTransitions.AnimateIn()
end

local function transitionGameToLobbyScreen(screenName, onDone)
	GameHudTransitions.AnimateOut(function()
		GameBoard:ExitLevel()
		LevelSelect:ShowPackList()
		applyLobbyScenary()
		UIManager:ShowScreen(screenName)
		if onDone then
			onDone()
		end
	end)
end

local function transitionFinishedGameToHome(onDone)
	transitionGameToLobbyScreen("HomeScreen", onDone)
end

local function getHomeButtonByNames(names)
	return HomeHud.GetHomeButtonByNames(names)
end

local function updateAssistButtonNotifications()
	HomeHud.UpdateAssistButtonNotifications()
	local wheelRoot = gameScreen and gameScreen:FindFirstChild("WheelRoot")
	local arrowBtn = (gameButtons and gameButtons:FindFirstChild("Arrow"))
		or (wheelRoot and wheelRoot:FindFirstChild("Arrow"))
	local hintBtn = (gameButtons and (gameButtons:FindFirstChild("Hint") or gameButtons:FindFirstChild("HintButton")))
		or (gameInGameBar and gameInGameBar:FindFirstChild("HintButton"))
	local normalHintCoinPrice = 150
	local normalArrowCoinPrice = 75
	local timedHintCoinPrice = normalHintCoinPrice
	local timedArrowCoinPrice = normalArrowCoinPrice
	local pvpArrowCoinPrice = normalArrowCoinPrice

	local function applyPriceMode(button, coinPrice, robuxPrice, useRobux)
		if not (button and button:IsA("GuiObject")) then
			return
		end
		local coinRoot = button:FindFirstChild("CoinPrice", true)
		local coinLabel = coinRoot and (coinRoot:FindFirstChild("Price", true) or coinRoot:FindFirstChild("Pric", true))
		local robuxRoot = button:FindFirstChild("RobuxPrice", true)
		local robuxLabel = robuxRoot and robuxRoot:FindFirstChild("RobuxPrice", true)

		if coinRoot and coinRoot:IsA("GuiObject") then
			coinRoot.Visible = not useRobux
		end
		if robuxRoot and robuxRoot:IsA("GuiObject") then
			robuxRoot.Visible = useRobux
		end
		if coinLabel and coinLabel:IsA("TextLabel") then
			coinLabel.Text = tostring(math.max(0, math.floor(tonumber(coinPrice) or 0)))
		end
		if robuxLabel and robuxLabel:IsA("TextLabel") then
			robuxLabel.Text = tostring(math.max(0, math.floor(tonumber(robuxPrice) or 0)))
		end
	end

	if isPvPMatch then
		applyPriceMode(
			hintBtn,
			0,
			MonetizationConfig.HintProducts
				and MonetizationConfig.HintProducts.pvpHint
				and MonetizationConfig.HintProducts.pvpHint.robux,
			true
		)
		applyPriceMode(arrowBtn, pvpArrowCoinPrice, 0, false)
	elseif isTimedMode then
		applyPriceMode(hintBtn, timedHintCoinPrice, 0, false)
		applyPriceMode(arrowBtn, timedArrowCoinPrice, 0, false)
	elseif isDailyPuzzleMode then
		applyPriceMode(
			hintBtn,
			0,
			MonetizationConfig.HintProducts
				and MonetizationConfig.HintProducts.dailyHint
				and MonetizationConfig.HintProducts.dailyHint.robux,
			true
		)
		applyPriceMode(arrowBtn, normalArrowCoinPrice, 0, false)
	else
		applyPriceMode(hintBtn, normalHintCoinPrice, 0, false)
		applyPriceMode(arrowBtn, normalArrowCoinPrice, 0, false)
	end

	if arrowBtn and arrowBtn:IsA("GuiObject") then
		local allowArrow = not isDailyPuzzleMode
		arrowBtn.Visible = allowArrow
		if arrowBtn:IsA("GuiButton") then
			arrowBtn.Active = allowArrow
			arrowBtn.AutoButtonColor = allowArrow
		end
	end
end

local function updateBonusWordsCounter()
	HomeHud.UpdateBonusWordsCounter(guessedBonusWords)
end

ClientBridge.SetCallback("UpdateBonusWordsCounter", updateBonusWordsCounter)

local function applyHomeNotificationBadges()
	HomeHud.ApplyHomeNotificationBadges()
end

local function setHomeNotificationCount(flag, amount)
	HomeHud.SetHomeNotificationCount(flag, amount)
end

local function setHomeNotificationFlag(flag, value)
	HomeHud.SetHomeNotificationFlag(flag, value)
end

local TIMED_REQUIRED_RANK = "SILVER_1"
local HARDCORE_REQUIRED_RANK = "GOLD_1"

local function rankAtLeast(currentRankId, requiredRankId)
	return HomeHud.RankAtLeast(currentRankId, requiredRankId)
end

ClientBridge.SetCallback("ShowBonusWords", function()
	HomeHud.ShowBonusWords(guessedBonusWords)
end)

ClientBridge.SetCallback("StartArrowSelection", function()
	if isDailyPuzzleMode then
		return
	end
	GameBoard:BeginArrowMode()
	onTutorialArrowModeStarted()
end)

local function updateHomeRankVisual(rankInfo)
	HomeHud.UpdateHomeRankVisual(rankInfo)
end

local function startRankShadowPulse()
	HomeHud.StartRankShadowPulse()
end

local function startPlayButtonPulse()
	HomeHud.StartPlayButtonPulse()
end

local function startHintButtonPulse()
	HomeHud.StartHintButtonPulse()
end

local function shakeButtonOnce(button)
	HomeHud.ShakeButtonOnce(button)
end

local function updateCurrencyLabels(coins)
	HomeHud.UpdateCurrencyLabels(coins)
end

updateProfileRowValue = function(key, amountText)
	HomePanels.UpdateProfileRowValue(key, amountText)
end

local function updateSelectionHintDisplays(tokens)
	local tokenCount = math.max(0, math.floor(tonumber(tokens) or 0))
	playerData.selectionHints = tokenCount
	updateAssistButtonNotifications()
	updateProfileRowValue("selection_hints", tokenCount)
	updateProfileRowValue("selection_hints_free", tokenCount)

	local shopPanel = HomePanels.GetShopFrame()
	local shopFrameRoot = shopPanel and (shopPanel:FindFirstChild("Frame") or shopPanel)
	local tokenRoots = {
		shopFrameRoot and shopFrameRoot:FindFirstChild("CurrencySelectionHints", true),
		shopFrameRoot and shopFrameRoot:FindFirstChild("SelectionHints", true),
	}
	for _, root in ipairs(tokenRoots) do
		local label = root and (root:FindFirstChild("Label", true) or root:FindFirstChildWhichIsA("TextLabel"))
		if label and label:IsA("TextLabel") then
			label.Text = tostring(tokenCount)
		end
	end
end

ClientBridge.SetCallback("OnCoinsUpdated", updateCurrencyLabels)
updateBonusWordsCounter()
startPlayButtonPulse()
startHintButtonPulse()
updateAssistButtonNotifications()
ClientBridge.SetCallback("OnSelectionHintsUpdated", function(tokens)
	updateSelectionHintDisplays(tokens)
end)

local function bindCoinValue()
	local leaderstats = player:FindFirstChild("leaderstats")
	local coinsValue = leaderstats and leaderstats:FindFirstChild("Coins")
	if coinsValue and coinsValue:IsA("IntValue") and not coinsValue:GetAttribute("CoinsWatcherConnected") then
		coinsValue:SetAttribute("CoinsWatcherConnected", true)
		coinsValue:GetPropertyChangedSignal("Value"):Connect(function()
			local value = coinsValue.Value
			playerData.coins = value
			updateCurrencyLabels(value)
			updateProfileRowValue("coins", value)
		end)
		local value = coinsValue.Value
		playerData.coins = value
		updateCurrencyLabels(value)
		updateProfileRowValue("coins", value)
	end
end

local function bindSelectionHintValue()
	local dataFolder = player:FindFirstChild("Data")
	local currencyFolder = dataFolder and dataFolder:FindFirstChild("Currency")
	local selectionHintsValue = currencyFolder and currencyFolder:FindFirstChild("SelectionHints")
	if selectionHintsValue and selectionHintsValue:IsA("IntValue") then
		if selectionHintsValue == ClientBridge.GetState("SelectionHintsWatcherValue") then
			updateSelectionHintDisplays(selectionHintsValue.Value)
			return
		end
		ClientBridge.SetState("SelectionHintsWatcherValue", selectionHintsValue)
		selectionHintsValue:GetPropertyChangedSignal("Value"):Connect(function()
			updateSelectionHintDisplays(selectionHintsValue.Value)
		end)
		updateSelectionHintDisplays(selectionHintsValue.Value)
	end
end

local function bindSolvedValue()
	local dataFolder = player:FindFirstChild("Data")
	local progressFolder = dataFolder and dataFolder:FindFirstChild("Progress")
	local solvedValue = progressFolder and progressFolder:FindFirstChild("Solved")
	if solvedValue and solvedValue:IsA("IntValue") and solvedValue ~= ClientBridge.GetState("SolvedWatcherValue") then
		ClientBridge.SetState("SolvedWatcherValue", solvedValue)
		local function onSolvedChanged()
			if (tonumber(solvedValue.Value) or 0) >= 5 then
				maybePromptFavoriteGame()
			end
		end
		solvedValue:GetPropertyChangedSignal("Value"):Connect(onSolvedChanged)
		onSolvedChanged()
	end
end

task.defer(bindCoinValue)
task.defer(bindSelectionHintValue)
task.defer(bindSolvedValue)
player.ChildAdded:Connect(function(child)
	if child.Name == "Data" then
		task.defer(bindSelectionHintValue)
		task.defer(bindSolvedValue)
	end
	if child.Name == "leaderstats" then
		task.defer(bindCoinValue)
	end
end)

QuestsPanel.Init({
	UIManager = UIManager,
	RemoteRegistry = RemoteRegistry,
	frames = frames,
	onCoinsUpdated = function(coins)
		ClientBridge.Call("OnCoinsUpdated", coins)
	end,
	formatResetTime = formatQuestResetTime,
	closeOtherPanels = function(exceptPanel)
		ClientBridge.Call("CloseHomePanels", exceptPanel)
	end,
})

GroupRewardPanel.Init({
	player = player,
	playerData = playerData,
	frames = frames,
	UIManager = UIManager,
	RemoteRegistry = RemoteRegistry,
	groupId = 34241464,
	onCoinsUpdated = function(coins)
		ClientBridge.Call("OnCoinsUpdated", coins)
	end,
	closeOtherPanels = function(exceptPanel)
		ClientBridge.Call("CloseHomePanels", exceptPanel)
	end,
	isTutorialActive = function()
		return (TutorialController.IsActive and TutorialController.IsActive()) or tutorialSessionActive == true
	end,
})

HomeHud.Init({
	homeScreen = homeScreen,
	gameScreen = gameScreen,
	gameButtons = gameButtons,
	bonusWordsFrame = bonusWordsFrame,
	playerData = playerData,
	uiState = uiState,
})
updateHomeRankVisual(playerData.rank or nil)
startRankShadowPulse()

local streakFrame = frames and frames:FindFirstChild("Streak")
if streakFrame and streakFrame:IsA("GuiObject") then
	streakFrame.Visible = false
	streakFrame.BackgroundTransparency = 1
end

updateCurrencyLabels(playerData.coins or 0)
updateSelectionHintDisplays(playerData.selectionHints or 0)
updateAssistButtonNotifications()
UIManager:OnShow("HomeScreen", function()
	updateCurrencyLabels(playerData.coins or 0)
	updateSelectionHintDisplays(playerData.selectionHints or 0)
	syncDropBackgroundImage()
end)
UIManager:OnShow("LevelSelect", function()
	syncDropBackgroundImage()
end)
UIManager:OnShow("GameScreen", function()
	updateCurrencyLabels(playerData.coins or 0)
	updateSelectionHintDisplays(playerData.selectionHints or 0)
	syncDropBackgroundImage()
end)

BonusFx.Init({
	gameScreen = gameScreen,
	gameButtons = gameButtons,
	gameInGameBar = gameInGameBar,
})

playBonusCoinFly = function(count)
	BonusFx.PlayCoins(count)
end

playBonusWordFly = function(word)
	BonusFx.PlayWord(word)
end

HomePanels.Init({
	player = player,
	playerData = playerData,
	frames = frames,
	UIManager = UIManager,
	RemoteRegistry = RemoteRegistry,
	MonetizationConfig = MonetizationConfig,
	MarketplaceService = MarketplaceService,
	TweenService = TweenService,
	dayStampNow = dayStampNow,
	formatHMS = formatHMS,
	setHomeNotificationFlag = function(flag, value)
		HomeHud.SetHomeNotificationFlag(flag, value)
	end,
	onCoinsUpdated = function(coins)
		ClientBridge.Call("OnCoinsUpdated", coins)
	end,
})

ClientBridge.SetCallback("CloseHomePanels", function(exceptPanel)
	HomePanels.CloseAllPanels(exceptPanel)
end)

TutorialController.Init({
	hud = hud,
	gameScreen = gameScreen,
	UIManager = UIManager,
	RemoteRegistry = RemoteRegistry,
	LetterWheel = LetterWheel,
	GameBoard = GameBoard,
	LevelSelect = LevelSelect,
	InputState = InputState,
	GroupRewardPanel = GroupRewardPanel,
	applyLobbyScenary = applyLobbyScenary,
	animateGameHudOut = GameHudTransitions.AnimateOut,
	forceTesting = FORCE_TUTORIAL_FOR_TESTING,
	forceReplay = TutorialConfig.ShouldReplayForUserId(player.UserId),
	tutorialCompleted = tutorialCompleted,
})

local function openQuestsPanel()
	HomeHud.SetHomeNotificationFlag("quests", false)
	QuestsPanel.Open()
end

local function setDailyPuzzleButtonState(completed)
	local isCompleted = completed == true
	local buttonsRoot = homeScreen and homeScreen:FindFirstChild("Buttons")
	local lowerButtons = buttonsRoot and buttonsRoot:FindFirstChild("LowerButtons")
	local dailyButtons = {
		buttonsRoot and buttonsRoot:FindFirstChild("Daily"),
		lowerButtons and lowerButtons:FindFirstChild("Daily"),
	}
	for _, dailyBtn in ipairs(dailyButtons) do
		if dailyBtn and dailyBtn:IsA("GuiObject") then
			local checkmark = dailyBtn:FindFirstChild("Check", true) or dailyBtn:FindFirstChild("Checkmark", true)
			local icon = dailyBtn:FindFirstChild("Icon", true)
			if checkmark and checkmark:IsA("GuiObject") then
				checkmark.Visible = isCompleted
			end
			if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
				icon.ImageTransparency = isCompleted and 0.3 or 0.1
			end
			if dailyBtn:IsA("GuiButton") then
				dailyBtn.AutoButtonColor = not isCompleted
			end
		end
	end
end

local function pollHomeNotificationSources()
	applyHomeNotificationBadges()

	local currentDailyKey = tostring(dayStampNow())
	local dailyPuzzleInfo = uiState.cachedDailyPuzzleInfo
	if uiState.cachedDailyPuzzleDayKey ~= currentDailyKey then
		uiState.cachedDailyPuzzleInfo = nil
		uiState.cachedDailyPuzzleDayKey = currentDailyKey
		dailyPuzzleInfo = nil
		setDailyPuzzleButtonState(false)
	end
	if not dailyPuzzleInfo then
		dailyPuzzleInfo = RemoteRegistry:GetFunction("GetDailyPuzzle"):InvokeServer(false)
		uiState.cachedDailyPuzzleInfo = dailyPuzzleInfo
		uiState.cachedDailyPuzzleDayKey = currentDailyKey
	end
	setDailyPuzzleButtonState(dailyPuzzleInfo and dailyPuzzleInfo.completed == true)

	local dailyInfo = HomePanels.GetCachedDailyRewardInfo and HomePanels.GetCachedDailyRewardInfo() or nil
	if not dailyInfo then
		dailyInfo = RemoteRegistry:GetFunction("GetDailyLoginReward"):InvokeServer()
		if HomePanels.SetCachedDailyRewardInfo then
			HomePanels.SetCachedDailyRewardInfo(dailyInfo)
		end
	end
	if dailyInfo and dailyInfo.canClaim then
		setHomeNotificationCount("daily", 1)
	else
		setHomeNotificationCount("daily", 0)
	end

	local function checkQuest(period)
		local board = QuestsPanel.GetCachedBoard and QuestsPanel.GetCachedBoard(period) or nil
		if not board then
			board = RemoteRegistry:GetFunction("GetQuestBoard"):InvokeServer(period)
			if QuestsPanel.SetCachedBoard then
				QuestsPanel.SetCachedBoard(period, board)
			end
		end
		if not board or typeof(board) ~= "table" then
			return nil, 0
		end
		local key = tostring(board.key or "")
		local claimable = 0
		for _, quest in ipairs(board.quests or {}) do
			if quest.completed == true and quest.claimed ~= true then
				claimable += 1
			end
		end
		return key, claimable
	end

	local _, dailyClaimable = checkQuest("daily")
	local _, weeklyClaimable = checkQuest("weekly")
	setHomeNotificationCount("quests", dailyClaimable + weeklyClaimable)

	local achievementsBoard = HomePanels.GetCachedAchievementsBoard and HomePanels.GetCachedAchievementsBoard() or nil
	if not achievementsBoard then
		achievementsBoard = RemoteRegistry:GetFunction("GetAchievements"):InvokeServer()
		if HomePanels.SetCachedAchievementsBoard then
			HomePanels.SetCachedAchievementsBoard(achievementsBoard)
		end
	end
	local unlocked = tonumber(achievementsBoard and achievementsBoard.unlocked) or 0
	if lastAchievementUnlockedSeen == nil then
		lastAchievementUnlockedSeen = unlocked
	elseif unlocked > lastAchievementUnlockedSeen then
		local delta = unlocked - lastAchievementUnlockedSeen
		lastAchievementUnlockedSeen = unlocked
		setHomeNotificationCount("achievements", math.max(uiState.homeNotificationCounts.achievements or 0, delta))
	end
	if (uiState.homeNotificationCounts.achievements or 0) == 0 then
		lastAchievementUnlockedSeen = unlocked
	end

	local inviteCount = 0
	for _ in pairs(pendingPvPInvites) do
		inviteCount += 1
	end
	setHomeNotificationCount("oneVsOne", inviteCount)
end

local function openDailyRewardsPanel()
	HomePanels.OpenDailyRewards()
end

local function openShopPanel()
	if TutorialController.IsActive and TutorialController.IsActive() then
		return
	end
	HomePanels.OpenShop()
end

ClientBridge.SetCallback("OpenShopPanel", openShopPanel)

local function openGeneralInfo(titleText, subtitleText, options)
	HomePanels.OpenGeneralInfo(titleText, subtitleText, options)
end

local function openSettingsPanel()
	HomePanels.OpenSettings()
end

local function openProfilePanel()
	HomePanels.OpenProfile()
end

local function openAchievementsPanel()
	HomePanels.SetLastAchievementUnlockedSeen(lastAchievementUnlockedSeen)
	HomePanels.OpenAchievements()
	lastAchievementUnlockedSeen = HomePanels.GetLastAchievementUnlockedSeen()
end

ModeFlows.Init({
	UIManager = UIManager,
	RemoteRegistry = RemoteRegistry,
	GameBoard = GameBoard,
	LetterWheel = LetterWheel,
	InputState = InputState,
	gameScreen = gameScreen,
	frames = frames,
	bonusWordsFrame = bonusWordsFrame,
	pvpFrame = pvpFrame,
	clearGuessedBonusWords = clearGuessedBonusWords,
	applyGameScenaryForPack = applyGameScenaryForPack,
	showLoadedGameScreen = showLoadedGameScreen,
	transitionFinishedGameToHome = transitionFinishedGameToHome,
	openGeneralInfo = openGeneralInfo,
	cancelOnboardingTutorial = function()
		cancelOnboardingTutorial()
	end,
	onCoinsUpdated = function(coins)
		ClientBridge.Call("OnCoinsUpdated", coins)
	end,
	getIsPvPMatch = function()
		return isPvPMatch
	end,
	setIsPvPMatch = function(v)
		isPvPMatch = v
	end,
	getIsDailyPuzzleMode = function()
		return isDailyPuzzleMode
	end,
	setIsDailyPuzzleMode = function(v)
		isDailyPuzzleMode = v
	end,
	getIsTimedMode = function()
		return isTimedMode
	end,
	setIsTimedMode = function(v)
		isTimedMode = v
	end,
	getIsHardcoreMode = function()
		return isHardcoreMode
	end,
	setIsHardcoreMode = function(v)
		isHardcoreMode = v
	end,
	getTimedMatchToken = function()
		return timedMatchToken
	end,
	setTimedMatchToken = function(v)
		timedMatchToken = v
	end,
	getTimedModeState = function()
		return timedModeState
	end,
	setTimedModeState = function(v)
		timedModeState = v
	end,
	setTimedExitPending = function(v)
		timedExitPending = v == true
	end,
	getHardcoreState = function()
		return hardcoreState
	end,
	setHardcoreState = function(v)
		hardcoreState = v
	end,
})

local function bindInGameHintButton(gameButtonsRef, inGameBarRef)
	local hintBtn = (
		gameButtonsRef and (gameButtonsRef:FindFirstChild("Hint") or gameButtonsRef:FindFirstChild("HintButton"))
	) or (inGameBarRef and inGameBarRef:FindFirstChild("HintButton"))
	if not hintBtn or not hintBtn:IsA("GuiButton") then
		return
	end
	if hintBtn:GetAttribute("Wired") then
		return
	end
	hintBtn:SetAttribute("Wired", true)

	local hintSelectionPanel = frames and frames:FindFirstChild("HintSelection")
	local hintSelectionFrame = hintSelectionPanel and (hintSelectionPanel:FindFirstChild("Frame") or hintSelectionPanel)
	local hintSelectionCoinsRoot = hintSelectionFrame and hintSelectionFrame:FindFirstChild("Coins", true)
	local hintSelectionRobuxOneRoot = hintSelectionFrame and hintSelectionFrame:FindFirstChild("RobuxOne", true)
	local hintSelectionRobuxTenRoot = hintSelectionFrame and hintSelectionFrame:FindFirstChild("RobuxTen", true)

	local function resolveHintSelectionButton(name)
		local root = hintSelectionFrame and hintSelectionFrame:FindFirstChild(name, true)
		if not root then
			return nil
		end
		if root:IsA("GuiButton") then
			return root
		end
		local nested = root:FindFirstChild("Purchase", true)
		if nested and nested:IsA("GuiButton") then
			return nested
		end
		return nil
	end

	local hintSelectionClose = resolveHintSelectionButton("Close")
	local hintSelectionCoins = resolveHintSelectionButton("Coins")
	local hintSelectionRobuxOne = resolveHintSelectionButton("RobuxOne")
	local hintSelectionRobuxTen = resolveHintSelectionButton("RobuxTen")
	local hintCoinCost = 150
	local hintSelectionPulseButtons = {}
	local activeHintSelectionConfig = {
		coinCost = hintCoinCost,
		robuxOneKind = nil,
		robuxOnePrice = 0,
		robuxOneProductId = 0,
		robuxTenPrice = 0,
		robuxTenProductId = 0,
	}

	local function stopHintSelectionButtonPulse(button)
		if not (button and button:IsA("GuiButton")) then
			return
		end
		button:SetAttribute("HintSelectionPulseActive", false)
		local stroke = button:FindFirstChild("HintSelectionPulseStroke")
		if stroke and stroke:IsA("UIStroke") then
			stroke.Thickness = 0
			stroke.Transparency = 1
		end
	end

	local function startHintSelectionButtonPulse(button)
		if not (button and button:IsA("GuiButton")) then
			return
		end
		for _, other in ipairs(hintSelectionPulseButtons) do
			if other ~= button then
				stopHintSelectionButtonPulse(other)
			end
		end
		if button:GetAttribute("HintSelectionPulseActive") == true then
			return
		end
		button:SetAttribute("HintSelectionPulseActive", true)
		task.spawn(shakeButtonOnce, button)
		local stroke = button:FindFirstChild("HintSelectionPulseStroke")
		if not stroke then
			stroke = Instance.new("UIStroke")
			stroke.Name = "HintSelectionPulseStroke"
			stroke.Color = Color3.fromRGB(255, 255, 255)
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Thickness = 0
			stroke.Transparency = 1
			stroke.Parent = button
		end
		task.spawn(function()
			while button.Parent and button:GetAttribute("HintSelectionPulseActive") == true do
				stroke.Thickness = 0
				stroke.Transparency = 0.55
				local pulse =
					TweenService:Create(stroke, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
						Thickness = 5,
						Transparency = 1,
					})
				pulse:Play()
				pulse.Completed:Wait()
				if button:GetAttribute("HintSelectionPulseActive") ~= true then
					break
				end
				task.wait(0.1)
			end
			if stroke and stroke.Parent then
				stroke.Thickness = 0
				stroke.Transparency = 1
			end
		end)
	end

	local function wireHintSelectionHover(button)
		if not (button and button:IsA("GuiButton")) or button:GetAttribute("HintSelectionHoverWired") then
			return
		end
		button:SetAttribute("HintSelectionHoverWired", true)
		table.insert(hintSelectionPulseButtons, button)
		button.MouseEnter:Connect(function()
			startHintSelectionButtonPulse(button)
		end)
		button.MouseLeave:Connect(function()
			stopHintSelectionButtonPulse(button)
		end)
		button.SelectionGained:Connect(function()
			startHintSelectionButtonPulse(button)
		end)
		button.SelectionLost:Connect(function()
			stopHintSelectionButtonPulse(button)
		end)
	end

	local function closeHintSelection()
		if hintSelectionPanel and hintSelectionPanel:IsA("GuiObject") then
			for _, button in ipairs(hintSelectionPulseButtons) do
				stopHintSelectionButtonPulse(button)
			end
			uiState.hideAnimatedPanel(hintSelectionPanel)
		end
	end

	local function setHintSelectionDealLabel(root, price)
		local label = root and root:FindFirstChild("DealName", true)
		if label and label:IsA("TextLabel") then
			label.Text = tostring(math.max(0, math.floor(tonumber(price) or 0)))
		end
	end

	local function setHintSelectionRobuxLabel(root, price)
		local label = root and root:FindFirstChild("DealName", true)
		if label and label:IsA("TextLabel") then
			label.Text = utf8.char(0xE002) .. tostring(math.max(0, math.floor(tonumber(price) or 0)))
		end
	end

	local function resolveHintSelectionConfig()
		local hintProducts = MonetizationConfig.HintProducts or {}
		local singleProduct = hintProducts.singleHint
		local singleKind = nil
		if isPvPMatch then
			singleProduct = hintProducts.pvpHint or singleProduct
			singleKind = "pvp_hint"
		elseif isDailyPuzzleMode then
			singleProduct = hintProducts.dailyHint or singleProduct
			singleKind = "daily_hint"
		end
		local tenProduct = hintProducts.hints10
		return {
			coinCost = hintCoinCost,
			robuxOneKind = singleKind,
			robuxOnePrice = tonumber(singleProduct and singleProduct.robux) or 0,
			robuxOneProductId = tonumber(singleProduct and singleProduct.id) or 0,
			robuxTenPrice = tonumber(tenProduct and tenProduct.robux) or 0,
			robuxTenProductId = tonumber(tenProduct and tenProduct.id) or 0,
		}
	end

	local function openHintSelection()
		if not (hintSelectionPanel and hintSelectionPanel:IsA("GuiObject")) then
			openShopPanel()
			return
		end
		activeHintSelectionConfig = resolveHintSelectionConfig()
		setHintSelectionDealLabel(hintSelectionCoinsRoot, activeHintSelectionConfig.coinCost)
		setHintSelectionRobuxLabel(hintSelectionRobuxOneRoot, activeHintSelectionConfig.robuxOnePrice)
		setHintSelectionRobuxLabel(hintSelectionRobuxTenRoot, activeHintSelectionConfig.robuxTenPrice)
		uiState.showAnimatedPanel(hintSelectionPanel)
		if hintSelectionFrame and hintSelectionFrame:IsA("GuiObject") then
			hintSelectionFrame.Visible = true
		end
	end

	if hintSelectionPanel and not hintSelectionPanel:GetAttribute("Wired") then
		hintSelectionPanel:SetAttribute("Wired", true)
		wireHintSelectionHover(hintSelectionCoins)
		wireHintSelectionHover(hintSelectionRobuxOne)
		wireHintSelectionHover(hintSelectionRobuxTen)
		if hintSelectionClose and hintSelectionClose:IsA("GuiButton") then
			hintSelectionClose.MouseButton1Click:Connect(closeHintSelection)
		end
		if hintSelectionCoins and hintSelectionCoins:IsA("GuiButton") then
			hintSelectionCoins.MouseButton1Click:Connect(function()
				local success = RemoteRegistry:GetFunction("BuyHintsWithCoins")
					:InvokeServer(1, activeHintSelectionConfig.coinCost)
				if success then
					UIEffects.PlaySound("Purchase")
					closeHintSelection()
				else
					UIEffects.PlaySound("Error")
					UIManager:ShowAlert("Not enough coins", "error")
				end
			end)
		end
		if hintSelectionRobuxOne and hintSelectionRobuxOne:IsA("GuiButton") then
			hintSelectionRobuxOne.MouseButton1Click:Connect(function()
				closeHintSelection()
				if activeHintSelectionConfig.robuxOneKind then
					uiState.promptSpecialHintPurchase(activeHintSelectionConfig.robuxOneKind)
					return
				end
				if activeHintSelectionConfig.robuxOneProductId > 0 then
					MarketplaceService:PromptProductPurchase(player, activeHintSelectionConfig.robuxOneProductId)
				else
					UIManager:ShowAlert("Set 1-hint product id first", "error")
				end
			end)
		end
		if hintSelectionRobuxTen and hintSelectionRobuxTen:IsA("GuiButton") then
			hintSelectionRobuxTen.MouseButton1Click:Connect(function()
				closeHintSelection()
				if activeHintSelectionConfig.robuxTenProductId > 0 then
					MarketplaceService:PromptProductPurchase(player, activeHintSelectionConfig.robuxTenProductId)
				else
					UIManager:ShowAlert("Set 10-hint product id first", "error")
				end
			end)
		end
	end

	local function handleHintButtonPress()
		if ClientBridge.Call("TutorialAllowsAction", "hint") == false then
			return false
		end
		if TutorialController.IsActive() then
			local hintCell = GameBoard.GetFirstHiddenCell and GameBoard:GetFirstHiddenCell()
			if hintCell and hintCell.row ~= nil and hintCell.col ~= nil then
				onTutorialHintUsed({
					row = hintCell.row,
					col = hintCell.col,
					letter = hintCell.letter,
					mode = "hint",
				})
			else
				UIEffects.PlaySound("Error")
				UIManager:ShowAlert("Tutorial hint unavailable", "error")
			end
			return true
		end
		if isHardcoreMode then
			UIEffects.PlaySound("Error")
			UIManager:ShowAlert("Hints disabled in hardcore", "error")
			return false
		end
		local hintCount = tonumber(playerData.hints) or 0
		if hintCount <= 0 then
			openHintSelection()
			return true
		end
		GameBoard:RequestHint()
		return true
	end

	hintBtn.MouseButton1Click:Connect(handleHintButtonPress)
	ClientBridge.SetCallback("PressHintButton", handleHintButtonPress)
	ClientBridge.SetCallback("CloseHintSelection", closeHintSelection)
end

local function bindInGameButtons(gameScreenRef)
	if not gameScreenRef then
		return
	end
	local inGameBarRef = gameScreenRef:FindFirstChild("InGameBar")
	local gameButtonsRef = gameScreenRef:FindFirstChild("Buttons")
	if not (inGameBarRef or gameButtonsRef) then
		return
	end

	local gameCurrencyBtn = gameButtonsRef and gameButtonsRef:FindFirstChild("Currency")
	if gameCurrencyBtn and gameCurrencyBtn:IsA("GuiButton") and not gameCurrencyBtn:GetAttribute("Wired") then
		gameCurrencyBtn:SetAttribute("Wired", true)
		gameCurrencyBtn.MouseButton1Click:Connect(openShopPanel)
	end

	local backBtn = (gameButtonsRef and gameButtonsRef:FindFirstChild("Return"))
		or (inGameBarRef and inGameBarRef:FindFirstChild("Return"))
	if backBtn and backBtn:IsA("GuiButton") and not backBtn:GetAttribute("Wired") then
		backBtn:SetAttribute("Wired", true)
		backBtn.MouseButton1Click:Connect(function()
			if gameExitPending then
				return
			end
			if TutorialController.IsActive and TutorialController.IsActive() then
				return
			end
			invalidateAutoAdvanceToken()
			if isPvPMatch then
				gameExitPending = true
				RemoteRegistry:GetFunction("LeavePvPMatch"):InvokeServer()
				return
			end
			if isTimedMode then
				if timedExitPending then
					return
				end
				gameExitPending = true
				timedExitPending = true
				local resp = RemoteRegistry:GetFunction("FinishTimedMode"):InvokeServer()
				finishTimedToLobby(resp and resp.reward, resp and resp.coins, resp and resp.solvedCount)
				return
			end
			if isHardcoreMode then
				gameExitPending = true
				stopHardcoreMode(true)
				return
			end
			if isDailyPuzzleMode then
				gameExitPending = true
				isDailyPuzzleMode = false
				cancelOnboardingTutorial()
				InputState:SetEnabled(false)
				transitionGameToLobbyScreen("HomeScreen")
				return
			end
			gameExitPending = true
			isDailyPuzzleMode = false
			cancelOnboardingTutorial()
			InputState:SetEnabled(false)
			transitionGameToLobbyScreen("LevelSelect")
		end)
	end

	bindInGameHintButton(gameButtonsRef, inGameBarRef)
end

local function handleWordFound(result)
	local wheelCenter = LetterWheel.GetWheelCenter and LetterWheel:GetWheelCenter()
	if TutorialController.PrepareWordTransition then
		TutorialController.PrepareWordTransition(result)
	end
	GameBoard:OnWordResult(result, wheelCenter)

	if not result.valid then
		LetterWheel:FlashInvalid()
		local reason = tostring(result.reason or "")
		if reason == "too short" then
			UIManager:ShowAlert("Guesses need at least 3 letters", "error", {
				debounceKey = "guess_too_short",
			})
		else
			UIEffects.PlaySound("NotificationLow")
		end
	else
		UIEffects.PlaySound("NotificationMid")
		if LetterWheel.FlashValid then
			LetterWheel:FlashValid()
		end
		if result.isBonus then
			local wordUpper = tostring(result.word or ""):upper()
			local exists = false
			for _, w in ipairs(guessedBonusWords) do
				if w == wordUpper then
					exists = true
					break
				end
			end
			if not exists and wordUpper ~= "" then
				table.insert(guessedBonusWords, wordUpper)
				updateBonusWordsCounter()
			end
			playBonusCoinFly(result.coinsEarned or 5)
			playBonusWordFly(result.word)
		end
	end
	if onTutorialWordFound then
		onTutorialWordFound(result)
	end
end

uiState.setPlayerImageAsync = function(imageLabel, userId)
	if not imageLabel or not imageLabel:IsA("ImageLabel") then
		return
	end
	imageLabel.Image = "rbxassetid://0"
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and imageLabel and imageLabel.Parent then
			imageLabel.Image = content
		end
	end)
end

AdminPanel.Init({
	player = player,
	frames = frames,
	RemoteRegistry = RemoteRegistry,
	UIManager = UIManager,
	HomePanels = HomePanels,
	showPanel = uiState.showAnimatedPanel,
	hidePanel = uiState.hideAnimatedPanel,
	setPlayerImageAsync = uiState.setPlayerImageAsync,
})

uiState.ensureListPadding = function(container, paddingOffset)
	if not container then
		return
	end
	local layout = container:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, paddingOffset or 10)
	end
end

local function countPendingInvites()
	local count = 0
	for _ in pairs(pendingPvPInvites) do
		count += 1
	end
	return count
end

local function refreshPvPInviteBadge()
	setHomeNotificationCount("oneVsOne", countPendingInvites())
end

local function pruneExpiredPvPInvites()
	local now = os.clock()
	local removedAny = false
	for inviterUserId, invite in pairs(pendingPvPInvites) do
		local expiresAt = tonumber(invite and invite.expiresAt) or 0
		if expiresAt > 0 and expiresAt <= now then
			pendingPvPInvites[inviterUserId] = nil
			removedAny = true
		end
	end
	if removedAny then
		refreshPvPInviteBadge()
	end
	return removedAny
end

local function getPvPPanelContentRoot(panel)
	if not panel then
		return nil
	end
	local frameRoot = panel:FindFirstChild("Frame") or panel
	local scroll = frameRoot:FindFirstChildWhichIsA("ScrollingFrame", true)
	if scroll then
		return scroll:FindFirstChild("Content") or scroll
	end
	local content = frameRoot:FindFirstChild("Content", true)
	if content and content:IsA("GuiObject") then
		return content
	end
	return frameRoot
end

local function clearPvPListContent(content, preserved)
	for _, child in ipairs(content:GetChildren()) do
		if not preserved[child] and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function addPvPSeparator(content, template, titleText)
	if not (content and template) then
		return
	end
	local row = template:Clone()
	row.Name = "Separator_" .. tostring(titleText)
	row.Visible = true
	row.Parent = content
	row.LayoutOrder = (titleText == "- Invites -") and 10 or 100
	local title = row:FindFirstChild("Title", true)
	if title and title:IsA("TextLabel") then
		title.Text = tostring(titleText)
	end
end

local function clearPvPInviteSection(content)
	if not content then
		return
	end
	for _, child in ipairs(content:GetChildren()) do
		if child.Name == "Separator_- Invites -" or string.sub(child.Name, 1, 7) == "Invite_" then
			child:Destroy()
		end
	end
end

local function addPvPInviteRow(content, template, inviterUserId, invite)
	if not (content and template and invite) then
		return
	end
	local row = template:Clone()
	row.Name = "Invite_" .. tostring(inviterUserId)
	row.Visible = true
	row.Parent = content
	row.LayoutOrder = 10 + tonumber(inviterUserId) % 100000

	local nameLabel = row:FindFirstChild("Label", true)
	local mugshot = row:FindFirstChild("Mugshot", true)
	local acceptBtn = row:FindFirstChild("Accept", true)
	local denyBtn = row:FindFirstChild("Deny", true)
	local barBg = row:FindFirstChild("TimedBar", true)
		or row:FindFirstChild("BarBG", true)
		or row:FindFirstChild("Bar", true)
	local fill = barBg and barBg:FindFirstChild("Fill", true)
	local timerLabel = row:FindFirstChild("Timer", true)
	local expiresAt = tonumber(invite.expiresAt) or 0
	local inviteName = tostring(invite.username or invite.name or "Player")

	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = inviteName
	end
	uiState.setPlayerImageAsync(mugshot, inviterUserId)

	if fill and fill:IsA("GuiObject") then
		fill.Size = UDim2.fromScale(0, 1)
		local duration = math.max(0, expiresAt - os.clock())
		if duration > 0 then
			TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
				Size = UDim2.fromScale(1, 1),
			}):Play()
		else
			fill.Size = UDim2.fromScale(1, 1)
		end
	end

	local handled = false
	local function finalizeInvite(accepted)
		if handled then
			return
		end
		if acceptBtn and acceptBtn:IsA("GuiButton") then
			acceptBtn.Active = false
			acceptBtn.AutoButtonColor = false
		end
		if denyBtn and denyBtn:IsA("GuiButton") then
			denyBtn.Active = false
			denyBtn.AutoButtonColor = false
		end
		if accepted then
			local result = RemoteRegistry:GetFunction("RespondPvPInvite"):InvokeServer(inviterUserId, true)
			if not (result and result.success) then
				if acceptBtn and acceptBtn:IsA("GuiButton") then
					acceptBtn.Active = true
					acceptBtn.AutoButtonColor = true
				end
				if denyBtn and denyBtn:IsA("GuiButton") then
					denyBtn.Active = true
					denyBtn.AutoButtonColor = true
				end
				UIManager:ShowAlert(result and result.message or "Could not accept invite", "error")
				return
			end
		else
			RemoteRegistry:GetFunction("RespondPvPInvite"):InvokeServer(inviterUserId, false)
		end
		handled = true
		local contentRoot = row and row.Parent
		pendingPvPInvites[inviterUserId] = nil
		refreshPvPInviteBadge()
		if row and row.Parent then
			row:Destroy()
		end
		if contentRoot and not next(pendingPvPInvites) then
			local inviteSeparator = contentRoot:FindFirstChild("Separator_- Invites -")
			if inviteSeparator then
				inviteSeparator:Destroy()
			end
		end
	end

	if acceptBtn and acceptBtn:IsA("GuiButton") then
		acceptBtn.MouseButton1Click:Connect(function()
			finalizeInvite(true)
		end)
	end

	if denyBtn and denyBtn:IsA("GuiButton") then
		denyBtn.MouseButton1Click:Connect(function()
			finalizeInvite(false)
		end)
	end

	task.spawn(function()
		while row.Parent and pendingPvPInvites[inviterUserId] == invite and not handled do
			local remaining = math.max(0, math.ceil(expiresAt - os.clock()))
			if timerLabel and timerLabel:IsA("TextLabel") then
				timerLabel.Text = tostring(remaining) .. "s"
			end
			if remaining <= 0 then
				pendingPvPInvites[inviterUserId] = nil
				refreshPvPInviteBadge()
				if pvpFrame and pvpFrame.Visible then
					uiState.renderPvPPanel()
				end
				break
			end
			task.wait(0.2)
		end
	end)
end

local function addPvPPlayerRow(content, template, info)
	if not (content and template and info) then
		return
	end
	local row = template:Clone()
	row.Name = "Player_" .. tostring(info.userId)
	row.Visible = true
	row.Parent = content
	row.LayoutOrder = 1000 + tonumber(info.userId) % 1000000

	local nameLabel = row:FindFirstChild("Label", true)
	local mugshot = row:FindFirstChild("Mugshot", true)
	local requestBtn = row:FindFirstChild("Request", true)

	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = tostring(info.name or "Player")
	end
	uiState.setPlayerImageAsync(mugshot, info.userId)

	if requestBtn and requestBtn:IsA("GuiButton") then
		if info.inMatch then
			requestBtn.Active = false
			requestBtn.AutoButtonColor = false
		else
			requestBtn.Active = true
			requestBtn.AutoButtonColor = true
			requestBtn.MouseButton1Click:Connect(function()
				local result = RemoteRegistry:GetFunction("SendPvPInvite"):InvokeServer(info.userId)
				if result and result.success then
					requestBtn.Active = false
					requestBtn.AutoButtonColor = false
					UIManager:ShowAlert("Invite sent to " .. tostring(info.name), "success")
				else
					UIManager:ShowAlert((result and result.message) or "Invite failed", "error")
				end
			end)
		end
	end
end

local function updatePvPInviteSection()
	local panel = uiState.ensurePvPFrame()
	if not (panel and panel.Visible) then
		return
	end
	local frameRoot = panel:FindFirstChild("Frame") or panel
	local content = getPvPPanelContentRoot(panel)
	local playerMatchTemplate = frameRoot and frameRoot:FindFirstChild("PlayerMatchTemplate", true)
	local separatorTemplate = frameRoot and frameRoot:FindFirstChild("Seperator", true)
	if not content or not playerMatchTemplate or not separatorTemplate then
		return
	end

	clearPvPInviteSection(content)

	local sortedInvites = {}
	for inviterUserId, invite in pairs(pendingPvPInvites) do
		table.insert(sortedInvites, {
			userId = inviterUserId,
			invite = invite,
		})
	end
	table.sort(sortedInvites, function(a, b)
		local aExpiry = tonumber(a.invite and a.invite.expiresAt) or 0
		local bExpiry = tonumber(b.invite and b.invite.expiresAt) or 0
		if aExpiry == bExpiry then
			return tostring(a.invite and a.invite.name or "") < tostring(b.invite and b.invite.name or "")
		end
		return aExpiry < bExpiry
	end)

	if #sortedInvites > 0 then
		addPvPSeparator(content, separatorTemplate, "- Invites -")
		for index, entry in ipairs(sortedInvites) do
			addPvPInviteRow(content, playerMatchTemplate, entry.userId, entry.invite)
			local row = content:FindFirstChild("Invite_" .. tostring(entry.userId))
			if row then
				row.LayoutOrder = 10 + index
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.5)
		if pruneExpiredPvPInvites() and pvpFrame and pvpFrame.Visible then
			updatePvPInviteSection()
		end
	end
end)

stopTimedModeTimer = function()
	ModeFlows.StopTimedModeTimer()
end

finishTimedToLobby = function(extraReward, finalCoins, solvedCount)
	ModeFlows.FinishTimedToLobby(extraReward, finalCoins, solvedCount)
end

local function requestNextTimedPuzzle()
	return ModeFlows.RequestNextTimedPuzzle()
end

stopHardcoreMode = function(goToLobby)
	ModeFlows.StopHardcoreMode(goToLobby)
end

local function startTimedModeFromHome(modeKey)
	ModeFlows.StartTimedModeFromHome(modeKey)
end

local function beginOnboardingTutorial(level)
	if tutorialShownThisSession then
		return
	end
	if TutorialController.Begin(level) then
		tutorialSessionActive = true
		tutorialShownThisSession = true
	end
end

onTutorialWordFound = function(result)
	TutorialController.OnWordFound(result)
end

onTutorialHintUsed = function(info)
	TutorialController.OnHintUsed(info)
end

onTutorialArrowModeStarted = function()
	if TutorialController.OnArrowModeStarted then
		TutorialController.OnArrowModeStarted()
	end
end

cancelOnboardingTutorial = function()
	tutorialToken += 1
	tutorialSessionActive = false
	TutorialController.Cancel()
end

ClientBridge.SetCallback("OnTutorialCompletedClient", function()
	tutorialCompleted = true
	tutorialSessionActive = false
	tutorialShownThisSession = true
	TutorialController.SetCompleted(true)
end)

uiState.ensurePvPFrame = function()
	if not frames then
		return nil
	end
	if not pvpFrame then
		pvpFrame = frames:FindFirstChild("PlayerList") or frames:FindFirstChild("PvPPanel")
	end
	if pvpFrame and pvpFrame:IsA("Frame") then
		if not pvpFrame:GetAttribute("WiredClose") then
			pvpFrame:SetAttribute("WiredClose", true)
			local closeBtn = pvpFrame:FindFirstChild("Close", true)
			if closeBtn and closeBtn:IsA("GuiButton") then
				closeBtn.MouseButton1Click:Connect(function()
					uiState.hideAnimatedPanel(pvpFrame)
				end)
			end
		end
		return pvpFrame
	end
	return nil
end

uiState.renderPvPPanel = function()
	local panel = uiState.ensurePvPFrame()
	if not panel then
		return
	end
	pruneExpiredPvPInvites()
	local frameRoot = panel:FindFirstChild("Frame") or panel
	local content = getPvPPanelContentRoot(panel)
	local playerTemplate = frameRoot and frameRoot:FindFirstChild("PlayerTemplate", true)
	local playerMatchTemplate = frameRoot and frameRoot:FindFirstChild("PlayerMatchTemplate", true)
	local separatorTemplate = frameRoot and frameRoot:FindFirstChild("Seperator", true)
	if not content or not playerTemplate or not playerMatchTemplate or not separatorTemplate then
		return
	end
	uiState.ensureListPadding(content, 12)
	clearPvPListContent(content, {
		[playerTemplate] = true,
		[playerMatchTemplate] = true,
		[separatorTemplate] = true,
	})

	local sortedInvites = {}
	for inviterUserId, invite in pairs(pendingPvPInvites) do
		table.insert(sortedInvites, {
			userId = inviterUserId,
			invite = invite,
		})
	end
	table.sort(sortedInvites, function(a, b)
		local aExpiry = tonumber(a.invite and a.invite.expiresAt) or 0
		local bExpiry = tonumber(b.invite and b.invite.expiresAt) or 0
		if aExpiry == bExpiry then
			return tostring(a.invite and a.invite.name or "") < tostring(b.invite and b.invite.name or "")
		end
		return aExpiry < bExpiry
	end)

	if #sortedInvites > 0 then
		addPvPSeparator(content, separatorTemplate, "- Invites -")
		for index, entry in ipairs(sortedInvites) do
			addPvPInviteRow(content, playerMatchTemplate, entry.userId, entry.invite)
			local row = content:FindFirstChild("Invite_" .. tostring(entry.userId))
			if row then
				row.LayoutOrder = 10 + index
			end
		end
	end

	local playersList = RemoteRegistry:GetFunction("GetPvPPlayers"):InvokeServer() or {}
	table.sort(playersList, function(a, b)
		return tostring(a and a.name or ""):lower() < tostring(b and b.name or ""):lower()
	end)
	if #playersList > 0 then
		addPvPSeparator(content, separatorTemplate, "- Players -")
		for _, info in ipairs(playersList) do
			addPvPPlayerRow(content, playerTemplate, info)
		end
	end
end

uiState.setModeLocked = function(button, locked)
	if not button then
		return
	end
	local icon = button:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		icon.ImageTransparency = locked and 0.3 or 0.1
	end
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = locked and 0.64 or 0
	end
	local lock = button:FindFirstChild("Lock")
	if lock and lock:IsA("ImageLabel") then
		lock.Visible = locked
	end
end

uiState.startLevelFromData = function(data)
	if not data then
		return
	end
	if tonumber(data.packId) ~= -1 then
		resetFreeplaySessionStreak()
	end
	playerData.lastPack = tonumber(data.packId) or playerData.lastPack or 1
	playerData.lastLevel = tonumber(data.levelId) or playerData.lastLevel or 1
	isDailyPuzzleMode = false
	isTimedMode = false
	isHardcoreMode = false
	ClientBridge.SetState("IsHardcoreMode", false)
	stopTimedModeTimer()
	InputState:SetEnabled(true)
	clearGuessedBonusWords()
	if bonusWordsFrame then
		bonusWordsFrame.Visible = false
	end
	GameBoard:LoadLevel(data)
	uiState.applySavedBoardProgress(data)
	LetterWheel:LoadLevel(data)
	updateAssistButtonNotifications()
	applyGameScenaryForPack(data.packId)
	showLoadedGameScreen()
end

local function startDailyPuzzleFromHome()
	local info = RemoteRegistry:GetFunction("GetDailyPuzzle"):InvokeServer(true)
	uiState.cachedDailyPuzzleInfo = info
	if not info or not info.puzzle then
		UIManager:ShowAlert("Daily puzzle unavailable", "error")
		return
	end
	setDailyPuzzleButtonState(info.completed == true)
	if info.completed then
		UIManager:ShowAlert("Daily puzzle already completed. New one tomorrow.", "bonus")
		return
	end
	resetFreeplaySessionStreak()
	isDailyPuzzleMode = true
	isTimedMode = false
	isHardcoreMode = false
	ClientBridge.SetState("IsHardcoreMode", false)
	stopTimedModeTimer()
	InputState:SetEnabled(true)
	clearGuessedBonusWords()
	if bonusWordsFrame then
		bonusWordsFrame.Visible = false
	end
	GameBoard:LoadLevel(info.puzzle)
	uiState.applySavedBoardProgress(info)
	LetterWheel:LoadLevel(info.puzzle)
	updateAssistButtonNotifications()
	applyGameScenaryForPack(info.puzzle and info.puzzle.packId)
	showLoadedGameScreen()
	UIManager:ShowAlert("Daily challenge started", "success")
end

local function wireHomeScreen()
	if not homeScreen then
		return
	end
	local btns = homeScreen:FindFirstChild("Buttons")
	if not btns then
		return
	end
	local playBtn = btns:FindFirstChild("Play")
	local levelsBtn = btns:FindFirstChild("Levels")
	local settingsBtn = btns:FindFirstChild("Settings")
	local profileBtn = btns:FindFirstChild("Profile")
	local leaderboardBtn = btns:FindFirstChild("Leaderboard") or homeScreen:FindFirstChild("Leaderboard", true)
	local adminBtn = btns:FindFirstChild("Admin")
	local shopBtn = btns:FindFirstChild("Shop")
	local currencyBtn = btns:FindFirstChild("Currency")
	local achievementsBtn = (btns and btns:FindFirstChild("Achievements"))
		or (homeScreen and homeScreen:FindFirstChild("Achievements", true))
	local videoAdBtn = btns:FindFirstChild("VideoAd")
	local dailyMainBtn = btns:FindFirstChild("Daily")
	local questsMainBtn = btns:FindFirstChild("Quests")
	local oneVsOneMainBtn = btns:FindFirstChild("OneVsOne")
	local lower = btns:FindFirstChild("LowerButtons")
	local dailyTopBtn = dailyMainBtn
	local dailyLowerBtn = lower and lower:FindFirstChild("Daily")
	local questsBtn = questsMainBtn or (lower and lower:FindFirstChild("Quests"))
	local hardcoreBtn = lower and lower:FindFirstChild("Hardcore")
	local timedBtn = lower and lower:FindFirstChild("Timed")
	local oneVsOneBtn = oneVsOneMainBtn or (lower and lower:FindFirstChild("OneVsOne"))

	local function refreshModeLocks(rankInfo)
		local currentRankId = rankInfo and rankInfo.id or "BRONZE_1"
		local timedLocked = not rankAtLeast(currentRankId, TIMED_REQUIRED_RANK)
		local hardcoreLocked = true
		uiState.setModeLocked(timedBtn, timedLocked)
		uiState.setModeLocked(hardcoreBtn, hardcoreLocked)
	end

	refreshModeLocks(playerData.rank)
	refreshPlayButtonLevelLabel()
	if adminBtn and adminBtn:IsA("GuiObject") then
		adminBtn.Visible = AdminPanel.IsAdmin()
	end

	if playBtn and playBtn:IsA("GuiButton") and not playBtn:GetAttribute("Wired") then
		playBtn:SetAttribute("Wired", true)
		playBtn.MouseButton1Click:Connect(function()
			local packId, levelId = findNextPlayableLevel()
			packId = tonumber(packId) or tonumber(playerData.lastPack) or 1
			levelId = tonumber(levelId) or tonumber(playerData.lastLevel) or 1
			local data, requestStatus = uiState.requestLevelData(packId, levelId, 1, 1)
			if requestStatus == "stale" then
				return
			end
			uiState.startLevelFromData(data)
		end)
	end
	if levelsBtn and levelsBtn:IsA("GuiButton") and not levelsBtn:GetAttribute("Wired") then
		levelsBtn:SetAttribute("Wired", true)
		levelsBtn.MouseButton1Click:Connect(function()
			LevelSelect:ShowPackList()
			applyLobbyScenary()
			UIManager:ShowScreen("LevelSelect")
		end)
	end

	if settingsBtn and settingsBtn:IsA("GuiButton") and not settingsBtn:GetAttribute("Wired") then
		settingsBtn:SetAttribute("Wired", true)
		settingsBtn.MouseButton1Click:Connect(function()
			openSettingsPanel()
		end)
	end
	if profileBtn and profileBtn:IsA("GuiButton") and not profileBtn:GetAttribute("Wired") then
		profileBtn:SetAttribute("Wired", true)
		profileBtn.MouseButton1Click:Connect(function()
			openProfilePanel()
		end)
	end
	if leaderboardBtn and leaderboardBtn:IsA("GuiButton") and not leaderboardBtn:GetAttribute("Wired") then
		leaderboardBtn:SetAttribute("Wired", true)
		leaderboardBtn.MouseButton1Click:Connect(function()
			HomePanels.CloseAllPanels(frames and frames:FindFirstChild("Leaderboard"))
			UIManager:ShowLeaderboard()
		end)
	end
	if adminBtn and adminBtn:IsA("GuiButton") and not adminBtn:GetAttribute("Wired") then
		adminBtn:SetAttribute("Wired", true)
		adminBtn.MouseButton1Click:Connect(AdminPanel.Open)
	end
	if dailyTopBtn and dailyTopBtn:IsA("GuiButton") and not dailyTopBtn:GetAttribute("Wired") then
		dailyTopBtn:SetAttribute("Wired", true)
		dailyTopBtn.MouseButton1Click:Connect(function()
			setHomeNotificationFlag("daily", false)
			openDailyRewardsPanel()
		end)
	end
	if dailyLowerBtn and dailyLowerBtn:IsA("GuiButton") and not dailyLowerBtn:GetAttribute("Wired") then
		dailyLowerBtn:SetAttribute("Wired", true)
		dailyLowerBtn.MouseButton1Click:Connect(function()
			setHomeNotificationFlag("daily", false)
			startDailyPuzzleFromHome()
		end)
	end
	if questsBtn and questsBtn:IsA("GuiButton") and not questsBtn:GetAttribute("Wired") then
		questsBtn:SetAttribute("Wired", true)
		questsBtn.MouseButton1Click:Connect(openQuestsPanel)
	end
	if currencyBtn and currencyBtn:IsA("GuiButton") and not currencyBtn:GetAttribute("Wired") then
		currencyBtn:SetAttribute("Wired", true)
		currencyBtn.MouseButton1Click:Connect(openShopPanel)
	end
	if shopBtn and shopBtn:IsA("GuiButton") and not shopBtn:GetAttribute("Wired") then
		shopBtn:SetAttribute("Wired", true)
		shopBtn.MouseButton1Click:Connect(openShopPanel)
	end
	if achievementsBtn and achievementsBtn:IsA("GuiButton") and not achievementsBtn:GetAttribute("Wired") then
		achievementsBtn:SetAttribute("Wired", true)
		achievementsBtn.MouseButton1Click:Connect(function()
			openAchievementsPanel()
		end)
	end
	if videoAdBtn and videoAdBtn:IsA("GuiButton") then
		videoAdBtn.Visible = false
		videoAdBtn.Active = false
		if not videoAdBtn:GetAttribute("Wired") then
			videoAdBtn:SetAttribute("Wired", true)
			videoAdBtn.MouseButton1Click:Connect(function()
				UIManager:ShowAlert("Video ads coming soon", "bonus")
			end)
		end
	end
	if oneVsOneBtn and oneVsOneBtn:IsA("GuiButton") and not oneVsOneBtn:GetAttribute("Wired") then
		oneVsOneBtn:SetAttribute("Wired", true)
		oneVsOneBtn.MouseButton1Click:Connect(function()
			setHomeNotificationFlag("oneVsOne", false)
			local panel = uiState.ensurePvPFrame()
			if panel then
				uiState.renderPvPPanel()
				HomePanels.CloseAllPanels(panel)
				uiState.showAnimatedPanel(panel)
			end
		end)
	end
	if timedBtn and timedBtn:IsA("GuiButton") and not timedBtn:GetAttribute("Wired") then
		timedBtn:SetAttribute("Wired", true)
		timedBtn.MouseButton1Click:Connect(function()
			local rankInfo = playerData.rank or {}
			if not rankAtLeast(rankInfo.id, TIMED_REQUIRED_RANK) then
				openGeneralInfo(
					"Hey!",
					"Reach " .. string.gsub(TIMED_REQUIRED_RANK, "_", " ") .. " rank to unlock timed mode",
					{
						showAccept = true,
						acceptText = "Okay",
					}
				)
				return
			end
			startTimedModeFromHome("classic")
		end)
	end
	if hardcoreBtn and hardcoreBtn:IsA("GuiButton") and not hardcoreBtn:GetAttribute("Wired") then
		hardcoreBtn:SetAttribute("Wired", true)
		hardcoreBtn.MouseButton1Click:Connect(function()
			openGeneralInfo("Coming soon!", "Hardcore mode is coming soon.", {
				showAccept = true,
				acceptText = "Okay",
			})
		end)
	end

	-- update lock state when rank changes
	homeScreen:SetAttribute("RefreshLocks", true)
	homeScreen:SetAttribute("TimedReq", TIMED_REQUIRED_RANK)
	homeScreen:SetAttribute("HardcoreReq", HARDCORE_REQUIRED_RANK)
	ClientBridge.SetCallback("RefreshHomeLocks", function(rankInfo)
		refreshModeLocks(rankInfo)
	end)
end

wireHomeScreen()
applyHomeNotificationBadges()
task.defer(pollHomeNotificationSources)
task.spawn(function()
	while hud and hud.Parent do
		task.wait(30)
		pcall(pollHomeNotificationSources)
	end
end)

task.spawn(function()
	while hud and hud.Parent do
		task.wait(3)
		local dailyBtn = getHomeButtonByNames({ "Daily" })
		local questsBtn = getHomeButtonByNames({ "Quests" })
		if (uiState.homeNotificationCounts.daily or 0) > 0 then
			task.spawn(shakeButtonOnce, dailyBtn)
		end
		if (uiState.homeNotificationCounts.quests or 0) > 0 then
			task.spawn(shakeButtonOnce, questsBtn)
		end
	end
end)

task.spawn(function()
	while hud and hud.Parent do
		task.wait(8)
		if not homeScreen or not homeScreen.Visible then
			continue
		end
		local btns = homeScreen:FindFirstChild("Buttons")
		local shopBtn = btns and btns:FindFirstChild("Shop")
		if shopBtn and shopBtn:IsA("GuiButton") and shopBtn.Visible then
			task.spawn(shakeButtonOnce, shopBtn)
		end
	end
end)

bindInGameButtons(gameScreen)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(userId, gamePassId, purchased)
	if userId ~= player.UserId or purchased ~= true then
		return
	end
	local premiumPassId = MonetizationConfig.Passes
			and MonetizationConfig.Passes.premium
			and tonumber(MonetizationConfig.Passes.premium.id)
		or 0
	if premiumPassId > 0 and tonumber(gamePassId) == premiumPassId then
		playerData.premiumOwned = true
		if LevelSelect.SetPremiumOwned then
			LevelSelect:SetPremiumOwned(true)
		end
		LevelSelect:ShowPackList()
	end
end)

LevelSelect:OnLevelChosen(function(packId, levelId)
	local data, requestStatus = uiState.requestLevelData(packId, levelId)
	if requestStatus == "stale" then
		return
	end
	if not data then
		return
	end

	if tonumber(data.packId) ~= -1 then
		resetFreeplaySessionStreak()
	end
	isDailyPuzzleMode = false
	isTimedMode = false
	isHardcoreMode = false
	ClientBridge.SetState("IsHardcoreMode", false)
	stopTimedModeTimer()
	InputState:SetEnabled(true)
	clearGuessedBonusWords()
	if bonusWordsFrame then
		bonusWordsFrame.Visible = false
	end
	GameBoard:LoadLevel(data)
	uiState.applySavedBoardProgress(data)
	LetterWheel:LoadLevel(data)
	updateAssistButtonNotifications()
	applyGameScenaryForPack(data.packId)
	showLoadedGameScreen()
	beginOnboardingTutorial(data)
end)

uiState.startPvPMatch = function(payload)
	local data = payload and payload.levelData
	if not data then
		UIManager:ShowAlert("Failed to start 1v1 match", "error")
		return
	end

	resetFreeplaySessionStreak()
	isPvPMatch = true
	isTimedMode = false
	isHardcoreMode = false
	ClientBridge.SetState("IsHardcoreMode", false)
	isDailyPuzzleMode = false
	cancelOnboardingTutorial()
	InputState:SetEnabled(true)
	clearGuessedBonusWords()
	if bonusWordsFrame then
		bonusWordsFrame.Visible = false
	end

	local oppName = payload.opponent and payload.opponent.name or "Opponent"
	GameBoard:LoadLevel(data, { isPvP = true, opponentName = oppName })
	LetterWheel:LoadLevel(data)
	updateAssistButtonNotifications()
	applyGameScenaryForPack(data.packId)
	showLoadedGameScreen()
	if pvpFrame then
		uiState.hideAnimatedPanel(pvpFrame)
	end
	UIManager:ShowAlert("1v1 started vs " .. tostring(oppName), "success")
end

uiState.endPvPMatch = function(result)
	if not isPvPMatch then
		return
	end

	resetFreeplaySessionStreak()
	isPvPMatch = false
	isTimedMode = false
	isHardcoreMode = false
	ClientBridge.SetState("IsHardcoreMode", false)
	isDailyPuzzleMode = false
	stopTimedModeTimer()
	InputState:SetEnabled(false)
	if gameScreen and gameScreen:IsA("GuiObject") then
		gameScreen.ClipsDescendants = true
	end
	local outcome = result and result.result or "draw"
	local reason = tostring(result and result.reason or "")
	transitionGameToLobbyScreen("LevelSelect", function()
		if outcome == "win" then
			if reason == "opponent forfeited" then
				UIManager:ShowAlert("1v1 win (opponent left)", "success")
			else
				UIManager:ShowAlert("1v1 win", "success")
			end
		elseif outcome == "lose" then
			UIManager:ShowAlert("1v1 lost", "error")
		else
			UIManager:ShowAlert("1v1 ended", "bonus")
		end
	end)
end

RemoteRegistry:GetEvent("PvPInviteReceived").OnClientEvent:Connect(function(info)
	local inviterUserId = info and tonumber(info.inviterUserId)
	local inviterName = info and tostring(info.inviterName or "Player")
	local expiresIn = math.max(1, math.floor(tonumber(info and info.expiresIn) or 60))
	if inviterUserId then
		pendingPvPInvites[inviterUserId] = {
			name = inviterName,
			username = inviterName,
			expiresAt = os.clock() + expiresIn,
		}
		refreshPvPInviteBadge()
		UIManager:ShowAlert(inviterName .. " sent a 1v1 invite", "bonus")
		if pvpFrame and pvpFrame.Visible then
			updatePvPInviteSection()
		end
	end
end)

RemoteRegistry:GetEvent("PvPInviteStatus").OnClientEvent:Connect(function(info)
	local status = info and info.status
	local targetName = info and tostring(info.targetName or "player")
	if status == "accepted" then
		UIManager:ShowAlert(targetName .. " accepted your invite", "success")
	elseif status == "declined" then
		UIManager:ShowAlert(targetName .. " declined your invite", "error")
	end
	pruneExpiredPvPInvites()
	refreshPvPInviteBadge()
	if pvpFrame and pvpFrame.Visible then
		updatePvPInviteSection()
	end
end)

RemoteRegistry:GetEvent("PvPMatchStart").OnClientEvent:Connect(function(payload)
	uiState.startPvPMatch(payload)
end)

RemoteRegistry:GetEvent("PvPOppWordProgress").OnClientEvent:Connect(function(info)
	GameBoard:AnimateOpponentWordProgress(info)
end)

RemoteRegistry:GetEvent("PvPMatchEnd").OnClientEvent:Connect(function(result)
	uiState.endPvPMatch(result)
end)

RemoteRegistry:GetEvent("WordFound").OnClientEvent:Connect(handleWordFound)

RemoteRegistry:GetEvent("LevelComplete").OnClientEvent:Connect(function(info)
	if isHardcoreMode then
		resetFreeplaySessionStreak()
		if hardcoreState then
			hardcoreState.streak = (hardcoreState.streak or 0) + 1
			UIManager:ShowAlert("Hardcore streak: " .. tostring(hardcoreState.streak), "success")
		end
		task.delay(0.35, function()
			if not isHardcoreMode then
				return
			end
			local resp = RemoteRegistry:GetFunction("GetHardcoreNextLevel"):InvokeServer()
			if not (resp and resp.success and resp.levelData) then
				stopHardcoreMode(true)
				return
			end
			clearGuessedBonusWords()
			if bonusWordsFrame then
				bonusWordsFrame.Visible = false
			end
			InputState:SetEnabled(true)
			GameBoard:LoadLevel(resp.levelData)
			LetterWheel:LoadLevel(resp.levelData)
			updateAssistButtonNotifications()
			applyGameScenaryForPack(resp.levelData.packId)
		end)
		return
	end
	if isTimedMode then
		resetFreeplaySessionStreak()
		cancelOnboardingTutorial()
		if (tonumber(info.packId) or 1) > 0 then
			playerData.progress = playerData.progress or {}
			local pKey = tostring(tonumber(info.packId) or 1)
			local lKey = tostring(tonumber(info.levelId) or 1)
			playerData.progress[pKey] = playerData.progress[pKey] or {}
			playerData.progress[pKey][lKey] = true
			playerData.lastPack, playerData.lastLevel = findNextPlayableLevel()
			refreshPlayButtonLevelLabel()
			LevelSelect:UpdateProgress(info.packId, info.levelId)
		end
		if timedModeState then
			timedModeState.solvedCount = (timedModeState.solvedCount or 0) + 1
		end
		InputState:SetEnabled(false)
		if isTimedMode then
			requestNextTimedPuzzle()
		end
		return
	end
	if tutorialSessionActive then
		return
	end

	isDailyPuzzleMode = false
	local completedPackId = tonumber(info and info.packId) or 0
	if completedPackId == -1 then
		freeplaySessionStreak += 1
		updateProfileRowValue(
			"current_freeplay_streak",
			tostring(info.stats and info.stats.currentFreeplayStreak or freeplaySessionStreak)
		)
		updateProfileRowValue(
			"best_freeplay_streak",
			tostring(info.stats and info.stats.highestFreeplayStreak or freeplaySessionStreak)
		)
	else
		resetFreeplaySessionStreak()
	end
	cancelOnboardingTutorial()
	InputState:SetEnabled(false)
	issueAutoAdvanceToken()
	playerData.progress = playerData.progress or {}
	if (tonumber(info.packId) or 1) > 0 then
		local pKey = tostring(tonumber(info.packId) or 1)
		local lKey = tostring(tonumber(info.levelId) or 1)
		playerData.progress[pKey] = playerData.progress[pKey] or {}
		playerData.progress[pKey][lKey] = true
		local nextPack, nextLevel = findNextPlayableLevel()
		playerData.lastPack = nextPack
		playerData.lastLevel = nextLevel
		refreshPlayButtonLevelLabel()
	end
	if completedPackId == -1 then
		playFreeplayStreakAnimation(freeplaySessionStreak, function()
			GameBoard:OnLevelComplete(info)
		end)
	else
		GameBoard:OnLevelComplete(info)
	end
	if (tonumber(info.packId) or 1) > 0 then
		LevelSelect:UpdateProgress(info.packId, info.levelId)
	end
	-- Show coin reward alert
	if info.coinsEarned then
		UIManager:ShowAlert("Level Complete! +" .. info.coinsEarned .. " coins!", "coin")
	end
	if tonumber(info.eventReward) and tonumber(info.eventReward) > 0 then
		UIManager:ShowAlert("Event bonus +" .. tostring(info.eventReward) .. " coins", "coin")
		if info.eventCompleted then
			UIManager:ShowAlert("Event track completed", "bonus")
		end
	end
	if info.perfectClear then
		local bonusReward = tonumber(info.perfectClearReward) or 0
		local msg = "Perfect clear! All bonus words found"
		if bonusReward > 0 then
			msg = msg .. " (+" .. bonusReward .. " coins)"
		end
		UIManager:ShowAlert(msg, "bonus")
	end
	local previousSkillLevel = math.clamp(math.floor(tonumber(playerData.skill and playerData.skill.level) or 1), 1, 5)
	if info.skill then
		playerData.skill = info.skill
		updateProfileRowValue(
			"skill_level",
			string.format("%d / 5", math.clamp(math.floor(tonumber(info.skill.level) or 1), 1, 5))
		)
		updateProfileRowValue("skill_score", string.format("%.2f / 100", tonumber(info.skill.score) or 0))
		updateProfileRowValue("skill_recent_levels", tostring(tonumber(info.skill.recentLevelsTracked) or 0))
		local nextSkillLevel = math.clamp(math.floor(tonumber(info.skill.level) or 1), 1, 5)
		if nextSkillLevel > previousSkillLevel then
			UIManager:ShowAlert("Skill level up! " .. tostring(nextSkillLevel) .. "/5", "success")
		end
	end
	-- Update coin display
	ClientBridge.Call("OnCoinsUpdated", info.coins)
	task.defer(pollHomeNotificationSources)
end)

RemoteRegistry:GetEvent("DailyPuzzleComplete").OnClientEvent:Connect(function(info)
	resetFreeplaySessionStreak()
	isDailyPuzzleMode = false
	isTimedMode = false
	stopTimedModeTimer()
	cancelOnboardingTutorial()
	InputState:SetEnabled(false)
	GameBoard:OnDailyComplete(info, function(dailyInfo)
		transitionFinishedGameToHome(function()
			setDailyPuzzleButtonState(true)
			uiState.cachedDailyPuzzleInfo = {
				completed = true,
				claimed = true,
				canPlay = false,
			}

			ClientBridge.Call("OnCoinsUpdated", dailyInfo and dailyInfo.coins or 0)

			local reward = tonumber(dailyInfo and dailyInfo.reward) or 0
			local streak = tonumber(dailyInfo and dailyInfo.streak) or 0
			UIManager:ShowAlert("Daily complete! +" .. tostring(reward) .. " coins", "coin")
			UIManager:ShowAlert("Daily streak: " .. tostring(streak), "bonus")
			task.defer(pollHomeNotificationSources)
		end)
	end)
end)

RemoteRegistry:GetEvent("HintReveal").OnClientEvent:Connect(function(info)
	GameBoard:RevealHintCell(info)
	onTutorialHintUsed(info)
end)

RemoteRegistry:GetEvent("UpdateHints").OnClientEvent:Connect(function(hints)
	playerData.hints = tonumber(hints) or 0
	ClientBridge.Call("OnHintsUpdated", hints)
	updateProfileRowValue("hints", playerData.hints)
	updateAssistButtonNotifications()
end)

RemoteRegistry:GetEvent("UpdateSelectionHints").OnClientEvent:Connect(function(tokens)
	ClientBridge.Call("OnSelectionHintsUpdated", tokens)
end)

RemoteRegistry:GetEvent("UpdateCoins").OnClientEvent:Connect(function(coins)
	playerData.coins = tonumber(coins) or playerData.coins or 0
	ClientBridge.Call("OnCoinsUpdated", coins)
	updateProfileRowValue("coins", playerData.coins)
end)

RemoteRegistry:GetEvent("DevProductPurchased").OnClientEvent:Connect(function()
	UIEffects.PlaySound("Purchase")
end)

RemoteRegistry:GetEvent("RankUpdated").OnClientEvent:Connect(function(payload)
	local newRank = payload and payload.newRank or nil
	local oldRank = payload and payload.oldRank or nil
	if newRank then
		playerData.rank = newRank
		updateHomeRankVisual(newRank)
		ClientBridge.Call("RefreshHomeLocks", newRank)
	end
	if newRank and oldRank and newRank.id ~= oldRank.id then
		UIManager:ShowAlert("Rank up! " .. tostring(newRank.name or newRank.id), "success")
	end
end)

if bonusWordsFrame then
	uiState.bonusWordsCloseButton = (bonusWordsFrame:FindFirstChild("Frame") or bonusWordsFrame):FindFirstChild("Close")
	if uiState.bonusWordsCloseButton and uiState.bonusWordsCloseButton:IsA("GuiButton") then
		uiState.bonusWordsCloseButton.MouseButton1Click:Connect(function()
			uiState.hideAnimatedPanel(bonusWordsFrame)
		end)
	end
	bonusWordsFrame.Visible = false
end

ClientBridge.SetCallback("OnLevelComplete", function(_info)
	if tutorialSessionActive then
		return
	end
	if isTimedMode or isHardcoreMode or isDailyPuzzleMode or isPvPMatch then
		return
	end
	-- GameBoard calls this after completion/fall sequence finishes.
	InputState:SetEnabled(false)
	local autoAdvanceToken = ClientBridge.GetState("PendingAutoAdvanceToken")
	GameHudTransitions.AnimateOut(function()
		task.delay(1, function()
			if tutorialSessionActive or isTimedMode or isHardcoreMode or isDailyPuzzleMode or isPvPMatch then
				return
			end
			ClientBridge.Call("LoadNextLevel", autoAdvanceToken)
		end)
	end)
end)

ClientBridge.SetCallback("LoadNextLevel", function(expectedAutoAdvanceToken)
	if expectedAutoAdvanceToken ~= nil then
		local expectedToken = tonumber(expectedAutoAdvanceToken)
		if expectedToken == nil or expectedToken ~= nextAutoAdvanceToken then
			return
		end
		invalidateAutoAdvanceToken()
	end

	if isHardcoreMode then
		resetFreeplaySessionStreak()
		stopHardcoreMode(true)
		return
	end
	isDailyPuzzleMode = false
	isTimedMode = false
	isHardcoreMode = false
	ClientBridge.SetState("IsHardcoreMode", false)
	tutorialSessionActive = false
	stopTimedModeTimer()
	cancelOnboardingTutorial()
	local currentPackId, currentLevelId = GameBoard:GetCurrentLevel()
	local wasFreeplay = tonumber(currentPackId) == -1
	local success = false

	if wasFreeplay then
		local nextData, requestStatus = uiState.requestLevelData(-1, 1)
		if requestStatus == "stale" then
			return
		end
		if nextData then
			GameBoard:LoadLevel(nextData)
			GameHudTransitions.SetHidden()
			clearGuessedBonusWords()
			if bonusWordsFrame then
				bonusWordsFrame.Visible = false
			end
			uiState.applySavedBoardProgress(nextData)
			updateAssistButtonNotifications()
			LetterWheel:LoadLevel(nextData)
			applyGameScenaryForPack(nextData and nextData.packId)
			GameHudTransitions.AnimateIn()
			InputState:SetEnabled(true)
			success = true
		end
	else
		local nextPackId, nextLevelId = findNextAdvanceLevel(currentPackId, currentLevelId)
		if nextPackId and nextLevelId then
			local nextData, requestStatus = uiState.requestLevelData(nextPackId, nextLevelId)
			if requestStatus == "stale" then
				return
			end
			if nextData then
				GameBoard:LoadLevel(nextData)
				GameHudTransitions.SetHidden()
				clearGuessedBonusWords()
				if bonusWordsFrame then
					bonusWordsFrame.Visible = false
				end
				uiState.applySavedBoardProgress(nextData)
				updateAssistButtonNotifications()
				LetterWheel:LoadLevel(nextData)
				applyGameScenaryForPack(nextData and nextData.packId)
				GameHudTransitions.AnimateIn()
				InputState:SetEnabled(true)
				success = true
			end
		end
	end

	if not success then
		resetFreeplaySessionStreak()
		InputState:SetEnabled(false)
		GameBoard:ExitLevel()
		LevelSelect:ShowPackList()
		applyLobbyScenary()
		UIManager:ShowScreen("LevelSelect")
	elseif not wasFreeplay then
		resetFreeplaySessionStreak()
	end
end)

ClientBridge.SetCallback("ExitToPackList", function()
	invalidateAutoAdvanceToken()

	if isHardcoreMode then
		resetFreeplaySessionStreak()
		stopHardcoreMode(true)
		return
	end
	resetFreeplaySessionStreak()
	isDailyPuzzleMode = false
	isTimedMode = false
	isHardcoreMode = false
	ClientBridge.SetState("IsHardcoreMode", false)
	tutorialSessionActive = false
	stopTimedModeTimer()
	cancelOnboardingTutorial()
	InputState:SetEnabled(false)
	if bonusWordsFrame then
		bonusWordsFrame.Visible = false
	end
	transitionGameToLobbyScreen("HomeScreen")
end)

introLoader.SetProgress(0.97, "Finalizing...")
hud.Enabled = true
GameBoard:ExitLevel()
if homeScreen then
	homeScreen.Visible = false
end
if levelsScreen then
	levelsScreen.Visible = false
end
if gameScreen then
	gameScreen.Visible = false
end
if homeScreen then
	UIManager:ShowScreen("HomeScreen")
else
	UIManager:ShowScreen("LevelSelect")
end
introLoader.SetProgress(1, "Ready")
introLoader.Finish()

task.defer(function()
	updateCurrencyLabels(playerData.coins or 0)
	updateAssistButtonNotifications()
	applyLobbyScenary()
	task.defer(pollHomeNotificationSources)
	GroupRewardPanel.Schedule(10)
end)

task.spawn(function()
	task.wait(120)
	local chatIndex = 1
	while hud and hud.Parent do
		local waitTime = math.random(300, 1200)
		task.wait(waitTime)
		if not (hud and hud.Parent) then
			break
		end
		if not tutorialSessionActive and not (TutorialController.IsActive and TutorialController.IsActive()) then
			UIManager:ShowAlert("Make sure to like the game! 👍", "bonus")
		end
		postSystemChatMessage(SYSTEM_CHAT_MESSAGES[chatIndex])
		chatIndex += 1
		if chatIndex > #SYSTEM_CHAT_MESSAGES then
			chatIndex = 1
		end
	end
end)

uiState.findTutorialLevelData = function()
	local data, requestStatus = uiState.requestLevelData(1, 5, nil, nil, { tutorial = true })
	if requestStatus == "stale" then
		return nil
	end
	return data
end

task.delay(0.2, function()
	if tutorialShownThisSession then
		return
	end
	if not TutorialConfig.ShouldStart(tutorialCompleted, player.UserId, FORCE_TUTORIAL_FOR_TESTING) then
		return
	end
	local data = uiState.findTutorialLevelData()
	if not data then
		return
	end
	isDailyPuzzleMode = false
	isTimedMode = false
	stopTimedModeTimer()
	InputState:SetEnabled(true)
	clearGuessedBonusWords()
	if bonusWordsFrame then
		bonusWordsFrame.Visible = false
	end
	GameBoard:LoadLevel(data)
	LetterWheel:LoadLevel(data)
	updateAssistButtonNotifications()
	applyGameScenaryForPack(data.packId)
	showLoadedGameScreen()
	beginOnboardingTutorial(data)
end)
