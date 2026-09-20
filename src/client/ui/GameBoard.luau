-- GameBoard.luau
-- Renders crossword grid with Wordscapes-style animations

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GameBoard = {}

local RemoteRegistry = require(ReplicatedStorage:WaitForChild("Shared").RemoteRegistry)
local UIEffects = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("util"):WaitForChild("UIEffects"))
local InputState = require(script.Parent.Parent.core.InputState)
local ClientBridge = require(script.Parent.Parent.core.ClientBridge)

local uiMgr = nil
local hud = nil
local gridFrame = nil
local oppGridFrame = nil

-- Current level state
local levelData = nil
local currentPackId = nil
local currentLevelId = nil
local oppCellMap = {}
local cellMap = {} -- [row][col] stores frame, label, letter, found state, and word positions
local animatingCells = {} -- Cells currently being animated
local hintPending = false
local levelColor = Color3.fromRGB(255, 210, 45) -- Default yellow
local LETTER_STAGGER = 0.095
local LETTER_FLY_DURATION = 0.624
local FILL_SWEEP_DURATION = 0.18
local COMPLETION_PULSE_SPEED_SCALE = 1.75
local TILE_CORNER_RADIUS = UDim.new(0.14, 0)
local lastWordAnimCompleteAt = 0
local PRE_FALL_DELAY = 1
local POST_FALL_DELAY = 1
local ARROW_COST_COINS = 125
local PVP_ARROW_COST_COINS = 100
local selectionHintArmed = false
local arrowPending = false
local controllerArrowRow = nil
local controllerArrowCol = nil
local controllerMoveCooldownUntil = 0
local controllerGamepadActive = false
local THUMBSTICK_DEADZONE = 0.6
local CONTROLLER_MOVE_COOLDOWN = 0.16
local inputBarShakeTween = nil
local inputBarShakeToken = 0
local inputBarBasePos = nil
local tutorialPulseToken = 0
local quickRiseAfterLoad = false
local NORMAL_GRID_POS = UDim2.new(0.5, 0, 0.368, 0)
local NORMAL_GRID_SIZE = UDim2.new(0.904, 0, 0.542, 0)
local PVP_GRID_POS = UDim2.new(0.353, 0, 0.372, 0)
local PVP_GRID_SIZE = UDim2.new(0.706, 0, 0.423, 0)
local DESKTOP_OPP_GRID_POS = UDim2.new(1.45, 0, 0.5, 0)
local DESKTOP_OPP_GRID_SIZE = UDim2.new(0.55, 0, 0.55, 0)
local DESKTOP_OPPONENT_LABEL_POS = UDim2.new(1.45, 0, 0.293, 0)
local DESKTOP_OPPONENT_LABEL_SIZE = UDim2.new(0.547, 0, 0.047, 0)
local getLetterFromWordSlots
local completionSequenceToken = 0

local function isTouchOnlyMobile()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled
end

local function isGamepadInputType(inputType)
	return inputType == Enum.UserInputType.Gamepad1
		or inputType == Enum.UserInputType.Gamepad2
		or inputType == Enum.UserInputType.Gamepad3
		or inputType == Enum.UserInputType.Gamepad4
		or inputType == Enum.UserInputType.Gamepad5
		or inputType == Enum.UserInputType.Gamepad6
		or inputType == Enum.UserInputType.Gamepad7
		or inputType == Enum.UserInputType.Gamepad8
end

local function getControllerArrowCell(row, col)
	local cell = row ~= nil and col ~= nil and cellMap[row] and cellMap[row][col]
	if not cell or cell.found or cell.hinted or not cell.frame or not cell.frame.Parent then
		return nil
	end
	return cell
end

local function clearControllerArrowFocusVisual()
	for _, rowMap in pairs(cellMap) do
		for _, cell in pairs(rowMap) do
			local frame = cell and cell.frame
			if frame then
				local stroke = frame:FindFirstChild("ControllerArrowStroke")
				if stroke and stroke:IsA("UIStroke") then
					stroke.Enabled = false
				end
				local scale = frame:FindFirstChild("ControllerArrowScale")
				if scale and scale:IsA("UIScale") then
					scale.Scale = 1
				end
			end
		end
	end
end

local function resolveInitialControllerArrowTarget()
	for _, slot in ipairs(levelData and levelData.wordSlots or {}) do
		local word = tostring(slot.word or "")
		local baseRow = tonumber(slot.row) or 0
		local baseCol = tonumber(slot.col) or 0
		local dir = tostring(slot.dir or "H")
		for i = 1, #word do
			local row = (dir == "V") and (baseRow + (i - 1)) or baseRow
			local col = (dir == "H") and (baseCol + (i - 1)) or baseCol
			if getControllerArrowCell(row, col) then
				return row, col
			end
		end
	end
	return nil, nil
end

