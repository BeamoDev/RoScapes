-- UIManager.luau
-- UI wiring and screen transitions.


local TweenService      = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIEffects = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("util"):WaitForChild("UIEffects"))
local ClientBridge = require(script.Parent.Parent.core.ClientBridge)
local CoinCounter = require(script.Parent.CoinCounter)
local GuiMotion = require(script.Parent.GuiMotion)

local UIManager = {}

local gui           = nil
local screens       = {}
local currentScreen = nil
local onShowCallbacks = {}
local hud           = nil
local alertHost     = nil
local alertTemplate = nil
local alertSequence = 0
local activeAlertKeys = {}

UIManager.Colors = {
	bg          = Color3.fromRGB(10,  14,  22),   -- near-black base
	bgDark      = Color3.fromRGB(0,   0,   0),    -- pure black for overlays
	bgPanel     = Color3.fromRGB(18,  22,  32),   -- dark panel
	cell        = Color3.fromRGB(242, 238, 228),  -- warm cream (unfound)
	cellFound   = Color3.fromRGB(105, 195,  80),  -- green (found)
	cellHint    = Color3.fromRGB(255, 210,  55),  -- gold (hinted)
	cellEmpty   = Color3.fromRGB(0,   0,   0),    -- unused (transparent)
	wheelBg     = Color3.fromRGB(0,   0,   0),
	letterBtn   = Color3.fromRGB(255, 255, 255),
	letterSel   = Color3.fromRGB(255, 220,  25),
	text        = Color3.fromRGB(255, 255, 255),
	textDark    = Color3.fromRGB(10,  14,  22),
	accent      = Color3.fromRGB(255, 210,  45),
	bonusGreen  = Color3.fromRGB(60,  205,  95),
	invalid     = Color3.fromRGB(215,  70,  70),
	shopGold    = Color3.fromRGB(255, 200,  30),
	shopBlue    = Color3.fromRGB(40,  100, 220),
}

local INFO  = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local INFO2 = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)


local function makeFrame(name, parent, props)
	local f = Instance.new("Frame")
	f.Name              = name
	f.BackgroundColor3  = props.bg   or Color3.fromRGB(0, 0, 0)
	f.BorderSizePixel   = 0
	f.Size              = props.size or UDim2.fromScale(1, 1)
	f.Position          = props.pos  or UDim2.fromScale(0, 0)
	f.ClipsDescendants  = props.clip or false
	f.Parent            = parent
	return f
end

local function makeLabel(text, parent, props)
	local l = Instance.new("TextLabel")
	l.Text              = text
	l.Font              = props.font   or Enum.Font.GothamBold
	l.TextSize          = props.size   or 18
	l.TextColor3        = props.color  or UIManager.Colors.text
	l.BackgroundTransparency = 1
	l.Size              = props.sz     or UDim2.fromScale(1, 1)
	l.Position          = props.pos    or UDim2.fromScale(0, 0)
	l.TextXAlignment    = props.xAlign or Enum.TextXAlignment.Center
	l.TextYAlignment    = props.yAlign or Enum.TextYAlignment.Center
	l.TextScaled        = props.scaled or false
	l.Parent            = parent
	return l
end

local function makeButton(text, parent, props)
	local b = Instance.new("TextButton")
	b.Text              = text
	b.Font              = props.font   or Enum.Font.GothamBold
	b.TextSize          = props.size   or 18
	b.TextColor3        = props.color  or UIManager.Colors.textDark
	b.BackgroundColor3  = props.bg     or UIManager.Colors.accent
	b.BorderSizePixel   = 0
	b.Size              = props.sz     or UDim2.fromScale(0.4, 0.06)
	b.Position          = props.pos    or UDim2.fromScale(0.3, 0.47)
	b.AutoButtonColor   = false
	b.Parent            = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, props.radius or 12)
	corner.Parent = b

	local origBg = props.bg or UIManager.Colors.accent
	b.MouseEnter:Connect(function()
		TweenService:Create(b, INFO,
			{BackgroundColor3 = origBg:Lerp(Color3.new(1, 1, 1), 0.15)}):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, INFO,
			{BackgroundColor3 = origBg}):Play()
	end)
	b.MouseButton1Down:Connect(function()
		local sz = props.sz or UDim2.fromScale(0.4, 0.06)
		local shrunk = UDim2.new(
			sz.X.Scale * 0.93, sz.X.Offset * 0.93,
			sz.Y.Scale * 0.93, sz.Y.Offset * 0.93
		)
		TweenService:Create(b, TweenInfo.new(0.08), {Size = shrunk}):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(b, INFO2,
			{Size = props.sz or UDim2.fromScale(0.4, 0.06)}):Play()
	end)

	return b
end

UIManager.makeFrame  = makeFrame
UIManager.makeLabel  = makeLabel
UIManager.makeButton = makeButton
UIManager.INFO       = INFO
UIManager.INFO2      = INFO2


local function makeOverlay(zBase)
	local ov = Instance.new("Frame")
	ov.Size                   = UDim2.fromScale(1, 1)
	ov.BackgroundColor3       = Color3.new(0, 0, 0)
	ov.BackgroundTransparency = 0.35
	ov.ZIndex                 = zBase
	ov.Parent                 = hud or gui
	return ov
end

local function popInPanel(panel, targetSize, targetPos)
	panel.Size     = UDim2.fromOffset(0, 0)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	TweenService:Create(panel,
		TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size     = targetSize,
			Position = targetPos,
		}):Play()
