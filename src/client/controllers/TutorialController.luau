local TweenService = game:GetService("TweenService")
local ClientBridge = require(script.Parent.Parent.core.ClientBridge)

local TutorialController = {}

local state = {
	hud = nil,
	gameScreen = nil,
	UIManager = nil,
	RemoteRegistry = nil,
	LetterWheel = nil,
	GameBoard = nil,
	LevelSelect = nil,
	InputState = nil,
	GroupRewardPanel = nil,
	applyLobbyScenary = nil,
	forceTesting = false,
	forceReplay = false,
	tutorialCompleted = false,
	tutorialState = nil,
	tutorialPathDuration = 3.8,
	animateGameHudOut = nil,
}

local TUTORIAL_FRAME_TWEEN_DURATION = 1.02
local TUTORIAL_UI_FADE_MULTIPLIER = 1.2
local TUTORIAL_ACTION_FOCUS_DELAY = 0.85
local TUTORIAL_HINT_REVEAL_DELAY = 0.6
local TUTORIAL_HINT_STEP_ADVANCE_DELAY = 1.55

local TUTORIAL_STEP_COUNT = 8
local setTutorialStep
local queueAutoAdvance
local drawTutorialGuide
local getTutorialTargetWord

local function isCurrentTutorial(tutorialState, expectedStep)
	return tutorialState ~= nil
		and state.tutorialState == tutorialState
		and tutorialState.active == true
		and (expectedStep == nil or tutorialState.step == expectedStep)
end

local function hasCompletedTutorialWords(tutorialState)
	local requiredCount = math.min(3, #(tutorialState.words or {}))
	if requiredCount < 1 then
		return false
	end
	for index = 1, requiredCount do
		if not tutorialState.solvedWords[tutorialState.words[index]] then
			return false
		end
	end
	return true
end

local function findTutorialSkipButton(overlay)
	for _, descendant in ipairs(overlay:GetDescendants()) do
		if descendant:IsA("GuiButton") and string.find(string.lower(descendant.Name), "skip", 1, true) then
			return descendant
		end
	end
	return nil
end

local function getFallbackTutorialTargetWord()
	local tutorialState = state.tutorialState
	if not tutorialState or not tutorialState.active then
		return nil
	end
	for _, word in ipairs(tutorialState.words or {}) do
		if not tutorialState.solvedWords[word] then
			return word
		end
	end
	return nil
end

local function refreshTutorialGuideNow(word)
	local tutorialState = state.tutorialState
	if not tutorialState or not tutorialState.active then
		return
	end
	tutorialState.guideToken = (tutorialState.guideToken or 0) + 1
	drawTutorialGuide(word or getTutorialTargetWord())
end

local function toLocalPoint(gui, absolutePoint)
	if not (gui and absolutePoint) then
		return nil
	end
	return absolutePoint - gui.AbsolutePosition
end

local function getGuiCenter(gui)
	if not (gui and gui:IsA("GuiObject")) then
		return nil
	end
	return gui.AbsolutePosition + (gui.AbsoluteSize * 0.5)
end

local function getTutorialWords(level)
	local words = {}
	local seen = {}
	for _, slot in ipairs(level and level.wordSlots or {}) do
		local word = tostring(slot.word or ""):upper()
		if word ~= "" and not seen[word] then
			seen[word] = true
			table.insert(words, word)
		end
	end
	return words
end

local function resolveTutorialHintInfo(info)
	local row = tonumber(info and info.row)
	local col = tonumber(info and info.col)
	local letter = tostring(info and info.letter or "")

	if row ~= nil and col ~= nil and letter ~= "" then
		return {
			row = row,
			col = col,
			letter = letter,
			mode = "hint",
		}
	end

	local fallback = state.GameBoard and state.GameBoard.GetFirstHiddenCell and state.GameBoard:GetFirstHiddenCell()
	if not fallback then
		return nil
	end

	local fallbackRow = tonumber(fallback.row)
	local fallbackCol = tonumber(fallback.col)
	local fallbackLetter = tostring(fallback.letter or "")
	if fallbackRow == nil or fallbackCol == nil or fallbackLetter == "" then
		return nil
	end

	return {
		row = fallbackRow,
		col = fallbackCol,
		letter = fallbackLetter,
		mode = "hint",
	}
end

getTutorialTargetWord = function()
	local tutorialState = state.tutorialState
	if not tutorialState or not tutorialState.active then
		return nil
	end
	local orderedWords = tutorialState.words or {}
	if tutorialState.step == 2 then
		return orderedWords[1] or getFallbackTutorialTargetWord()
	elseif tutorialState.step == 6 then
		return orderedWords[2] or getFallbackTutorialTargetWord()
	elseif tutorialState.step == 7 then
		return orderedWords[3] or getFallbackTutorialTargetWord()
	end
	return getFallbackTutorialTargetWord()
end

local function setButtonEnabled(btn, enabled)
	local tutorialState = state.tutorialState
	if not btn or not btn:IsA("GuiButton") or not tutorialState then
		return
	end
	if tutorialState.buttonStates[btn] == nil then
		tutorialState.buttonStates[btn] = {
			active = btn.Active,
			auto = btn.AutoButtonColor,
		}
	end
	btn.Active = enabled
	btn.AutoButtonColor = enabled
end

local function restoreTutorialButtons()
	local tutorialState = state.tutorialState
	if not tutorialState then
		return
	end
	for btn, entry in pairs(tutorialState.buttonStates) do
		if btn and btn.Parent then
			btn.Active = entry.active
			btn.AutoButtonColor = entry.auto
		end
	end
end

local function clearTutorialLines()
	local tutorialState = state.tutorialState
	if not tutorialState or not tutorialState.guideLayer then
		return
	end
	if tutorialState.pointerTween then
		tutorialState.pointerTween:Cancel()
		tutorialState.pointerTween = nil
	end
	for _, child in ipairs(tutorialState.guideLayer:GetChildren()) do
		if child.Name:match("^GuideLine_") or child.Name:match("^GuideDot_") then
			child:Destroy()
		end
	end
	if tutorialState.pointer then
		tutorialState.pointer.Visible = false
	end
end

local function pulseTutorialGuide(guiObject, token, minTransparency, maxTransparency, duration)
	if not guiObject then
		return
	end
	task.spawn(function()
		while state.tutorialState and state.tutorialState.active and state.tutorialState.guideToken == token and guiObject.Parent do
			guiObject.BackgroundTransparency = maxTransparency
			local fadeIn = TweenService:Create(guiObject, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				BackgroundTransparency = minTransparency,
			})
			fadeIn:Play()
			fadeIn.Completed:Wait()
			if not (state.tutorialState and state.tutorialState.active and state.tutorialState.guideToken == token and guiObject.Parent) then
				return
			end
			local fadeOut = TweenService:Create(guiObject, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				BackgroundTransparency = maxTransparency,
			})
			fadeOut:Play()
			fadeOut.Completed:Wait()
		end
	end)