local function refreshControllerArrowFocus()
	clearControllerArrowFocusVisual()
	if not selectionHintArmed or not controllerGamepadActive then
		return
	end
	local cell = getControllerArrowCell(controllerArrowRow, controllerArrowCol)
	if not cell then
		controllerArrowRow, controllerArrowCol = resolveInitialControllerArrowTarget()
		cell = getControllerArrowCell(controllerArrowRow, controllerArrowCol)
	end
	if not cell then
		return
	end
	local stroke = cell.frame:FindFirstChild("ControllerArrowStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = "ControllerArrowStroke"
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 3
		stroke.Transparency = 0.1
		stroke.Parent = cell.frame
	end
	stroke.Enabled = true
	local scale = cell.frame:FindFirstChild("ControllerArrowScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "ControllerArrowScale"
		scale.Parent = cell.frame
	end
	scale.Scale = 1.08
end

local function findControllerArrowNeighbor(direction)
	local current = getControllerArrowCell(controllerArrowRow, controllerArrowCol)
	if not current then
		local row, col = resolveInitialControllerArrowTarget()
		return row, col
	end
	local currentCenter = current.frame.AbsolutePosition + (current.frame.AbsoluteSize * 0.5)
	local bestCell = nil
	local bestScore = -math.huge
	for row, rowMap in pairs(cellMap) do
		for col, cell in pairs(rowMap) do
			if cell ~= current and not cell.found and not cell.hinted and cell.frame then
				local targetCenter = cell.frame.AbsolutePosition + (cell.frame.AbsoluteSize * 0.5)
				local delta = targetCenter - currentCenter
				local distance = delta.Magnitude
				if distance > 0 then
					local unit = delta.Unit
					local alignment = unit:Dot(direction)
					local score = (alignment * 10) - (distance * 0.01)
					if alignment > 0.15 and score > bestScore then
						bestScore = score
						bestCell = cell
					end
				end
			end
		end
	end
	if bestCell then
		return bestCell.row, bestCell.col
	end
	return controllerArrowRow, controllerArrowCol
end

local function moveControllerArrowFocus(direction)
	if not selectionHintArmed or not InputState:IsEnabled() then
		return
	end
	controllerArrowRow, controllerArrowCol = findControllerArrowNeighbor(direction)
	refreshControllerArrowFocus()
end

local function handleControllerArrowVector(vec)
	if not selectionHintArmed or not controllerGamepadActive or not InputState:IsEnabled() then
		return
	end
	if tick() < controllerMoveCooldownUntil or vec.Magnitude < THUMBSTICK_DEADZONE then
		return
	end
	controllerMoveCooldownUntil = tick() + CONTROLLER_MOVE_COOLDOWN
	moveControllerArrowFocus(Vector2.new(vec.X, -vec.Y))
end

local function applyGridLayout(isPvP)
	if not gridFrame then
		return
	end
	local gameScreenFrame = hud and (hud:FindFirstChild("Game") or hud:FindFirstChild("GameScreen"))
	local inGameBar = gameScreenFrame and gameScreenFrame:FindFirstChild("InGameBar")
	local opponentLabel = gameScreenFrame and (gameScreenFrame:FindFirstChild("OpponentLabel")
		or (inGameBar and inGameBar:FindFirstChild("OpponentLabel")))
	if gameScreenFrame and gameScreenFrame:IsA("GuiObject") then
		gameScreenFrame.ClipsDescendants = not (isPvP and not isTouchOnlyMobile())
	end
	if isPvP then
		if isTouchOnlyMobile() then
			gridFrame.Position = PVP_GRID_POS
			gridFrame.Size = PVP_GRID_SIZE
		end
	else
		gridFrame.Position = NORMAL_GRID_POS
		gridFrame.Size = NORMAL_GRID_SIZE
	end
	if oppGridFrame then
		oppGridFrame.Visible = isPvP == true
		if isPvP and not isTouchOnlyMobile() then
			oppGridFrame.AnchorPoint = Vector2.new(0.5, 0.5)
			oppGridFrame.Position = DESKTOP_OPP_GRID_POS
			oppGridFrame.Size = DESKTOP_OPP_GRID_SIZE
		end
		local parent = oppGridFrame.Parent
		while parent and parent ~= hud do
			if parent:IsA("GuiObject") then
				parent.Visible = true
			end
			parent = parent.Parent
		end
	end
	if opponentLabel and opponentLabel:IsA("GuiObject") and isPvP and not isTouchOnlyMobile() then
		opponentLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		opponentLabel.Position = DESKTOP_OPPONENT_LABEL_POS
		opponentLabel.Size = DESKTOP_OPPONENT_LABEL_SIZE
	end
end

local function shakeInputBar(inputBar)
	if not inputBar then
		return
	end
	if not inputBarBasePos then
		inputBarBasePos = inputBar.Position
	end
	inputBar.Position = inputBarBasePos
	if inputBarShakeTween then
		inputBarShakeTween:Cancel()
		inputBarShakeTween = nil
	end
	inputBarShakeToken += 1
	local token = inputBarShakeToken

	-- Shake animation
	inputBarShakeTween = TweenService:Create(
		inputBar,
		TweenInfo.new(0.05, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, 4, true),
		{
			Position = inputBarBasePos + UDim2.fromOffset(8, 0),
		}
	)
	inputBarShakeTween:Play()

	task.delay(0.4, function()
		if token ~= inputBarShakeToken then
			return
		end
		if inputBarShakeTween then
			inputBarShakeTween:Cancel()
			inputBarShakeTween = nil
		end
		inputBar.Position = inputBarBasePos
	end)
end

local function animateCellReveal(cell, letter, fillColor, withPop, applyFillNow)
	if not cell or not cell.frame or not cell.label then
		return
	end
	if cell.found then
		return
	end

	cell.found = true
	cell.hinted = false
	cell.label.Text = letter
	cell.label.TextColor3 = Color3.fromRGB(255, 255, 255)
	cell.label.TextTransparency = 0

	local frame = cell.frame
	if applyFillNow ~= false then
		frame.BackgroundColor3 = fillColor
		frame.BackgroundTransparency = 0
	end

	if withPop then
		local baseSize = frame.Size
		local popSize =
			UDim2.fromOffset(math.floor(baseSize.X.Offset * 1.08), math.floor(baseSize.Y.Offset * 1.08))

		frame.Size = UDim2.fromOffset(math.floor(baseSize.X.Offset * 0.86), math.floor(baseSize.Y.Offset * 0.86))

		local popOut =
			TweenService:Create(frame, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = popSize,
			})
		popOut:Play()
		popOut.Completed:Connect(function()
			TweenService:Create(frame, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = baseSize,
			}):Play()
		end)
	end
end

local function playTileFillSweep(cell, fillColor, dir)
	if not cell or not cell.frame then
		return
	end

	local frame = cell.frame
	local existing = frame:FindFirstChild("FillSweep")
	if existing then
		existing:Destroy()
	end
	local existingAccent = frame:FindFirstChild("EffectAccent")
	if existingAccent then
		existingAccent:Destroy()
	end

	local sweep = Instance.new("Frame")
	sweep.Name = "FillSweep"
	sweep.BackgroundColor3 = fillColor
	sweep.BorderSizePixel = 0
	sweep.ZIndex = math.max(frame.ZIndex + 1, 2)
	sweep.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = TILE_CORNER_RADIUS
	corner.Parent = sweep

	local grad = Instance.new("UIGradient")
	grad.Rotation = (dir == "V") and 90 or 0
	local sweepDuration = 0.16
	sweep.BackgroundColor3 = fillColor
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.75, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = sweep

	if dir == "V" then
		sweep.AnchorPoint = Vector2.new(0, 0)
		sweep.Position = UDim2.fromScale(0, 0)
		sweep.Size = UDim2.new(1, 0, 0, 0)
		TweenService:Create(sweep, TweenInfo.new(sweepDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1, 1),
		}):Play()
	else
		sweep.AnchorPoint = Vector2.new(0, 0)
		sweep.Position = UDim2.fromScale(0, 0)
		sweep.Size = UDim2.new(0, 0, 1, 0)
		TweenService:Create(sweep, TweenInfo.new(sweepDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1, 1),
		}):Play()
	end

	task.delay(0.18, function()
		if frame and frame.Parent then
			frame.BackgroundColor3 = fillColor
			frame.BackgroundTransparency = 0
		end
		if sweep and sweep.Parent then
			sweep:Destroy()
		end
	end)