end

local function closeButton(parent, zIdx, onClose)
	local btn = Instance.new("TextButton")
	btn.Text                 = "X"
	btn.Font                 = Enum.Font.GothamBold
	btn.TextSize             = 20
	btn.TextColor3           = UIManager.Colors.text
	btn.BackgroundTransparency = 1
	btn.Size                 = UDim2.fromOffset(40, 40)
	btn.Position             = UDim2.new(1, -44, 0, 4)
	btn.ZIndex               = zIdx
	btn.Parent               = parent
	btn.MouseButton1Click:Connect(onClose)
	return btn
end


function UIManager:ShowLeaderboard()
	local C       = self.Colors
	local overlay = makeOverlay(50)

	local W, H   = 340, 440
	local panel  = makeFrame("LBPanel", overlay, {
		bg   = C.bgPanel,
		size = UDim2.fromOffset(W, H),
		pos  = UDim2.new(0.5, -W/2, 0.5, -H/2),
	})
	panel.ZIndex = 51

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 22)
	corner.Parent = panel

	-- Title
	makeLabel("ðŸ†  LEADERBOARD", panel, {
		size  = 20,
		sz    = UDim2.new(1, 0, 0, 50),
		pos   = UDim2.fromScale(0, 0),
		color = C.accent,
	}).ZIndex = 52

	closeButton(panel, 52, function()
		overlay:Destroy()
	end)

	-- Loading
	local loadLbl = makeLabel("Loading...", panel, {
		size  = 15,
		sz    = UDim2.new(1, 0, 1, -54),
		pos   = UDim2.fromOffset(0, 54),
		color = Color3.fromRGB(160, 190, 255),
	})
	loadLbl.ZIndex = 52

	-- Divider
	local div = Instance.new("Frame")
	div.Size             = UDim2.new(0.85, 0, 0, 1)
	div.Position         = UDim2.new(0.075, 0, 0, 50)
	div.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	div.BackgroundTransparency = 0.85
	div.BorderSizePixel  = 0
	div.ZIndex           = 52
	div.Parent           = panel

	-- Fetch
	task.spawn(function()
		local RemoteRegistry = require(ReplicatedStorage:WaitForChild("Shared").RemoteRegistry)
		local data = RemoteRegistry:GetFunction("GetLeaderboard"):InvokeServer()

		if not data or #data == 0 then
			loadLbl.Text = "No entries yet - complete levels!"
			return
		end

		loadLbl:Destroy()

		local scroll = Instance.new("ScrollingFrame")
		scroll.Size                  = UDim2.new(1, -20, 1, -60)
		scroll.Position              = UDim2.fromOffset(10, 58)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel       = 0
		scroll.ScrollBarThickness    = 3
		scroll.ScrollBarImageColor3  = C.accent
		scroll.CanvasSize            = UDim2.fromScale(0, 0)
		scroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
		scroll.ZIndex                = 52
		scroll.Parent                = panel

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.Parent  = scroll

		for _, entry in ipairs(data) do
			local isTop3 = entry.rank <= 3
			local rowBg  = isTop3
				and Color3.fromRGB(40, 30, 5)
				or  Color3.fromRGB(22, 24, 34)

			local row = makeFrame("Row_"..entry.rank, scroll, {
				bg   = rowBg,
				size = UDim2.new(1, 0, 0, 46),
			})
			row.ZIndex = 53

			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(0, 10)
			rc.Parent = row

			-- Rank medal / number
			local rankTxt = isTop3
				and ({"ðŸ¥‡","ðŸ¥ˆ","ðŸ¥‰"})[entry.rank]
				or  ("#" .. entry.rank)

			makeLabel(rankTxt, row, {
				size  = isTop3 and 22 or 16,
				sz    = UDim2.fromOffset(44, 46),
				pos   = UDim2.fromScale(0, 0),
				color = isTop3 and C.accent or C.text,
			}).ZIndex = 54

			makeLabel(entry.name, row, {
				size   = 15,
				sz     = UDim2.new(1, -130, 1, 0),
				pos    = UDim2.fromOffset(46, 0),
				xAlign = Enum.TextXAlignment.Left,
				color  = C.text,
			}).ZIndex = 54

			makeLabel(tostring(entry.solved) .. " solved", row, {
				size   = 14,
				sz     = UDim2.fromOffset(80, 46),
				pos    = UDim2.new(1, -84, 0, 0),
				xAlign = Enum.TextXAlignment.Right,
				color  = C.bonusGreen,
			}).ZIndex = 54
		end
	end)

	popInPanel(panel, UDim2.fromOffset(W, H), UDim2.new(0.5, -W/2, 0.5, -H/2))
end


--[[
-- For Roblox DevProducts (paid hints), use this config:
local HINT_PACKS = {
	{ label = "3 Hints",  icon = "ðŸ’¡", amount = 3,  productId = 1234500001, priceLabel = "Small" },
	{ label = "10 Hints", icon = "ðŸ’¡ðŸ’¡", amount = 10, productId = 1234500002, priceLabel = "Value" },
	{ label = "50 Hints", icon = "ðŸ’¡ðŸ’¡ðŸ’¡", amount = 50, productId = 1234500003, priceLabel = "Best Value" },
}
--]]