end

local function styleGuideDot(dot, size)
	dot.Size = UDim2.fromOffset(size, size)
	dot.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
end

local function stopTutorialCellPulse()
	if state.GameBoard and state.GameBoard.StopTutorialCellPulse then
		state.GameBoard:StopTutorialCellPulse()
	end
end

local function tweenTutorialFrame(position, spotlightPoint, spotlightTransparency, spotlightSize)
	local tutorialState = state.tutorialState
	if not tutorialState then
		return
	end
	local tweens = {}
	if tutorialState.tutorialFrame and position then
		table.insert(tweens, TweenService:Create(
			tutorialState.tutorialFrame,
			TweenInfo.new(TUTORIAL_FRAME_TWEEN_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Position = position }
		))
	end
	if tutorialState.spotlight then
		local goals = {}
		if spotlightPoint then
			tutorialState.spotlight.AnchorPoint = Vector2.new(0.5, 0.5)
			goals.Position = UDim2.fromOffset(spotlightPoint.X, spotlightPoint.Y)
		end
		if spotlightTransparency ~= nil then
			goals.ImageTransparency = spotlightTransparency
		end
		if spotlightSize then
			goals.Size = spotlightSize
		elseif tutorialState.defaultSpotlightSize then
			goals.Size = tutorialState.defaultSpotlightSize
		end
		if next(goals) then
			table.insert(tweens, TweenService:Create(
				tutorialState.spotlight,
				TweenInfo.new(TUTORIAL_FRAME_TWEEN_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				goals
			))
		end
	end
	for _, tween in ipairs(tweens) do
		tween:Play()
	end
end

local function setTutorialUiVisible(visible, duration)
	local tutorialState = state.tutorialState
	if not tutorialState then
		return
	end
	local tweenDuration = math.max(0.01, (tonumber(duration) or 0.25) * TUTORIAL_UI_FADE_MULTIPLIER)
	if tutorialState.tutorialFrame then
		if tutorialState.tutorialFrame:IsA("CanvasGroup") then
			TweenService:Create(
				tutorialState.tutorialFrame,
				TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ GroupTransparency = visible and 0 or 1 }
			):Play()
		else
			local descendants = tutorialState.tutorialFrame:GetDescendants()
			table.insert(descendants, tutorialState.tutorialFrame)
			for _, gui in ipairs(descendants) do
				if gui:IsA("UIStroke") then
					TweenService:Create(
						gui,
						TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
						{ Transparency = visible and 0.5 or 1 }
					):Play()
				elseif gui.Name == "Pattern" and (gui:IsA("ImageLabel") or gui:IsA("ImageButton")) then
					TweenService:Create(
						gui,
						TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
						{ ImageTransparency = visible and 0.6 or 1 }
					):Play()
				elseif gui:IsA("TextLabel") or gui:IsA("TextButton") then
					TweenService:Create(
						gui,
						TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
						{
							TextTransparency = visible and 0 or 1,
						}
					):Play()
				elseif gui:IsA("ImageLabel") or gui:IsA("ImageButton") then
					TweenService:Create(
						gui,
						TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
						{
							ImageTransparency = visible and 0 or 1,
							BackgroundTransparency = visible and 0 or 1,
						}
					):Play()
				elseif gui:IsA("Frame") then
					local targetTransparency = visible and 0 or 1
					if gui == tutorialState.tutorialFrame then
						targetTransparency = visible and 0.45 or 1
					end
					TweenService:Create(
						gui,
						TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
						{ BackgroundTransparency = targetTransparency }
					):Play()
				end
			end
		end
	end
	if tutorialState.spotlight then
		TweenService:Create(
			tutorialState.spotlight,
			TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ ImageTransparency = visible and 0.4 or 1 }
		):Play()
	end
