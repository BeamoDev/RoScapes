-- LevelSelect.luau
-- Handles pack select and level select UI.


local LevelSelect = {}

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MonetizationConfig"))

local uiMgr = nil
local hud = nil
local progress = {}
local packsData = {}
local onLevelChosen = nil

local content = nil
local packListFrame = nil
local packTemplate = nil
local levelGrid = nil
local levelTemplate = nil
local levelsFrame = nil
local levelsTitle = nil
local levelsButtons = nil
local packSceneryResolver = nil
local onPackOpened = nil
local onPackListShown = nil
local showingGrid = false
local premiumOwned = false

local function getOrderedPacks()
	local ordered = {}
	for _, pack in ipairs(packsData) do
		table.insert(ordered, pack)
	end
	table.sort(ordered, function(a, b)
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
	return ordered
end

local function getPackProgress(packId)
	return progress[tostring(packId)] or {}
end

local function getLastAccessibleLevel(packInfo)
	local levelCount = math.max(0, tonumber(packInfo and packInfo.levelCount) or 0)
	return levelCount
end

local function isPremiumLockedLevel(packInfo, levelId)
	return false
end

local function promptPremiumPassPurchase()
	return
end

local function getNextPlayablePackId()
	for _, pack in ipairs(getOrderedPacks()) do
		local packId = tonumber(pack and pack.packId) or 1
		if packId < 1 then
			continue
		end
		local levelCount = math.max(0, getLastAccessibleLevel(pack))
		if levelCount <= 0 then
			continue
		end
		local packProgress = getPackProgress(packId)
		for levelId = 1, levelCount do
			if packProgress[tostring(levelId)] ~= true then
				return packId
			end
		end
	end
	local ordered = getOrderedPacks()
	local lastPack = ordered[#ordered]
	return tonumber(lastPack and lastPack.packId) or 1
end

local function getDoneCount(packInfo, levelCount)
	local packId = tonumber(packInfo and packInfo.packId) or 0
	local countedMaxLevel = math.max(0, tonumber(levelCount) or 0)
	if packId >= 1 and not premiumOwned then
		countedMaxLevel = math.min(countedMaxLevel, getLastAccessibleLevel(packInfo))
	end
	local done = 0
	for levelId = 1, countedMaxLevel do
		if getPackProgress(packId)[tostring(levelId)] == true then
			done += 1
		end
	end
	return math.clamp(done, 0, math.max(0, tonumber(levelCount) or 0))
end

local function getPackNameById(targetPackId)
	for _, pack in ipairs(getOrderedPacks()) do
		if (tonumber(pack and pack.packId) or 0) == (tonumber(targetPackId) or 0) then
			return tostring(pack.name or ("Pack " .. tostring(targetPackId)))
		end
	end
	return "previous pack"
end

local function startCurrentPackPulse(card)
	if not card or not card:IsA("GuiObject") then
		return
	end
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if not stroke then
		return
	end
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.15
	stroke.Thickness = math.max(2, stroke.Thickness)
	task.spawn(function()
		while card.Parent do
			local up = TweenService:Create(stroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				Transparency = 0.65,
				Thickness = math.max(3, stroke.Thickness + 1),
			})
			local down = TweenService:Create(stroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Transparency = 0.1,
				Thickness = math.max(2, stroke.Thickness),
			})
			up:Play()
			up.Completed:Wait()
			if not card.Parent then
				return
			end
			down:Play()
			down.Completed:Wait()
		end
	end)
end

local function getLevelContainer()
	if not levelGrid then
		return nil
	end
	return levelGrid:FindFirstChild("ScrollingFrame") or levelGrid
end

local function ensureLevelLayout(container)
	local layout = container:FindFirstChildOfClass("UIGridLayout")
	if not layout then
		layout = Instance.new("UIGridLayout")
		layout.Parent = container
	end
	layout.CellSize = UDim2.fromOffset(68, 68)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.StartCorner = Enum.StartCorner.TopLeft
	return layout
end