-- Hint packs with coin prices
local HINT_PACKS = {
	{ label = "3 Hints",  icon = "ðŸ’¡", amount = 3,  priceLabel = "50 coins", cost = 50 },
	{ label = "10 Hints", icon = "ðŸ’¡ðŸ’¡", amount = 10, priceLabel = "150 coins", cost = 150 },
	{ label = "50 Hints", icon = "ðŸ’¡ðŸ’¡ðŸ’¡", amount = 50, priceLabel = "600 coins", cost = 600 },
}

-- NOTE: All main UI is in PlayerGui.HUD (created in Studio)
-- This module only handles screen visibility and modals

function UIManager:Init(playerGui, playerData)
	-- Store reference to playerGui for modals
	gui = playerGui
	screens = {}
	currentScreen = nil
	
	-- Get HUD and register screens
	hud = playerGui:WaitForChild("HUD")
	
	-- New hierarchy: HUD.Home / HUD.Game / HUD.Levels
	local homeFrame = hud:FindFirstChild("Home")
	local levelsFrame = hud:FindFirstChild("Levels") or hud:FindFirstChild("LevelSelect")
	local gameScreenFrame = hud:FindFirstChild("Game") or hud:FindFirstChild("GameScreen")

	if homeFrame then
		self:RegisterScreen("HomeScreen", homeFrame)
	end
	if levelsFrame then
		self:RegisterScreen("LevelSelect", levelsFrame)
	end
	if gameScreenFrame then
		self:RegisterScreen("GameScreen", gameScreenFrame)
	end
end

function UIManager:RegisterScreen(name, frame)
	screens[name] = frame
	frame.Visible = false
end

function UIManager:ShowScreen(name)
	local frame = screens[name]
	if not frame then
		warn("[UIManager] Unknown screen:", name)
		return
	end
	if currentScreen == name and frame.Visible then
		return
	end

	if currentScreen and screens[currentScreen] then
		if currentScreen == "HomeScreen" or currentScreen == "LevelSelect" then
			GuiMotion.HideFlow(screens[currentScreen])
		else
			GuiMotion.Hide(screens[currentScreen])
		end
	end

	currentScreen = name
	if name == "HomeScreen" or name == "LevelSelect" then
		GuiMotion.ShowFlow(frame)
	else
		GuiMotion.Show(frame)
	end

	if onShowCallbacks[name] then
		onShowCallbacks[name]()
	end
end

function UIManager:OnShow(name, fn)
	onShowCallbacks[name] = fn
end

function UIManager:GetGui()
	return gui
end

function UIManager:GetHUD()
	return hud
end

-- Hint updates handled in ClientMain

function UIManager:Bounce(element)
	local orig = element.Size
	TweenService:Create(element,
		TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = orig * UDim2.fromScale(1.15, 1.15)}):Play()
	task.delay(0.12, function()
		TweenService:Create(element,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Size = orig}):Play()
	end)
end

local function ensureAlertHost()
	if not hud then
		return nil
	end
	if alertHost and alertHost.Parent then
		return alertHost
	end

	alertHost = hud:FindFirstChild("AlertHost")
	if not (alertHost and alertHost:IsA("GuiObject")) then
		alertHost = Instance.new("Frame")
		alertHost.Name = "AlertHost"
		alertHost.AnchorPoint = Vector2.new(0.5, 0)
		alertHost.BackgroundTransparency = 1
		alertHost.Size = UDim2.new(0, 380, 1, -24)
		alertHost.Position = UDim2.new(0.5, 0, 0, 18)
		alertHost.ZIndex = 100
		alertHost.Parent = hud
	end

	local list = alertHost:FindFirstChildOfClass("UIListLayout")
	if not list then
		list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 10)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = alertHost
	end

	return alertHost
end

local function ensureAlertTemplate()
	if not hud then
		return nil
	end
	if alertTemplate and alertTemplate.Parent then
		return alertTemplate
	end
	alertTemplate = hud:FindFirstChild("AlertTemplate")
	if alertTemplate and alertTemplate:IsA("GuiObject") then
		alertTemplate.Visible = false
		return alertTemplate
	end
	return nil
end

local function getAlertTheme(alertType)
	local tint = Color3.fromRGB(84, 142, 255)
	if alertType == "success" then
		tint = Color3.fromRGB(90, 212, 142)
	elseif alertType == "error" then
		tint = Color3.fromRGB(244, 104, 104)
	elseif alertType == "bonus" then
		tint = Color3.fromRGB(255, 210, 106)
	elseif alertType == "coin" then
		tint = Color3.fromRGB(255, 192, 92)
	end
	return {
		tint = tint,
		bg = Color3.fromRGB(18, 22, 31):Lerp(tint, 0.14),
		text = Color3.fromRGB(245, 248, 255),
	}
end