end

local function playFinishConfetti()
	local tutorialState = state.tutorialState
	if not tutorialState then
		return
	end
	local host = tutorialState.overlay
	if not host then
		return
	end

	local colors = {
		Color3.fromRGB(255, 211, 102),
		Color3.fromRGB(255, 138, 175),
		Color3.fromRGB(107, 214, 255),
		Color3.fromRGB(122, 255, 167),
	}

	for i = 1, 22 do
		local piece = Instance.new("Frame")
		piece.Name = "TutorialConfetti"
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Size = UDim2.fromOffset(math.random(8, 13), math.random(14, 20))
		piece.Position = UDim2.fromScale(math.random(8, 92) / 100, -0.08 - (math.random() * 0.08))
		piece.Rotation = math.random(-35, 35)
		piece.BackgroundColor3 = colors[((i - 1) % #colors) + 1]
		piece.BorderSizePixel = 0
		piece.ZIndex = 223
		piece.Parent = host

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 3)
		corner.Parent = piece

		local duration = 1.85 + (math.random() * 0.95)
		local targetX = math.clamp(piece.Position.X.Scale + ((math.random() - 0.5) * 0.18), 0.05, 0.95)
		local drift = math.random(-140, 140)
		local fallTween = TweenService:Create(piece, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(targetX, 1.12),
			Rotation = piece.Rotation + drift,
			BackgroundTransparency = 0.08,
		})
		fallTween:Play()
		task.delay(duration + 0.08, function()
			if piece and piece.Parent then
				piece:Destroy()
			end
		end)
	end
end

local function getTutorialTargets()
	local gameScreen = state.gameScreen
	local wheelRoot = gameScreen and gameScreen:FindFirstChild("WheelRoot")
	local gameButtons = gameScreen and gameScreen:FindFirstChild("Buttons")
	local inGameBar = gameScreen and gameScreen:FindFirstChild("InGameBar")
	local hintBtn = (gameButtons and (gameButtons:FindFirstChild("Hint") or gameButtons:FindFirstChild("HintButton")))
		or (inGameBar and inGameBar:FindFirstChild("HintButton"))
	local arrowBtn = (gameButtons and gameButtons:FindFirstChild("Arrow")) or (wheelRoot and wheelRoot:FindFirstChild("Arrow"))
	local wheel = wheelRoot and wheelRoot:FindFirstChild("Wheel")
	return {
		wheel = wheel,
		hint = hintBtn,
		arrow = arrowBtn,
	}
end

