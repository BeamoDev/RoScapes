local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIEffects = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("util"):WaitForChild("UIEffects"))

local QuestsPanel = {}

local state = {
	UIManager = nil,
	RemoteRegistry = nil,
	frames = nil,
	currentQuestPeriod = "daily",
	currentBoard = nil,
	boardCache = {
		daily = nil,
		weekly = nil,
	},
	refreshThreadId = 0,
	onCoinsUpdated = nil,
	formatResetTime = nil,
	closeOtherPanels = nil,
}

local function ensurePanel()
	local frames = state.frames
	if not frames then
		return nil
	end
	local panel = frames:FindFirstChild("Quests") or frames:FindFirstChild("DailyChallenge")
	if panel and panel:IsA("Frame") then
		return panel
	end
	return nil
end

local function getQuestPanelParts(panel)
	if not panel then
		return nil, nil, nil, nil
	end
	local frame = panel:FindFirstChild("Frame") or panel
	local statusLabel = frame and frame:FindFirstChild("Status")
	local scroll = frame and frame:FindFirstChild("Scroll")
	local template = frame and frame:FindFirstChild("QuestTemplate")
	return frame, statusLabel, scroll, template
end

local function clearRows(panel)
	local _, _, scroll, template = getQuestPanelParts(panel)
	if not scroll or not scroll:IsA("GuiObject") then
		return
	end
	for _, child in ipairs(scroll:GetChildren()) do
		if child ~= template and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function addFallbackRow(panel, titleText, valueText, layoutOrder)
	local _, _, scroll = getQuestPanelParts(panel)
	if not scroll or not scroll:IsA("GuiObject") then
		return
	end

	local row = Instance.new("Frame")
	row.Name = "Row_" .. tostring(layoutOrder)
	row.BackgroundColor3 = Color3.fromRGB(23, 34, 58)
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 54)
	row.LayoutOrder = layoutOrder
	row.ZIndex = 152
	row.Parent = scroll
	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -16, 0, 20)
	title.Position = UDim2.fromOffset(8, 6)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = Color3.fromRGB(142, 178, 245)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = titleText
	title.ZIndex = 153
	title.Parent = row

	local value = Instance.new("TextLabel")
	value.BackgroundTransparency = 1
	value.Size = UDim2.new(1, -16, 0, 24)
	value.Position = UDim2.fromOffset(8, 24)
	value.Font = Enum.Font.Gotham
	value.TextSize = 16
	value.TextColor3 = Color3.fromRGB(240, 244, 255)
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Text = valueText
	value.ZIndex = 153
	value.Parent = row
end

