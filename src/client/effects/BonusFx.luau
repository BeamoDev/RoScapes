local RunService = game:GetService("RunService")

local BonusFx = {}

local COIN_FLY_IMAGE = "rbxassetid://111056627616692"

local state = {
	gameScreen = nil,
	gameButtons = nil,
	gameInGameBar = nil,
	bonusFxOverlay = nil,
}

local function getBonusFxOverlay()
	local gameScreen = state.gameScreen
	if not gameScreen then
		return nil
	end
	if state.bonusFxOverlay and state.bonusFxOverlay.Parent then
		return state.bonusFxOverlay
	end

	local overlay = gameScreen:FindFirstChild("BonusFxOverlay")
	if not overlay then
		overlay = Instance.new("Frame")
		overlay.Name = "BonusFxOverlay"
		overlay.BackgroundTransparency = 1
		overlay.BorderSizePixel = 0
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.Position = UDim2.fromScale(0, 0)
		overlay.ZIndex = 240
		overlay.Active = false
		overlay.Parent = gameScreen
	end

	state.bonusFxOverlay = overlay
	return overlay
end

local function getGuiCenter(gui)
	if not (gui and gui:IsA("GuiObject")) then
		return nil
	end
	return gui.AbsolutePosition + (gui.AbsoluteSize * 0.5)
end

local function getBonusCoinStartPosition()
	local gameScreen = state.gameScreen
	local gameInGameBar = state.gameInGameBar
	local inputBar = (gameScreen and gameScreen:FindFirstChild("InputBar", true))
		or (gameInGameBar and gameInGameBar:FindFirstChild("InputBar", true))
		or (gameScreen and gameScreen:FindFirstChild("InGameBar", true) and gameScreen:FindFirstChild("InGameBar", true):FindFirstChild("InputBar", true))
	local inputBarBg = inputBar and inputBar:FindFirstChild("Background")
	return getGuiCenter((inputBarBg and inputBarBg:IsA("GuiObject")) and inputBarBg or inputBar)
end

local function getCurrencyFlyTarget()
	local gameButtons = state.gameButtons
	local gameScreen = state.gameScreen
	local gameCurrency = (gameButtons and gameButtons:FindFirstChild("Currency")) or (gameScreen and gameScreen:FindFirstChild("Currency"))
	if not (gameCurrency and gameCurrency:IsA("GuiObject")) then
		return nil
	end
	local image = gameCurrency:FindFirstChildWhichIsA("ImageLabel", true) or gameCurrency:FindFirstChildWhichIsA("ImageButton", true)
	if image and image:IsA("GuiObject") then
		return image
	end
	return gameCurrency
end

local function getBonusWordsButtonTarget()
	local gameButtons = state.gameButtons
	local gameScreen = state.gameScreen
	return (gameButtons and (gameButtons:FindFirstChild("Star") or gameButtons:FindFirstChild("STAR")))
		or (gameScreen and gameScreen:FindFirstChild("Star", true))
		or (gameScreen and gameScreen:FindFirstChild("STAR", true))
end

local function quadraticBezier(p0, p1, p2, t)
	local inv = 1 - t
	return (p0 * (inv * inv)) + (p1 * (2 * inv * t)) + (p2 * (t * t))
end

local function easeInOutSine(alpha)
	return 0.5 - (math.cos(math.pi * math.clamp(alpha, 0, 1)) * 0.5)
end

local function addArrivalBounce(point, startPoint, endPoint, alpha)
	if alpha < 0.82 then
		return point
	end
	local dir = endPoint - startPoint
	local mag = dir.Magnitude
	if mag <= 0.001 then
		return point
	end
	local normal = Vector2.new(-dir.Y / mag, dir.X / mag)
	local phase = (alpha - 0.82) / 0.18
	local bounce = math.sin(phase * math.pi) * (1 - phase) * 10
	return point + (normal * bounce)
end

local function toOverlayPoint(overlay, absolutePoint)
	if not overlay or not absolutePoint then
		return nil
	end
	return absolutePoint - overlay.AbsolutePosition
end

function BonusFx.Init(options)
	state.gameScreen = options.gameScreen
	state.gameButtons = options.gameButtons
	state.gameInGameBar = options.gameInGameBar
end