drawTutorialGuide = function(word)
	local tutorialState = state.tutorialState
	if not tutorialState or not tutorialState.guideLayer or not tutorialState.pointer then
		return
	end
	clearTutorialLines()
	word = word or getTutorialTargetWord()
	if not word then
		return
	end
	tutorialState.pointer.Visible = true

	local points = state.LetterWheel.GetGuidePathForWord and state.LetterWheel:GetGuidePathForWord(word)
	if not points or #points < 2 then
		return
	end

	local localPoints = {}
	local guideOrigin = tutorialState.guideLayer.AbsolutePosition
	for i = 1, #points do
		localPoints[i] = points[i] - guideOrigin
	end

	for i = 2, #localPoints do
		local fromPos = localPoints[i - 1]
		local toPos = localPoints[i]
		local diff = toPos - fromPos
		local line = Instance.new("Frame")
		line.Name = "GuideLine_" .. tostring(i)
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Size = UDim2.fromOffset(diff.Magnitude, 6)
		line.Position = UDim2.fromOffset(fromPos.X + diff.X * 0.5, fromPos.Y + diff.Y * 0.5)
		line.Rotation = math.deg(math.atan2(diff.Y, diff.X))
		line.BackgroundColor3 = Color3.fromRGB(255, 232, 164)
		line.BackgroundTransparency = 0.5
		line.BorderSizePixel = 0
		line.ZIndex = 220
		line.Parent = tutorialState.guideLayer
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = line
	end

	tutorialState.pointer.Position = UDim2.fromOffset(localPoints[1].X, localPoints[1].Y)
	tutorialState.pointer.BackgroundTransparency = 0
	tutorialState.pointer.BackgroundColor3 = Color3.fromRGB(255, 220, 110)
	styleGuideDot(tutorialState.pointer, 18)
	local legTime = state.tutorialPathDuration / math.max(1, (#localPoints - 1))
	local moveToken = tutorialState.guideToken
	task.spawn(function()
		for i = 2, #localPoints do
			if not state.tutorialState or not state.tutorialState.active or state.tutorialState.guideToken ~= moveToken then
				return
			end
			local tween = TweenService:Create(
				state.tutorialState.pointer,
				TweenInfo.new(legTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Position = UDim2.fromOffset(localPoints[i].X, localPoints[i].Y) }
			)
			state.tutorialState.pointerTween = tween
			tween:Play()
			tween.Completed:Wait()
			if state.tutorialState and state.tutorialState.guideToken == moveToken then
				state.tutorialState.pointerTween = nil
			end
		end
		if state.tutorialState and state.tutorialState.active and state.tutorialState.guideToken == moveToken then
			tutorialState.pointer.Position = UDim2.fromOffset(localPoints[1].X, localPoints[1].Y)
		end
	end)
end

local function pulseTutorialButton(btn)
	local tutorialState = state.tutorialState
	if not tutorialState or not tutorialState.active or not btn or not btn:IsA("GuiObject") then
		return
	end
	tutorialState.guideToken = (tutorialState.guideToken or 0) + 1
	local token = tutorialState.guideToken
	local baseSize = btn.Size
	task.spawn(function()
		while state.tutorialState and state.tutorialState.active and state.tutorialState.guideToken == token do
			local up = TweenService:Create(btn, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				Size = baseSize + UDim2.fromOffset(7, 7),
			})
			up:Play()
			up.Completed:Wait()
			if not (state.tutorialState and state.tutorialState.active and state.tutorialState.guideToken == token) then
				break
			end
			local down = TweenService:Create(btn, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				Size = baseSize,
			})
			down:Play()
			down.Completed:Wait()
			task.wait(0.65)
		end
		if btn and btn.Parent then
			btn.Size = baseSize
		end
	end)
end

local function loopTutorialDragGuide(word)
	local tutorialState = state.tutorialState
	if not tutorialState or not tutorialState.active then
		return
	end
	tutorialState.guideToken = (tutorialState.guideToken or 0) + 1
	local token = tutorialState.guideToken
	drawTutorialGuide(word or getTutorialTargetWord())
	task.spawn(function()
		while state.tutorialState and state.tutorialState.active and state.tutorialState.guideToken == token do
			local currentWord = word or getTutorialTargetWord()
			task.wait(state.tutorialPathDuration + 0.12)
			if not (state.tutorialState and state.tutorialState.active and state.tutorialState.guideToken == token) then
				return
			end
			drawTutorialGuide(currentWord)
		end
	end)
end

local function refreshTutorialWheelState()
	if state.LetterWheel and state.LetterWheel.RefreshTutorialAvailability then
		state.LetterWheel:RefreshTutorialAvailability()
	end
end

queueAutoAdvance = function(expectedStep, delaySeconds, nextStep)
	local tutorialState = state.tutorialState
	task.delay(delaySeconds, function()
		if isCurrentTutorial(tutorialState, expectedStep) then
			setTutorialStep(nextStep)
		end
	end)
end