end

local function playHintStrike(cellFrame, strokeColor, durationScale)
	if not cellFrame then
		return
	end
	durationScale = math.max(0.1, tonumber(durationScale) or 1)

	local pulse = Instance.new("Frame")
	pulse.Name = "HintStrike"
	pulse.BackgroundTransparency = 1
	pulse.Size = UDim2.fromScale(1, 1)
	pulse.Position = UDim2.fromScale(0.5, 0.5)
	pulse.AnchorPoint = Vector2.new(0.5, 0.5)
	pulse.ZIndex = math.max(cellFrame.ZIndex + 2, 4)
	pulse.Parent = cellFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = TILE_CORNER_RADIUS
	corner.Parent = pulse

	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor or Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.1
	stroke.Parent = pulse

	local tweenDuration = 0.18 * durationScale
	local growTween = TweenService:Create(pulse, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1.28, 1.28),
	})
	local fadeTween = TweenService:Create(stroke, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Thickness = 5,
	})

	growTween:Play()
	fadeTween:Play()

	task.delay(0.2 * durationScale, function()
		if pulse and pulse.Parent then
			pulse:Destroy()
		end
	end)
end

local function playCompletionGridPulse()
	local cells = {}
	for r, row in pairs(cellMap) do
		for c, cell in pairs(row) do
			if cell and cell.frame and (cell.found or cell.hinted) then
				table.insert(cells, {
					row = r,
					col = c,
					frame = cell.frame,
				})
			end
		end
	end

	table.sort(cells, function(a, b)
		if a.row == b.row then
			return a.col < b.col
		end
		return a.row < b.row
	end)

	for _, item in ipairs(cells) do
		local delayTime = ((item.row * 0.015) + (item.col * 0.006)) * COMPLETION_PULSE_SPEED_SCALE
		task.delay(delayTime, function()
			if item.frame and item.frame.Parent then
				playHintStrike(item.frame, Color3.fromRGB(110, 255, 120), COMPLETION_PULSE_SPEED_SCALE)
			end
		end)
	end
end

local function flyLetterToGrid(letter, fromPos, toCell, levelColor, delayTime, dir)
	task.delay(delayTime, function()
		if not hud or not toCell or not toCell.frame or toCell.found then
			return
		end

		local targetGui = toCell.label or toCell.frame
		local targetCenter = targetGui.AbsolutePosition + (targetGui.AbsoluteSize * 0.5)
		targetCenter = Vector2.new(targetCenter.X, targetCenter.Y + toCell.frame.AbsoluteSize.Y)
		local targetSize = math.max(14, math.floor(math.min(targetGui.AbsoluteSize.X, targetGui.AbsoluteSize.Y)))
		local token = Instance.new("TextLabel")
		token.Text = letter
		token.Font = Enum.Font.GothamBold
		token.TextScaled = true
		token.TextColor3 = Color3.fromRGB(255, 255, 255)
		token.BackgroundTransparency = 1
		token.BorderSizePixel = 0
		token.Size = UDim2.fromOffset(36, 36)
		token.AnchorPoint = Vector2.new(0.5, 0.5)
		token.Position = UDim2.fromOffset(fromPos.X, fromPos.Y)
		token.ZIndex = 100
		token.Parent = hud

		local flyTween = TweenService:Create(token, TweenInfo.new(LETTER_FLY_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(targetCenter.X, targetCenter.Y),
			Size = UDim2.fromOffset(targetSize, targetSize),
		})
		flyTween:Play()
		flyTween.Completed:Connect(function()
			playTileFillSweep(toCell, levelColor, dir)
			animateCellReveal(toCell, letter, levelColor, false, false)
			if token and token.Parent then
				token:Destroy()
			end
		end)
	end)
end


local function clearGrid()
	if gridFrame then
		gridFrame:ClearAllChildren()
	end
	if oppGridFrame then
		oppGridFrame:ClearAllChildren()
	end
	cellMap = {}
	oppCellMap = {}
	animatingCells = {}
	lastWordAnimCompleteAt = 0
	selectionHintArmed = false
	arrowPending = false
	controllerArrowRow = nil
	controllerArrowCol = nil
	clearControllerArrowFocusVisual()
end

local function getGridCoverageScale(data)
	-- Keep tiny boards readable (not oversized), but let larger boards use near-full space.
	local rows = math.max(1, tonumber(data and data.gridRows) or 1)
	local cols = math.max(1, tonumber(data and data.gridCols) or 1)
	local smallSide = math.min(rows, cols)
	local largeSide = math.max(rows, cols)

	if largeSide <= 3 then
		return 0.72
	end
	if largeSide <= 4 then
		return 0.8
	end
	if smallSide <= 3 and largeSide <= 5 then
		return 0.86
	end
	if largeSide <= 6 then
		return 0.92
	end
	return 0.985
end

local function tryUseSelectionHintOnCell(row, col)
	if not selectionHintArmed or arrowPending or not InputState:IsEnabled() then
		return
	end

	local cell = cellMap[row] and cellMap[row][col]
	if not cell or cell.found or cell.hinted then
		uiMgr:ShowAlert("Pick an unrevealed tile", "error")
		return
	end

	arrowPending = true
	local result = RemoteRegistry:GetFunction("UseArrowOnCell"):InvokeServer(row, col)
	arrowPending = false

	if result and result.success then
		selectionHintArmed = false
		controllerArrowRow = nil
		controllerArrowCol = nil
		if result.selectionHints ~= nil then
			ClientBridge.Call("OnSelectionHintsUpdated", result.selectionHints)
		end
		if ClientBridge.Call("TutorialAllowsAction", "arrow") == true then
			ClientBridge.Call("OnTutorialArrowUsed", row, col)
		end
		refreshControllerArrowFocus()
	else
		if result and result.selectionHints ~= nil then
			ClientBridge.Call("OnSelectionHintsUpdated", result.selectionHints)
		end
		if result and result.message == "not enough coins" then
			ClientBridge.Call("OpenShopPanel")
		end
		uiMgr:ShowAlert((result and result.message) or "Arrow failed", "error")
		refreshControllerArrowFocus()
	end
end

local function tryUseSelectionHintAtPoint(point)
	if not selectionHintArmed or not point then
		return false
	end
	for row, rowMap in pairs(cellMap) do
		for col, cell in pairs(rowMap) do
			local frame = cell and cell.frame
			if frame and frame.Visible then
				local topLeft = frame.AbsolutePosition
				local size = frame.AbsoluteSize
				local inside = point.X >= topLeft.X
					and point.X <= topLeft.X + size.X
					and point.Y >= topLeft.Y
					and point.Y <= topLeft.Y + size.Y
				if inside then
					tryUseSelectionHintOnCell(row, col)
					return true
				end
			end
		end
	end
	return false