function UIManager:ShowAlert(message, alertType, options)
	if not hud then
		return
	end
	options = (typeof(options) == "table") and options or {}
	local debounceKey = options.debounceKey
	local ok, err = pcall(function()
		if ClientBridge.Call("IsTutorialActive") then
			return
		end
		if typeof(debounceKey) == "string" and debounceKey ~= "" then
			if activeAlertKeys[debounceKey] then
				return
			end
			activeAlertKeys[debounceKey] = true
		end

		local host = ensureAlertHost()
		if not host then
			if debounceKey then
				activeAlertKeys[debounceKey] = nil
			end
			return
		end

		alertSequence += 1
		local theme = getAlertTheme(alertType)
		local template = ensureAlertTemplate()
		local alert = nil
		if template then
			alert = template:Clone()
			alert.Name = "Alert"
			alert.Visible = true
			alert.LayoutOrder = alertSequence
			alert.Parent = host
		else
			alert = Instance.new("Frame")
			alert.Name = "Alert"
			alert.LayoutOrder = alertSequence
			alert.Size = UDim2.new(1, 0, 0.085, 0)
			alert.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
			alert.BackgroundTransparency = 0.4
			alert.BorderSizePixel = 0
			alert.ClipsDescendants = true
			alert.ZIndex = 100
			alert.Parent = host

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 14)
			corner.Parent = alert

			local fallbackLabel = Instance.new("TextLabel")
			fallbackLabel.Name = "Label"
			fallbackLabel.Text = tostring(message or "")
			fallbackLabel.Font = Enum.Font.GothamMedium
			fallbackLabel.TextScaled = true
			fallbackLabel.TextSize = 17
			fallbackLabel.TextColor3 = Color3.fromRGB(245, 248, 255)
			fallbackLabel.TextWrapped = true
			fallbackLabel.TextXAlignment = Enum.TextXAlignment.Center
			fallbackLabel.TextYAlignment = Enum.TextYAlignment.Center
			fallbackLabel.BackgroundTransparency = 1
			fallbackLabel.Size = UDim2.new(0.92, 0, 0.82, 0)
			fallbackLabel.Position = UDim2.fromScale(0.04, 0.09)
			fallbackLabel.ZIndex = 102
			fallbackLabel.Parent = alert

			local sizeConstraint = Instance.new("UITextSizeConstraint")
			sizeConstraint.MaxTextSize = 17
			sizeConstraint.MinTextSize = 13
			sizeConstraint.Parent = fallbackLabel
		end

		local scale = alert:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Scale = 0.96
			scale.Parent = alert
		else
			scale.Scale = 0.96
		end

		local label = alert:FindFirstChild("Label", true)
		if label and label:IsA("TextLabel") then
			label.Text = tostring(message or "")
			label.TextTransparency = 1
			label.TextColor3 = theme.text
			label.TextWrapped = true
		end

		alert.BackgroundTransparency = 1

		local stroke = alert:FindFirstChildWhichIsA("UIStroke", true)
		if stroke then
			stroke.Transparency = 1
		end

		TweenService:Create(alert, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.4,
		}):Play()
		TweenService:Create(scale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		if label then
			TweenService:Create(label, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				TextTransparency = 0,
			}):Play()
		end
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 0.55,
			}):Play()
		end

		task.delay(2.6, function()
			if not (alert and alert.Parent) then
				return
			end
			TweenService:Create(alert, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
			}):Play()
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Scale = 0.96,
			}):Play()
			if label then
				TweenService:Create(label, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					TextTransparency = 1,
				}):Play()
			end
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Transparency = 1,
				}):Play()
			end
			task.delay(0.22, function()
				if alert and alert.Parent then
					alert:Destroy()
				end
				if debounceKey then
					activeAlertKeys[debounceKey] = nil
				end
			end)
		end)
	end)
	if not ok then
		warn("[UIManager] ShowAlert failed:", err)
		if debounceKey then
			activeAlertKeys[debounceKey] = nil
		end
	end
end

local function formatInt(n)
	local v = tonumber(n) or 0
	local s = tostring(math.floor(v))
	local out = s
	while true do
		local replaced, count = out:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		out = replaced
		if count == 0 then
			break
		end
	end
	return out
end

local function readCurrency(name)
	local player = Players.LocalPlayer
	if name == "Coins" then
		local leaderstats = player and player:FindFirstChild("leaderstats")
		local valueObj = leaderstats and leaderstats:FindFirstChild("Coins")
		if valueObj and valueObj:IsA("IntValue") then
			return valueObj.Value
		end
		return 0
	end
	local data = player and player:FindFirstChild("Data")
	local currency = data and data:FindFirstChild("Currency")
	local valueObj = currency and currency:FindFirstChild(name)
	if valueObj and valueObj:IsA("IntValue") then
		return valueObj.Value
	end
	return 0
end

