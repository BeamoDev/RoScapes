local TweenService = game:GetService("TweenService")

local AdminPanel = {}

local ADMIN_USER_IDS = {
	[1790165114] = true,
	[123315075] = true,
}

local ACTIONS = {
	{ key = "give_coins", title = "Give Coins" },
	{ key = "give_big_coins", title = "Give Big Coins" },
	{ key = "give_hints", title = "Give Hints" },
	{ key = "give_many_hints", title = "Give Many Hints" },
	{ key = "give_selection_hints", title = "Give Selection Hints" },
	{ key = "give_many_selection_hints", title = "Give Many Selection Hints" },
}

local state = {
	player = nil,
	frames = nil,
	RemoteRegistry = nil,
	UIManager = nil,
	HomePanels = nil,
	showPanel = nil,
	hidePanel = nil,
	setPlayerImageAsync = nil,
	rows = {},
	cooldownEnds = {},
	cooldownTokens = {},
	cooldownTweens = {},
}

local function getParts()
	local panel = state.frames and state.frames:FindFirstChild("AdminPanel")
	if not panel then
		return nil
	end
	local frame = panel:FindFirstChild("Frame") or panel
	local scroll = frame:FindFirstChild("Scroll")
	local template = frame:FindFirstChild("Template")
	local playerFrame = frame:FindFirstChild("PlayerFrame")
	local playerScroll = playerFrame and playerFrame:FindFirstChild("Scroll")
	local playerTemplate = playerFrame and playerFrame:FindFirstChild("PlayerTemplate")
	return panel, frame, scroll, template, playerFrame, playerScroll, playerTemplate
end

local function setIconColor(icon, color)
	if not (icon and icon:IsA("GuiObject")) then
		return
	end
	if icon:IsA("ImageLabel") or icon:IsA("ImageButton") then
		icon.ImageColor3 = color
	else
		icon.BackgroundColor3 = color
	end
end

local function tweenIconColor(icon, color)
	if not (icon and icon:IsA("GuiObject")) then
		return nil
	end
	local property = (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) and "ImageColor3" or "BackgroundColor3"
	local tween = TweenService:Create(icon, TweenInfo.new(1, Enum.EasingStyle.Linear), { [property] = color })
	tween:Play()
	return tween
end

local function refreshRow(actionKey)
	local row = state.rows[actionKey]
	if not (row and row.Parent) then
		return
	end
	local button = row:FindFirstChild("Button", true)
	local cooldown = row:FindFirstChild("Debounce", true)
	local debounceButton = cooldown and cooldown:FindFirstChild("Button", true)
	local icon = cooldown and cooldown:FindFirstChild("Icon", true)
	local title = cooldown and cooldown:FindFirstChild("Title", true)
	local remaining = math.max(0, math.ceil((state.cooldownEnds[actionKey] or 0) - os.clock()))
	local active = remaining > 0
	if button and button:IsA("GuiButton") then
		button.Active = not active
		button.AutoButtonColor = not active
		button.BackgroundColor3 = active and Color3.fromRGB(120, 120, 120) or Color3.fromRGB(0, 255, 60)
	end
	if cooldown and cooldown:IsA("GuiObject") then
		cooldown.Visible = active
	end
	if debounceButton and debounceButton:IsA("GuiButton") then
		debounceButton.Active = false
		debounceButton.AutoButtonColor = false
		debounceButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	end
	if title and title:IsA("TextLabel") then
		title.Text = active and string.format("Ready in 0:%02d", remaining) or ""
	end
	if icon and not active then
		local gradient = icon:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient:Destroy()
		end
		setIconColor(icon, Color3.fromRGB(0, 255, 60))
	end
end