end

local function getReadyFrameSize(frameObj)
	local size = frameObj and frameObj.AbsoluteSize or Vector2.new(0, 0)
	local tries = 0
	while (size.X < 16 or size.Y < 16) and tries < 8 do
		tries += 1
		task.wait()
		size = frameObj and frameObj.AbsoluteSize or Vector2.new(0, 0)
	end
	return size
end

getLetterFromWordSlots = function(data, row, col)
	local targetRow = tonumber(row) or row
	local targetCol = tonumber(col) or col
	for _, slot in ipairs(data and data.wordSlots or {}) do
		local word = tostring(slot.word or "")
		local baseRow = tonumber(slot.row) or 0
		local baseCol = tonumber(slot.col) or 0
		local dir = tostring(slot.dir or "H")
		for i = 1, #word do
			local rr = (dir == "V") and (baseRow + (i - 1)) or baseRow
			local cc = (dir == "H") and (baseCol + (i - 1)) or baseCol
			if rr == targetRow and cc == targetCol then
				return word:sub(i, i)
			end
		end
	end
	return ""
end

local function getGridCellMetrics(data, frameObj)
	local rows = math.max(1, tonumber(data and data.gridRows) or 1)
	local cols = math.max(1, tonumber(data and data.gridCols) or 1)
	local frameSize = getReadyFrameSize(frameObj)
	local coverageScale = getGridCoverageScale(data)
	local usableWidth = frameSize.X * coverageScale
	local usableHeight = frameSize.Y * coverageScale
	local padding = 3
	local maxCellW = (usableWidth - (cols - 1) * padding) / cols
	local maxCellH = (usableHeight - (rows - 1) * padding) / rows
	local cellSize = math.max(1, math.min(maxCellW, maxCellH))
	local totalW = cols * cellSize + (cols - 1) * padding
	local totalH = rows * cellSize + (rows - 1) * padding
	local startX = (frameSize.X - totalW) / 2
	local startY = (frameSize.Y - totalH) / 2

	return {
		rows = rows,
		cols = cols,
		padding = padding,
		cellSize = cellSize,
		startX = startX,
		startY = startY,
	}
end

local function buildGrid(data)
	clearGrid()
	levelData = data

	-- Get level color from data
	levelColor = data.levelColor or Color3.fromRGB(255, 210, 45)

	local C = uiMgr.Colors
	local layout = getGridCellMetrics(data, gridFrame)
	local rows = layout.rows
	local cols = layout.cols
	local padding = layout.padding
	local cellSize = layout.cellSize
	local startX = layout.startX
	local startY = layout.startY

	-- Build cell lookup
	local occupiedMap = {}
	for r = 0, rows - 1 do
		occupiedMap[r] = {}
	end

	for _, cell in ipairs(data.occupiedCells or {}) do
		local row = tonumber(cell.row) or 0
		local col = tonumber(cell.col) or 0
		if occupiedMap[row] then
			occupiedMap[row][col] = true
		end
	end

	-- Instantiate cells
	for r = 0, rows - 1 do
		cellMap[r] = {}
		for c = 0, cols - 1 do
			local isWord = occupiedMap[r] and occupiedMap[r][c] == true

			local f = Instance.new(isWord and "TextButton" or "Frame")
			f.Name = ("Cell_%d_%d"):format(r, c)
			f.Size = UDim2.fromOffset(cellSize, cellSize)
			f.Position = UDim2.fromOffset(startX + c * (cellSize + padding), startY + r * (cellSize + padding))
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			-- Adjust position for anchor point
			f.Position = UDim2.fromOffset(
				startX + c * (cellSize + padding) + cellSize / 2,
				startY + r * (cellSize + padding) + cellSize / 2
			)
			f.BackgroundColor3 = C.cell
			f.BorderSizePixel = 0
			f.BackgroundTransparency = isWord and 0.1 or 1
			if f:IsA("TextButton") then
				f.Text = ""
				f.AutoButtonColor = false
				f.Selectable = true
			end
			f.Parent = gridFrame

			local corner = Instance.new("UICorner")
			corner.CornerRadius = TILE_CORNER_RADIUS
			corner.Parent = f

			local lbl = Instance.new("TextLabel")
			lbl.Text = isWord and "" or ""
			lbl.Font = Enum.Font.GothamBold
			lbl.TextScaled = true
			lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			lbl.BackgroundTransparency = 1
			lbl.Active = false
			lbl.ZIndex = 3
			lbl.Size = UDim2.fromScale(0.7, 0.7)
			lbl.AnchorPoint = Vector2.new(0.5, 0.5)
			lbl.Position = UDim2.fromScale(0.5, 0.5)
			lbl.TextXAlignment = Enum.TextXAlignment.Center
			lbl.TextYAlignment = Enum.TextYAlignment.Center
			lbl.Parent = f

			if isWord then
				local rr, cc = r, c
				f.Active = true
				local lastArrowClickAt = 0
				local function handleSelectionPress()
					local now = tick()
					if now - lastArrowClickAt < 0.08 then
						return
					end
					lastArrowClickAt = now
					tryUseSelectionHintOnCell(rr, cc)
				end

				if f:IsA("GuiButton") then
					f.MouseButton1Down:Connect(function()
						handleSelectionPress()
					end)
					f.TouchTap:Connect(function()
						handleSelectionPress()
					end)
					f.SelectionGained:Connect(function()
						controllerArrowRow = rr
						controllerArrowCol = cc
						refreshControllerArrowFocus()
					end)
					f.Activated:Connect(function()
						if not selectionHintArmed then
							return
						end
						controllerArrowRow = rr
						controllerArrowCol = cc
						tryUseSelectionHintOnCell(rr, cc)
					end)
				else
					f.InputBegan:Connect(function(input)
						if input.UserInputType ~= Enum.UserInputType.MouseButton1
							and input.UserInputType ~= Enum.UserInputType.Touch then
							return
						end
						handleSelectionPress()
					end)
				end

				cellMap[r][c] = {
					frame = f,
					label = lbl,
					letter = "",
					found = false,
					hinted = false,
					row = r,
					col = c,
				}
			end
		end
	end
end

