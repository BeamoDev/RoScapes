local TweenService = game:GetService("TweenService")

local HomeHud = {}

local RANK_ORDER = {
	"BRONZE_1","BRONZE_2","BRONZE_3","BRONZE_4","BRONZE_5",
	"SILVER_1","SILVER_2","SILVER_3","SILVER_4","SILVER_5",
	"GOLD_1","GOLD_2","GOLD_3","GOLD_4","GOLD_5",
}

local RANK_INDEX = {}
for i, rankId in ipairs(RANK_ORDER) do
	RANK_INDEX[rankId] = i
end

local state = {
	homeScreen = nil,
	gameScreen = nil,
	gameButtons = nil,
	bonusWordsFrame = nil,
	playerData = nil,
	uiState = nil,
}

local function getHomeButtonByNames(names)
	local homeScreen = state.homeScreen
	if not homeScreen then
		return nil
	end
	local btns = homeScreen:FindFirstChild("Buttons")
	if not btns then
		return nil
	end
	local lower = btns:FindFirstChild("LowerButtons")
	for _, name in ipairs(names) do
		local direct = btns:FindFirstChild(name)
		if direct and direct:IsA("GuiObject") then
			return direct
		end
		local low = lower and lower:FindFirstChild(name)
		if low and low:IsA("GuiObject") then
			return low
		end
	end
	return nil
end

local function applyButtonNotification(button, visible, amount)
	if not button then
		return
	end
	local notif = button:FindFirstChild("Notification")
	if not notif or not notif:IsA("GuiObject") then
		return
	end
	notif.Visible = visible == true
	local amountLabel = notif:FindFirstChild("Amount")
	if amountLabel and amountLabel:IsA("TextLabel") then
		amountLabel.Text = tostring(amount or 1)
	end
end

local function getRankShadowColor(rankInfo)
	local rankId = tostring(rankInfo and rankInfo.id or "BRONZE_1")
	if string.find(rankId, "GOLD", 1, true) then
		return Color3.fromRGB(255, 152, 35)
	end
	if string.find(rankId, "SILVER", 1, true) then
		return Color3.fromRGB(198, 208, 224)
	end
	return Color3.fromRGB(176, 116, 72)
end

local function getRankFillColor(rankInfo)
	return getRankShadowColor(rankInfo)
end

local function renderBonusWords(words)
	local bonusWordsFrame = state.bonusWordsFrame
	if not bonusWordsFrame then
		return
	end
	local frameRoot = bonusWordsFrame:FindFirstChild("Frame") or bonusWordsFrame
	local container = frameRoot:FindFirstChild("Container") or bonusWordsFrame:FindFirstChild("Container")
	local template = frameRoot:FindFirstChild("BonusTemplate") or bonusWordsFrame:FindFirstChild("BonusTemplate", true)
	if not container or not container:IsA("GuiObject") or not template or not template:IsA("GuiObject") then
		return
	end

	template.Visible = false
	template.LayoutOrder = -1000

	for _, child in ipairs(container:GetChildren()) do
		if child ~= template and not child:IsA("UIGridLayout") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	if #words == 0 then
		return
	end

	table.sort(words)
	for i, word in ipairs(words) do
		local row = template:Clone()
		row.Name = "BonusWord_" .. i
		row.LayoutOrder = i
		row.Visible = true
		row.Parent = container

		local wordLabel = row:FindFirstChild("Word", true)
		if wordLabel and wordLabel:IsA("TextLabel") then
			wordLabel.Text = tostring(word)
		end
	end
end

function HomeHud.Init(options)
	state.homeScreen = options.homeScreen
	state.gameScreen = options.gameScreen
	state.gameButtons = options.gameButtons
	state.bonusWordsFrame = options.bonusWordsFrame
	state.playerData = options.playerData
	state.uiState = options.uiState
end

function HomeHud.GetHomeButtonByNames(names)
	return getHomeButtonByNames(names)
end

function HomeHud.UpdateAssistButtonNotifications()
	local gameScreen = state.gameScreen
	local playerData = state.playerData or {}
	local gameBtns = gameScreen and gameScreen:FindFirstChild("Buttons")
	local inGameBar = gameScreen and gameScreen:FindFirstChild("InGameBar")
	local hintBtn = gameBtns and (gameBtns:FindFirstChild("Hint") or gameBtns:FindFirstChild("HintButton"))
	local topHintBtn = inGameBar and inGameBar:FindFirstChild("HintButton")
	local arrowBtn = gameBtns and gameBtns:FindFirstChild("Arrow")
	local hintCount = tonumber(playerData.hints) or 0
	applyButtonNotification(hintBtn, hintCount > 0, hintCount)
	applyButtonNotification(topHintBtn, hintCount > 0, hintCount)
	applyButtonNotification(arrowBtn, (tonumber(playerData.selectionHints) or 0) > 0, tonumber(playerData.selectionHints) or 0)