local function finishTutorialToLobby(skipCelebration)
	local tutorialState = state.tutorialState
	if not tutorialState or tutorialState.completionStarted then
		return
	end
	tutorialState.completionStarted = true
	state.tutorialCompleted = true
	pcall(function()
		state.RemoteRegistry:GetFunction("MarkTutorialComplete"):InvokeServer()
	end)
	ClientBridge.Call("OnTutorialCompletedClient")
	TutorialController.Cancel()
	state.InputState:SetEnabled(false)
	local function showLobby()
		state.GameBoard:ExitLevel()
		state.LevelSelect:ShowPackList()
		state.applyLobbyScenary()
		state.UIManager:ShowScreen("HomeScreen")
		if state.forceTesting then
			task.delay(0.2, function()
				state.GroupRewardPanel.Open(true)
			end)
		else
			state.GroupRewardPanel.Schedule(1.25)
		end
	end
	if skipCelebration and state.animateGameHudOut then
		state.animateGameHudOut(showLobby)
	else
		showLobby()
	end
end

local function finishTutorialCelebration()
	local tutorialState = state.tutorialState
	if not tutorialState or not tutorialState.active then
		return
	end
	if tutorialState.stepTitle then
		tutorialState.stepTitle.Text = "You Won!"
	end
	if tutorialState.stepDesc then
		tutorialState.stepDesc.Text = "Great job. You are ready to play."
	end
	if tutorialState.status then
		tutorialState.status.Text = string.format("%d/%d", TUTORIAL_STEP_COUNT, TUTORIAL_STEP_COUNT)
	end
	setTutorialUiVisible(true, 0.35)
	tweenTutorialFrame(UDim2.fromScale(0.5, 0.5), nil, 1, nil)
	playFinishConfetti()
	local finishingState = tutorialState
	task.delay(2.4, function()
		if isCurrentTutorial(finishingState, 8) then
			finishTutorialToLobby()
		end
	end)
end

local function focusTutorialAction(expectedStep, framePosition, spotlightPoint, onFocused)
	local tutorialState = state.tutorialState
	task.delay(TUTORIAL_ACTION_FOCUS_DELAY, function()
		if not isCurrentTutorial(tutorialState, expectedStep) then
			return
		end
		tweenTutorialFrame(framePosition, spotlightPoint, 0.28, nil)
		if onFocused then
			onFocused()
		end
	end)
end