local function buildOppGrid(data)
	if not oppGridFrame then
		return
	end

	oppGridFrame:ClearAllChildren()
	oppCellMap = {}

	local layout = getGridCellMetrics(data, oppGridFrame)
	local rows = layout.rows
	local cols = layout.cols
	local padding = layout.padding
	local cellSize = layout.cellSize
	local startX = layout.startX
	local startY = layout.startY

	local usedCells = {}
	for r = 0, rows - 1 do
		usedCells[r] = {}
	end
	for _, pos in ipairs(data.wordSlots or {}) do
		local length = tonumber(pos.length) or 0
		for i = 1, length do
			local r, c
			if pos.dir == "H" then
				r = pos.row
				c = pos.col + (i - 1)
			else
				r = pos.row + (i - 1)
				c = pos.col
			end
			usedCells[r][c] = true
		end
	end

	for r = 0, rows - 1 do
		oppCellMap[r] = {}
		for c = 0, cols - 1 do
			if usedCells[r] and usedCells[r][c] then
				local f = Instance.new("Frame")
				f.Name = ("OppCell_%d_%d"):format(r, c)
				f.Size = UDim2.fromOffset(cellSize, cellSize)
				f.Position = UDim2.fromOffset(
					startX + c * (cellSize + padding) + cellSize / 2,
					startY + r * (cellSize + padding) + cellSize / 2
				)
				f.AnchorPoint = Vector2.new(0.5, 0.5)
				f.BackgroundColor3 = Color3.fromRGB(80, 95, 125)
				f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				f.BackgroundTransparency = 0.08
				f.BorderSizePixel = 0
				f.Parent = oppGridFrame

				local corner = Instance.new("UICorner")
				corner.CornerRadius = TILE_CORNER_RADIUS
				corner.Parent = f

				local stroke = Instance.new("UIStroke")
				stroke.Color = Color3.fromRGB(210, 210, 210)
				stroke.Thickness = 1
				stroke.Transparency = 0.15
				stroke.Parent = f

				oppCellMap[r][c] = {
					frame = f,
					revealed = false,
				}
			end
		end
	end
end