-- Cleaner v2 shop UI with coin pricing cards.
function UIManager:ShowHintShop()
	local C = self.Colors
	local overlay = makeOverlay(70)
	local W, H = 410, 440
	local panel = makeFrame("HintShopV2", overlay, {
		bg = Color3.fromRGB(14, 20, 34),
		size = UDim2.fromOffset(W, H),
		pos = UDim2.new(0.5, -W / 2, 0.5, -H / 2),
	})
	panel.ZIndex = 71

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = panel

	makeLabel("Hint Shop", panel, {
		size = 24,
		sz = UDim2.new(1, -90, 0, 42),
		pos = UDim2.fromOffset(14, 10),
		xAlign = Enum.TextXAlignment.Left,
		color = Color3.fromRGB(243, 248, 255),
	}).ZIndex = 72

	local close = makeButton("Close", panel, {
		sz = UDim2.fromOffset(86, 30),
		pos = UDim2.new(1, -98, 0, 14),
		bg = Color3.fromRGB(64, 78, 118),
		color = Color3.fromRGB(232, 240, 255),
		size = 14,
		radius = 9,
	})
	close.ZIndex = 72
	close.MouseButton1Click:Connect(function()
		overlay:Destroy()
	end)

	local statusCard = makeFrame("StatusCard", panel, {
		bg = Color3.fromRGB(24, 34, 58),
		size = UDim2.new(1, -24, 0, 60),
		pos = UDim2.fromOffset(12, 56),
	})
	statusCard.ZIndex = 72
	local statusCorner = Instance.new("UICorner")
	statusCorner.CornerRadius = UDim.new(0, 12)
	statusCorner.Parent = statusCard

	local hintsLabel = makeLabel("", statusCard, {
		size = 15,
		sz = UDim2.new(0.5, -8, 1, 0),
		pos = UDim2.fromOffset(10, 0),
		xAlign = Enum.TextXAlignment.Left,
		color = Color3.fromRGB(225, 235, 255),
	})
	hintsLabel.ZIndex = 73

	local coinsLabel = makeLabel("", statusCard, {
		size = 15,
		sz = UDim2.new(0.5, -8, 1, 0),
		pos = UDim2.new(0.5, 0, 0, 0),
		xAlign = Enum.TextXAlignment.Right,
		color = Color3.fromRGB(255, 221, 128),
	})
	coinsLabel.ZIndex = 73

	local function refreshBalance()
		hintsLabel.Text = "Hints: " .. formatInt(readCurrency("Hints"))
		CoinCounter.Set(coinsLabel, readCurrency("Coins"), { prefix = "Coins: " })
	end
	refreshBalance()

	local list = Instance.new("ScrollingFrame")
	list.Name = "PackList"
	list.Size = UDim2.new(1, -24, 1, -144)
	list.Position = UDim2.fromOffset(12, 126)
	list.BackgroundColor3 = Color3.fromRGB(11, 17, 30)
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.fromScale(0, 0)
	list.ZIndex = 72
	list.Parent = panel
	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0, 12)
	listCorner.Parent = list

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Size = UDim2.new(1, -12, 0, 0)
	content.Position = UDim2.fromOffset(6, 6)
	content.ZIndex = 73
	content.Parent = list

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = content

	for i, pack in ipairs(HINT_PACKS) do
		local card = makeFrame("Pack_" .. i, content, {
			bg = Color3.fromRGB(23, 31, 52),
			size = UDim2.new(1, 0, 0, 74),
		})
		card.ZIndex = 73
		card.LayoutOrder = i
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 12)
		cc.Parent = card

		makeLabel(pack.label, card, {
			size = 18,
			sz = UDim2.new(0.55, 0, 0, 30),
			pos = UDim2.fromOffset(12, 6),
			xAlign = Enum.TextXAlignment.Left,
			color = Color3.fromRGB(244, 248, 255),
		}).ZIndex = 74

		makeLabel("Price: " .. formatInt(pack.cost) .. " coins", card, {
			size = 14,
			sz = UDim2.new(0.55, 0, 0, 22),
			pos = UDim2.fromOffset(12, 38),
			xAlign = Enum.TextXAlignment.Left,
			color = Color3.fromRGB(255, 214, 121),
		}).ZIndex = 74

		local buyBtn = makeButton("Buy", card, {
			sz = UDim2.fromOffset(96, 42),
			pos = UDim2.new(1, -106, 0.5, -21),
			bg = C.shopGold,
			color = C.textDark,
			size = 15,
			radius = 10,
		})
		buyBtn.ZIndex = 74

		buyBtn.MouseButton1Click:Connect(function()
			buyBtn.Active = false
			local RemoteRegistry = require(ReplicatedStorage:WaitForChild("Shared").RemoteRegistry)
			local success = RemoteRegistry:GetFunction("BuyHintsWithCoins"):InvokeServer(pack.amount, pack.cost)
			if success then
				UIEffects.PlaySound("Purchase")
				self:ShowAlert("Purchased " .. pack.amount .. " hints", "success")
			else
				UIEffects.PlaySound("Error")
				self:ShowAlert("Not enough coins", "error")
			end
			refreshBalance()
			buyBtn.Active = true
		end)
	end

	makeLabel("Tip: bigger packs are better value over time.", panel, {
		size = 12,
		sz = UDim2.new(1, -24, 0, 18),
		pos = UDim2.fromOffset(12, H - 24),
		xAlign = Enum.TextXAlignment.Left,
		color = Color3.fromRGB(145, 166, 207),
	}).ZIndex = 72

	popInPanel(panel, UDim2.fromOffset(W, H), UDim2.new(0.5, -W / 2, 0.5, -H / 2))
end