setTutorialStep = function(step)
	local tutorialState = state.tutorialState
	if not tutorialState or not tutorialState.active then
		return
	end
	if step == 8 and not hasCompletedTutorialWords(tutorialState) then
		return
	end
	tutorialState.step = step
	local status = tutorialState.status
	local stepTitle = tutorialState.stepTitle
	local stepDesc = tutorialState.stepDesc
	local stepFill = tutorialState.stepFill
	local inGameBar = state.gameScreen:FindFirstChild("InGameBar")
	local gameButtons = state.gameScreen:FindFirstChild("Buttons")
	local hintBtn = (gameButtons and (gameButtons:FindFirstChild("Hint") or gameButtons:FindFirstChild("HintButton")))
		or (inGameBar and inGameBar:FindFirstChild("HintButton"))
	local wheelRoot = state.gameScreen:FindFirstChild("WheelRoot")
	local shuffleBtn = (gameButtons and gameButtons:FindFirstChild("Shuffle")) or (wheelRoot and wheelRoot:FindFirstChild("Shuffle"))
	local starBtn = (gameButtons and gameButtons:FindFirstChild("Star")) or (wheelRoot and wheelRoot:FindFirstChild("Star"))

	setButtonEnabled(hintBtn, false)
	setButtonEnabled(shuffleBtn, false)
	setButtonEnabled(starBtn, false)

	local function setStepText(title, desc)
		if stepTitle then
			stepTitle.Text = title
		end
		if stepDesc then
			stepDesc.Text = desc
		end
		if status then
			status.Text = string.format("%d/%d", step, TUTORIAL_STEP_COUNT)
		end
		if stepFill and stepFill:IsA("GuiObject") then
			local alpha = math.clamp(step / TUTORIAL_STEP_COUNT, 0, 1)
			TweenService:Create(
				stepFill,
				TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.fromScale(alpha, 1) }
			):Play()
		end
	end

	tutorialState.guideToken = (tutorialState.guideToken or 0) + 1
	stopTutorialCellPulse()
	local targets = getTutorialTargets()
	local overlayRoot = tutorialState.overlay
	local spotlightPoint = toLocalPoint(overlayRoot, getGuiCenter(targets.wheel))
	local centerStagePosition = UDim2.fromScale(0.5, 0.28)
	local wheelActionPosition = UDim2.fromScale(0.5, 0.18)
	local framePosition = centerStagePosition
	local spotlightSize = nil

	if step == 1 then
		setStepText("Welcome", "We will show you how to play.")
		framePosition = centerStagePosition
		spotlightPoint = nil
		clearTutorialLines()
		if tutorialState.pointer then
			tutorialState.pointer.Visible = false
		end
		queueAutoAdvance(1, 1.8, 2)
	elseif step == 2 then
		setStepText("Let's Start", "Follow the dot and make the first word.")
		framePosition = centerStagePosition
		spotlightPoint = nil
		clearTutorialLines()
		if tutorialState.pointer then
			tutorialState.pointer.Visible = false
		end
		focusTutorialAction(2, wheelActionPosition, toLocalPoint(overlayRoot, getGuiCenter(targets.wheel)), function()
			loopTutorialDragGuide(nil)
		end)
	elseif step == 3 then
		setStepText("Need Help?", "Tap Hint to show one letter.")
		setButtonEnabled(hintBtn, true)
		framePosition = UDim2.fromScale(0.67, 0.56)
		spotlightPoint = toLocalPoint(overlayRoot, getGuiCenter(targets.hint))
		clearTutorialLines()
		pulseTutorialButton(hintBtn)
	elseif step == 4 then
		setStepText("Here Is Your Hint", "A hint shows one letter on the board.")
		framePosition = centerStagePosition
		spotlightPoint = nil
		clearTutorialLines()
		if tutorialState.pointer then
			tutorialState.pointer.Visible = false
		end
		local hintInfo = tutorialState.pendingHintInfo
		local cellCenter = hintInfo and state.GameBoard.GetCellCenter and state.GameBoard:GetCellCenter(hintInfo.row, hintInfo.col)
		if cellCenter then
			focusTutorialAction(4, UDim2.fromScale(0.5, 0.16), toLocalPoint(overlayRoot, cellCenter))
		end
	elseif step == 5 then
		setStepText("Mix It Up", "Tap Shuffle to move the letters.")
		setButtonEnabled(shuffleBtn, true)
		framePosition = centerStagePosition
		spotlightPoint = toLocalPoint(overlayRoot, getGuiCenter(shuffleBtn))
		clearTutorialLines()
		pulseTutorialButton(shuffleBtn)
	elseif step == 6 then
		setStepText("Next Word", "Great. Now make the next word.")
		framePosition = centerStagePosition
		spotlightPoint = nil
		clearTutorialLines()
		if tutorialState.pointer then
			tutorialState.pointer.Visible = false
		end
		focusTutorialAction(6, wheelActionPosition, toLocalPoint(overlayRoot, getGuiCenter(targets.wheel)), function()
			refreshTutorialGuideNow(getTutorialTargetWord())
			loopTutorialDragGuide(nil)
		end)
	elseif step == 7 then
		setStepText("One More", "Make the last word to finish.")
		framePosition = centerStagePosition
		spotlightPoint = nil
		clearTutorialLines()
		if tutorialState.pointer then
			tutorialState.pointer.Visible = false
		end
		focusTutorialAction(7, wheelActionPosition, toLocalPoint(overlayRoot, getGuiCenter(targets.wheel)), function()
			refreshTutorialGuideNow(getTutorialTargetWord())
			loopTutorialDragGuide(nil)
		end)
	elseif step == 8 then
		setStepText("All Done", "Nice work. You did it.")
		clearTutorialLines()
		if tutorialState.pointer then
			tutorialState.pointer.Visible = false
		end
		setTutorialUiVisible(false, 0.25)
		if state.GameBoard and state.GameBoard.OnDailyComplete then
			state.InputState:SetEnabled(false)
			state.GameBoard:OnDailyComplete(nil, function()
				if state.animateGameHudOut then
					state.animateGameHudOut(finishTutorialCelebration)
				else
					finishTutorialCelebration()
				end
			end)
		else
			finishTutorialCelebration()
		end
		return
	end
	refreshTutorialWheelState()
	tweenTutorialFrame(framePosition, spotlightPoint, 0.28, spotlightSize)
	setTutorialUiVisible(true, 0.7)
end

function TutorialController.Init(options)
	for key, value in pairs(options or {}) do
		state[key] = value
	end
	ClientBridge.SetCallback("IsTutorialActive", function()
		return state.tutorialState ~= nil and state.tutorialState.active == true
	end)
	ClientBridge.SetCallback("GetTutorialTargetWord", function()
		return getTutorialTargetWord()
	end)
	ClientBridge.SetCallback("TutorialAllowsAction", function(action)
		local tutorialState = state.tutorialState
		if not tutorialState or not tutorialState.active then
			return true
		end
		if action == "drag" then
			return tutorialState.step == 2 or tutorialState.step == 6 or tutorialState.step == 7
		elseif action == "hint" then
			return tutorialState.step == 3
		elseif action == "bonus" then
			return false
		elseif action == "shuffle" then
			return tutorialState.step == 5
		elseif action == "arrow" then
			return false
		end
		return false
	end)
	ClientBridge.SetCallback("OnTutorialArrowUsed", function()
		TutorialController.OnArrowUsed()
	end)
	ClientBridge.SetCallback("OnTutorialShuffleUsed", function()
		TutorialController.OnShuffleUsed()
	end)