local function render(panel, board)
	local _, statusLabel, scroll, template = getQuestPanelParts(panel)
	clearRows(panel)

	if not board or typeof(board) ~= "table" then
		if statusLabel and statusLabel:IsA("TextLabel") then
			statusLabel.Text = "Status: unavailable"
		end
		addFallbackRow(panel, "Connection", "Could not load daily challenge.", 1)
		return
	end

	local quests = board.quests or {}
	local resetsIn = tonumber(board.resetsIn) or 0
	if statusLabel and statusLabel:IsA("TextLabel") then
		statusLabel.Text = string.format("Resets in %s", state.formatResetTime(resetsIn))
	end

	if not scroll or not scroll:IsA("GuiObject") or not template or not template:IsA("GuiObject") then
		return
	end
	template.Visible = false

	if #quests == 0 then
		addFallbackRow(panel, "No quests", "Come back after midnight for new quests.", 1)
		return
	end

	table.sort(quests, function(a, b)
		local aCompleted = a and a.completed == true
		local bCompleted = b and b.completed == true
		local aClaimed = a and a.claimed == true
		local bClaimed = b and b.claimed == true
		local aClaimable = aCompleted and not aClaimed
		local bClaimable = bCompleted and not bClaimed
		if aClaimable ~= bClaimable then
			return aClaimable
		end
		if aClaimed ~= bClaimed then
			return not aClaimed
		end
		if not aClaimed and not bClaimed and not aClaimable and not bClaimable then
			local aTarget = math.max(1, tonumber(a and a.target) or 1)
			local bTarget = math.max(1, tonumber(b and b.target) or 1)
			local aRatio = math.clamp((tonumber(a and a.progress) or 0) / aTarget, 0, 1)
			local bRatio = math.clamp((tonumber(b and b.progress) or 0) / bTarget, 0, 1)
			if aRatio ~= bRatio then
				return aRatio > bRatio
			end
		end
		local aReward = tonumber(a and a.reward) or 0
		local bReward = tonumber(b and b.reward) or 0
		if aReward ~= bReward then
			return aReward > bReward
		end
		return tostring(a and a.id or "") < tostring(b and b.id or "")
	end)

	for i, quest in ipairs(quests) do
		local row = template:Clone()
		row.Name = "Quest_" .. tostring(quest.id or i)
		row.LayoutOrder = i
		row.Visible = true
		row.Parent = scroll

		local title = row:FindFirstChild("Title", true)
		local reward = row:FindFirstChild("Reward", true)
		local progressLabel = row:FindFirstChild("Progress", true)
		local claim = row:FindFirstChild("Claim", true)
		local completedBadge = row:FindFirstChild("Completed", true)
		local barBg = row:FindFirstChild("BarBg", true)
		local fill = barBg and barBg:FindFirstChild("Fill")
		local claimLabel = claim and claim:FindFirstChild("Label", true)

		if title and title:IsA("TextLabel") then
			local cleanTitle = tostring(quest.title or "Quest")
			cleanTitle = cleanTitle:gsub("^Elite:%s*", "")
			cleanTitle = cleanTitle:gsub("^Combo:%s*", "")
			title.Text = cleanTitle
			title.TextColor3 = Color3.fromRGB(234, 244, 255)
		end

		local qp = tonumber(quest.progress) or 0
		local qt = math.max(1, tonumber(quest.target) or 1)
		if reward and reward:IsA("TextLabel") then
			reward.Text = tostring(quest.reward or 0)
		end
		if progressLabel and progressLabel:IsA("TextLabel") then
			progressLabel.Text = tostring(qp) .. "/" .. tostring(qt)
		end
		local done = quest.completed == true
		local claimed = quest.claimed == true
		if fill and fill:IsA("GuiObject") then
			local ratio = math.clamp(qp / qt, 0, 1)
			local visualRatio = 0.1 + (ratio * 0.9)
			fill.Size = UDim2.fromScale(math.clamp(visualRatio, 0.1, 1), 1)
			fill.BackgroundColor3 = claimed and Color3.fromRGB(92, 148, 106) or Color3.fromRGB(35, 255, 79)
		end
		if completedBadge and completedBadge:IsA("GuiObject") then
			completedBadge.Visible = done and claimed
		end
		if claim and claim:IsA("GuiButton") then
			local function setClaimText(textValue)
				if claimLabel and claimLabel:IsA("TextLabel") then
					claimLabel.Text = textValue
				else
					pcall(function()
						claim.Text = textValue
					end)
				end
			end

			if claimed then
				setClaimText("Claimed")
				claim.BackgroundColor3 = Color3.fromRGB(83, 98, 126)
				claim.Active = false
				claim.AutoButtonColor = false
			elseif done then
				setClaimText("Claim")
				claim.BackgroundColor3 = Color3.fromRGB(35, 255, 79)
				claim.Active = true
				claim.AutoButtonColor = true
				claim.MouseButton1Click:Connect(function()
					local resp = state.RemoteRegistry:GetFunction("ClaimQuestReward"):InvokeServer(state.currentQuestPeriod, quest.id)
					if resp and resp.success then
						UIEffects.PlaySound("Victory")
						if state.onCoinsUpdated then
							state.onCoinsUpdated(resp.coins or 0)
						end
						state.UIManager:ShowAlert("Quest reward +" .. tostring(resp.reward or 0) .. " coins", "coin")
						state.currentBoard = resp.board or state.currentBoard
						state.boardCache[state.currentQuestPeriod] = state.currentBoard
						render(panel, state.currentBoard)
					else
						UIEffects.PlaySound("Error")
						state.UIManager:ShowAlert((resp and resp.message) or "Claim failed", "error")
					end
				end)
			else
				setClaimText("Locked")
				claim.BackgroundColor3 = Color3.fromRGB(58, 64, 78)
				claim.Active = false
				claim.AutoButtonColor = false
			end
		end
	end
end

local function countClaimableQuests(board)
	local total = 0
	for _, quest in ipairs((board and board.quests) or {}) do
		if quest and quest.completed == true and quest.claimed ~= true then
			total += 1
		end
	end
	return total
end

