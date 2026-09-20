-- LetterWheel.luau
-- Handles the wheel input and drag path.


local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local LetterWheel = {}

local RemoteRegistry = require(ReplicatedStorage:WaitForChild("Shared").RemoteRegistry)
local UIEffects = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("util"):WaitForChild("UIEffects"))
local InputState = require(script.Parent.Parent.core.InputState)
local ClientBridge = require(script.Parent.Parent.core.ClientBridge)

local uiMgr            = nil
local hud              = nil
local gameButtons      = nil
local wheelRoot        = nil
local wheelFrame       = nil
local lineCanvas       = nil
local letterTemp       = nil
local letterBtns       = {}    -- { frame, label, letter, index }
local selected         = {}    -- ordered indices
local selectedSet      = {}    -- selected indices
local currentWordLabel = nil
local levelData        = nil
local isShuffling      = false
local dragging         = false
local lastHoveredIndex = nil
local inputBgBasePos   = nil
local invalidShakeTween = nil
local invalidFadeTween = nil
local invalidLabelFadeTween = nil
local invalidAnimToken = 0
local validPulseTween = nil
local WHEEL_CENTER_OFFSET = Vector2.new(0, 0)
local pendingBuildToken = 0
local WHEEL_LAYOUT_SETTLE_DELAY = 0.18
local updateTutorialLetterAvailability
local shuffleLetters

-- Level color drives the line and selected letter tint.
local COL_LETTER_NRM = Color3.fromRGB(0, 0, 0)
local COL_LETTER_SEL = Color3.fromRGB(255, 220, 25)  -- Default yellow, overwritten by levelColor
local COL_LINE       = Color3.fromRGB(255, 220, 25)  -- Default yellow, overwritten by levelColor
local levelColor     = Color3.fromRGB(255, 220, 25)
local transitionToken = 0
local currentLineThickness = 8
local activePointerInput = nil
local latestPointerPosition = nil
local mouseHoldLatch = false
local lastMouseClickTime = 0
local DOUBLE_CLICK_LATCH_WINDOW = 0.32
local controllerFocusIndex = nil
local controllerHelpFrame = nil
local controllerMoveCooldownUntil = 0
local THUMBSTICK_DEADZONE = 0.6
local CONTROLLER_MOVE_COOLDOWN = 0.16
local controllerGamepadActive = false

local function playLetterAddSfx()
	UIEffects.PlaySound("Plus")
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

local function isArrowSelectionActive()
	return ClientBridge.Call("IsArrowSelectionActive") == true
end

local function tutorialAllowsDrag()
	return ClientBridge.Call("TutorialAllowsAction", "drag") ~= false
end

local function circlePos(index, total, radius)
	local angle = (2 * math.pi * (index - 1) / total) - math.pi / 2
	return Vector2.new(radius * math.cos(angle), radius * math.sin(angle))
end

local function getWheelLayout(total, wheelDiameter)
	total = math.max(2, tonumber(total) or 2)
	wheelDiameter = math.max(120, tonumber(wheelDiameter) or 120)

	local boundaryInset = total <= 4 and math.clamp(wheelDiameter * 0.045, 8, 12)
		or (total == 5 and math.clamp(wheelDiameter * 0.05, 9, 13)
		or (total == 6 and math.clamp(wheelDiameter * 0.055, 10, 14) or math.clamp(wheelDiameter * 0.06, 11, 16)))
	local outerRadius = (wheelDiameter * 0.5) - boundaryInset
	local chordAtEdge = 2 * outerRadius * math.sin(math.pi / total)
	local chordFactor = total <= 4 and 0.82 or (total == 5 and 0.76 or (total == 6 and 0.71 or 0.65))
	local visualCap = total <= 4 and (wheelDiameter * 0.295)
		or (total == 5 and (wheelDiameter * 0.255)
		or (total == 6 and (wheelDiameter * 0.225) or (wheelDiameter * 0.19)))
	local minLetterSize = total <= 4 and 42 or (total == 5 and 38 or (total == 6 and 34 or 30))
	local maxLetterSize = math.max(minLetterSize, visualCap)
	local letterSize = math.clamp(chordAtEdge * chordFactor, minLetterSize, maxLetterSize)
	local radius = math.max(24, outerRadius - (letterSize * 0.5))
	local lineThickness = math.clamp(math.floor(letterSize * 0.15 + 0.5), 5, 12)
	return letterSize, radius, lineThickness
end

-- Frame with AnchorPoint (0.5, 0.5) has AbsolutePosition at center
local function frameCentre(frame)
	return frame.AbsolutePosition + (frame.AbsoluteSize * 0.5)
end

local function getGuiMousePosition()
	local mousePos = UserInputService:GetMouseLocation()
	local insetTopLeft = GuiService:GetGuiInset()
	return mousePos - insetTopLeft
end

local function toGuiPosition(input)
	if not input then
		return nil
	end
	local position = input.Position
	if typeof(position) == "Vector3" then
		return Vector2.new(position.X, position.Y)
	end
	if typeof(position) == "Vector2" then
		return position
	end
	return nil
end

local function getCurrentPointerPosition()
	return latestPointerPosition or getGuiMousePosition()
end

local function isPointInsideWheel(pos)
	if not wheelFrame then
		return false
	end
	local topLeft = wheelFrame.AbsolutePosition
	local size = wheelFrame.AbsoluteSize
	return pos.X >= topLeft.X and pos.X <= (topLeft.X + size.X)
		and pos.Y >= topLeft.Y and pos.Y <= (topLeft.Y + size.Y)
end

local function drawLine(from, to, name)
	local existing = lineCanvas:FindFirstChild(name)
	if existing then existing:Destroy() end

	local diff = to - from
	local length = diff.Magnitude
	local angle = math.atan2(diff.Y, diff.X)
	local cp = lineCanvas.AbsolutePosition

	local line = Instance.new("Frame")
	line.Name = name
	line.Size = UDim2.fromOffset(length, currentLineThickness)
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromOffset(
		from.X + diff.X * 0.5 - cp.X,
		from.Y + diff.Y * 0.5 - cp.Y
	)
	line.Rotation = math.deg(angle)
	line.BackgroundColor3 = COL_LINE
	line.BorderSizePixel = 0
	line.ZIndex = 5
	line.Parent = lineCanvas

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = line
end