function GameBoard:AnimateWordSubmission(word, revealedCells, isValid, wheelCenterPos)
	if not levelData then
		return
	end

	local activeGame = hud:FindFirstChild("Game") or hud:FindFirstChild("GameScreen")
	local inputBar = (activeGame and activeGame:FindFirstChild("InputBar"))
		or (activeGame and activeGame:FindFirstChild("InGameBar") and activeGame.InGameBar:FindFirstChild("InputBar"))
	local inputBarBg = inputBar and inputBar:FindFirstChild("Background")

	if not isValid then
		-- Shake animation for invalid word
		shakeInputBar(inputBar)
		return
	end

	-- Find cells for this word
	local targetCells = {}
	for _, reveal in ipairs(revealedCells or {}) do
		local cell = cellMap[reveal.row] and cellMap[reveal.row][reveal.col]
		if cell and not cell.found then
			table.insert(targetCells, {
				cell = cell,
				letter = tostring(reveal.letter or ""),
				index = tonumber(reveal.index) or (#targetCells + 1),
				dir = tostring(reveal.dir or "H"),
			})
		end
	end

	-- Animate letters flying from wheel to grid
	if #targetCells > 0 then
		-- Change InputBar to level color temporarily
		if inputBarBg then
			TweenService:Create(inputBarBg, TweenInfo.new(0.2), {
				BackgroundColor3 = levelColor,
			}):Play()
		end

		-- Fly each letter
		local center = wheelCenterPos
		if not center then
			local hudPos = hud.AbsolutePosition
			local hudSize = hud.AbsoluteSize
			center = Vector2.new(hudPos.X + (hudSize.X * 0.5), hudPos.Y + (hudSize.Y * 0.75))
		end

		local count = #targetCells
		for i, data in ipairs(targetCells) do
			local offsetX = (i - ((count + 1) * 0.5)) * 14
			local offsetY = -math.abs(offsetX) * 0.12
			flyLetterToGrid(
				data.letter,
				Vector2.new(center.X + offsetX, center.Y + offsetY),
				data.cell,
				levelColor,
				(i - 1) * LETTER_STAGGER,
				data.dir
			)
		end

		local fullWordAnimTime = ((#targetCells - 1) * LETTER_STAGGER) + LETTER_FLY_DURATION + FILL_SWEEP_DURATION
		lastWordAnimCompleteAt = math.max(lastWordAnimCompleteAt, tick() + fullWordAnimTime)

		-- Reset InputBar color after animation
		task.delay(#targetCells * LETTER_STAGGER + 0.44, function()
			if inputBarBg then
				TweenService:Create(inputBarBg, TweenInfo.new(0.2), {
					BackgroundColor3 = levelColor,
				}):Play()
			end
		end)
	end
end


function GameBoard:Init(manager, hudScreen)
	uiMgr = manager
	hud = hudScreen
	controllerGamepadActive = isGamepadInputType(UserInputService:GetLastInputType())
	local gameScreen = hud:FindFirstChild("Game") or hud:WaitForChild("GameScreen")
	local content = gameScreen:WaitForChild("Content")
	gridFrame = content:WaitForChild("GridFrame")
	oppGridFrame = content:FindFirstChild("OppGrid")
	gridFrame.Active = true
	gridFrame.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local pos = input.Position
		local point = typeof(pos) == "Vector3" and Vector2.new(pos.X, pos.Y) or pos
		tryUseSelectionHintAtPoint(point)
	end)
	UserInputService.InputChanged:Connect(function(input)
		if isGamepadInputType(input.UserInputType) and input.KeyCode == Enum.KeyCode.Thumbstick1 then
			handleControllerArrowVector(input.Position)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not isGamepadInputType(input.UserInputType) then
			return
		end
		controllerGamepadActive = true
		refreshControllerArrowFocus()
		if not selectionHintArmed or not InputState:IsEnabled() then
			return
		end
		if input.KeyCode == Enum.KeyCode.DPadLeft then
			moveControllerArrowFocus(Vector2.new(-1, 0))
		elseif input.KeyCode == Enum.KeyCode.DPadRight then
			moveControllerArrowFocus(Vector2.new(1, 0))
		elseif input.KeyCode == Enum.KeyCode.DPadUp then
			moveControllerArrowFocus(Vector2.new(0, -1))
		elseif input.KeyCode == Enum.KeyCode.DPadDown then
			moveControllerArrowFocus(Vector2.new(0, 1))
		elseif input.KeyCode == Enum.KeyCode.ButtonA then
			if controllerArrowRow ~= nil and controllerArrowCol ~= nil then
				tryUseSelectionHintOnCell(controllerArrowRow, controllerArrowCol)
			end
		elseif input.KeyCode == Enum.KeyCode.ButtonB then
			selectionHintArmed = false
			controllerArrowRow = nil
			controllerArrowCol = nil
			refreshControllerArrowFocus()
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		controllerGamepadActive = isGamepadInputType(inputType)
		refreshControllerArrowFocus()
	end)
	ClientBridge.SetCallback("IsArrowSelectionActive", function()
		return selectionHintArmed == true
	end)
ClientBridge.SetCallback("CancelArrowSelection", function()
	selectionHintArmed = false
	controllerArrowRow = nil
	controllerArrowCol = nil
	refreshControllerArrowFocus()
	return true
end)
	ClientBridge.SetCallback("MoveArrowSelection", function(dx, dy)
		local dir = Vector2.new(tonumber(dx) or 0, tonumber(dy) or 0)
		if dir.Magnitude <= 0 then
			return false
		end
		moveControllerArrowFocus(dir)
		return true
	end)
	ClientBridge.SetCallback("ConfirmArrowSelection", function()
		if controllerArrowRow == nil or controllerArrowCol == nil then
			return false
		end
		tryUseSelectionHintOnCell(controllerArrowRow, controllerArrowCol)
		return true
	end)
	applyGridLayout(false)
end


local playGridRise
local playQuickGridRise

function GameBoard:LoadLevel(data, options)
	levelData = data
	currentPackId = data.packId
	currentLevelId = data.levelId
	levelColor = data.levelColor or Color3.fromRGB(255, 210, 45)
	options = options or {}

	-- Update level label
	local gameScreenFrame = hud:FindFirstChild("Game") or hud:FindFirstChild("GameScreen")
	if gameScreenFrame then
		local inGameBar = gameScreenFrame:FindFirstChild("InGameBar")
		local levelLabel = gameScreenFrame:FindFirstChild("LevelLabel")
			or (inGameBar and inGameBar:FindFirstChild("LevelLabel"))
		local opponentLabel = gameScreenFrame:FindFirstChild("OpponentLabel")
			or (inGameBar and inGameBar:FindFirstChild("OpponentLabel"))
		if levelLabel then
			if options.isPvP == true then
				levelLabel.Text = "1v1"
			elseif tonumber(data.packId) == 0 then
				levelLabel.Text = "DAILY"
			elseif tonumber(data.packId) == -1 then
				levelLabel.Text = "FREEPLAY"
			else
				levelLabel.Text = "LEVEL " .. tostring(tonumber(data.globalLevelId) or tonumber(data.levelId) or 1)
			end
			levelLabel.Visible = true
		end
		if opponentLabel and opponentLabel:IsA("GuiObject") then
			if options.isPvP == true then
				local opponentName = tostring(options.opponentName or "Opponent")
				if opponentLabel:IsA("TextLabel") or opponentLabel:IsA("TextButton") then
					if isTouchOnlyMobile() then
						opponentLabel.Text = opponentName
					else
						opponentLabel.Text = opponentName .. "'s Board"
					end
				end
				opponentLabel.Visible = true
			else
				opponentLabel.Visible = false
			end
		end
	end

	applyGridLayout(options.isPvP == true)
	buildGrid(data)
	refreshControllerArrowFocus()
	if quickRiseAfterLoad then
		quickRiseAfterLoad = false
		playQuickGridRise(self._quickRiseSpeedScale)
		self._quickRiseSpeedScale = nil
	else
		playGridRise()
	end
	if oppGridFrame then
		if options.isPvP then
			oppGridFrame.Visible = true
			buildOppGrid(data)
		else
			oppGridFrame.Visible = false
		end
	end
end

function GameBoard:AnimateOpponentWordProgress(info)
	if not oppGridFrame or not oppGridFrame.Visible then
		return
	end

	local row = tonumber(info.row)
	local col = tonumber(info.col)
	local len = tonumber(info.length)
	local dir = tostring(info.dir or "H")
	if not row or not col or not len then
		return
	end

	for i = 0, len - 1 do
		local r = (dir == "V") and (row + i) or row
		local c = (dir == "H") and (col + i) or col
		local cell = oppCellMap[r] and oppCellMap[r][c]
		if cell and cell.frame and not cell.revealed then
			cell.revealed = true
			task.delay(i * 0.05, function()
				if not cell.frame or not cell.frame.Parent then
					return
				end
				playTileFillSweep(cell, levelColor, dir)
			end)
		end
	end
end

function GameBoard:OnWordResult(result, wheelCenterPos)
	if not result.valid then
		-- Trigger shake animation
		local gameScreen = hud:FindFirstChild("Game") or hud:FindFirstChild("GameScreen")
		local inGameBar = gameScreen and gameScreen:FindFirstChild("InGameBar")
		local inputBar = (gameScreen and gameScreen:FindFirstChild("InputBar")) or (inGameBar and inGameBar:FindFirstChild("InputBar"))
		shakeInputBar(inputBar)
		return
	end

	-- Animate word submission
	self:AnimateWordSubmission(result.word, result.revealedCells, true, wheelCenterPos)
end

function GameBoard:ApplySavedDailyProgress(progressCells)
	if not levelData or typeof(progressCells) ~= "table" then
		return
	end

	for _, revealed in ipairs(progressCells) do
		local r = tonumber(revealed.row)
		local c = tonumber(revealed.col)
		local letter = tostring(revealed.letter or "")
		local cell = r and c and cellMap[r] and cellMap[r][c]
		if cell and not cell.found then
			animateCellReveal(cell, letter, levelColor, false, true)
		end
	end
end

function GameBoard:ApplySavedHintCells(hintCells)
	if not levelData or typeof(hintCells) ~= "table" then
		return
	end

	for _, hinted in ipairs(hintCells) do
		local r = tonumber(hinted and hinted.row)
		local c = tonumber(hinted and hinted.col)
		local letter = tostring(hinted and hinted.letter or "")
		local cell = r and c and cellMap[r] and cellMap[r][c]
		if cell and not cell.found then
			if letter == "" then
				letter = tostring(getLetterFromWordSlots(levelData, r, c) or "")
			end
			if letter == "" then
				letter = tostring(cell.letter or "")
			end
			if letter ~= "" then
				cell.hinted = true
				cell.letter = letter
				cell.label.Text = letter
				cell.label.TextColor3 = Color3.fromRGB(20, 20, 20)
				cell.label.TextTransparency = 0
				cell.frame.BackgroundTransparency = 0.1
			end
		end
	end
end

function GameBoard:RevealHintCell(info)
	hintPending = false
	local r, c = tonumber(info.row), tonumber(info.col)
	local cell = cellMap[r] and cellMap[r][c]
	if cell and not cell.found then
		cell.hinted = true
		local resolvedLetter = tostring(info.letter or "")
		if resolvedLetter == "" then
			resolvedLetter = tostring(cell.letter or "")
		end
		if resolvedLetter == "" then
			resolvedLetter = tostring(getLetterFromWordSlots(levelData, r, c) or "")
		end
		cell.letter = resolvedLetter
		if cell.letter == "" then
			cell.letter = "?"
		end
		cell.label.Text = cell.letter
		cell.label.TextColor3 = Color3.fromRGB(20, 20, 20)
		cell.label.TextTransparency = 0
		-- Keep tile background unchanged for hint/arrow reveals.
		cell.frame.BackgroundTransparency = 0.1
		UIEffects.PlaySound("NotificationMid")
		playHintStrike(cell.frame)
	end
end

local function playGridFall(onDone)
	if gridFrame then
		local cells = {}
		for r, row in pairs(cellMap) do
			for c, cell in pairs(row) do
				if cell and cell.frame then
					table.insert(cells, {
						row = r,
						col = c,
						frame = cell.frame,
						label = cell.label,
					})
				end
			end
		end

		table.sort(cells, function(a, b)
			if a.row == b.row then
				return a.col < b.col
			end
			return a.row > b.row
		end)

		local maxDelay = 0
		for _, item in ipairs(cells) do
			local cellFrame = item.frame
			local rowDelay = item.row * 0.03
			local colDelay = item.col * 0.005
			local delayTime = rowDelay + colDelay
			if delayTime > maxDelay then
				maxDelay = delayTime
			end

			local drop = 120 + (item.row * 4)
			local currentPos = cellFrame.Position
			local fallTween = TweenService:Create(cellFrame, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(
					currentPos.X.Scale,
					currentPos.X.Offset,
					currentPos.Y.Scale,
					currentPos.Y.Offset + drop
				),
				BackgroundTransparency = 1,
			})
			local labelTween = nil
			if item.label then
				labelTween = TweenService:Create(item.label, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					TextTransparency = 1,
				})
			end

			task.delay(delayTime, function()
				if labelTween then
					labelTween:Play()
				end
				fallTween:Play()
			end)
		end

		local finishDelay = maxDelay + 0.42
		task.delay(finishDelay + POST_FALL_DELAY, function()
			clearGrid()
			if onDone then
				onDone()
			end
		end)
		return
	end

	task.delay(1, function()
		if onDone then
			onDone()
		end
	end)