local function clearLevelButtons(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:GetAttribute("GeneratedLevelButton") == true then
			child:Destroy()
		end
	end
end

local function createLevelButton(levelId, unlocked, completed, isPremiumLocked, isPremiumTile, callback)
	if not levelTemplate then
		return nil
	end
	local button = levelTemplate:Clone()
	button.Name = "Level_" .. tostring(levelId)
	button:SetAttribute("GeneratedLevelButton", true)
	button.Visible = true
	button.LayoutOrder = levelId
	button.AutoButtonColor = unlocked or isPremiumLocked
	button.Active = unlocked or isPremiumLocked
	if isPremiumTile then
		button.BackgroundColor3 = Color3.fromRGB(156, 122, 40)
	elseif unlocked then
		button.BackgroundColor3 = Color3.fromRGB(58, 138, 90)
	else
		button.BackgroundColor3 = Color3.fromRGB(74, 78, 88)
	end
	button:SetAttribute("IsPremiumTile", isPremiumTile)

	local label = button:FindFirstChild("Levbel", true) or button:FindFirstChild("Level", true)
	if label and label:IsA("TextLabel") then
		label.Text = tostring(levelId)
	end

	local completedBadge = button:FindFirstChild("Completed", true)
	if completedBadge and completedBadge:IsA("GuiObject") then
		completedBadge.Visible = completed
	end

	local lockedBadge = button:FindFirstChild("Locked", true)
	if lockedBadge and lockedBadge:IsA("GuiObject") then
		lockedBadge.Visible = (not unlocked) or isPremiumLocked
	end

	if unlocked or isPremiumLocked then
		local baseSize = button.Size
		local shrinkSize = UDim2.new(baseSize.X.Scale, math.floor(baseSize.X.Offset * 0.91), baseSize.Y.Scale, math.floor(baseSize.Y.Offset * 0.91))
		button.MouseButton1Down:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.08), { Size = shrinkSize }):Play()
		end)
		button.MouseButton1Up:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.14, Enum.EasingStyle.Back), { Size = baseSize }):Play()
		end)
		button.MouseButton1Click:Connect(function()
			if isPremiumLocked then
				promptPremiumPassPurchase()
				return
			end
			callback()
		end)
	end

	return button
end

local function startCurrentLevelPulse(button)
	if not button or not button.Parent then
		return
	end
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = button
	end
	stroke.Color = Color3.fromRGB(72, 255, 138)
	stroke.Thickness = 2
	task.spawn(function()
		while button.Parent do
			local up = TweenService:Create(stroke, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				Transparency = 0.55,
				Thickness = 4,
			})
			local down = TweenService:Create(stroke, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Transparency = 0.05,
				Thickness = 2,
			})
			up:Play()
			up.Completed:Wait()
			if not button.Parent then
				return
			end
			down:Play()
			down.Completed:Wait()
		end
	end)
end

local function startPremiumLevelPulse(button)
	if not button or not button.Parent then
		return
	end
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = button
	end
	stroke.Color = Color3.fromRGB(255, 220, 92)
	stroke.Thickness = 2
	task.spawn(function()
		while button.Parent do
			local up = TweenService:Create(stroke, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				Transparency = 0.5,
				Thickness = 4,
			})
			local down = TweenService:Create(stroke, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Transparency = 0.05,
				Thickness = 2,
			})
			up:Play()
			up.Completed:Wait()
			if not button.Parent then
				return
			end
			down:Play()
			down.Completed:Wait()
		end
	end)
end

local function showLevelGrid(packInfo)
	if showingGrid then
		return
	end
	showingGrid = true

	local currentPackId = getNextPlayablePackId()
	local requestedPackId = tonumber(packInfo and packInfo.packId) or 1
	if requestedPackId < 1 then
		showingGrid = false
		if onLevelChosen then
			onLevelChosen(requestedPackId, 1)
		end
		return
	end
	if requestedPackId >= 1 and requestedPackId > currentPackId then
		showingGrid = false
		if uiMgr and uiMgr.ShowAlert then
			uiMgr:ShowAlert("Finish the current pack first", "error")
		end
		return
	end

	local container = getLevelContainer()
	if not container then
		showingGrid = false
		return
	end
	ensureLevelLayout(container)
	clearLevelButtons(container)

	if packListFrame then
		packListFrame.Visible = false
	end
	levelGrid.Visible = true

	local packNameLabel = levelGrid:FindFirstChild("PackName")
	if packNameLabel and packNameLabel:IsA("TextLabel") then
		packNameLabel.Text = tostring(packInfo.name or "Pack")
	end
	if levelsTitle and levelsTitle:IsA("TextLabel") then
		levelsTitle.Text = tostring(packInfo.name or "Pack")
	end
	if onPackOpened then
		onPackOpened(packInfo)
	end

	local packProgress = getPackProgress(requestedPackId)
	for levelId = 1, math.max(1, tonumber(packInfo.levelCount) or 1) do
		local completed = packProgress[tostring(levelId)] == true
		local previousDone = (levelId == 1) or (packProgress[tostring(levelId - 1)] == true)
		local premiumLocked = isPremiumLockedLevel(packInfo, levelId)
		local premiumTile = MonetizationConfig.IsPremiumLevel(levelId, tonumber(packInfo.levelCount) or 0)
		local unlocked = (requestedPackId < 1 or requestedPackId < currentPackId or previousDone) and not premiumLocked
		local isCurrentLevel = unlocked and not completed and requestedPackId == currentPackId and ((levelId == 1) or previousDone)
		local button = createLevelButton(levelId, unlocked, completed, premiumLocked, premiumTile, function()
			if onLevelChosen then
				onLevelChosen(requestedPackId, levelId)
			end
		end)
		if button then
			if isCurrentLevel then
				if button:IsA("GuiObject") then
					if button:GetAttribute("IsPremiumTile") then
						button.BackgroundColor3 = Color3.fromRGB(226, 186, 68)
					else
					button.BackgroundColor3 = Color3.fromRGB(72, 176, 108)
					end
				end
				local completedBadge = button:FindFirstChild("Completed", true)
				local lockedBadge = button:FindFirstChild("Locked", true)
				if completedBadge and completedBadge:IsA("GuiObject") then
					completedBadge.Visible = false
				end
				if lockedBadge and lockedBadge:IsA("GuiObject") then
					lockedBadge.Visible = false
				end
				startCurrentLevelPulse(button)
			elseif premiumLocked then
				local completedBadge = button:FindFirstChild("Completed", true)
				local lockedBadge = button:FindFirstChild("Locked", true)
				if button:IsA("GuiObject") then
					button.BackgroundColor3 = Color3.fromRGB(156, 122, 40)
				end
				if completedBadge and completedBadge:IsA("GuiObject") then
					completedBadge.Visible = false
				end
				if lockedBadge and lockedBadge:IsA("GuiObject") then
					lockedBadge.Visible = false
				end
				startPremiumLevelPulse(button)
			elseif completed and button:GetAttribute("IsPremiumTile") then
				if button:IsA("GuiObject") then
					button.BackgroundColor3 = Color3.fromRGB(156, 122, 40)
				end
			end
			button.Parent = container
		end
	end

	if container:IsA("ScrollingFrame") then
		container.CanvasPosition = Vector2.zero
		container.CanvasSize = UDim2.fromScale(0, 0)
		container.AutomaticCanvasSize = Enum.AutomaticSize.Y
	end

	task.delay(0.3, function()
		showingGrid = false
	end)