local function clearLines()
	if not lineCanvas then return end
	-- Remove all lines except DragLine (handled separately)
	for _, child in ipairs(lineCanvas:GetChildren()) do
		if child.Name ~= "DragLine" then
			child:Destroy()
		end
	end
end


local function setSelected(btn, on)
	-- LetterTemp is a TextButton, so use the frame itself
	local bg = btn.frame
	if bg and bg:IsA("GuiObject") then
		TweenService:Create(bg, TweenInfo.new(0.09), {
			BackgroundColor3 = on and levelColor or Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = on and 0 or 1,  -- 0 = visible when selected, 1 = transparent when not
		}):Play()
	end
	if btn.label and btn.label:IsA("TextLabel") then
		btn.label.TextColor3 = on and Color3.fromRGB(255, 255, 255) or COL_LETTER_NRM
	end
end

local function refreshLines()
	-- Remove old connection lines (keep drag line)
	for _, child in ipairs(lineCanvas:GetChildren()) do
		if child.Name ~= "DragLine" and child.Name:match("^Line_%d+") then
			child:Destroy()
		end
	end
	-- Draw connection lines between selected letters
	for i = 2, #selected do
		local a = letterBtns[selected[i - 1]]
		local b = letterBtns[selected[i]]
		drawLine(frameCentre(a.frame), frameCentre(b.frame), "Line_" .. i)
	end
end

local function refreshCurrentWordText()
	if not currentWordLabel then
		return
	end
	local word = ""
	for _, idx in ipairs(selected) do
		local btn = letterBtns[idx]
		if btn and btn.letter then
			word = word .. btn.letter
		end
	end
	currentWordLabel.Text = word
end

local function clearInputBarVisuals(clearText)
	local inputBar = wheelRoot and wheelRoot:FindFirstChild("InputBar")
	local bg = inputBar and inputBar:FindFirstChild("Background")
	if bg then
		if not inputBgBasePos then
			inputBgBasePos = bg.Position
		end
		bg.Position = inputBgBasePos
		bg.BackgroundColor3 = levelColor
		bg.BackgroundTransparency = 1
	end
	if currentWordLabel then
		currentWordLabel.TextTransparency = 0
		currentWordLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		if clearText ~= false then
			currentWordLabel.Text = ""
		end
	end
end

local function cancelInvalidVisualState(clearText)
	invalidAnimToken += 1
	if invalidShakeTween then
		invalidShakeTween:Cancel()
		invalidShakeTween = nil
	end
	if invalidFadeTween then
		invalidFadeTween:Cancel()
		invalidFadeTween = nil
	end
	if invalidLabelFadeTween then
		invalidLabelFadeTween:Cancel()
		invalidLabelFadeTween = nil
	end
	clearInputBarVisuals(clearText)
end

local function canSelectTutorialIndex(btnIndex)
	local tutorialTarget = ClientBridge.Call("GetTutorialTargetWord")
	if not tutorialTarget or tutorialTarget == "" then
		return true
	end
	if ClientBridge.Call("TutorialAllowsAction", "drag") == false then
		return false
	end

	local expectedIndices = {}
	local used = {}
	local upperTarget = string.upper(tostring(tutorialTarget))
	for i = 1, #upperTarget do
		local ch = upperTarget:sub(i, i)
		local chosen = nil
		for index, btn in ipairs(letterBtns) do
			if not used[index] and btn.letter == ch then
				chosen = index
				break
			end
		end
		if not chosen then
			return true
		end
		used[chosen] = true
		expectedIndices[i] = chosen
	end

	local nextSlot = #selected + 1
	for i = nextSlot, #expectedIndices do
		if expectedIndices[i] == btnIndex then
			return true
		end
	end
	return false
end

local function getTutorialExpectedIndices()
	local tutorialTarget = ClientBridge.Call("GetTutorialTargetWord")
	if not tutorialTarget or tutorialTarget == "" then
		return nil
	end
	if ClientBridge.Call("TutorialAllowsAction", "drag") == false then
		return nil
	end

	local expectedIndices = {}
	local used = {}
	local upperTarget = string.upper(tostring(tutorialTarget))
	for i = 1, #upperTarget do
		local ch = upperTarget:sub(i, i)
		local chosen = nil
		for index, btn in ipairs(letterBtns) do
			if not used[index] and btn.letter == ch then
				chosen = index
				break
			end
		end
		if not chosen then
			return nil
		end
		used[chosen] = true
		expectedIndices[i] = chosen
	end
	return expectedIndices
end

local function selectTutorialIndex(btnIndex)
	if selectedSet[btnIndex] then
		return
	end
	local btn = letterBtns[btnIndex]
	if not btn then
		return
	end
	lastHoveredIndex = btnIndex
	table.insert(selected, btnIndex)
	selectedSet[btnIndex] = true
	setSelected(btn, true)
	playLetterAddSfx()
	refreshLines()
	refreshCurrentWordText()
	updateTutorialLetterAvailability()
end

local function trySelectTutorialProgress(btnIndex)
	local expectedIndices = getTutorialExpectedIndices()
	if not expectedIndices then
		return false
	end
	local nextSlot = #selected + 1
	for i = nextSlot, #expectedIndices do
		if expectedIndices[i] == btnIndex then
			for fillIndex = nextSlot, i do
				selectTutorialIndex(expectedIndices[fillIndex])
			end
			return true
		end
	end
	return false
end

local function isTutorialSelectionActive()
	local tutorialTarget = ClientBridge.Call("GetTutorialTargetWord")
	if not tutorialTarget or tutorialTarget == "" then
		return false
	end
	if ClientBridge.Call("TutorialAllowsAction", "drag") == false then
		return false
	end
	return true
end