local function startCooldown(actionKey)
	state.cooldownEnds[actionKey] = os.clock() + 3
	state.cooldownTokens[actionKey] = (state.cooldownTokens[actionKey] or 0) + 1
	local token = state.cooldownTokens[actionKey]
	local row = state.rows[actionKey]
	local cooldown = row and row:FindFirstChild("Debounce", true)
	local icon = cooldown and cooldown:FindFirstChild("Icon", true)
	if state.cooldownTweens[actionKey] then
		state.cooldownTweens[actionKey]:Cancel()
	end
	if icon then
		local gradient = icon:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient:Destroy()
		end
		setIconColor(icon, Color3.fromRGB(255, 70, 70))
	end
	task.spawn(function()
		while state.cooldownTokens[actionKey] == token do
			local currentRow = state.rows[actionKey]
			local currentCooldown = currentRow and currentRow:FindFirstChild("Debounce", true)
			local currentIcon = currentCooldown and currentCooldown:FindFirstChild("Icon", true)
			if state.cooldownTweens[actionKey] then
				state.cooldownTweens[actionKey]:Cancel()
			end
			state.cooldownTweens[actionKey] = tweenIconColor(currentIcon, Color3.fromRGB(0, 255, 60))
			refreshRow(actionKey)
			if os.clock() >= (state.cooldownEnds[actionKey] or 0) then
				state.cooldownEnds[actionKey] = nil
				refreshRow(actionKey)
				return
			end
			task.wait(1)
		end
	end)
end

local function openPlayerPicker(action)
	local _, _, _, _, playerFrame, scroll, template = getParts()
	if not (playerFrame and scroll and template) then
		return
	end
	state.showPanel(playerFrame)
	local close = playerFrame:FindFirstChild("Close")
	if close and close:IsA("GuiButton") and not close:GetAttribute("Wired") then
		close:SetAttribute("Wired", true)
		close.MouseButton1Click:Connect(function()
			state.hidePanel(playerFrame)
		end)
	end
	for _, child in ipairs(scroll:GetChildren()) do
		if child ~= template and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	template.Visible = false
	for _, info in ipairs(state.RemoteRegistry:GetFunction("GetAdminPlayers"):InvokeServer() or {}) do
		local row = template:Clone()
		row.Name = "AdminPlayer_" .. tostring(info.userId)
		row.Visible = true
		row.Parent = scroll
		local label = row:FindFirstChild("Label", true)
		if label and label:IsA("TextLabel") then
			label.Text = tostring(info.name or "Player")
		end
		state.setPlayerImageAsync(row:FindFirstChild("Mugshot", true), info.userId)
		local button = row:FindFirstChildWhichIsA("GuiButton", true)
		if button then
			button.MouseButton1Click:Connect(function()
				button.Active = false
				button.AutoButtonColor = false
				local result = state.RemoteRegistry:GetFunction("RunAdminAction"):InvokeServer(action.key, info.userId)
				if result and result.success then
					state.hidePanel(playerFrame)
					startCooldown(action.key)
					state.UIManager:ShowAlert(
						(result.message or "Done") .. " -> " .. tostring(result.targetName or info.name),
						"success"
					)
				else
					button.Active = true
					button.AutoButtonColor = true
					state.UIManager:ShowAlert((result and result.message) or "Admin action failed", "error")
				end
			end)
		end
	end
end

function AdminPanel.Init(options)
	for key, value in pairs(options) do
		state[key] = value
	end
end

function AdminPanel.IsAdmin()
	return state.player ~= nil and ADMIN_USER_IDS[state.player.UserId] == true
end

function AdminPanel.Open()
	if not AdminPanel.IsAdmin() then
		return
	end
	local panel, frame, scroll, template, playerFrame = getParts()
	if not (panel and scroll and template) then
		return
	end
	local close = frame:FindFirstChild("Close", true)
	if close and close:IsA("GuiButton") and not close:GetAttribute("Wired") then
		close:SetAttribute("Wired", true)
		close.MouseButton1Click:Connect(function()
			state.hidePanel(panel)
			if playerFrame then
				state.hidePanel(playerFrame)
			end
		end)
	end
	for _, child in ipairs(scroll:GetChildren()) do
		if child ~= template and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	template.Visible = false
	state.rows = {}
	for _, action in ipairs(ACTIONS) do
		local row = template:Clone()
		row.Name = "AdminAction_" .. action.key
		row.Visible = true
		row.Parent = scroll
		state.rows[action.key] = row
		local title = row:FindFirstChild("Title", true)
		if title and title:IsA("TextLabel") then
			title.Text = action.title
		end
		local button = row:FindFirstChild("Button", true)
		if button and button:IsA("GuiButton") then
			button.MouseButton1Click:Connect(function()
				if (state.cooldownEnds[action.key] or 0) <= os.clock() then
					openPlayerPicker(action)
				end
			end)
		end
		refreshRow(action.key)
	end
	if playerFrame then
		playerFrame.Visible = false
	end
	state.HomePanels.CloseAllPanels(panel)
	state.showPanel(panel)
end

return AdminPanel
