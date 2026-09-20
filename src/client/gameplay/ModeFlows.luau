local TweenService = game:GetService("TweenService")

local ModeFlows = {}
local ClientBridge = require(script.Parent.Parent.core.ClientBridge)

local state = {}

local TIMED_MODES = {
	classic = { label = "Classic", desc = "120s standard", duration = 120, reward = 130 },
	brutal = { label = "Brutal", desc = "75s hard", duration = 75, reward = 220 },
}

local function getTimedModeUi()
	local gameScreen = state.gameScreen
	if not gameScreen then
		return nil, nil, nil, nil
	end
	local inGameBar = gameScreen:FindFirstChild("InGameBar")
	local levelLabel = gameScreen:FindFirstChild("LevelLabel") or (inGameBar and inGameBar:FindFirstChild("LevelLabel"))
	local timedRoot = gameScreen:FindFirstChild("TimedMode")
	local fill = timedRoot and timedRoot:FindFirstChild("Fill", true)
	local timerLabel = timedRoot and (timedRoot:FindFirstChild("timer", true) or timedRoot:FindFirstChild("Timer", true))
	return timedRoot, fill, timerLabel, levelLabel
end

local function requestNextTimedPuzzle()
	if not state.getIsTimedMode() then
		return false
	end
	local resp = state.RemoteRegistry:GetFunction("GetTimedModeLevel"):InvokeServer()
	if resp and resp.success and resp.levelData then
		local timedModeState = state.getTimedModeState()
		if timedModeState then
			timedModeState.endsAt = os.clock() + (tonumber(resp.remaining) or 0)
			timedModeState.solvedCount = tonumber(resp.solvedCount) or (timedModeState.solvedCount or 0)
		end
		state.clearGuessedBonusWords()
		if state.bonusWordsFrame then
			state.bonusWordsFrame.Visible = false
		end
		state.InputState:SetEnabled(true)
		state.GameBoard:QuickSwapLevel(resp.levelData, { speedScale = 2 / 3 })
		state.LetterWheel:LoadLevel(resp.levelData)
		state.applyGameScenaryForPack(resp.levelData.packId)
		return true
	end
	if resp and resp.expired then
		local endResp = state.RemoteRegistry:GetFunction("FinishTimedMode"):InvokeServer()
		ModeFlows.FinishTimedToLobby(endResp and endResp.reward, endResp and endResp.coins, endResp and endResp.solvedCount)
		return false
	end
	task.delay(0.2, function()
		if state.getIsTimedMode() then
			requestNextTimedPuzzle()
		end
	end)
	return false
end

local function runTimedModeCountdown()
	local timedModeState = state.getTimedModeState()
	if not state.getIsTimedMode() or not timedModeState then
		return
	end
	local timedRoot, fill, timerLabel, levelLabel = getTimedModeUi()
	local token = state.getTimedMatchToken() + 1
	state.setTimedMatchToken(token)
	local fullDuration = math.max(1, tonumber(timedModeState.duration) or math.floor((timedModeState.endsAt or os.clock()) - os.clock()))
	if timedRoot and timedRoot:IsA("GuiObject") then
		timedRoot.Visible = true
	end
	if levelLabel and levelLabel:IsA("GuiObject") then
		levelLabel.Visible = false
	end

	task.spawn(function()
		while state.getIsTimedMode() and token == state.getTimedMatchToken() and state.getTimedModeState() do
			local activeState = state.getTimedModeState()
			local remaining = math.max(0, math.floor((activeState.endsAt or os.clock()) - os.clock()))
			local ratio = math.clamp(remaining / fullDuration, 0, 1)
			if timerLabel and timerLabel:IsA("TextLabel") then
				timerLabel.Text = tostring(remaining) .. "s"
			end
			if fill and fill:IsA("GuiObject") then
				local targetColor
				if ratio > 0.5 then
					local alpha = (ratio - 0.5) / 0.5
					targetColor = Color3.fromRGB(255, 170, 50):Lerp(Color3.fromRGB(35, 255, 79), alpha)
				else
					local alpha = ratio / 0.5
					targetColor = Color3.fromRGB(255, 70, 70):Lerp(Color3.fromRGB(255, 170, 50), alpha)
				end
				TweenService:Create(fill, TweenInfo.new(0.18, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
					Size = UDim2.fromScale(ratio, 1),
					BackgroundColor3 = targetColor,
				}):Play()
			end
			if remaining <= 0 then
				state.InputState:SetEnabled(false)
				local resp = state.RemoteRegistry:GetFunction("FinishTimedMode"):InvokeServer()
				ModeFlows.FinishTimedToLobby(resp and resp.reward, resp and resp.coins, resp and resp.solvedCount)
				return
			end
			task.wait(0.2)
		end
	end)
end

function ModeFlows.Init(options)
	state = options or {}
end

function ModeFlows.StopTimedModeTimer()
	state.setTimedMatchToken(state.getTimedMatchToken() + 1)
	state.setTimedModeState(nil)
	if state.setTimedExitPending then
		state.setTimedExitPending(false)
	end
	local timedRoot, fill, timerLabel, levelLabel = getTimedModeUi()
	if timedRoot and timedRoot:IsA("GuiObject") then
		timedRoot.Visible = false
	end
	if timerLabel and timerLabel:IsA("TextLabel") then
		timerLabel.Text = "0s"
	end
	if fill and fill:IsA("GuiObject") then
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Color3.fromRGB(35, 255, 79)
	end