end

function TutorialController.Begin(level)
	if ((not state.forceTesting) and (not state.forceReplay) and state.tutorialCompleted) or not level or state.tutorialState then
		return false
	end
	local overlay = state.hud:FindFirstChild("TutorialOverlay")
	if not overlay or not overlay:IsA("GuiObject") then
		return false
	end
	overlay.Visible = true
	overlay.ZIndex = 220

	local background = overlay:FindFirstChild("Background")
	local spotlight = overlay:FindFirstChild("Spotlight")
	local tutorialFrame = overlay:FindFirstChild("TutorialFrame")
	local status = tutorialFrame and tutorialFrame:FindFirstChild("Status")
	local stepTitle = tutorialFrame and tutorialFrame:FindFirstChild("Title")
	local stepDesc = tutorialFrame and (tutorialFrame:FindFirstChild("Subtitle") or tutorialFrame:FindFirstChild("Subtiel"))
	local progressBar = tutorialFrame and tutorialFrame:FindFirstChild("ProgressBar")
	local stepFill = progressBar and progressBar:FindFirstChild("Fill")
	local skipButton = findTutorialSkipButton(overlay)

	local wheelRoot = state.gameScreen:FindFirstChild("WheelRoot")
	local guideLayer = nil
	if wheelRoot then
		guideLayer = Instance.new("Frame")
		guideLayer.Name = "TutorialGuideLayer"
		guideLayer.BackgroundTransparency = 1
		guideLayer.BorderSizePixel = 0
		guideLayer.Size = UDim2.fromScale(1, 1)
		guideLayer.ZIndex = 220
		guideLayer.Parent = wheelRoot
	end

	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Size = UDim2.fromOffset(18, 18)
	pointer.Position = UDim2.new(0.5, 0, 0.7, 0)
	pointer.BackgroundColor3 = Color3.fromRGB(255, 220, 110)
	pointer.BorderSizePixel = 0
	pointer.ZIndex = 221
	pointer.Parent = guideLayer or overlay
	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(1, 0)
	pCorner.Parent = pointer

	state.tutorialState = {
		active = true,
		overlay = overlay,
		background = background,
		spotlight = spotlight,
		tutorialFrame = tutorialFrame,
		guideLayer = guideLayer or overlay,
		status = status,
		stepTitle = stepTitle,
		stepDesc = stepDesc,
		stepFill = stepFill,
		pointer = pointer,
		words = getTutorialWords(level),
		solvedWords = {},
		step = 0,
		guideToken = 0,
		buttonStates = {},
		completionStarted = false,
		defaultSpotlightSize = spotlight and spotlight.Size or nil,
	}
	if skipButton and skipButton:IsA("GuiButton") and not skipButton:GetAttribute("TutorialSkipWired") then
		skipButton:SetAttribute("TutorialSkipWired", true)
		skipButton.MouseButton1Click:Connect(function()
			TutorialController.Skip()
		end)
	end

	if spotlight and spotlight:IsA("ImageLabel") then
		spotlight.AnchorPoint = Vector2.new(0.5, 0.5)
		spotlight.ImageTransparency = 1
	end
	if tutorialFrame and tutorialFrame:IsA("GuiObject") then
		tutorialFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	end
	if stepFill and stepFill:IsA("GuiObject") then
		stepFill.Size = UDim2.fromScale(0, 1)
	end
	setTutorialUiVisible(false, 0.01)

	local inGameBar = state.gameScreen:FindFirstChild("InGameBar")
	local gameButtons = state.gameScreen:FindFirstChild("Buttons")
	local currencyBtn = (gameButtons and gameButtons:FindFirstChild("Currency")) or state.gameScreen:FindFirstChild("Currency")
	if inGameBar then
		for _, child in ipairs(inGameBar:GetChildren()) do
			setButtonEnabled(child, false)
		end
	end
	if wheelRoot then
		setButtonEnabled((gameButtons and gameButtons:FindFirstChild("Shuffle")) or wheelRoot:FindFirstChild("Shuffle"), false)
		setButtonEnabled((gameButtons and gameButtons:FindFirstChild("Star")) or wheelRoot:FindFirstChild("Star"), false)
	end
	setButtonEnabled(currencyBtn, false)
	setTutorialStep(1)
	return true
end