function BonusFx.PlayCoins(count)
	local overlay = getBonusFxOverlay()
	if not overlay then
		return
	end

	local startPos = toOverlayPoint(overlay, getBonusCoinStartPosition())
	local targetGui = getCurrencyFlyTarget()
	local endPos = toOverlayPoint(overlay, getGuiCenter(targetGui))
	if not (startPos and endPos) then
		return
	end

	local tokenCount = math.clamp(tonumber(count) or 6, 5, 8)
	for i = 1, tokenCount do
		task.delay((i - 1) * 0.045, function()
			if not overlay or not overlay.Parent then
				return
			end

			local coin = Instance.new("ImageLabel")
			coin.Name = "BonusCoinFly"
			coin.AnchorPoint = Vector2.new(0.5, 0.5)
			coin.BackgroundTransparency = 1
			coin.Image = COIN_FLY_IMAGE
			coin.ImageTransparency = 0
			coin.ZIndex = 241
			coin.Size = UDim2.fromOffset(30, 30)
			coin.Position = UDim2.fromOffset(startPos.X, startPos.Y)
			coin.Parent = overlay

			local start = startPos + Vector2.new(math.random(-14, 14), math.random(-10, 10))
			local finish = endPos + Vector2.new(math.random(-5, 5), math.random(-5, 5))
			local midpoint = (start + finish) * 0.5
			local control = midpoint + Vector2.new(math.random(-18, 18), -math.max(70, math.abs(finish.Y - start.Y) * 0.35) - math.random(12, 26))
			local duration = 1.8
			local startTick = os.clock()

			task.spawn(function()
				while coin.Parent do
					local alpha = math.clamp((os.clock() - startTick) / duration, 0, 1)
					local eased = easeInOutSine(alpha)
					local point = quadraticBezier(start, control, finish, eased)
					point = addArrivalBounce(point, start, finish, alpha)
					local size = 30 - (10 * eased)
					coin.Position = UDim2.fromOffset(point.X, point.Y)
					coin.Size = UDim2.fromOffset(size, size)
					coin.ImageTransparency = 0.9 * math.max(0, alpha - 0.68) / 0.32
					coin.Rotation = eased * 180
					if alpha >= 1 then
						break
					end
					RunService.RenderStepped:Wait()
				end
				if coin and coin.Parent then
					coin:Destroy()
				end
			end)
		end)
	end
end

function BonusFx.PlayWord(word)
	local overlay = getBonusFxOverlay()
	if not overlay then
		return
	end

	local startPos = toOverlayPoint(overlay, getBonusCoinStartPosition())
	local targetGui = getBonusWordsButtonTarget()
	local endPos = toOverlayPoint(overlay, getGuiCenter(targetGui))
	if not (startPos and endPos) then
		return
	end

	local letters = tostring(word or ""):upper()
	if letters == "" then
		return
	end

	for i = 1, #letters do
		local ch = letters:sub(i, i)
		task.delay((i - 1) * 0.04, function()
			if not overlay or not overlay.Parent then
				return
			end

			local token = Instance.new("TextLabel")
			token.Name = "BonusLetterFly"
			token.AnchorPoint = Vector2.new(0.5, 0.5)
			token.BackgroundTransparency = 1
			token.Text = ch
			token.Font = Enum.Font.GothamBlack
			token.TextScaled = true
			token.TextColor3 = Color3.fromRGB(255, 255, 255)
			token.TextStrokeTransparency = 1
			token.ZIndex = 241
			token.Size = UDim2.fromOffset(26, 26)
			token.Position = UDim2.fromOffset(startPos.X, startPos.Y)
			token.Parent = overlay

			local start = startPos + Vector2.new(math.random(-10, 10), math.random(-8, 8))
			local finish = endPos + Vector2.new(math.random(-12, 12), math.random(-10, 10))
			local midpoint = (start + finish) * 0.5
			local control = midpoint + Vector2.new(math.random(-24, 24), -math.max(55, math.abs(finish.Y - start.Y) * 0.28) - math.random(8, 18))
			local duration = 1.65
			local startTick = os.clock()

			task.spawn(function()
				while token.Parent do
					local alpha = math.clamp((os.clock() - startTick) / duration, 0, 1)
					local eased = easeInOutSine(alpha)
					local point = quadraticBezier(start, control, finish, eased)
					point = addArrivalBounce(point, start, finish, alpha)
					local size = 26 - (6 * eased)
					token.Position = UDim2.fromOffset(point.X, point.Y)
					token.Size = UDim2.fromOffset(size, size)
					token.TextTransparency = 0.9 * math.max(0, alpha - 0.7) / 0.3
					token.Rotation = math.sin(alpha * math.pi) * 10
					if alpha >= 1 then
						break
					end
					RunService.RenderStepped:Wait()
				end
				if token and token.Parent then
					token:Destroy()
				end
			end)
		end)
	end
end

return BonusFx