end

local function makeCompletionDone(onDone)
	local called = false
	return function()
		if called then
			return
		end
		called = true
		if onDone then
			task.spawn(function()
				local ok, err = pcall(onDone)
				if not ok then
					warn("[GameBoard] completion callback failed:", err)
				end
			end)
		end
	end
end

playGridRise = function()
	if not gridFrame then
		return
	end

	local cells = {}
	for r, row in pairs(cellMap) do
		for c, cell in pairs(row) do
			if cell and cell.frame then
				table.insert(cells, {
					row = r,
					col = c,
					frame = cell.frame,
					label = cell.label,
				})
			end
		end
	end

	table.sort(cells, function(a, b)
		if a.row == b.row then
			return a.col < b.col
		end
		return a.row < b.row
	end)

	for _, item in ipairs(cells) do
		local cellFrame = item.frame
		local cellLabel = item.label
		local targetPos = cellFrame.Position
		local targetTransparency = cellFrame.BackgroundTransparency
		local delayTime = (item.row * 0.024) + (item.col * 0.004)
		local rise = 120 + (item.row * 4)

		cellFrame.Position = UDim2.new(
			targetPos.X.Scale,
			targetPos.X.Offset,
			targetPos.Y.Scale,
			targetPos.Y.Offset + rise
		)
		cellFrame.BackgroundTransparency = 1

		if cellLabel then
			cellLabel.TextTransparency = 1
		end

		task.delay(delayTime, function()
			if not cellFrame.Parent then
				return
			end

			TweenService:Create(cellFrame, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = targetPos,
				BackgroundTransparency = targetTransparency,
			}):Play()

			if cellLabel then
				TweenService:Create(cellLabel, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					TextTransparency = 0,
				}):Play()
			end
		end)
	end
end

local function playCompletionSequence(onDone)
	completionSequenceToken += 1
	local token = completionSequenceToken
	local finish = makeCompletionDone(onDone)
	local waitForWordAnimations = math.max(0, lastWordAnimCompleteAt - tick())
	task.delay(waitForWordAnimations, function()
		if token ~= completionSequenceToken then
			return
		end
		playCompletionGridPulse()
	end)
	task.delay(waitForWordAnimations + PRE_FALL_DELAY, function()
		if token ~= completionSequenceToken then
			return
		end
		playGridFall(finish)
	end)
	task.delay(waitForWordAnimations + PRE_FALL_DELAY + POST_FALL_DELAY + 3, function()
		if token ~= completionSequenceToken then
			return
		end
		finish()
	end)
end

local function playQuickGridFall(onDone, speedScale)
	if not gridFrame then
		if onDone then
			onDone()
		end
		return
	end
	speedScale = math.max(0.05, tonumber(speedScale) or 1)

	local cells = {}
	for r, row in pairs(cellMap) do
		for c, cell in pairs(row) do
			if cell and cell.frame then
				table.insert(cells, {
					row = r,
					col = c,
					frame = cell.frame,
					label = cell.label,
				})
			end
		end
	end

	table.sort(cells, function(a, b)
		if a.row == b.row then
			return a.col < b.col
		end
		return a.row < b.row
	end)

	local maxDelay = 0
	for _, item in ipairs(cells) do
		local delayTime = ((item.row * 0.008) + (item.col * 0.0015)) * speedScale
		maxDelay = math.max(maxDelay, delayTime)
		local cellFrame = item.frame
		local currentPos = cellFrame.Position
		local fallTween = TweenService:Create(cellFrame, TweenInfo.new(0.1 * speedScale, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(currentPos.X.Scale, currentPos.X.Offset, currentPos.Y.Scale, currentPos.Y.Offset + 56),
			BackgroundTransparency = 1,
		})
		local labelTween = item.label and TweenService:Create(item.label, TweenInfo.new(0.08 * speedScale, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}) or nil
		task.delay(delayTime, function()
			if labelTween then
				labelTween:Play()
			end
			fallTween:Play()
		end)
	end

	task.delay(maxDelay + (0.12 * speedScale), function()
		clearGrid()
		if onDone then
			onDone()
		end
	end)
end