function TutorialController.OnWordFound(result)
	if not state.tutorialState or not state.tutorialState.active or not result or not result.valid then
		return
	end
	if result.isBonus then
		return
	end
	local tutorialState = state.tutorialState
	local foundWord = tostring(result.word or ""):upper()
	local expectedWord = getTutorialTargetWord()
	if foundWord == "" or expectedWord == nil or foundWord ~= expectedWord then
		return
	end
	tutorialState.solvedWords[foundWord] = true
	tutorialState.guideToken = (tutorialState.guideToken or 0) + 1
	clearTutorialLines()
	if tutorialState.pointer then
		tutorialState.pointer.Visible = false
	end
	if tutorialState.step == 2 then
		task.delay(1.9, function()
			if isCurrentTutorial(tutorialState, 2) then
				setTutorialStep(3)
			end
		end)
	elseif tutorialState.step == 6 then
		task.delay(1.9, function()
			if isCurrentTutorial(tutorialState, 6) then
				if hasCompletedTutorialWords(tutorialState) then
					setTutorialStep(8)
				else
					setTutorialStep(7)
				end
			end
		end)
	elseif tutorialState.step == 7 then
		task.delay(1.9, function()
			if isCurrentTutorial(tutorialState, 7) and hasCompletedTutorialWords(tutorialState) then
				setTutorialStep(8)
			end
		end)
	end
end

function TutorialController.Skip()
	local tutorialState = state.tutorialState
	if not tutorialState or not tutorialState.active or tutorialState.completionStarted then
		return false
	end
	finishTutorialToLobby(true)
	return true
end

function TutorialController.OnHintUsed(info)
	if state.tutorialState and state.tutorialState.active and state.tutorialState.step == 3 and info and info.mode == "hint" then
		local tutorialState = state.tutorialState
		local hintInfo = resolveTutorialHintInfo(info)
		if not hintInfo then
			return
		end
		state.tutorialState.lastHintCell = {
			row = hintInfo.row,
			col = hintInfo.col,
		}
		state.tutorialState.pendingHintInfo = {
			row = hintInfo.row,
			col = hintInfo.col,
			letter = hintInfo.letter,
			mode = "hint",
		}
		setTutorialStep(4)
		task.delay(TUTORIAL_HINT_REVEAL_DELAY, function()
			if not isCurrentTutorial(tutorialState, 4) then
				return
			end
			local pendingHintInfo = tutorialState.pendingHintInfo
			if pendingHintInfo and state.GameBoard and state.GameBoard.RevealHintCell then
				state.GameBoard:RevealHintCell(pendingHintInfo)
			end
		end)
		task.delay(TUTORIAL_HINT_STEP_ADVANCE_DELAY, function()
			if isCurrentTutorial(tutorialState, 4) then
				setTutorialStep(5)
			end
		end)
	end
end

function TutorialController.OnArrowModeStarted()
end

function TutorialController.OnArrowUsed()
end

function TutorialController.OnShuffleUsed()
	if state.tutorialState and state.tutorialState.active and state.tutorialState.step == 5 then
		refreshTutorialGuideNow()
		if hasCompletedTutorialWords(state.tutorialState) then
			setTutorialStep(8)
		else
			setTutorialStep(6)
		end
	end
end

function TutorialController.PrepareWordTransition(result)
	if not state.tutorialState or not state.tutorialState.active or not result or not result.valid or result.isBonus then
		return
	end
	stopTutorialCellPulse()
	state.tutorialState.guideToken = (state.tutorialState.guideToken or 0) + 1
	clearTutorialLines()
	if state.tutorialState.pointer then
		state.tutorialState.pointer.Visible = false
	end
	setTutorialUiVisible(false, 0.55)
end

function TutorialController.Cancel()
	if state.tutorialState then
		state.tutorialState.active = false
		stopTutorialCellPulse()
		restoreTutorialButtons()
		if state.tutorialState.spotlight and state.tutorialState.spotlight.Parent then
			state.tutorialState.spotlight.ImageTransparency = 1
		end
		if state.tutorialState.overlay and state.tutorialState.overlay.Parent then
			state.tutorialState.overlay.Visible = false
		end
		local overlay = state.tutorialState.overlay
		if overlay then
			for _, child in ipairs(overlay:GetChildren()) do
				if child.Name == "TutorialConfetti" then
					child:Destroy()
				end
			end
		end
		if state.tutorialState.guideLayer and state.tutorialState.guideLayer ~= state.tutorialState.overlay and state.tutorialState.guideLayer.Parent then
			state.tutorialState.guideLayer:Destroy()
		end
		state.tutorialState = nil
	end
end

function TutorialController.IsActive()
	return state.tutorialState ~= nil and state.tutorialState.active == true
end

function TutorialController.IsCompleted()
	return state.tutorialCompleted == true
end

function TutorialController.SetCompleted(value)
	state.tutorialCompleted = value == true
end

return TutorialController