updateTutorialLetterAvailability = function()
	for i, btn in ipairs(letterBtns) do
		if not (btn and btn.frame) then
			continue
		end

		btn.frame.Active = true
		btn.frame.Selectable = true
		btn.frame.AutoButtonColor = false

		if btn.label then
			btn.label.TextTransparency = 0
		end
		if not selectedSet[i] and not isTutorialSelectionActive() then
			btn.frame.BackgroundTransparency = 1
			btn.frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		end
	end
end

local function resetSelection(clearInputBar)
	for _, idx in ipairs(selected) do
		setSelected(letterBtns[idx], false)
	end
	selected = {}
	selectedSet = {}
	lastHoveredIndex = nil
	-- Remove drag line if exists
	local dragLine = lineCanvas:FindFirstChild("DragLine")
	if dragLine then dragLine:Destroy() end
	clearLines()
	if clearInputBar ~= false then
		cancelInvalidVisualState(true)
	end
	updateTutorialLetterAvailability()
end

local function ensureControllerHelpFrame()
	if controllerHelpFrame and controllerHelpFrame.Parent then
		return controllerHelpFrame
	end
	if not hud then
		return nil
	end
	local frame = hud:FindFirstChild("ControllerHelp", true)
	if frame and frame:IsA("GuiObject") then
		local body = frame:FindFirstChild("Body", true)
		if body and body:IsA("TextLabel") then
			body.RichText = true
			body.TextWrapped = true
			body.TextYAlignment = Enum.TextYAlignment.Top
		end
		local title = frame:FindFirstChild("Title", true)
		if title and title:IsA("TextLabel") then
			title.Text = "Controller"
		end
	end
	controllerHelpFrame = frame
	return frame
end

local function getControllerPromptPrefix()
	local ok, platform = pcall(function()
		return UserInputService:GetPlatform()
	end)
	local platformName = ok and platform and tostring(platform.Name) or ""
	if string.find(platformName, "PS", 1, true) or string.find(platformName, "PlayStation", 1, true) then
		return "PlayStation"
	end
	if string.find(platformName, "Xbox", 1, true) then
		return "Xbox"
	end
	return "Controller"
end

local function getControllerHelpRichText(isArrowMode)
	if isArrowMode then
		return table.concat({
			'<font color="#9FD6FF"><b>Move Tile</b></font>',
			'    ',
			'<font color="#9CFFB1"><b>A</b></font> <font color="#FFFFFF">Reveal</font>',
			'    ',
			'<font color="#FFB0B0"><b>B</b></font> <font color="#FFFFFF">Cancel</font>',
		})
	end
	return table.concat({
		'<font color="#9FD6FF"><b>Move</b></font>',
		'    ',
		'<font color="#9CFFB1"><b>A</b></font> <font color="#FFFFFF">Pick</font>',
		'    ',
		'<font color="#9FD6FF"><b>X</b></font> <font color="#FFFFFF">Submit</font>',
		'    ',
		'<font color="#FFB0B0"><b>B</b></font> <font color="#FFFFFF">Clear</font>',
		'\n',
		'<font color="#FFE08A"><b>Y</b></font> <font color="#FFFFFF">Shuffle</font>',
		'    ',
		'<font color="#CDB8FF"><b>LB</b></font> <font color="#FFFFFF">Hint</font>',
		'    ',
		'<font color="#FFB5E5"><b>RB</b></font> <font color="#FFFFFF">Tile Hint</font>',
	})
end

local function clearControllerFocusVisual()
	for _, btn in ipairs(letterBtns) do
		local frame = btn and btn.frame
		if frame then
			local stroke = frame:FindFirstChild("ControllerFocusStroke")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Enabled = false
			end
			local scale = frame:FindFirstChild("ControllerFocusScale")
			if scale and scale:IsA("UIScale") then
				scale.Scale = 1
			end
		end
	end
end