-- v2 leaderboard UI with category tabs.
function UIManager:ShowLeaderboard()
	local LEADERBOARD_REFRESH_SECONDS = 120
	local RemoteRegistry = require(ReplicatedStorage:WaitForChild("Shared").RemoteRegistry)
	local framesRoot = hud and hud:FindFirstChild("Frames")
	local panel = framesRoot and framesRoot:FindFirstChild("Leaderboard")
	if not panel then
		return
	end

	local frameRoot = panel:FindFirstChild("Frame") or panel
	local titleLabel = frameRoot:FindFirstChild("Title", true)
	local statusLabel = frameRoot:FindFirstChild("Status", true)
	local solvesFrame = frameRoot:FindFirstChild("SolvesFrame", true)
	local streakFrame = frameRoot:FindFirstChild("StreakFrame", true)
	local toggleHolder = frameRoot:FindFirstChild("TogglHolder", true) or frameRoot:FindFirstChild("ToggleHolder", true)
	local solvesToggle = toggleHolder and (toggleHolder:FindFirstChild("Solves") or toggleHolder:FindFirstChild("SolvesButton"))
	local streakToggle = toggleHolder and (toggleHolder:FindFirstChild("BestStreak") or toggleHolder:FindFirstChild("Streak") or toggleHolder:FindFirstChild("BestStreakButton"))
	local template = frameRoot:FindFirstChild("Template", true) or frameRoot:FindFirstChild("PlayerTemplate", true)
	local closeBtn = frameRoot:FindFirstChild("Close", true)
	if not (solvesFrame and streakFrame and template) then
		return
	end

	local medalColors = {
		[1] = Color3.fromRGB(255, 215, 80),
		[2] = Color3.fromRGB(210, 220, 235),
		[3] = Color3.fromRGB(205, 140, 95),
	}

	local function getListContent(scrollLike)
		if not scrollLike then
			return nil
		end
		return scrollLike:FindFirstChild("Content") or scrollLike
	end

	local solvesContent = getListContent(solvesFrame)
	local streakContent = getListContent(streakFrame)
	if not (solvesContent and streakContent) then
		return
	end

	local function formatRefreshCountdown(totalSeconds)
		local seconds = math.max(0, math.floor(totalSeconds))
		local mins = math.floor(seconds / 60)
		local secs = seconds % 60
		return string.format("Updating in %d:%02ds", mins, secs)
	end

	local function clearList(content)
		for _, child in ipairs(content:GetChildren()) do
			if child ~= template and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
	end

	local function setPlayerImage(imageLabel, userId)
		if not (imageLabel and imageLabel:IsA("ImageLabel")) then
			return
		end
		imageLabel.Image = "rbxassetid://0"
		task.spawn(function()
			local ok, content = pcall(function()
				return Players:GetUserThumbnailAsync(tonumber(userId) or 0, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and imageLabel.Parent then
				imageLabel.Image = content
			end
		end)
	end

	local function styleToggle(activeKey)
		local activeStroke = Color3.fromRGB(255, 217, 0)
		local inactiveStroke = Color3.fromRGB(255, 255, 255)
		local toggles = {
			solves = solvesToggle,
			streaks = streakToggle,
		}
		for key, button in pairs(toggles) do
			if button and button:IsA("GuiObject") then
				local stroke = button:FindFirstChildWhichIsA("UIStroke")
				if stroke then
					stroke.Color = (key == activeKey) and activeStroke or inactiveStroke
				end
			end
		end
		if titleLabel and titleLabel:IsA("TextLabel") then
			titleLabel.Text = (activeKey == "streaks") and "Freeplay Streak" or "Most Solves"
		end
		solvesFrame.Visible = activeKey == "solves"
		streakFrame.Visible = activeKey == "streaks"
	end

	local function populateList(content, entries, valueField)
		clearList(content)
		for _, entry in ipairs(entries or {}) do
			local row = template:Clone()
			row.Name = "Player_" .. tostring(entry.userId or entry.rank or entry.name or "Row")
			row.Visible = true
			row.Parent = content

			local mugshot = row:FindFirstChild("Mugshot", true)
			local username = row:FindFirstChild("Username", true)
			local rankLabel = row:FindFirstChild("Rank", true)
			local dataLabel = row:FindFirstChild("Data", true)
			local gradient = row:FindFirstChild("Gradient", true)
			local rankValue = tonumber(entry.rank) or 0
			local medalColor = medalColors[rankValue]

			setPlayerImage(mugshot, entry.userId)
			if username and username:IsA("TextLabel") then
				username.Text = tostring(entry.name or "Player")
			end
			if rankLabel and rankLabel:IsA("TextLabel") then
				rankLabel.Text = "#" .. tostring(rankValue)
				rankLabel.TextColor3 = medalColor or Color3.fromRGB(235, 242, 255)
			end
			if dataLabel and dataLabel:IsA("TextLabel") then
				dataLabel.Text = formatInt(tonumber(entry[valueField]) or 0)
			end
			if gradient and gradient:IsA("UIGradient") then
				gradient.Enabled = medalColor ~= nil
				if medalColor then
					gradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, medalColor:Lerp(Color3.new(1, 1, 1), 0.15)),
						ColorSequenceKeypoint.new(1, medalColor),
					})
				end
			elseif gradient and gradient:IsA("ImageLabel") then
				gradient.Visible = medalColor ~= nil
				if medalColor then
					gradient.ImageColor3 = medalColor
				end
			end
		end
	end

	local function refreshData()
		local rawData = RemoteRegistry:GetFunction("GetLeaderboard"):InvokeServer("all") or {}
		populateList(solvesContent, rawData.solves or {}, "solved")
		populateList(streakContent, rawData.streaks or {}, "bestStreak")
	end

	if not panel:GetAttribute("LeaderboardWired") then
		panel:SetAttribute("LeaderboardWired", true)
		if closeBtn and closeBtn:IsA("GuiButton") then
			closeBtn.MouseButton1Click:Connect(function()
				GuiMotion.Hide(panel, frameRoot)
			end)
		end
		if solvesToggle and solvesToggle:IsA("GuiButton") then
			solvesToggle.MouseButton1Click:Connect(function()
				styleToggle("solves")
			end)
		end
		if streakToggle and streakToggle:IsA("GuiButton") then
			streakToggle.MouseButton1Click:Connect(function()
				styleToggle("streaks")
			end)
		end
	end

	template.Visible = false
	styleToggle("solves")
	GuiMotion.Show(panel, frameRoot)
	refreshData()

	local refreshToken = (tonumber(panel:GetAttribute("LeaderboardRefreshToken")) or 0) + 1
	panel:SetAttribute("LeaderboardRefreshToken", refreshToken)
	panel:SetAttribute("LeaderboardRefreshDeadline", os.clock() + LEADERBOARD_REFRESH_SECONDS)
	task.spawn(function()
		local token = refreshToken
		while panel.Parent and panel.Visible and panel:GetAttribute("LeaderboardRefreshToken") == token do
			local deadline = tonumber(panel:GetAttribute("LeaderboardRefreshDeadline")) or (os.clock() + LEADERBOARD_REFRESH_SECONDS)
			local remaining = deadline - os.clock()
			if statusLabel and statusLabel:IsA("TextLabel") then
				statusLabel.Text = formatRefreshCountdown(remaining)
			end
			if remaining <= 0 then
				refreshData()
				deadline = os.clock() + LEADERBOARD_REFRESH_SECONDS
				panel:SetAttribute("LeaderboardRefreshDeadline", deadline)
				if statusLabel and statusLabel:IsA("TextLabel") then
					statusLabel.Text = formatRefreshCountdown(LEADERBOARD_REFRESH_SECONDS)
				end
			end
			task.wait(1)
		end
	end)