end

function HomeHud.UpdateBonusWordsCounter(words)
	local gameButtons = state.gameButtons
	local gameScreen = state.gameScreen
	local starBtn = (gameButtons and (gameButtons:FindFirstChild("Star") or gameButtons:FindFirstChild("STAR")))
		or (gameScreen and gameScreen:FindFirstChild("Star", true))
		or (gameScreen and gameScreen:FindFirstChild("STAR", true))
	if not starBtn or not starBtn:IsA("GuiObject") then
		return
	end
	local counter = starBtn:FindFirstChild("Counter", true)
	if not counter or not counter:IsA("GuiObject") then
		return
	end
	local count = #(words or {})
	counter.Visible = count > 0
	local label = counter:IsA("TextLabel") and counter or counter:FindFirstChildWhichIsA("TextLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = tostring(count)
	end
end

function HomeHud.ApplyHomeNotificationBadges()
	local counts = (state.uiState and state.uiState.homeNotificationCounts) or {}
	applyButtonNotification(getHomeButtonByNames({ "Daily" }), (counts.daily or 0) > 0, counts.daily)
	applyButtonNotification(getHomeButtonByNames({ "Quests" }), (counts.quests or 0) > 0, counts.quests)
	applyButtonNotification(getHomeButtonByNames({ "Achievements" }), (counts.achievements or 0) > 0, counts.achievements)
	applyButtonNotification(getHomeButtonByNames({ "OneVsOne", "1v1", "PvP" }), (counts.oneVsOne or 0) > 0, counts.oneVsOne)
end

function HomeHud.SetHomeNotificationCount(flag, amount)
	local uiState = state.uiState
	if not uiState or uiState.homeNotificationCounts[flag] == nil then
		return
	end
	uiState.homeNotificationCounts[flag] = math.max(0, math.floor(tonumber(amount) or 0))
	HomeHud.ApplyHomeNotificationBadges()
end

function HomeHud.SetHomeNotificationFlag(flag, value)
	HomeHud.SetHomeNotificationCount(flag, value and 1 or 0)
end

function HomeHud.RankAtLeast(currentRankId, requiredRankId)
	local current = RANK_INDEX[tostring(currentRankId or "BRONZE_1")] or 1
	local needed = RANK_INDEX[tostring(requiredRankId or "BRONZE_1")] or 1
	return current >= needed
end

function HomeHud.ShowBonusWords(words)
	if not state.bonusWordsFrame then
		return
	end
	renderBonusWords(words or {})
	state.bonusWordsFrame.Visible = true
end

function HomeHud.UpdateHomeRankVisual(rankInfo)
	local homeScreen = state.homeScreen
	if not homeScreen then
		local gameScreen = state.gameScreen
		local hudRoot = gameScreen and gameScreen.Parent
		local fallbackHome = hudRoot and hudRoot:FindFirstChild("Home")
		if fallbackHome and fallbackHome:IsA("GuiObject") then
			state.homeScreen = fallbackHome
			homeScreen = fallbackHome
		else
			return
		end
	end
	if not homeScreen.Parent then
		return
	end
	local rankRoot = homeScreen:FindFirstChild("Rank")
	if not rankRoot then
		return
	end
	local rankMain = rankRoot:FindFirstChild("RankMain")
	local rankShadow = rankRoot:FindFirstChild("RankShadow")
	local container = rankRoot:FindFirstChild("Container")
	local rankLabel = container and (container:FindFirstChild("RankLable") or container:FindFirstChild("RankLabel"))
	local bar = container and container:FindFirstChild("Bar")
	local fill = bar and bar:FindFirstChild("Fill")

	local imageId = rankInfo and rankInfo.imageId or "rbxassetid://0"
	if rankMain and rankMain:IsA("ImageLabel") then
		rankMain.Image = imageId
	end
	if rankShadow and rankShadow:IsA("ImageLabel") then
		rankShadow.Image = imageId
		rankShadow.ImageColor3 = getRankShadowColor(rankInfo)
		rankShadow.ImageTransparency = 1
	end
	if rankLabel and rankLabel:IsA("TextLabel") then
		rankLabel.Text = tostring(rankInfo and rankInfo.name or "Bronze 1")
	end
	if fill and fill:IsA("GuiObject") then
		fill.Size = UDim2.fromScale(math.clamp((tonumber(rankInfo and rankInfo.progress) or 0), 0, 1), 1)
		fill.BackgroundColor3 = getRankFillColor(rankInfo)
	end
end

function HomeHud.StartRankShadowPulse()
	local homeScreen = state.homeScreen
	if not homeScreen then
		return
	end
	local rankRoot = homeScreen:FindFirstChild("Rank")
	local rankShadow = rankRoot and rankRoot:FindFirstChild("RankShadow")
	if not rankShadow or not rankShadow:IsA("ImageLabel") or rankShadow:GetAttribute("PulseWired") then
		return
	end
	rankShadow:SetAttribute("PulseWired", true)
	local baseSize = rankShadow.Size
	local baseTransparency = 1
	local peakTransparency = 0.82
	task.spawn(function()
		while rankShadow.Parent do
			local up = TweenService:Create(rankShadow, TweenInfo.new(1.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				Size = UDim2.new(baseSize.X.Scale * 1.025, baseSize.X.Offset, baseSize.Y.Scale * 1.025, baseSize.Y.Offset),
				ImageTransparency = peakTransparency,
			})
			local down = TweenService:Create(rankShadow, TweenInfo.new(1.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Size = baseSize,
				ImageTransparency = baseTransparency,
			})
			up:Play()
			up.Completed:Wait()
			if rankShadow.Parent and math.random() < 0.4 then
				local echo = rankShadow:Clone()
				echo.Name = "RankShadowEcho"
				echo.ImageTransparency = 0.88
				echo.Size = rankShadow.Size
				echo.ZIndex = math.max(0, rankShadow.ZIndex - 1)
				echo.Parent = rankShadow.Parent
				local echoTween = TweenService:Create(echo, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.new(baseSize.X.Scale * 1.1, baseSize.X.Offset, baseSize.Y.Scale * 1.1, baseSize.Y.Offset),
					ImageTransparency = 1,
				})
				echoTween:Play()
				echoTween.Completed:Connect(function()
					if echo and echo.Parent then
						echo:Destroy()
					end
				end)
			end
			down:Play()
			down.Completed:Wait()
			task.wait(0.25)
		end
	end)