local function applyToggleNotification(toggle, count)
	if not (toggle and toggle:IsA("GuiObject")) then
		return
	end
	local notification = toggle:FindFirstChild("Notification")
	if not (notification and notification:IsA("GuiObject")) then
		return
	end
	notification.Visible = count > 0
	local label = notification:IsA("TextLabel") and notification or notification:FindFirstChildWhichIsA("TextLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = tostring(count)
	end
end

function QuestsPanel.Init(options)
	state.UIManager = options.UIManager
	state.RemoteRegistry = options.RemoteRegistry
	state.frames = options.frames
	state.onCoinsUpdated = options.onCoinsUpdated
	state.formatResetTime = options.formatResetTime
	state.closeOtherPanels = options.closeOtherPanels
end

function QuestsPanel.GetCachedBoard(period)
	local key = (period == "weekly") and "weekly" or "daily"
	return state.boardCache[key]
end

function QuestsPanel.SetCachedBoard(period, board)
	local key = (period == "weekly") and "weekly" or "daily"
	state.boardCache[key] = board
	if state.currentQuestPeriod == key then
		state.currentBoard = board
	end
end

function QuestsPanel.Open()
	local panel = ensurePanel()
	if not panel then
		return
	end
	if state.closeOtherPanels then
		state.closeOtherPanels(panel)
	end
	local frame = panel:FindFirstChild("Frame") or panel
	local closeBtn = frame:FindFirstChild("Close")
	local claimBtn = frame:FindFirstChild("Claim")
	local toggleHolder = frame:FindFirstChild("ToggleHolder")
	local dailyToggle = toggleHolder and toggleHolder:FindFirstChild("DailyToggle")
	local weeklyToggle = toggleHolder and toggleHolder:FindFirstChild("WeeklyToggle")

	local function setPeriod(period)
		state.currentQuestPeriod = (period == "weekly") and "weekly" or "daily"
		local activeStroke = Color3.fromRGB(255, 217, 0)
		local inactiveStroke = Color3.fromRGB(255, 255, 255)
		local function setToggleStroke(toggle, isActive)
			if not toggle or not toggle:IsA("GuiObject") then
				return
			end
			local stroke = toggle:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				stroke.Color = isActive and activeStroke or inactiveStroke
			end
		end
		setToggleStroke(dailyToggle, state.currentQuestPeriod == "daily")
		setToggleStroke(weeklyToggle, state.currentQuestPeriod == "weekly")
	end

	local function refreshQuestBoard()
		local board = state.boardCache[state.currentQuestPeriod]
		if not board then
			board = state.RemoteRegistry:GetFunction("GetQuestBoard"):InvokeServer(state.currentQuestPeriod)
			state.boardCache[state.currentQuestPeriod] = board
		end
		state.currentBoard = board
		render(panel, board)
	end

	local function updateToggleNotifications()
		local dailyBoard = state.boardCache.daily
		if not dailyBoard then
			dailyBoard = state.RemoteRegistry:GetFunction("GetQuestBoard"):InvokeServer("daily")
			state.boardCache.daily = dailyBoard
		end
		local weeklyBoard = state.boardCache.weekly
		if not weeklyBoard then
			weeklyBoard = state.RemoteRegistry:GetFunction("GetQuestBoard"):InvokeServer("weekly")
			state.boardCache.weekly = weeklyBoard
		end
		applyToggleNotification(dailyToggle, countClaimableQuests(dailyBoard))
		applyToggleNotification(weeklyToggle, countClaimableQuests(weeklyBoard))
	end

	if not panel:GetAttribute("Wired") then
		panel:SetAttribute("Wired", true)
		if closeBtn and closeBtn:IsA("GuiButton") then
			closeBtn.MouseButton1Click:Connect(function()
				panel.Visible = false
			end)
		end
		if claimBtn and claimBtn:IsA("GuiButton") then
			claimBtn.MouseButton1Click:Connect(refreshQuestBoard)
		end
		if dailyToggle and dailyToggle:IsA("GuiButton") then
			dailyToggle.MouseButton1Click:Connect(function()
				setPeriod("daily")
				refreshQuestBoard()
			end)
		end
		if weeklyToggle and weeklyToggle:IsA("GuiButton") then
			weeklyToggle.MouseButton1Click:Connect(function()
				setPeriod("weekly")
				refreshQuestBoard()
			end)
		end
	end

	setPeriod(state.currentQuestPeriod)
	refreshQuestBoard()
	panel.Visible = true
	if frame ~= panel and frame:IsA("GuiObject") then
		frame.Visible = true
	end

	state.refreshThreadId += 1
	local threadId = state.refreshThreadId
	task.spawn(function()
		local sec = 0
		while panel and panel.Parent and panel.Visible and threadId == state.refreshThreadId do
			task.wait(1)
			if not panel.Visible then
				break
			end
			sec += 1
			if state.currentBoard and typeof(state.currentBoard) == "table" then
				state.currentBoard.resetsIn = math.max(0, (tonumber(state.currentBoard.resetsIn) or 0) - 1)
				local refreshFrame = panel:FindFirstChild("Frame") or panel
				local statusLabel = refreshFrame:FindFirstChild("Status")
				if statusLabel and statusLabel:IsA("TextLabel") then
					statusLabel.Text = string.format("Resets in %s", state.formatResetTime(state.currentBoard.resetsIn))
				end
			end
			if sec >= 20 then
				sec = 0
				refreshQuestBoard()
				updateToggleNotifications()
			end
		end
	end)

	updateToggleNotifications()
end

return QuestsPanel