end

function ModeFlows.FinishTimedToLobby(extraReward, finalCoins, solvedCount)
	local timedModeState = state.getTimedModeState()
	local localSolvedCount = tonumber(timedModeState and timedModeState.solvedCount) or 0
	local finalSolvedCount = tonumber(solvedCount)
	if finalSolvedCount == nil then
		finalSolvedCount = localSolvedCount
	end
	state.setIsTimedMode(false)
	state.setIsPvPMatch(false)
	state.setIsDailyPuzzleMode(false)
	state.setIsHardcoreMode(false)
	ClientBridge.SetState("IsHardcoreMode", false)
	ModeFlows.StopTimedModeTimer()
	state.cancelOnboardingTutorial()
	state.InputState:SetEnabled(false)
	state.GameBoard:OnDailyComplete(nil, function()
		state.transitionFinishedGameToHome(function()
			if state.onCoinsUpdated and finalCoins then
				state.onCoinsUpdated(finalCoins)
			end
			local summary = "Score: " .. tostring(finalSolvedCount)
			if (extraReward or 0) > 0 then
				summary = summary .. " | Reward: +" .. tostring(extraReward) .. " coins"
			end
			state.openGeneralInfo("Timed Mode", summary, {
				showAccept = true,
				acceptText = "Okay",
			})
		end)
	end)
end

function ModeFlows.RequestNextTimedPuzzle()
	return requestNextTimedPuzzle()
end

function ModeFlows.StartTimedMode(payload)
	local data = payload and payload.levelData
	if not data then
		state.UIManager:ShowAlert("Failed to start timed mode", "error")
		return
	end
	state.setIsTimedMode(true)
	state.setIsPvPMatch(false)
	state.setIsDailyPuzzleMode(false)
	state.setIsHardcoreMode(false)
	ClientBridge.SetState("IsHardcoreMode", false)
	state.clearGuessedBonusWords()
	if state.bonusWordsFrame then
		state.bonusWordsFrame.Visible = false
	end
	if state.setTimedExitPending then
		state.setTimedExitPending(false)
	end
	state.setTimedModeState({
		key = tostring(payload.modeKey or "classic"),
		label = tostring(payload.modeLabel or "Timed"),
		reward = tonumber(payload.rewardCoins) or 0,
		duration = tonumber(payload.duration) or 100,
		endsAt = os.clock() + (tonumber(payload.duration) or 100),
		solvedCount = tonumber(payload.solvedCount) or 0,
	})
	state.InputState:SetEnabled(true)
	state.GameBoard:LoadLevel(data)
	state.LetterWheel:LoadLevel(data)
	state.applyGameScenaryForPack(data.packId)
	state.showLoadedGameScreen()
	local _, _, _, levelLabel = getTimedModeUi()
	if levelLabel and levelLabel:IsA("GuiObject") then
		levelLabel.Visible = false
	end
	runTimedModeCountdown()
end

function ModeFlows.StartHardcoreMode(payload)
	local data = payload and payload.levelData
	if not data then
		state.UIManager:ShowAlert("Failed to start hardcore", "error")
		return
	end
	state.setIsHardcoreMode(true)
	state.setIsTimedMode(false)
	state.setIsPvPMatch(false)
	state.setIsDailyPuzzleMode(false)
	ModeFlows.StopTimedModeTimer()
	state.setHardcoreState({ streak = tonumber(payload.streak) or 0 })
	ClientBridge.SetState("IsHardcoreMode", true)

	state.InputState:SetEnabled(true)
	state.clearGuessedBonusWords()
	if state.bonusWordsFrame then
		state.bonusWordsFrame.Visible = false
	end
	state.GameBoard:LoadLevel(data)
	state.LetterWheel:LoadLevel(data)
	state.applyGameScenaryForPack(data.packId)
	state.showLoadedGameScreen()
	state.UIManager:ShowAlert("Hardcore active: no hints, no accuracy, no shuffle", "error")
end

function ModeFlows.StopHardcoreMode(goToLobby)
	if not state.getIsHardcoreMode() then
		return
	end
	local resp = state.RemoteRegistry:GetFunction("FinishHardcoreMode"):InvokeServer()
	local streak = tonumber(resp and resp.streak) or 0
	local best = tonumber(resp and resp.best) or streak
	local coins = tonumber(resp and resp.coins) or nil
	state.setIsHardcoreMode(false)
	state.setHardcoreState(nil)
	ClientBridge.SetState("IsHardcoreMode", false)
	state.InputState:SetEnabled(false)
	if state.onCoinsUpdated and coins then
		state.onCoinsUpdated(coins)
	end
	state.UIManager:ShowAlert(("Hardcore ended. Run %d | Best %d"):format(streak, best), "bonus")
	if goToLobby ~= false then
		state.transitionFinishedGameToHome()
	end
end

function ModeFlows.StartTimedModeFromHome(modeKey)
	local resp = state.RemoteRegistry:GetFunction("StartTimedMode"):InvokeServer(modeKey or "classic")
	if resp and resp.success then
		local panel = state.frames and state.frames:FindFirstChild("TimedModePanel")
		if panel and panel:IsA("Frame") then
			panel.Visible = false
		end
		ModeFlows.StartTimedMode(resp)
	else
		state.UIManager:ShowAlert((resp and resp.message) or "Could not start timed mode", "error")
	end
end

ModeFlows.TIMED_MODES = TIMED_MODES

return ModeFlows