local function refreshControllerUiState()
	local help = ensureControllerHelpFrame()
	local shouldShow = controllerGamepadActive and levelData ~= nil and InputState:IsEnabled()
	if help then
		help.Visible = shouldShow
		local body = help:FindFirstChild("Body")
		if body and body:IsA("TextLabel") then
			body.RichText = true
			body.Text = getControllerHelpRichText(isArrowSelectionActive())
		end
	end
	if not shouldShow then
		clearControllerFocusVisual()
		return
	end
	if #letterBtns <= 0 then
		clearControllerFocusVisual()
		return
	end
	controllerFocusIndex = math.clamp(tonumber(controllerFocusIndex) or 1, 1, #letterBtns)
	clearControllerFocusVisual()
	local focused = letterBtns[controllerFocusIndex]
	local frame = focused and focused.frame
	if not frame then
		return
	end
	local stroke = frame:FindFirstChild("ControllerFocusStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = "ControllerFocusStroke"
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 3
		stroke.Transparency = 0.15
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
	end
	stroke.Enabled = true
	local scale = frame:FindFirstChild("ControllerFocusScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "ControllerFocusScale"
		scale.Parent = frame
	end
	scale.Scale = 1.08
end

local function addSelectionIndex(btnIndex)
	if selectedSet[btnIndex] then
		return false
	end
	local btn = letterBtns[btnIndex]
	if not (btn and canSelectTutorialIndex(btnIndex)) then
		return false
	end
	if #selected == 0 then
		cancelInvalidVisualState(true)
	end
	if not trySelectTutorialProgress(btnIndex) then
		lastHoveredIndex = btnIndex
		table.insert(selected, btnIndex)
		selectedSet[btnIndex] = true
		setSelected(btn, true)
		playLetterAddSfx()
		refreshLines()
		refreshCurrentWordText()
		updateTutorialLetterAvailability()
	end
	return true
end

local function findControllerNeighbor(direction)
	if #letterBtns <= 1 then
		return controllerFocusIndex or 1
	end
	local currentIndex = math.clamp(tonumber(controllerFocusIndex) or 1, 1, #letterBtns)
	local current = letterBtns[currentIndex]
	local currentCenter = current and current.frame and frameCentre(current.frame)
	if not currentCenter then
		return 1
	end
	local bestIndex = nil
	local bestScore = -math.huge
	for index, btn in ipairs(letterBtns) do
		if index ~= currentIndex and btn and btn.frame then
			local delta = frameCentre(btn.frame) - currentCenter
			local distance = delta.Magnitude
			if distance > 0 then
				local unit = delta.Unit
				local score = (unit:Dot(direction) * 10) - (distance * 0.01)
				if unit:Dot(direction) > 0.15 and score > bestScore then
					bestScore = score
					bestIndex = index
				end
			end
		end
	end
	if bestIndex then
		return bestIndex
	end
	if math.abs(direction.X) >= math.abs(direction.Y) then
		return ((currentIndex - 1 + (direction.X >= 0 and 1 or -1)) % #letterBtns) + 1
	end
	return ((currentIndex - 1 + (direction.Y >= 0 and 1 or -1)) % #letterBtns) + 1
end

local function moveControllerFocus(direction)
	if #letterBtns <= 0 then
		return
	end
	controllerFocusIndex = findControllerNeighbor(direction)
	refreshControllerUiState()
end

local function handleControllerMoveVector(vec)
	if not controllerGamepadActive or not levelData or not InputState:IsEnabled() then
		return
	end
	if tick() < controllerMoveCooldownUntil then
		return
	end
	if vec.Magnitude < THUMBSTICK_DEADZONE then
		return
	end
	controllerMoveCooldownUntil = tick() + CONTROLLER_MOVE_COOLDOWN
	moveControllerFocus(Vector2.new(vec.X, -vec.Y))
end

local function cancelDragSelection()
	dragging = false
	mouseHoldLatch = false
	activePointerInput = nil
	latestPointerPosition = nil
	resetSelection(true)
end

local function submitWord()
	if #selected == 0 then return end
	if not InputState:IsEnabled() then
		cancelDragSelection()
		return
	end

	local word = ""
	for _, idx in ipairs(selected) do
		word = word .. letterBtns[idx].letter
	end

	local tutorialTarget = ClientBridge.Call("GetTutorialTargetWord")
	if tutorialTarget and tutorialTarget ~= "" and string.upper(word) ~= string.upper(tostring(tutorialTarget)) then
		LetterWheel:FlashInvalid()
		resetSelection(false)
		return
	end

	if levelData and tonumber(levelData.packId) == 0 then
		RemoteRegistry:GetEvent("SubmitDailyWord"):FireServer(word)
	else
		RemoteRegistry:GetEvent("SubmitWord"):FireServer(word, levelData)
	end
	resetSelection(false)
end


local function startDrag(btnIndex)
	if not levelData or not InputState:IsEnabled() then return end
	if ClientBridge.Call("TutorialAllowsAction", "drag") == false then
		return
	end
	if dragging or #selected > 0 then
		cancelDragSelection()
	end
	local btn = letterBtns[btnIndex]
	if not (btn and not selectedSet[btnIndex] and canSelectTutorialIndex(btnIndex)) then
		return
	end

	cancelInvalidVisualState(true)
	dragging = true
	lastHoveredIndex = btnIndex
	latestPointerPosition = getCurrentPointerPosition()

	local inputBar = wheelRoot and wheelRoot:FindFirstChild("InputBar")
	if inputBar then
		local bg = inputBar:FindFirstChild("Background")
		if bg then
			TweenService:Create(bg, TweenInfo.new(0.1), {
				BackgroundColor3 = levelColor,
				BackgroundTransparency = 0,
			}):Play()
		end
	end

	addSelectionIndex(btnIndex)
end

local function isPointInButton(pos, btn)
	local topLeft = btn.frame.AbsolutePosition
	local sz = btn.frame.AbsoluteSize

	return pos.X >= topLeft.X and pos.X <= topLeft.X + sz.X
		and pos.Y >= topLeft.Y and pos.Y <= topLeft.Y + sz.Y
end

local function updateDragLine(mousePos)
	if #selected == 0 then return end
	-- Remove any existing drag line
	local existing = lineCanvas:FindFirstChild("DragLine")
	if existing then existing:Destroy() end
	
	-- Draw line from last selected letter to mouse position
	local lastBtn = letterBtns[selected[#selected]]
	if lastBtn then
		local cp = lineCanvas.AbsolutePosition
		local from = frameCentre(lastBtn.frame)
		local diff = mousePos - from
		local length = diff.Magnitude
		local angle = math.atan2(diff.Y, diff.X)
		
		local line = Instance.new("Frame")
		line.Name = "DragLine"
		line.Size = UDim2.fromOffset(length, currentLineThickness)
		-- Anchor at center so rotation works correctly
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromOffset(
			from.X + diff.X * 0.5 - cp.X,
			from.Y + diff.Y * 0.5 - cp.Y
		)
		line.Rotation = math.deg(angle)
		line.BackgroundColor3 = COL_LINE
		line.BorderSizePixel = 0
		line.ZIndex = 6
		line.Parent = lineCanvas
		
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = line
	end
end

local function continueDrag()
	if not dragging then return end
	if not InputState:IsEnabled() then
		cancelDragSelection()
		return
	end
	if not tutorialAllowsDrag() then
		cancelDragSelection()
		return
	end
	
	local pos = getCurrentPointerPosition()
	if not pos then
		return
	end
	if not isPointInsideWheel(pos) then
		dragging = false
		mouseHoldLatch = false
		activePointerInput = nil
		latestPointerPosition = nil
		lastHoveredIndex = nil
		local existing = lineCanvas:FindFirstChild("DragLine")
		if existing then existing:Destroy() end
		submitWord()
		return
	end

	local hoveredIndex = nil
	for i, btn in ipairs(letterBtns) do
		if isPointInButton(pos, btn) then
			hoveredIndex = i
			break
		end
	end

	if hoveredIndex and #selected >= 2 and hoveredIndex == selected[#selected - 1] and lastHoveredIndex ~= hoveredIndex then
		local removedIndex = table.remove(selected, #selected)
		if removedIndex then
			selectedSet[removedIndex] = nil
			setSelected(letterBtns[removedIndex], false)
		end
		lastHoveredIndex = hoveredIndex
		refreshLines()
		refreshCurrentWordText()
		updateTutorialLetterAvailability()
		local existing = lineCanvas:FindFirstChild("DragLine")
		if existing then existing:Destroy() end
		return
	end
	
	-- Check if hovering any unselected button
	local found = false
	for i, btn in ipairs(letterBtns) do
		if isPointInButton(pos, btn) then
			found = true
			if not selectedSet[i] then
				-- Only select if we're hovering a new letter
				if lastHoveredIndex ~= i and canSelectTutorialIndex(i) then
					addSelectionIndex(i)
				end
			end
			break
		end
	end
	
	if not found then
		lastHoveredIndex = nil
		-- Update drag line following mouse
		updateDragLine(pos)
	else
		-- Remove drag line when connected to a letter
		local existing = lineCanvas:FindFirstChild("DragLine")
		if existing then existing:Destroy() end
	end
end

local function endDrag()
	if not dragging then return end
	if not InputState:IsEnabled() then
		cancelDragSelection()
		return
	end
	if not tutorialAllowsDrag() then
		cancelDragSelection()
		return
	end
	if mouseHoldLatch then
		return
	end
	dragging = false
	activePointerInput = nil
	latestPointerPosition = nil
	lastHoveredIndex = nil
	-- Remove drag line
	local existing = lineCanvas:FindFirstChild("DragLine")
	if existing then existing:Destroy() end
	submitWord()
end

local function setupLetterInput(btn)
	-- Mouse/ touch events on the letter button itself
	-- Find index dynamically since shuffle changes positions
	btn.frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 
		   or input.UserInputType == Enum.UserInputType.Touch then
			if input.UserInputType == Enum.UserInputType.MouseButton1 and mouseHoldLatch and dragging then
				activePointerInput = input
				latestPointerPosition = toGuiPosition(input) or getGuiMousePosition()
				mouseHoldLatch = false
				endDrag()
				return
			end
			if dragging then
				return
			end
			activePointerInput = input
			latestPointerPosition = toGuiPosition(input) or getGuiMousePosition()
			-- Find current index of this button
			for i, b in ipairs(letterBtns) do
				if b == btn then
					startDrag(i)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						local now = tick()
						if (now - lastMouseClickTime) <= DOUBLE_CLICK_LATCH_WINDOW then
							mouseHoldLatch = true
						end
						lastMouseClickTime = now
					else
						mouseHoldLatch = false
					end
					return
				end
			end
		end
	end)
	if btn.frame:IsA("GuiButton") then
		btn.frame.SelectionGained:Connect(function()
			for i, b in ipairs(letterBtns) do
				if b == btn then
					controllerFocusIndex = i
					refreshControllerUiState()
					return
				end
			end
		end)
		btn.frame.Activated:Connect(function()
			if not levelData or not InputState:IsEnabled() or isArrowSelectionActive() then
				return
			end
			for i, b in ipairs(letterBtns) do
				if b == btn then
					controllerFocusIndex = i
					addSelectionIndex(i)
					refreshControllerUiState()
					return
				end
			end
		end)
	end
end

local function setupInput()
	-- Global input handling for drag continuation and release
	UserInputService.InputChanged:Connect(function(input)
		if dragging and not tutorialAllowsDrag() then
			cancelDragSelection()
			return
		end
		if isGamepadInputType(input.UserInputType) and input.KeyCode == Enum.KeyCode.Thumbstick1 then
			if isArrowSelectionActive() then
				return
			end
			handleControllerMoveVector(input.Position)
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement 
		   or input.UserInputType == Enum.UserInputType.Touch then
			if input.UserInputType == Enum.UserInputType.Touch then
				if activePointerInput and input ~= activePointerInput then
					return
				end
				activePointerInput = input
				latestPointerPosition = toGuiPosition(input)
			else
				latestPointerPosition = getGuiMousePosition()
			end
			continueDrag()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 
		   or input.UserInputType == Enum.UserInputType.Touch then
			if input.UserInputType == Enum.UserInputType.Touch and activePointerInput and input ~= activePointerInput then
				return
			end
			if input.UserInputType == Enum.UserInputType.Touch then
				latestPointerPosition = toGuiPosition(input) or latestPointerPosition
				activePointerInput = nil
			end
			endDrag()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not isGamepadInputType(input.UserInputType) then
			return
		end
		controllerGamepadActive = true
		refreshControllerUiState()
		if not levelData or not InputState:IsEnabled() then
			return
		end
		if isArrowSelectionActive() then
			if input.KeyCode == Enum.KeyCode.ButtonB then
				ClientBridge.Call("CancelArrowSelection")
				refreshControllerUiState()
			end
			return
		end
		if input.KeyCode == Enum.KeyCode.DPadLeft then
			moveControllerFocus(Vector2.new(-1, 0))
		elseif input.KeyCode == Enum.KeyCode.DPadRight then
			moveControllerFocus(Vector2.new(1, 0))
		elseif input.KeyCode == Enum.KeyCode.DPadUp then
			moveControllerFocus(Vector2.new(0, -1))
		elseif input.KeyCode == Enum.KeyCode.DPadDown then
			moveControllerFocus(Vector2.new(0, 1))
		elseif input.KeyCode == Enum.KeyCode.ButtonA then
			if controllerFocusIndex then
				addSelectionIndex(controllerFocusIndex)
				refreshControllerUiState()
			end
		elseif input.KeyCode == Enum.KeyCode.ButtonX then
			submitWord()
			refreshControllerUiState()
		elseif input.KeyCode == Enum.KeyCode.ButtonB then
			resetSelection(true)
			refreshControllerUiState()
		elseif input.KeyCode == Enum.KeyCode.ButtonY then
			shuffleLetters(function()
				ClientBridge.Call("OnTutorialShuffleUsed")
				refreshControllerUiState()
			end)
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			ClientBridge.Call("PressHintButton")
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			ClientBridge.Call("StartArrowSelection")
			refreshControllerUiState()
		end
	end)

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		controllerGamepadActive = isGamepadInputType(inputType)
		refreshControllerUiState()
	end)
	
	-- Wheel frame input (for dragging outside letters)
	wheelFrame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 
		   or input.UserInputType == Enum.UserInputType.Touch then
			-- Check if clicking on a letter is handled by the letter's own InputBegan
			-- This is just a fallback
		end
	end)
end


local function getLetterPosition(index, total, radius)
	local pos = circlePos(index, total, radius)
	return UDim2.new(
		0.5,
		math.floor(pos.X + WHEEL_CENTER_OFFSET.X + 0.5),
		0.5,
		math.floor(pos.Y + WHEEL_CENTER_OFFSET.Y + 0.5)
	)
end

local function relayoutLetters(tweenDuration)
	if not wheelFrame or #letterBtns == 0 then
		return
	end

	local wheelSize = wheelFrame.AbsoluteSize
	if wheelSize.X <= 0 or wheelSize.Y <= 0 then
		return
	end

	local total = #letterBtns
	local wheelDiameter = math.min(wheelSize.X, wheelSize.Y)
	local letterSize, radius, lineThickness = getWheelLayout(total, wheelDiameter)
	currentLineThickness = lineThickness
	local useTween = math.max(0, tonumber(tweenDuration) or 0) > 0

	for i, btn in ipairs(letterBtns) do
		btn.index = i
		local targetSize = UDim2.fromOffset(letterSize, letterSize)
		local targetPosition = getLetterPosition(i, total, radius)
		btn.frame.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.frame.Rotation = 0
		if useTween then
			local currentPos = btn.frame.Position
			local currentSize = btn.frame.Size
			local needsTween = math.abs(currentPos.X.Offset - targetPosition.X.Offset) > 1
				or math.abs(currentPos.Y.Offset - targetPosition.Y.Offset) > 1
				or math.abs(currentSize.X.Offset - targetSize.X.Offset) > 1
				or math.abs(currentSize.Y.Offset - targetSize.Y.Offset) > 1
			if needsTween then
				if btn.layoutTween then
					btn.layoutTween:Cancel()
					btn.layoutTween = nil
				end
				btn.layoutTween = TweenService:Create(btn.frame, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = targetPosition,
					Size = targetSize,
				})
				btn.layoutTween:Play()
			else
				btn.frame.Size = targetSize
				btn.frame.Position = targetPosition
			end
		else
			btn.frame.Size = targetSize
			btn.frame.Position = targetPosition
		end
	end
end

local function buildLetters(letters)
	-- Clear old letters
	for _, btn in ipairs(letterBtns) do
		btn.frame:Destroy()
	end
	letterBtns = {}
	selected = {}
	selectedSet = {}
	clearLines()
	if currentWordLabel then
		currentWordLabel.Text = ""
	end

	if not letterTemp then
		warn("[LetterWheel] LetterTemp not found in WheelRoot")
		return
	end

	local total = #letters
	local wheelSize = wheelFrame.AbsoluteSize
	local wheelDiameter = math.min(wheelSize.X, wheelSize.Y)

	local letterSize, radius, lineThickness = getWheelLayout(total, wheelDiameter)
	currentLineThickness = lineThickness


	for i, letter in ipairs(letters) do
		local targetPos = getLetterPosition(i, total, radius)

		-- Clone template
		local frame = letterTemp:Clone()
		frame.Name = "Letter_" .. i
		frame.Position = targetPos
		frame.Size = UDim2.new(0, letterSize, 0, letterSize)  -- {0, X, 0, Y} format
		frame.AnchorPoint = Vector2.new(0.5, 0.5)  -- Center anchor
		frame.Visible = true
		frame.AutoButtonColor = false  -- We handle visual feedback manually
		frame.Active = true  -- Ensure input is received
		frame.ZIndex = 10  -- Above lines (ZIndex 5)
		frame.Parent = wheelFrame

		-- Tutorial/visual cleanup: letter buttons should not render template strokes.
		for _, d in ipairs(frame:GetDescendants()) do
			if d:IsA("UIStroke") then
				d:Destroy()
			end
		end

		-- Set background transparent initially (shows selection on click)
		frame.BackgroundColor3 = Color3.fromRGB(255, 220, 25)  -- Yellow for selection
		frame.BackgroundTransparency = 1  -- Fully transparent until clicked
		
		-- Update letter text (TextLabel is direct child of LetterTemp which is a TextButton)
		local lbl = frame:FindFirstChild("TextLabel")
		if lbl then
			lbl.Text = letter
			lbl.TextScaled = true
			lbl.TextColor3 = COL_LETTER_NRM
			lbl.Active = false  -- Let clicks pass through to parent button
		else
			warn("[LetterWheel] TextLabel not found in LetterTemp for letter " .. letter)
		end

		local btnData = { 
			frame = frame, 
			label = lbl, 
			letter = letter,
			index = i,
		}
		table.insert(letterBtns, btnData)
		
		-- Setup input handling for this letter
		setupLetterInput(btnData)
	end

	relayoutLetters()
	updateTutorialLetterAvailability()
end

local function setLettersHiddenState()
	transitionToken += 1
	for _, btn in ipairs(letterBtns) do
		if btn.frame and btn.frame.Parent then
			btn.baseSize = btn.frame.Size
			btn.frame.Visible = false
			btn.frame.Size = UDim2.fromOffset(0, 0)
			btn.frame.BackgroundTransparency = 1
			if btn.label then
				btn.label.TextTransparency = 1
			end
		end
	end
end

local function animateLettersIn(duration)
	transitionToken += 1
	local token = transitionToken
	local tweenDuration = math.max(0.01, tonumber(duration) or 0.84)
	relayoutLetters()
	for _, btn in ipairs(letterBtns) do
		if btn.frame and btn.frame.Parent then
			local targetSize = btn.baseSize or btn.frame.Size
			btn.frame.Size = UDim2.fromOffset(0, 0)
			btn.frame.Visible = true
			btn.frame.BackgroundTransparency = selectedSet[btn.index] and 0 or 1
			if btn.label then
				btn.label.TextTransparency = 1
			end

			TweenService:Create(btn.frame, TweenInfo.new(tweenDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = targetSize,
			}):Play()

			if btn.label then
				task.delay(tweenDuration * 0.2, function()
					if token ~= transitionToken then
						return
					end
					if btn.label and btn.label.Parent then
						TweenService:Create(btn.label, TweenInfo.new(tweenDuration * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							TextTransparency = 0,
						}):Play()
					end
				end)
			end
		end
	end
	task.delay(tweenDuration + 0.03, function()
		if token ~= transitionToken then
			return
		end
		relayoutLetters(0.12)
		refreshLines()
	end)
end

local function animateLettersOut(duration, destroyAfter)
	transitionToken += 1
	local token = transitionToken
	local tweenDuration = math.max(0.01, tonumber(duration) or 0.66)
	local framesToDestroy = {}
	for _, btn in ipairs(letterBtns) do
		if btn.frame and btn.frame.Parent then
			table.insert(framesToDestroy, btn.frame)
			btn.baseSize = btn.frame.Size
			TweenService:Create(btn.frame, TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
			}):Play()
			if btn.label then
				TweenService:Create(btn.label, TweenInfo.new(tweenDuration * 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					TextTransparency = 1,
				}):Play()
			end
		end
	end

	if destroyAfter then
		task.delay(tweenDuration + 0.02, function()
			if token ~= transitionToken then
				return
			end
			for _, frame in ipairs(framesToDestroy) do
				if frame and frame.Parent then
					frame.Visible = false
					frame:Destroy()
				end
			end
			letterBtns = {}
			selected = {}
			selectedSet = {}
			clearLines()
		end)
	end
end

-- Shuffle letters
shuffleLetters = function(onComplete)
	if not InputState:IsEnabled() or not levelData or #letterBtns == 0 or isShuffling then return end
	if ClientBridge.GetState("IsHardcoreMode") then
		if uiMgr and uiMgr.ShowAlert then
			uiMgr:ShowAlert("Shuffle disabled in hardcore", "error")
		end
		return
	end

	isShuffling = true
	resetSelection()

	local n = #letterBtns
	local wheelSize = wheelFrame.AbsoluteSize
	local wheelDiameter = math.min(wheelSize.X, wheelSize.Y)

	local letterSize, radius = getWheelLayout(n, wheelDiameter)
	

	-- Force visible movement by rotating everyone to a shifted slot.
	local newSlots = {}
	local shift = (n > 1) and math.random(1, n - 1) or 0
	for i = 1, n do
		newSlots[i] = ((i + shift - 1) % n) + 1
	end

	local snap = {}
	for i, btn in ipairs(letterBtns) do
		snap[i] = { btn = btn }
	end

	local pending = n
	for i = 1, n do
		local targetPos = getLetterPosition(newSlots[i], n, radius)
		local tween = TweenService:Create(snap[i].btn.frame,
			TweenInfo.new(0.4725, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{
				Position = targetPos,
				Rotation = snap[i].btn.frame.Rotation + 360,
			}
		)
		tween.Completed:Connect(function()
			snap[i].btn.frame.Rotation = 0
			pending -= 1
			if pending <= 0 then
				local newBtns = table.create(n)
				for k = 1, n do
					newBtns[newSlots[k]] = snap[k].btn
					newBtns[newSlots[k]].index = newSlots[k]
				end
				letterBtns = newBtns
				relayoutLetters()
				updateTutorialLetterAvailability()
				isShuffling = false
				if onComplete then
					onComplete()
				end
			end
		end)
		tween:Play()
	end
end


function LetterWheel:Init(manager, hudScreen)
	uiMgr = manager
	hud = hudScreen

	-- WheelRoot is at HUD.Game.WheelRoot (fallback HUD.GameScreen.WheelRoot)
	local gameScreen = hud:FindFirstChild("Game") or hud:WaitForChild("GameScreen")
	gameButtons = gameScreen:FindFirstChild("Buttons")
	wheelRoot = gameScreen:WaitForChild("WheelRoot")
	wheelFrame = wheelRoot:WaitForChild("Wheel")
	lineCanvas = wheelFrame:WaitForChild("LineCanvas")
	letterTemp = wheelRoot:WaitForChild("LetterTemp")

	-- Hide template
	letterTemp.Visible = false

	-- Get input bar label
	local inputBar = wheelRoot:FindFirstChild("InputBar")
	if inputBar then
		local bg = inputBar:FindFirstChild("Background")
		if bg then
			currentWordLabel = bg:FindFirstChild("TextLabel")
			inputBgBasePos = bg.Position
			bg.BackgroundTransparency = 1
		end
	end

	-- Connect shuffle button
	local shuffleBtn = (gameButtons and gameButtons:FindFirstChild("Shuffle")) or wheelRoot:FindFirstChild("Shuffle")
	if shuffleBtn then
		shuffleBtn.MouseButton1Click:Connect(function()
			if ClientBridge.Call("TutorialAllowsAction", "shuffle") == false then
				return
			end
			shuffleLetters(function()
				ClientBridge.Call("OnTutorialShuffleUsed")
			end)
		end)
	end

	-- Connect star button (bonus hint)
	local starBtn = (gameButtons and gameButtons:FindFirstChild("Star")) or wheelRoot:FindFirstChild("Star")
	if starBtn then
		starBtn.MouseButton1Click:Connect(function()
			if not InputState:IsEnabled() or not levelData then return end
			if ClientBridge.Call("TutorialAllowsAction", "bonus") == false then
				return
			end
			ClientBridge.Call("ShowBonusWords")
		end)
	end

	-- Connect arrow button (paid tile reveal mode)
	local arrowBtn = (gameButtons and gameButtons:FindFirstChild("Arrow")) or wheelRoot:FindFirstChild("Arrow")
	if arrowBtn then
		arrowBtn.MouseButton1Click:Connect(function()
			if not InputState:IsEnabled() or not levelData then return end
			if ClientBridge.Call("TutorialAllowsAction", "arrow") == false then
				return
			end
			ClientBridge.Call("StartArrowSelection")
		end)
	end

	setupInput()
	controllerGamepadActive = isGamepadInputType(UserInputService:GetLastInputType())
	refreshControllerUiState()
end


function LetterWheel:LoadLevel(data)
	levelData = data
	pendingBuildToken += 1
	local buildToken = pendingBuildToken
	
	-- Update colors from level data
	levelColor = data.levelColor or Color3.fromRGB(255, 210, 45)
	COL_LETTER_SEL = levelColor
	COL_LINE = levelColor
	
	-- Update InputBar background color
	local inputBar = wheelRoot and wheelRoot:FindFirstChild("InputBar")
	if inputBar then
		local bg = inputBar:FindFirstChild("Background")
		if bg then
			bg.BackgroundColor3 = levelColor
			bg.BackgroundTransparency = 1
		end
	end

	for _, btn in ipairs(letterBtns) do
		if btn.frame and btn.frame.Parent then
			btn.frame:Destroy()
		end
	end
	letterBtns = {}
	selected = {}
	selectedSet = {}
	clearLines()
	if currentWordLabel then
		currentWordLabel.Text = ""
	end

	task.delay(WHEEL_LAYOUT_SETTLE_DELAY, function()
		if buildToken ~= pendingBuildToken then
			return
		end
		buildLetters(data.letters)
		controllerFocusIndex = (#letterBtns > 0) and 1 or nil
		updateTutorialLetterAvailability()
		refreshControllerUiState()
	end)
end

function LetterWheel:SetLettersHiddenState()
	setLettersHiddenState()
end

function LetterWheel:AnimateLettersIn(duration)
	animateLettersIn(duration)
end

function LetterWheel:AnimateLettersOut(duration, destroyAfter)
	animateLettersOut(duration, destroyAfter)
end


function LetterWheel:FlashInvalid()
	local inputBar = wheelRoot and wheelRoot:FindFirstChild("InputBar")
	local bg = inputBar and inputBar:FindFirstChild("Background")
	local label = currentWordLabel
	if not bg then return end

	cancelInvalidVisualState(false)
	if not inputBgBasePos then
		inputBgBasePos = bg.Position
	end
	bg.Position = inputBgBasePos
	local token = invalidAnimToken

	local origText = label and label.Text or ""
	local origTextColor = label and label.TextColor3

	bg.BackgroundTransparency = 0
	bg.BackgroundColor3 = levelColor
	if label then
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextTransparency = 0
	end

	invalidShakeTween = TweenService:Create(bg, TweenInfo.new(0.035, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, 3, true), {
		Position = inputBgBasePos + UDim2.fromOffset(6, 0)
	})
	invalidShakeTween:Play()

	task.delay(0.26, function()
		if token ~= invalidAnimToken then
			return
		end
		if invalidShakeTween then
			invalidShakeTween:Cancel()
			invalidShakeTween = nil
		end
		bg.Position = inputBgBasePos
		bg.BackgroundColor3 = levelColor
		bg.BackgroundTransparency = 0
		if label then
			label.TextTransparency = 0
			label.TextColor3 = origTextColor or Color3.fromRGB(255, 255, 255)
		end
	end)

	task.delay(0.4, function()
		if token ~= invalidAnimToken then
			return
		end
		if dragging or #selected > 0 then
			return
		end
		if label and label.Text == origText then
			label.Text = ""
		end
		bg.BackgroundTransparency = 1
	end)
end


function LetterWheel:FlashValid()
	cancelInvalidVisualState(true)
	if not wheelFrame then
		return
	end

	if validPulseTween then
		validPulseTween:Cancel()
		validPulseTween = nil
	end

	local pulse = Instance.new("Frame")
	pulse.Name = "WheelValidPulse"
	pulse.AnchorPoint = Vector2.new(0.5, 0.5)
	pulse.Position = UDim2.fromScale(0.5, 0.5)
	pulse.Size = UDim2.fromScale(1, 1)
	pulse.BackgroundTransparency = 1
	pulse.BorderSizePixel = 0
	pulse.ZIndex = 30
	pulse.Parent = wheelFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pulse

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(116, 238, 148)
	stroke.Thickness = 2
	stroke.Transparency = 0.1
	stroke.Parent = pulse

	local sizeTween = TweenService:Create(pulse, TweenInfo.new(0.33, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1.08, 1.08),
	})
	local strokeTween = TweenService:Create(stroke, TweenInfo.new(0.33, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Thickness = 6,
		Transparency = 1,
	})

	validPulseTween = sizeTween
	sizeTween:Play()
	strokeTween:Play()
	sizeTween.Completed:Connect(function()
		if pulse and pulse.Parent then
			pulse:Destroy()
		end
		validPulseTween = nil
	end)
end

function LetterWheel:GetWheelCenter()
	if not wheelFrame then return nil end
	local pos = wheelFrame.AbsolutePosition
	local size = wheelFrame.AbsoluteSize
	return Vector2.new(
		pos.X + size.X / 2,
		pos.Y + size.Y / 2
	)
end

function LetterWheel:GetGuidePathForWord(word)
	if typeof(word) ~= "string" or word == "" then
		return nil
	end
	local upper = string.upper(word)
	local used = {}
	local points = {}

	for i = 1, #upper do
		local ch = upper:sub(i, i)
		local chosen = nil
		for idx, btn in ipairs(letterBtns) do
			if not used[idx] and btn.letter == ch then
				chosen = idx
				break
			end
		end
		if not chosen then
			return nil
		end
		used[chosen] = true
		table.insert(points, frameCentre(letterBtns[chosen].frame))
	end

	return points
end

function LetterWheel:GetHintButton()
	if gameButtons then
		local hint = gameButtons:FindFirstChild("Hint")
		if hint then
			return hint
		end
	end
	return wheelRoot and wheelRoot:FindFirstChild("HintButton")
end

function LetterWheel:RefreshTutorialAvailability()
	updateTutorialLetterAvailability()
	refreshControllerUiState()
end

return LetterWheel