end

local function buildPackCards()
	if not packListFrame or not packTemplate then
		return
	end

	for _, child in ipairs(packListFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= packTemplate then
			child:Destroy()
		end
	end

	local currentPackId = getNextPlayablePackId()
	for _, packInfo in ipairs(getOrderedPacks()) do
		local packId = tonumber(packInfo and packInfo.packId) or 1
		local total = math.max(1, tonumber(packInfo and packInfo.levelCount) or 1)
		local done = getDoneCount(packInfo, total)
		local unlocked = packId < 1 or packId <= currentPackId
		local completed = packId >= 1 and done >= total
		local isCurrentPack = packId >= 1 and packId == currentPackId

		local card = packTemplate:Clone()
		card.Name = "Pack_" .. tostring(packId)
		card.LayoutOrder = packId
		card.Visible = true
		card.Parent = packListFrame

		local titleLabel = card:FindFirstChild("PackTitle")
		if titleLabel and titleLabel:IsA("TextLabel") then
			titleLabel.Text = tostring(packInfo.name or "Pack")
		end

		local scenary = card:FindFirstChild("Scenary", true)
		if scenary and (scenary:IsA("ImageLabel") or scenary:IsA("ImageButton")) and packSceneryResolver then
			local imageId = packSceneryResolver(packId)
			if typeof(imageId) == "string" and imageId ~= "" then
				scenary.Image = imageId
			end
		end

		local levelsLabel = card:FindFirstChild("PackLevels")
		if levelsLabel and levelsLabel:IsA("TextLabel") then
			if packId < 1 then
				levelsLabel.Text = "Infinite boards"
			else
				levelsLabel.Text = tostring(done) .. " / " .. tostring(total) .. " levels"
			end
		end

		local barBg = card:FindFirstChild("BarBg")
		if barBg then
			barBg.Visible = packId >= 1
			local fill = barBg:FindFirstChild("Fill")
			if fill and fill:IsA("Frame") then
				local ratio = packId < 1 and 1 or ((total > 0) and math.clamp(done / total, 0, 1) or 0)
				fill.Size = UDim2.new(ratio, 0, 1, 0)
				fill.BackgroundColor3 = Color3.fromRGB(75, 255, 66)
			end
		end

		local playBtn = card:FindFirstChild("Play")
		if playBtn and playBtn:IsA("GuiButton") then
			playBtn.Active = true
			playBtn.AutoButtonColor = true
			playBtn.MouseButton1Click:Connect(function()
				if not unlocked then
					if uiMgr and uiMgr.ShowAlert then
						uiMgr:ShowAlert("Finish the current pack first", "error")
					end
					return
				end
				showLevelGrid(packInfo)
			end)
		end

		local lockedObj = card:FindFirstChild("Locked", true) or card:FindFirstChild("Lock", true)
		if lockedObj and lockedObj:IsA("GuiObject") then
			lockedObj.Visible = not unlocked
			local lockedStatus = lockedObj:FindFirstChild("Status", true)
			if lockedStatus and lockedStatus:IsA("TextLabel") then
				lockedStatus.Text = 'Complete "' .. getPackNameById(packId - 1) .. '"'
			end
		end
		local completedObj = card:FindFirstChild("Completed", true)
		if completedObj and completedObj:IsA("GuiObject") then
			completedObj.Visible = completed
		end
		if card:IsA("GuiObject") then
			card.BackgroundTransparency = unlocked and card.BackgroundTransparency or math.max(0.1, card.BackgroundTransparency)
		end
		if isCurrentPack then
			startCurrentPackPulse(card)
		end
	end

	for spacerIndex = 1, 2 do
		local spacer = Instance.new("Frame")
		spacer.Name = "PackListSpacer" .. tostring(spacerIndex)
		spacer.LayoutOrder = 100000 + spacerIndex
		spacer.Size = UDim2.new(1, 0, 0, 96)
		spacer.BackgroundTransparency = 1
		spacer.BorderSizePixel = 0
		spacer.Parent = packListFrame
	end
end

function LevelSelect:Init(manager, playerData, hudScreen)
	uiMgr = manager
	hud = hudScreen
	progress = playerData.progress or {}
	packsData = playerData.packs or {}
	premiumOwned = playerData.premiumOwned == true

	levelsFrame = hud:FindFirstChild("Levels") or hud:WaitForChild("LevelSelect")
	levelsButtons = levelsFrame:FindFirstChild("Buttons")
	levelsTitle = levelsFrame:FindFirstChild("Title")
	content = levelsFrame:WaitForChild("Content")
	packListFrame = content:WaitForChild("PackList")
	packTemplate = content:WaitForChild("PackTemplate")
	levelGrid = content:WaitForChild("LevelGrid")
	levelTemplate = content:WaitForChild("LevelTemplate")
	levelTemplate.Visible = false

	levelGrid.Visible = false
	packListFrame.Visible = true

	local listLayout = packListFrame:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	end

	local returnBtn = (levelsButtons and levelsButtons:FindFirstChild("Return")) or (levelGrid and levelGrid:FindFirstChild("Return"))
	if returnBtn and returnBtn:IsA("GuiButton") then
		returnBtn.MouseButton1Click:Connect(function()
			if levelGrid.Visible then
				levelGrid.Visible = false
				packListFrame.Visible = true
				if levelsTitle and levelsTitle:IsA("TextLabel") then
					levelsTitle.Text = "Packs"
				end
				if onPackListShown then
					onPackListShown()
				end
				return
			end
			if uiMgr and uiMgr.ShowScreen then
				uiMgr:ShowScreen("HomeScreen")
			end
		end)
	end

	if levelsTitle and levelsTitle:IsA("TextLabel") then
		levelsTitle.Text = "Packs"
	end

	buildPackCards()
end

function LevelSelect:UpdateProgress(packId, levelId)
	progress[tostring(packId)] = progress[tostring(packId)] or {}
	progress[tostring(packId)][tostring(levelId)] = true
	buildPackCards()
end

function LevelSelect:SetPremiumOwned(owned)
	premiumOwned = owned == true
end

function LevelSelect:OwnsPremium()
	return premiumOwned == true
end

function LevelSelect:IsPremiumLevel(packId, levelId)
	for _, pack in ipairs(packsData) do
		if (tonumber(pack and pack.packId) or 0) == (tonumber(packId) or 0) then
			return isPremiumLockedLevel(pack, levelId)
		end
	end
	return false
end

function LevelSelect:GetLastAccessibleLevel(packId)
	for _, pack in ipairs(packsData) do
		if (tonumber(pack and pack.packId) or 0) == (tonumber(packId) or 0) then
			return getLastAccessibleLevel(pack)
		end
	end
	return 0
end

function LevelSelect:ShowPackList()
	if levelGrid then
		levelGrid.Visible = false
	end
	if packListFrame then
		packListFrame.Visible = true
	end
	if levelsTitle and levelsTitle:IsA("TextLabel") then
		levelsTitle.Text = "Packs"
	end
	if onPackListShown then
		onPackListShown()
	end
	buildPackCards()
end

function LevelSelect:OnLevelChosen(fn)
	onLevelChosen = fn
end

function LevelSelect:SetPackSceneryResolver(resolver)
	packSceneryResolver = (typeof(resolver) == "function") and resolver or nil
	if packListFrame and packTemplate then
		buildPackCards()
	end
end

function LevelSelect:SetOnPackOpened(fn)
	onPackOpened = (typeof(fn) == "function") and fn or nil
end

function LevelSelect:SetOnPackListShown(fn)
	onPackListShown = (typeof(fn) == "function") and fn or nil
end

return LevelSelect