end

function HomeHud.StartPlayButtonPulse()
	local homeScreen = state.homeScreen
	if not homeScreen then
		return
	end
	local btns = homeScreen:FindFirstChild("Buttons")
	local playBtn = btns and btns:FindFirstChild("Play")
	if not playBtn or not playBtn:IsA("GuiButton") or playBtn:GetAttribute("PulseWired") then
		return
	end
	playBtn:SetAttribute("PulseWired", true)
	task.spawn(function()
		while playBtn.Parent do
			task.wait(3)
			if not playBtn.Parent then
				break
			end
			local stroke = playBtn:FindFirstChild("PlayPulseStroke")
			if stroke then
				stroke:Destroy()
			end
			stroke = Instance.new("UIStroke")
			stroke.Name = "PlayPulseStroke"
			stroke.Color = Color3.fromRGB(88, 240, 135)
			stroke.Thickness = 0
			stroke.Transparency = 0
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = playBtn

			stroke.BorderOffset = UDim.new(0, 0)

			local tweenInfo = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local thicknessTween = TweenService:Create(stroke, tweenInfo, {
				Thickness = 6,
				Transparency = 1,
				BorderOffset = UDim.new(0.5, 0),
			})

			thicknessTween:Play()
			thicknessTween.Completed:Wait()
			if stroke and stroke.Parent then
				stroke:Destroy()
			end
		end
	end)
end

function HomeHud.ShakeButtonOnce(button)
	if not button or not button:IsA("GuiButton") or button:GetAttribute("ShakeBusy") then
		return
	end
	button:SetAttribute("ShakeBusy", true)
	local baseRot = button.Rotation
	local t1 = TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Rotation = baseRot + 4 })
	local t2 = TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Rotation = baseRot - 4 })
	local t3 = TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Rotation = baseRot + 2 })
	local t4 = TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Rotation = baseRot })
	t1:Play()
	t1.Completed:Wait()
	t2:Play()
	t2.Completed:Wait()
	t3:Play()
	t3.Completed:Wait()
	t4:Play()
	t4.Completed:Wait()
	button.Rotation = baseRot
	button:SetAttribute("ShakeBusy", false)
end

function HomeHud.UpdateCurrencyLabels(coins)
	local value = tonumber(coins) or 0
	local playerData = state.playerData
	if playerData then
		playerData.coins = value
	end
	local function updateCurrencyLabel(screen)
		if not screen then
			return
		end
		local buttons = screen:FindFirstChild("Buttons")
		local currency = buttons and buttons:FindFirstChild("Currency")
		local label = currency and currency:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Text = tostring(value)
		end
	end
	updateCurrencyLabel(state.homeScreen)
	updateCurrencyLabel(state.gameScreen)
end

return HomeHud