function playQuickGridRise(speedScale)
	if not gridFrame then
		return
	end
	speedScale = math.max(0.05, tonumber(speedScale) or 1)

	local cells = {}
	for r, row in pairs(cellMap) do
		for c, cell in pairs(row) do
			if cell and cell.frame then
				table.insert(cells, {
					row = r,
					col = c,
					frame = cell.frame,
					label = cell.label,
				})
			end
		end
	end

	table.sort(cells, function(a, b)
		if a.row == b.row then
			return a.col < b.col
		end
		return a.row < b.row
	end)

	for _, item in ipairs(cells) do
		local cellFrame = item.frame
		local cellLabel = item.label
		local targetPos = cellFrame.Position
		local targetTransparency = cellFrame.BackgroundTransparency
		local delayTime = ((item.row * 0.008) + (item.col * 0.0015)) * speedScale

		cellFrame.Position = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, targetPos.Y.Scale, targetPos.Y.Offset + 56)
		cellFrame.BackgroundTransparency = 1
		if cellLabel then
			cellLabel.TextTransparency = 1
		end

		task.delay(delayTime, function()
			if not cellFrame.Parent then
				return
			end
			TweenService:Create(cellFrame, TweenInfo.new(0.1 * speedScale, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = targetPos,
				BackgroundTransparency = targetTransparency,
			}):Play()
			if cellLabel then
				TweenService:Create(cellLabel, TweenInfo.new(0.08 * speedScale, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					TextTransparency = 0,
				}):Play()
			end
		end)
	end
end

function GameBoard:QuickSwapLevel(nextData, options)
	if not nextData then
		return
	end
	options = options or {}
	local speedScale = math.max(0.05, tonumber(options.speedScale) or 1)
	playQuickGridFall(function()
		quickRiseAfterLoad = true
		self._quickRiseSpeedScale = speedScale
		self:LoadLevel(nextData)
	end, speedScale)
end

function GameBoard:OnLevelComplete(info)
	playCompletionSequence(function()
		ClientBridge.SetState("LastLevelCompleteInfo", info)
		ClientBridge.Call("OnLevelComplete", info)
	end)
end

function GameBoard:OnDailyComplete(info, onDone)
	playCompletionSequence(function()
		if onDone then
			onDone(info)
		end
	end)
end

function GameBoard:RequestHint()
	if hintPending or not levelData or not InputState:IsEnabled() then
		return
	end
	hintPending = true
	RemoteRegistry:GetEvent("RequestHint"):FireServer()
	task.delay(0.75, function()
		if hintPending then
			hintPending = false
		end
	end)
end

function GameBoard:BeginArrowMode()
	if not InputState:IsEnabled() or not levelData then
		return
	end
	if ClientBridge.GetState("IsHardcoreMode") then
		uiMgr:ShowAlert("Accuracy disabled in hardcore", "error")
		return
	end
	if arrowPending then
		return
	end
	selectionHintArmed = true
	controllerArrowRow, controllerArrowCol = resolveInitialControllerArrowTarget()
	refreshControllerArrowFocus()
	uiMgr:ShowAlert("Selection hint active: choose a tile", "bonus")
end

function GameBoard:IsHintPending()
	return hintPending
end

function GameBoard:GetFirstHiddenCell()
	for _, slot in ipairs(levelData and levelData.wordSlots or {}) do
		local word = tostring(slot.word or "")
		local baseRow = tonumber(slot.row) or 0
		local baseCol = tonumber(slot.col) or 0
		local dir = tostring(slot.dir or "H")
		for i = 1, #word do
			local row = (dir == "V") and (baseRow + (i - 1)) or baseRow
			local col = (dir == "H") and (baseCol + (i - 1)) or baseCol
			local cell = cellMap[row] and cellMap[row][col]
			if cell and not cell.found then
				return {
					row = row,
					col = col,
					letter = word:sub(i, i),
				}
			end
		end
	end
	return nil
end

function GameBoard:GetPreferredTutorialArrowCell(baseRow, baseCol)
	local sourceRow = tonumber(baseRow)
	local sourceCol = tonumber(baseCol)
	if sourceRow ~= nil and sourceCol ~= nil then
		local rr = sourceRow
		local cc = sourceCol + 1
		local cell = cellMap[rr] and cellMap[rr][cc]
		if cell and not cell.found and not cell.hinted then
			return {
				row = rr,
				col = cc,
				letter = (cell.letter and cell.letter ~= "") and cell.letter or getLetterFromWordSlots(levelData, rr, cc),
			}
		end
	end

	return self:GetFirstHiddenCell()
end

function GameBoard:StopTutorialCellPulse()
	tutorialPulseToken += 1
end

function GameBoard:StartTutorialCellPulse(row, col)
	local r = tonumber(row)
	local c = tonumber(col)
	local cell = r and c and cellMap[r] and cellMap[r][c]
	if not cell or not cell.frame then
		return
	end

	tutorialPulseToken += 1
	local token = tutorialPulseToken
	task.spawn(function()
		while tutorialPulseToken == token do
			local liveCell = cellMap[r] and cellMap[r][c]
			if not liveCell or liveCell.found or liveCell.hinted or not liveCell.frame or not liveCell.frame.Parent then
				break
			end
			playHintStrike(liveCell.frame)
			task.wait(0.52)
		end
	end)
end

function GameBoard:GetCellCenter(row, col)
	local r = tonumber(row)
	local c = tonumber(col)
	local cell = r and c and cellMap[r] and cellMap[r][c]
	if not cell or not cell.frame then
		return nil
	end
	return cell.frame.AbsolutePosition + (cell.frame.AbsoluteSize * 0.5)
end

function GameBoard:GetLevelData()
	return levelData
end

function GameBoard:GetCurrentLevel()
	return currentPackId, currentLevelId
end

function GameBoard:ExitLevel()
	completionSequenceToken += 1
	levelData = nil
	currentPackId = nil
	currentLevelId = nil
	controllerArrowRow = nil
	controllerArrowCol = nil
	clearGrid()
	local gameScreenFrame = hud and (hud:FindFirstChild("Game") or hud:FindFirstChild("GameScreen"))
	if gameScreenFrame then
		gameScreenFrame.ClipsDescendants = true
		local inGameBar = gameScreenFrame:FindFirstChild("InGameBar")
		local opponentLabel = gameScreenFrame:FindFirstChild("OpponentLabel")
			or (inGameBar and inGameBar:FindFirstChild("OpponentLabel"))
		if opponentLabel and opponentLabel:IsA("GuiObject") then
			opponentLabel.Visible = false
		end
	end
	if oppGridFrame then
		oppGridFrame.Visible = false
	end
end

return GameBoard