end

function UIManager:ShowStats()
	local overlay = makeOverlay(70)
	local W, H = 430, 500
	local panel = makeFrame("StatsPanel", overlay, {
		bg = Color3.fromRGB(16, 22, 36),
		size = UDim2.fromOffset(W, H),
		pos = UDim2.new(0.5, -W / 2, 0.5, -H / 2),
	})
	panel.ZIndex = 71
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = panel

	makeLabel("Player Stats", panel, {
		size = 24,
		sz = UDim2.new(1, -94, 0, 42),
		pos = UDim2.fromOffset(14, 10),
		xAlign = Enum.TextXAlignment.Left,
		color = Color3.fromRGB(243, 248, 255),
	}).ZIndex = 72

	local close = makeButton("Close", panel, {
		sz = UDim2.fromOffset(86, 30),
		pos = UDim2.new(1, -98, 0, 14),
		bg = Color3.fromRGB(64, 78, 118),
		color = Color3.fromRGB(232, 240, 255),
		size = 14,
		radius = 9,
	})
	close.ZIndex = 72
	close.MouseButton1Click:Connect(function()
		overlay:Destroy()
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -24, 1, -68)
	scroll.Position = UDim2.fromOffset(12, 56)
	scroll.BackgroundColor3 = Color3.fromRGB(11, 18, 31)
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	scroll.ZIndex = 72
	scroll.Parent = panel
	local scrollCorner = Instance.new("UICorner")
	scrollCorner.CornerRadius = UDim.new(0, 10)
	scrollCorner.Parent = scroll

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Size = UDim2.new(1, -12, 0, 0)
	content.Position = UDim2.fromOffset(6, 6)
	content.Parent = scroll
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = content

	local function addStatRow(labelText, valueText, color)
		local row = makeFrame("Row_" .. labelText, content, {
			bg = Color3.fromRGB(24, 33, 54),
			size = UDim2.new(1, 0, 0, 40),
		})
		row.ZIndex = 73
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 9)
		rc.Parent = row
		makeLabel(labelText, row, {
			size = 14,
			sz = UDim2.new(0.6, -12, 1, 0),
			pos = UDim2.fromOffset(10, 0),
			xAlign = Enum.TextXAlignment.Left,
			color = Color3.fromRGB(214, 226, 247),
		}).ZIndex = 74
		makeLabel(valueText, row, {
			size = 14,
			sz = UDim2.new(0.4, -12, 1, 0),
			pos = UDim2.new(0.6, 0, 0, 0),
			xAlign = Enum.TextXAlignment.Right,
			color = color or Color3.fromRGB(140, 255, 180),
		}).ZIndex = 74
	end

	task.spawn(function()
		local RemoteRegistry = require(ReplicatedStorage:WaitForChild("Shared").RemoteRegistry)
		local payload = RemoteRegistry:GetFunction("GetPlayerStats"):InvokeServer() or {}
		local stats = payload.stats or {}
		local rank = payload.rank or {}
		local coins = tonumber(payload.coins) or 0
		local hints = tonumber(payload.hints) or 0
		local solved = tonumber(payload.solved) or 0

		addStatRow("Coins", formatInt(coins), Color3.fromRGB(255, 214, 121))
		addStatRow("Hints", formatInt(hints), Color3.fromRGB(220, 238, 255))
		addStatRow("Rank", tostring(rank.name or "Bronze 1"), Color3.fromRGB(255, 214, 121))
		addStatRow("Rank Points", formatInt(rank.points or 0))
		addStatRow("Rank Progress", tostring(rank.progressPercent or 0) .. "%")
		addStatRow("Coin Multiplier", string.format("%.2fx", tonumber(rank.coinMultiplier) or 1), Color3.fromRGB(140, 255, 180))
		addStatRow("Levels Solved", formatInt(solved))
		addStatRow("Best Streak", formatInt(stats.highestStreak or 0))
		addStatRow("Current Streak", formatInt(stats.currentStreak or 0))
		addStatRow("Best Freeplay Streak", formatInt(stats.highestFreeplayStreak or 0))
		addStatRow("Total Words Found", formatInt(stats.totalWordsFound or 0))
		addStatRow("Total Bonus Words", formatInt(stats.totalBonusWords or 0))
		addStatRow("Perfect Levels", formatInt(stats.perfectLevels or 0))
		addStatRow("Daily Streak", formatInt(stats.dailyStreak or 0))
		addStatRow("1v1 Wins", formatInt(stats.pvpWins or 0))
		addStatRow("1v1 Losses", formatInt(stats.pvpLosses or 0))
		addStatRow("1v1 Draws", formatInt(stats.pvpDraws or 0))
		addStatRow("1v1 Best Streak", formatInt(stats.pvpBestStreak or 0))
		addStatRow("Hints Used", formatInt(stats.totalHintsUsed or 0))
		addStatRow("Coins Earned", formatInt(stats.totalCoinsEarned or 0))
		addStatRow("Coins Spent", formatInt(stats.totalCoinsSpent or 0))
	end)

	popInPanel(panel, UDim2.fromOffset(W, H), UDim2.new(0.5, -W / 2, 0.5, -H / 2))
end

function UIManager:ShowAchievements()
	local overlay = makeOverlay(70)
	local W, H = 460, 520
	local panel = makeFrame("AchievementsPanel", overlay, {
		bg = Color3.fromRGB(16, 22, 36),
		size = UDim2.fromOffset(W, H),
		pos = UDim2.new(0.5, -W / 2, 0.5, -H / 2),
	})
	panel.ZIndex = 71
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = panel

	local title = makeLabel("Achievements", panel, {
		size = 24,
		sz = UDim2.new(1, -100, 0, 42),
		pos = UDim2.fromOffset(14, 10),
		xAlign = Enum.TextXAlignment.Left,
		color = Color3.fromRGB(243, 248, 255),
	})
	title.ZIndex = 72

	local summary = makeLabel("Loading...", panel, {
		size = 13,
		sz = UDim2.new(1, -24, 0, 18),
		pos = UDim2.fromOffset(12, 46),
		xAlign = Enum.TextXAlignment.Left,
		color = Color3.fromRGB(160, 184, 223),
	})
	summary.ZIndex = 72

	local close = makeButton("Close", panel, {
		sz = UDim2.fromOffset(86, 30),
		pos = UDim2.new(1, -98, 0, 14),
		bg = Color3.fromRGB(64, 78, 118),
		color = Color3.fromRGB(232, 240, 255),
		size = 14,
		radius = 9,
	})
	close.ZIndex = 72
	close.MouseButton1Click:Connect(function()
		overlay:Destroy()
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -24, 1, -76)
	scroll.Position = UDim2.fromOffset(12, 66)
	scroll.BackgroundColor3 = Color3.fromRGB(11, 18, 31)
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	scroll.ZIndex = 72
	scroll.Parent = panel
	local scrollCorner = Instance.new("UICorner")
	scrollCorner.CornerRadius = UDim.new(0, 10)
	scrollCorner.Parent = scroll

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Size = UDim2.new(1, -12, 0, 0)
	content.Position = UDim2.fromOffset(6, 6)
	content.Parent = scroll
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = content

	task.spawn(function()
		local RemoteRegistry = require(ReplicatedStorage:WaitForChild("Shared").RemoteRegistry)
		local board = RemoteRegistry:GetFunction("GetAchievements"):InvokeServer() or {}
		local items = board.achievements or {}
		summary.Text = string.format("Unlocked %d / %d", tonumber(board.unlocked) or 0, tonumber(board.total) or #items)
		for i, a in ipairs(items) do
			local row = makeFrame("Ach_" .. tostring(i), content, {
				bg = a.unlocked and Color3.fromRGB(30, 62, 42) or Color3.fromRGB(24, 33, 54),
				size = UDim2.new(1, 0, 0, 58),
			})
			row.ZIndex = 73
			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(0, 9)
			rc.Parent = row

			makeLabel((a.unlocked and "[UNLOCKED] " or "[LOCKED] ") .. tostring(a.title or "Achievement"), row, {
				size = 14,
				sz = UDim2.new(1, -16, 0, 24),
				pos = UDim2.fromOffset(8, 4),
				xAlign = Enum.TextXAlignment.Left,
				color = a.unlocked and Color3.fromRGB(159, 248, 186) or Color3.fromRGB(225, 235, 255),
			}).ZIndex = 74

			makeLabel(tostring(a.desc or ""), row, {
				size = 12,
				sz = UDim2.new(1, -16, 0, 16),
				pos = UDim2.fromOffset(8, 26),
				xAlign = Enum.TextXAlignment.Left,
				color = Color3.fromRGB(160, 180, 214),
			}).ZIndex = 74

			local p = tonumber(a.progress) or 0
			local t = math.max(1, tonumber(a.target) or 1)
			makeLabel(string.format("%d / %d", math.min(p, t), t), row, {
				size = 12,
				sz = UDim2.fromOffset(92, 16),
				pos = UDim2.new(1, -100, 1, -20),
				xAlign = Enum.TextXAlignment.Right,
				color = a.unlocked and Color3.fromRGB(159, 248, 186) or Color3.fromRGB(255, 214, 121),
			}).ZIndex = 74
		end
	end)

	popInPanel(panel, UDim2.fromOffset(W, H), UDim2.new(0.5, -W / 2, 0.5, -H / 2))
end

return UIManager
