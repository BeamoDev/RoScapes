-- ServerMain.server.luau
-- Server entry point.


local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TextService        = game:GetService("TextService")
local DataStoreService   = game:GetService("DataStoreService")

local Server = script.Parent

-- Create all remotes FIRST
local RemoteRegistry = require(ReplicatedStorage:WaitForChild("Shared").RemoteRegistry)
RemoteRegistry.EnsureRemotes()

-- Load services
local DataService  = require(Server.services.DataService)
local LevelService = require(Server.services.LevelService)
local GameService  = require(Server.services.GameService)
local DailyPuzzleService = require(Server.services.DailyPuzzleService)
local DailyQuestService = require(Server.services.DailyQuestService)
local AchievementService = require(Server.services.AchievementService)
local BadgeAwardService = require(Server.services.BadgeAwardService)
local DailyLoginService = require(Server.services.DailyLoginService)
local WebhookService = require(Server.services.WebhookService)
local FlagService = require(Server.services.FlagService)
local ModerationConfig = require(Server.services.ModerationConfig)
local RankService = require(Server.services.RankService)
local LevelPayloadService = require(Server.services.LevelPayloadService)
local FreeplayService = require(Server.services.FreeplayService)
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MonetizationConfig"))
require(Server.services.Anti_AFK_Kick)
local ARROW_COST_COINS = 75
local PVP_ARROW_COST_COINS = 75
local NORMAL_HINT_REFILL_COIN_COST = 150
local TIMED_ARROW_COST_COINS = ARROW_COST_COINS
local AUTOSAVE_INTERVAL_SECONDS = 180
local AUTOSAVE_POLL_SECONDS = 5
local AUTOSAVE_WRITE_SPACING_SECONDS = 0.2
local AUTOSAVE_RETRY_BASE_SECONDS = 15
local AUTOSAVE_RETRY_MAX_SECONDS = 180
local AUTOSAVE_STARTUP_JITTER_SECONDS = 30
local AUTOSAVE_REQUEST_TYPE = Enum.DataStoreRequestType.SetIncrementAsync
local PVP_INVITE_EXPIRE_SECONDS = 60
local PVP_INVITE_RESEND_COOLDOWN = 8
local ADMIN_ACTION_COOLDOWN = 30
local GROUP_REWARD_GROUP_ID = 34241464
local GROUP_REWARD_COINS = 63
local BOARD_SAVE_SUBSCRIPTION_ID = 55555555
local filterTextForBroadcast
local getFilteredWordPayload
local GROUP_REWARD_HINTS = 2
local TIMED_MODES = {
	quick = { label = "Quick 90s", duration = 90, rewardCoins = 45, packMin = 1, packMax = 2 },
	classic = { label = "Classic 100s", duration = 100, rewardCoins = 65, packMin = 2, packMax = 3 },
	brutal = { label = "Brutal 75s", duration = 75, rewardCoins = 110, packMin = 3, packMax = 4 },
}
local pvpInvitesByTarget = {} -- [targetUserId] = { [inviterUserId] = inviteData }
local pvpMatchByPlayer = {} -- [userId] = matchId
local pvpMatches = {} -- [matchId] = matchData
local timedMatchByPlayer = {} -- [userId] = {modeKey, rewardCoins, expiresAt, packId, levelId}
local hardcoreRunByPlayer = {} -- [userId] = {streak}
local sessionPlaytimeClockByPlayer = {} -- [userId] = os.clock()
local pendingSpecialHintPurchaseByPlayer = {} -- [userId] = { kind = string, productId = number, createdAt = os.time() }
local premiumPassOwnershipByPlayer = {} -- [userId] = boolean
local boardSaveSubscriptionStatusByPlayer = {} -- [userId] = boolean
local latestLevelDataRequestTokenByPlayer = {} -- [userId] = number
local autosaveNextAtByPlayer = {} -- [userId] = os.clock timestamp
local autosaveFailureCountByPlayer = {} -- [userId] = integer
local saveInFlightByPlayer = {} -- [userId] = boolean
local adminActionCooldowns = {} -- [adminUserId] = { [actionKey] = expiresAt }
local updateLeaderboard
local dirtyLeaderboardUsers = {}
local flushLeaderboardForUserId
local isLevelDataPlayable
local ADMIN_USER_IDS = {
	[1790165114] = true,
	[123315075] = true,
}
local ADMIN_ACTIONS = {
	give_coins = { coins = 1000, message = "+1000 coins" },
	give_big_coins = { coins = 5000, message = "+5000 coins" },
	give_hints = { hints = 5, message = "+5 hints" },
	give_many_hints = { hints = 25, message = "+25 hints" },
	give_selection_hints = { selectionHints = 3, message = "+3 selection hints" },
	give_many_selection_hints = { selectionHints = 10, message = "+10 selection hints" },
}

local function applyRankedCoinReward(player, baseCoins)
	local data = DataService.getData(player)
	local points = data and data.stats and data.stats.rankPoints or 0
	local coins, rank = RankService.GetCoinReward(baseCoins, points)
	coins = math.max(1, math.floor((coins * 0.5) + 0.5))
	return coins, rank
end

local function addRankProgress(player, amount, reason)
	local gained = math.max(0, math.floor(tonumber(amount) or 0))
	if gained <= 0 then
		return DataService.getRankState(player)
	end
	local before = DataService.getRankState(player)
	local after = DataService.addRankPoints(player, gained)
	if after then
		RemoteRegistry:GetEvent("RankUpdated"):FireClient(player, {
			oldRank = before,
			newRank = after,
			reason = reason or "progress",
			pointsGained = gained,
		})
	end
	if before and after and before.id ~= after.id then
		BadgeAwardService.AwardRank(player, after.id)
	end
	return after
end

local function playerIsInRewardGroup(player)
	if not player then
		return false
	end
	local ok, inGroup = pcall(function()
		return player:IsInGroup(GROUP_REWARD_GROUP_ID)
	end)
	return ok and inGroup == true
end

local function grantGroupReward(player)
	if not player or DataService.getGroupRewardClaimed(player) then
		return false, "already claimed"
	end
	DataService.addCoins(player, GROUP_REWARD_COINS, "GroupReward", "Reward")
	DataService.addHints(player, GROUP_REWARD_HINTS)
	DataService.setGroupRewardClaimed(player, true)
	RemoteRegistry:GetEvent("UpdateCoins"):FireClient(player, DataService.getCoins(player))
	RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
	return true, "granted"
end

local function grantExistingGroupRewardIfEligible(player)
	if not player or DataService.getGroupRewardClaimed(player) then
		return false
	end
	if not playerIsInRewardGroup(player) then
		return false
	end
	return grantGroupReward(player)
end

local function getMatchForPlayer(player)
	local matchId = pvpMatchByPlayer[player.UserId]
	if not matchId then
		return nil
	end
	return pvpMatches[matchId]
end

local function getOpponentInMatch(match, userId)
	if not match then
		return nil
	end
	for _, p in ipairs(match.players) do
		if p.UserId ~= userId then
			return p
		end
	end
	return nil
end

local function getTimedMatch(player)
	return timedMatchByPlayer[player.UserId]
end

local function idsMatch(a, b)
	local aNum = tonumber(a)
	local bNum = tonumber(b)
	if aNum ~= nil and bNum ~= nil then
		return aNum == bNum
	end
	return tostring(a) == tostring(b)
end

local function getHardcoreRun(player)
	return hardcoreRunByPlayer[player.UserId]
end

local function isNormalModeSession(player, session)
	if not player or not session then
		return false
	end
	local packId = tonumber(session.packId) or 0
	if packId <= 0 then
		return false
	end
	if getTimedMatch(player) then
		return false
	end
	if getHardcoreRun(player) then
		return false
	end
	local match = getMatchForPlayer(player)
	if match and not match.completed then
		return false
	end
	return true
end

local function playerOwnsPremiumPass(player)
	if not player then
		return false
	end
	local cached = premiumPassOwnershipByPlayer[player.UserId]
	if cached == true then
		return true
	end
	local passId = MonetizationConfig.Passes and MonetizationConfig.Passes.premium and tonumber(MonetizationConfig.Passes.premium.id) or 0
	if passId <= 0 then
		return false
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	if ok and owns == true then
		premiumPassOwnershipByPlayer[player.UserId] = true
		return true
	end
	return false
end

local function parseSubscriptionStatus(status)
	local function indicatesActive(text)
		local lowered = string.lower(tostring(text or ""))
		return string.find(lowered, "active", 1, true) ~= nil
			or string.find(lowered, "subscribed", 1, true) ~= nil
			or lowered == "owned"
	end
	if typeof(status) == "boolean" then
		return status
	end
	if typeof(status) == "EnumItem" then
		return indicatesActive(status.Name)
	end
	if typeof(status) == "table" then
		if status.IsSubscribed ~= nil then
			return status.IsSubscribed == true
		end
		if status.isSubscribed ~= nil then
			return status.isSubscribed == true
		end
		local state = status.Status or status.status or status.SubscriptionState or status.subscriptionState
		if typeof(state) == "EnumItem" then
			return indicatesActive(state.Name)
		end
		if typeof(state) == "string" then
			return indicatesActive(state)
		end
	end
	return false
end

local function playerHasBoardSaveSubscription(player)
	if not player then
		return false
	end
	
	if 1 == 1 then
		return false -- BYPASS
	end
	
	local cached = boardSaveSubscriptionStatusByPlayer[player.UserId]
	if cached ~= nil then
		return cached == true
	end
	local subscriptionId = tonumber(BOARD_SAVE_SUBSCRIPTION_ID) or 0
	if subscriptionId <= 0 then
		boardSaveSubscriptionStatusByPlayer[player.UserId] = false
		return false
	end
	local checker = MarketplaceService.GetUserSubscriptionStatusAsync
	if type(checker) ~= "function" then
		boardSaveSubscriptionStatusByPlayer[player.UserId] = false
		return false
	end
	local ok, status = pcall(function()
		return checker(MarketplaceService, player, subscriptionId)
	end)
	local subscribed = ok and parseSubscriptionStatus(status)
	boardSaveSubscriptionStatusByPlayer[player.UserId] = subscribed == true
	return subscribed == true
end

local function playerHasFullBoardSaveAccess(player)
	if not player then
		return false
	end
	if player.MembershipType == Enum.MembershipType.Premium then
		return true
	end
	if player:GetAttribute("FullBoardSaveAccess") == true then
		return true
	end
	return playerHasBoardSaveSubscription(player)
end

local function refreshBoardSaveAccess(player)
	if not player then
		return false
	end
	local hasAccess = (player.MembershipType == Enum.MembershipType.Premium) or playerHasBoardSaveSubscription(player)
	player:SetAttribute("FullBoardSaveAccess", hasAccess == true)
	return hasAccess == true
end

local function prepareBoardSavePolicyForSession(player, packId, levelId)
	if not player or playerHasFullBoardSaveAccess(player) then
		return
	end
	-- Non-entitled save policy is enforced centrally by DataService:
	-- only the player's current progression level persists and cannot be overwritten
	-- by other level/mode sessions.
end

local function startSessionWithBoardSavePolicy(player, packId, levelId, levelData)
	prepareBoardSavePolicyForSession(player, packId, levelId)
	GameService.StartSession(player, packId, levelId, levelData)
end

local function getAutosaveWriteBudget()
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(AUTOSAVE_REQUEST_TYPE)
	end)
	if not ok then
		return 0
	end
	return math.max(0, math.floor(tonumber(budget) or 0))
end

local function scheduleNextAutosave(player, secondsFromNow, withJitter)
	if not player then
		return
	end
	local delaySeconds = math.max(1, tonumber(secondsFromNow) or AUTOSAVE_INTERVAL_SECONDS)
	local jitter = withJitter and math.random(0, AUTOSAVE_STARTUP_JITTER_SECONDS) or 0
	autosaveNextAtByPlayer[player.UserId] = os.clock() + delaySeconds + jitter
end

local function computeAutosaveRetryDelay(failureCount)
	local failures = math.max(1, math.floor(tonumber(failureCount) or 1))
	return math.min(AUTOSAVE_RETRY_MAX_SECONDS, AUTOSAVE_RETRY_BASE_SECONDS * failures)
end

local function savePlayerDataGuarded(player, reason, options)
	options = options or {}
	local saveReason = tostring(reason or "unspecified")
	if not player then
		return false, "invalid player"
	end

	local userId = player.UserId
	if saveInFlightByPlayer[userId] then
		if options.waitForInFlight == true then
			local timeoutAt = os.clock() + math.max(0.5, tonumber(options.waitTimeoutSeconds) or 3)
			while saveInFlightByPlayer[userId] and os.clock() < timeoutAt do
				task.wait(0.1)
			end
		end
		if saveInFlightByPlayer[userId] then
			return false, "save in progress"
		end
	end

	if options.requireBudget == true and getAutosaveWriteBudget() < 1 then
		return false, "budget exhausted"
	end

	saveInFlightByPlayer[userId] = true
	local callOk, saveOk, saveErr = pcall(function()
		return DataService.savePlayerData(player)
	end)
	saveInFlightByPlayer[userId] = nil
	if not callOk then
		local failureCount = (autosaveFailureCountByPlayer[userId] or 0) + 1
		autosaveFailureCountByPlayer[userId] = failureCount
		warn(string.format("[AUTOSAVE] Unhandled save error (%s) for %s (%d): %s", saveReason, player.Name, userId, tostring(saveOk)))
		return false, tostring(saveOk)
	end

	if saveOk then
		autosaveFailureCountByPlayer[userId] = 0
		return true
	end

	local failureCount = (autosaveFailureCountByPlayer[userId] or 0) + 1
	autosaveFailureCountByPlayer[userId] = failureCount
	warn(string.format("[AUTOSAVE] Save failed (%s) for %s (%d): %s", saveReason, player.Name, userId, tostring(saveErr)))
	return false, saveErr
end

local function isPremiumLevel(packId, levelId)
	local resolvedPackId = tonumber(packId) or 0
	local resolvedLevelId = tonumber(levelId) or 0
	if resolvedPackId < 1 or resolvedLevelId < 1 then
		return false
	end
	local levelCount = LevelService.GetLevelCount(resolvedPackId)
	return MonetizationConfig.IsPremiumLevel(resolvedLevelId, levelCount)
end

local function safeFireClient(eventName, targetPlayer, payload)
	if targetPlayer and targetPlayer.Parent == Players then
		RemoteRegistry:GetEvent(eventName):FireClient(targetPlayer, payload)
	end
end

local function isAdminPlayer(player)
	return player and ADMIN_USER_IDS[player.UserId] == true
end

local function getAdminCooldownRemaining(player, actionKey)
	local byAction = adminActionCooldowns[player.UserId]
	local expiresAt = byAction and tonumber(byAction[actionKey]) or 0
	return math.max(0, math.ceil(expiresAt - os.clock()))
end

local function startAdminCooldown(player, actionKey)
	adminActionCooldowns[player.UserId] = adminActionCooldowns[player.UserId] or {}
	adminActionCooldowns[player.UserId][actionKey] = os.clock() + ADMIN_ACTION_COOLDOWN
end

local function choosePvPLevel()
	local packCount = math.max(1, LevelService.GetPackCount())
	for _ = 1, 24 do
		local packId = math.random(1, packCount)
		local levelCount = math.max(1, LevelService.GetLevelCount(packId))
		local levelId = math.random(1, levelCount)
		local levelData = LevelService.GetLevelData(packId, levelId)
		if levelData and isLevelDataPlayable(levelData) then
			return levelData
		end
	end
	local fallback = LevelService.GetLevelData(1, 1)
	return isLevelDataPlayable(fallback) and fallback or nil
end

local function getPackListForPlayer()
	local packs = {}
	table.insert(packs, {
		packId = -1,
		name = "Freeplay",
		levelCount = 1,
	})
	for _, packInfo in ipairs(LevelService.GetPackList()) do
		table.insert(packs, packInfo)
	end
	return packs
end

local function getActiveLevelData(player, session)
	local currentSession = session or GameService.GetSession(player.UserId)
	if not currentSession then
		return nil
	end
	if currentSession.levelData then
		return currentSession.levelData
	end
	if tonumber(currentSession.packId) == 0 then
		return DailyPuzzleService.GetTodaysPuzzle()
	end
	if tonumber(currentSession.packId) == -1 then
		return FreeplayService.GetOrCreateBoard(player, DataService)
	end
	return LevelService.GetLevelData(currentSession.packId, currentSession.levelId)
end

local function getClientLevelData(levelData)
	return LevelPayloadService.BuildClientLevelData(levelData)
end

local function isPerfectClearResult(levelStats)
	return math.max(0, math.floor(tonumber(levelStats and levelStats.accuracy) or 0)) >= 100
end

-- Drops out-of-order GetLevelData requests so older responses cannot replace a newer session.
local function resolveStaleLevelDataRequest(player, requestToken)
	local token = tonumber(requestToken) or 0
	if token <= 0 then
		return false, nil
	end

	local userId = player.UserId
	local latestToken = tonumber(latestLevelDataRequestTokenByPlayer[userId]) or 0
	if token < latestToken then
		local currentSession = GameService.GetSession(userId)
		if currentSession then
			local currentData = getActiveLevelData(player, currentSession)
			if currentData then
				return true, getClientLevelData(currentData)
			end
		else
			-- Allow new client sessions (for example after a local script reset) to recover.
			latestLevelDataRequestTokenByPlayer[userId] = token
		end
	elseif token > latestToken then
		latestLevelDataRequestTokenByPlayer[userId] = token
	end

	return false, nil
end

isLevelDataPlayable = function(levelData)
	if not levelData then
		return false
	end
	local requiredWords = levelData.words or {}
	if #requiredWords <= 0 then
		return false
	end
	for _, requiredWord in ipairs(requiredWords) do
		local upperWord = tostring(requiredWord or ""):upper()
		if upperWord == "" then
			return false
		end
		local revealCells = LevelPayloadService.GetRevealCells(levelData, upperWord)
		if #revealCells ~= #upperWord then
			return false
		end
	end
	return true
end

local function getNextIncompleteRequiredWord(levelData, session)
	if not levelData or not session then
		return nil
	end
	for _, word in ipairs(levelData.words or {}) do
		local upper = tostring(word or ""):upper()
		if upper ~= "" and not session.foundWords[upper] then
			return upper
		end
	end
	return nil
end

local function revealCellsToPlayer(player, session, levelData, cells, mode)
	if not player or not session or not levelData then
		return false
	end
	local revealedAny = false
	for _, cell in ipairs(cells or {}) do
		local row = tonumber(cell.row)
		local col = tonumber(cell.col)
		if row ~= nil and col ~= nil then
			LevelPayloadService.MarkHintedCell(session, row, col)
			RemoteRegistry:GetEvent("HintReveal"):FireClient(player, {
				row = row,
				col = col,
				letter = LevelPayloadService.GetLetterAtCell(levelData, row, col),
				mode = mode or "hint",
			})
			revealedAny = true
		end
	end
	if revealedAny and isNormalModeSession(player, session) then
		DataService.saveNormalModeBoardSession(player, levelData, session)
	end
	return revealedAny
end

local function grantPvPRowHint(player)
	local session = GameService.GetSession(player.UserId)
	local match = getMatchForPlayer(player)
	if not session or not match or match.completed then
		return false
	end
	local levelData = getActiveLevelData(player, session)
	local nextWord = getNextIncompleteRequiredWord(levelData, session)
	if not nextWord then
		return false
	end
	local cells = LevelPayloadService.GetRevealCells(levelData, nextWord)
	return revealCellsToPlayer(player, session, levelData, cells, "pvp_row_hint")
end

local function grantPvPCellHint(player)
	local session = GameService.GetSession(player.UserId)
	local match = getMatchForPlayer(player)
	if not session or not match or match.completed then
		return false
	end
	local levelData = getActiveLevelData(player, session)
	local target = LevelPayloadService.FindNextHintCell(levelData, session)
	if not target then
		return false
	end
	return revealCellsToPlayer(player, session, levelData, { target }, "pvp_hint")
end

local function grantDailyCellHint(player)
	local session = GameService.GetSession(player.UserId)
	if not session or tonumber(session.packId) ~= 0 then
		return false
	end
	local levelData = getActiveLevelData(player, session)
	local target = LevelPayloadService.FindNextHintCell(levelData, session)
	if not target then
		return false
	end
	return revealCellsToPlayer(player, session, levelData, { target }, "daily_hint")
end

local function isWordCell(levelData, row, col)
	if not levelData or not levelData.positions then
		return false
	end
	for _, pos in ipairs(levelData.positions) do
		local word = pos.word
		for i = 1, #word do
			local r, c
			if pos.dir == "H" then
				r = pos.row
				c = pos.col + (i - 1)
			else
				r = pos.row + (i - 1)
				c = pos.col
			end
			if r == row and c == col then
				return true
			end
		end
	end
	return false
end

local function grantDailySelectedCellHint(player, row, col)
	local session = GameService.GetSession(player.UserId)
	if not session or tonumber(session.packId) ~= 0 then
		return false
	end
	local levelData = getActiveLevelData(player, session)
	if not levelData or not isWordCell(levelData, row, col) then
		return false
	end
	local cellKey = tostring(row) .. ":" .. tostring(col)
	if session.hintedCells and session.hintedCells[cellKey] then
		return false
	end
	return revealCellsToPlayer(player, session, levelData, {
		{ row = row, col = col },
	}, "daily_hint")
end

local function chooseLevelInRange(config)
	local packCount = math.max(1, LevelService.GetPackCount())
	local minPack = math.clamp(tonumber(config.packMin) or 1, 1, packCount)
	local maxPack = math.clamp(tonumber(config.packMax) or packCount, minPack, packCount)

	for _ = 1, 32 do
		local packId = math.random(minPack, maxPack)
		local levelCount = math.max(1, LevelService.GetLevelCount(packId))
		local levelId = math.random(1, levelCount)
		local levelData = LevelService.GetLevelData(packId, levelId)
		if levelData and isLevelDataPlayable(levelData) then
			return levelData
		end
	end
	for packId = minPack, maxPack do
		local levelCount = math.max(1, LevelService.GetLevelCount(packId))
		for levelId = 1, levelCount do
			local levelData = LevelService.GetLevelData(packId, levelId)
			if levelData and isLevelDataPlayable(levelData) then
				return levelData
			end
		end
	end
	local fallback = LevelService.GetLevelData(1, 1)
	return isLevelDataPlayable(fallback) and fallback or nil
end

local function chooseTimedLevel(mode)
	return chooseLevelInRange(mode)
end

local function chooseHardcoreLevel()
	return chooseLevelInRange({ packMin = 2, packMax = 4 })
end

local function clearPlayerInvites(userId)
	pvpInvitesByTarget[userId] = nil
	for targetUserId, invites in pairs(pvpInvitesByTarget) do
		if invites[userId] then
			invites[userId] = nil
			if next(invites) == nil then
				pvpInvitesByTarget[targetUserId] = nil
			end
		end
	end
end

local function destroyMatch(matchId, winnerUserId, reason)
	local match = pvpMatches[matchId]
	if not match then
		return
	end
	match.completed = true
	pvpMatches[matchId] = nil

	for _, p in ipairs(match.players) do
		pvpMatchByPlayer[p.UserId] = nil
		GameService.EndSession(p)
	end

	local p1 = match.players[1]
	local p2 = match.players[2]
	local p1Won = winnerUserId ~= nil and p1 and p1.UserId == winnerUserId
	local p2Won = winnerUserId ~= nil and p2 and p2.UserId == winnerUserId

	if p1 then
		local p1Result = "draw"
		if winnerUserId then
			p1Result = p1Won and "win" or "lose"
		end
		safeFireClient("PvPMatchEnd", p1, {
			result = p1Result,
			reason = reason or "match ended",
			winnerUserId = winnerUserId,
			opponentName = p2 and p2.Name or "Opponent",
		})
	end
	if p2 then
		local p2Result = "draw"
		if winnerUserId then
			p2Result = p2Won and "win" or "lose"
		end
		safeFireClient("PvPMatchEnd", p2, {
			result = p2Result,
			reason = reason or "match ended",
			winnerUserId = winnerUserId,
			opponentName = p1 and p1.Name or "Opponent",
		})
	end

	if p1 and p2 and winnerUserId then
		if p1Won then
			DataService.recordPvPMatchResult(p1, p2, true)
			DataService.recordPvPMatchResult(p2, p1, false)
			addRankProgress(p1, 25, "pvp_win")
			addRankProgress(p2, 8, "pvp_loss")
			task.spawn(updateLeaderboard, p1)
			task.spawn(updateLeaderboard, p2)
		elseif p2Won then
			DataService.recordPvPMatchResult(p2, p1, true)
			DataService.recordPvPMatchResult(p1, p2, false)
			addRankProgress(p2, 25, "pvp_win")
			addRankProgress(p1, 8, "pvp_loss")
			task.spawn(updateLeaderboard, p1)
			task.spawn(updateLeaderboard, p2)
		end
	elseif p1 and p2 then
		DataService.recordPvPMatchResult(p1, p2, nil)
		DataService.recordPvPMatchResult(p2, p1, nil)
		addRankProgress(p1, 12, "pvp_draw")
		addRankProgress(p2, 12, "pvp_draw")
		task.spawn(updateLeaderboard, p1)
		task.spawn(updateLeaderboard, p2)
	end
end

local function startPvPMatch(playerA, playerB)
	timedMatchByPlayer[playerA.UserId] = nil
	timedMatchByPlayer[playerB.UserId] = nil
	DataService.logFunnelStep(playerA, "discovered_1v1")
	DataService.logFunnelStep(playerB, "discovered_1v1")

	local levelData = choosePvPLevel()
	if not levelData then
		return false, "no level available"
	end

	local matchId = tostring(playerA.UserId) .. "_" .. tostring(playerB.UserId) .. "_" .. tostring(os.time())
	local match = {
		matchId = matchId,
		levelData = levelData,
		players = { playerA, playerB },
		foundByPlayer = {
			[playerA.UserId] = {},
			[playerB.UserId] = {},
		},
		completed = false,
		startedAt = tick(),
	}

	pvpMatches[matchId] = match
	pvpMatchByPlayer[playerA.UserId] = matchId
	pvpMatchByPlayer[playerB.UserId] = matchId

	startSessionWithBoardSavePolicy(playerA, levelData.packId, levelData.levelId, levelData)
	startSessionWithBoardSavePolicy(playerB, levelData.packId, levelData.levelId, levelData)

	safeFireClient("PvPMatchStart", playerA, {
		matchId = matchId,
		levelData = getClientLevelData(levelData),
		opponent = {
			userId = playerB.UserId,
			name = playerB.Name,
		},
	})
	safeFireClient("PvPMatchStart", playerB, {
		matchId = matchId,
		levelData = getClientLevelData(levelData),
		opponent = {
			userId = playerA.UserId,
			name = playerA.Name,
		},
	})
	return true
end

local function areRequiredCellsFullyCovered(session, levelData)
	if not session or not levelData or typeof(levelData.positions) ~= "table" then
		return false
	end
	local requiredSet = {}
	for _, word in ipairs(levelData.words or {}) do
		requiredSet[tostring(word):upper()] = true
	end
	local requiredCells = {}
	local coveredCells = {}
	for _, pos in ipairs(levelData.positions or {}) do
		local word = tostring(pos.word or ""):upper()
		if requiredSet[word] then
			for i = 1, #word do
				local r, c
				if pos.dir == "H" then
					r = tonumber(pos.row) or 0
					c = (tonumber(pos.col) or 0) + (i - 1)
				else
					r = (tonumber(pos.row) or 0) + (i - 1)
					c = tonumber(pos.col) or 0
				end
				local key = tostring(r) .. ":" .. tostring(c)
				requiredCells[key] = true
				if session.foundWords[word] then
					coveredCells[key] = true
				end
			end
		end
	end
	for key in pairs(requiredCells) do
		if not coveredCells[key] then
			return false
		end
	end
	return next(requiredCells) ~= nil
end

local function anchorCharacter(character)
	if not character then
		return
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	end
end

local function bindCharacterAnchor(player)
	player.CharacterAdded:Connect(function(character)
		anchorCharacter(character)
	end)
	if player.Character then
		anchorCharacter(player.Character)
	end
end


Players.PlayerAdded:Connect(function(player)
	sessionPlaytimeClockByPlayer[player.UserId] = os.clock()
	player:SetAttribute("FullBoardSaveAccess", false)
	refreshBoardSaveAccess(player)
	autosaveFailureCountByPlayer[player.UserId] = 0
	scheduleNextAutosave(player, AUTOSAVE_INTERVAL_SECONDS, true)
	bindCharacterAnchor(player)
	DataService.loadPlayerData(player)
	grantExistingGroupRewardIfEligible(player)
	task.spawn(function()
		playerOwnsPremiumPass(player)
		BadgeAwardService.AwardWelcome(player)
		local rankState = DataService.getRankState(player)
		if rankState and rankState.id then
			BadgeAwardService.AwardRank(player, rankState.id)
		end
		if updateLeaderboard then
			updateLeaderboard(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local joinClock = sessionPlaytimeClockByPlayer[player.UserId]
	if joinClock then
		DataService.addPlaytime(player, os.clock() - joinClock)
		sessionPlaytimeClockByPlayer[player.UserId] = nil
	end
	local match = getMatchForPlayer(player)
	if match and not match.completed then
		local opponent = getOpponentInMatch(match, player.UserId)
		local winnerUserId = opponent and opponent.UserId or nil
		destroyMatch(match.matchId, winnerUserId, "opponent left")
	end
	local activeSession = GameService.GetSession(player.UserId)
	if activeSession and tonumber(activeSession.packId) == -1 then
		DataService.resetFreeplayStreak(player)
	end
	timedMatchByPlayer[player.UserId] = nil
	hardcoreRunByPlayer[player.UserId] = nil
	pendingSpecialHintPurchaseByPlayer[player.UserId] = nil
	premiumPassOwnershipByPlayer[player.UserId] = nil
	boardSaveSubscriptionStatusByPlayer[player.UserId] = nil
	latestLevelDataRequestTokenByPlayer[player.UserId] = nil
	autosaveNextAtByPlayer[player.UserId] = nil
	autosaveFailureCountByPlayer[player.UserId] = nil
	clearPlayerInvites(player.UserId)
	FlagService.ClearPlayer(player)
	if dirtyLeaderboardUsers[player.UserId] then
		flushLeaderboardForUserId(player.UserId)
		dirtyLeaderboardUsers[player.UserId] = nil
	end

	savePlayerDataGuarded(player, "player removing", {
		waitForInFlight = true,
		waitTimeoutSeconds = 4,
	})
	saveInFlightByPlayer[player.UserId] = nil
	DataService.clearPlayerData(player)
end)

-- Load data for anyone already in-game (Studio testing)
for _, player in Players:GetPlayers() do
	task.spawn(function()
		sessionPlaytimeClockByPlayer[player.UserId] = os.clock()
		player:SetAttribute("FullBoardSaveAccess", false)
		refreshBoardSaveAccess(player)
		autosaveFailureCountByPlayer[player.UserId] = 0
		scheduleNextAutosave(player, AUTOSAVE_INTERVAL_SECONDS, true)
		bindCharacterAnchor(player)
		DataService.loadPlayerData(player)
		grantExistingGroupRewardIfEligible(player)
		playerOwnsPremiumPass(player)
		BadgeAwardService.AwardWelcome(player)
		local rankState = DataService.getRankState(player)
		if rankState and rankState.id then
			BadgeAwardService.AwardRank(player, rankState.id)
		end
		if updateLeaderboard then
			updateLeaderboard(player)
		end
	end)
end

task.spawn(function()
	while true do
		task.wait(30)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local joinClock = sessionPlaytimeClockByPlayer[player.UserId]
			if joinClock then
				DataService.addPlaytime(player, now - joinClock)
				sessionPlaytimeClockByPlayer[player.UserId] = now
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_POLL_SECONDS)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local userId = player.UserId
			local nextAt = autosaveNextAtByPlayer[userId]
			if nextAt == nil then
				scheduleNextAutosave(player, AUTOSAVE_INTERVAL_SECONDS, true)
				continue
			end
			if now < nextAt then
				continue
			end

			local saved, reason = savePlayerDataGuarded(player, "autosave", {
				requireBudget = true,
			})
			if saved then
				scheduleNextAutosave(player, AUTOSAVE_INTERVAL_SECONDS, false)
			else
				if reason == "budget exhausted" then
					scheduleNextAutosave(player, AUTOSAVE_POLL_SECONDS + 1, false)
				else
					local retryDelay = computeAutosaveRetryDelay(autosaveFailureCountByPlayer[userId] or 1)
					scheduleNextAutosave(player, retryDelay, false)
				end
			end
			task.wait(AUTOSAVE_WRITE_SPACING_SECONDS)
		end
	end
end)


RemoteRegistry:GetFunction("GetLevelData").OnServerInvoke = function(player, packId, levelId, requestToken)
	local isStaleRequest, stalePayload = resolveStaleLevelDataRequest(player, requestToken)
	if isStaleRequest then
		return stalePayload
	end

	if typeof(packId) ~= "number" or typeof(levelId) ~= "number" then
		return nil
	end
	packId  = math.floor(packId)
	levelId = math.clamp(math.floor(levelId), 1, 999)
	local skillState = DataService.getSkillState(player)
	local savedNormalBoard = nil

	local data, err
	if packId == -1 then
		data = FreeplayService.GetOrCreateBoard(player, DataService)
	else
		packId = math.clamp(packId, 1, 999)
		savedNormalBoard = DataService.getSavedNormalModeBoard(player, packId, levelId)
		if savedNormalBoard and savedNormalBoard.levelData then
			data = savedNormalBoard.levelData
		else
			data, err = LevelService.GetLevelData(packId, levelId, {
				skillState = skillState,
			})
		end
	end
	if not data then
		warn("[SERVER] GetLevelData failed:", err)
		return nil
	end

	local becameStale, replacementPayload = resolveStaleLevelDataRequest(player, requestToken)
	if becameStale then
		return replacementPayload
	end

	timedMatchByPlayer[player.UserId] = nil
	hardcoreRunByPlayer[player.UserId] = nil
	startSessionWithBoardSavePolicy(player, data.packId, data.levelId, data)
	local session = GameService.GetSession(player.UserId)
	local progressWords = {}
	local progressBonus = {}
	local hintedCells = {}
	if session and savedNormalBoard then
		progressWords = savedNormalBoard.progressWords or {}
		progressBonus = savedNormalBoard.progressBonus or {}
		hintedCells = savedNormalBoard.hintedCells or {}
		for _, savedWord in ipairs(progressWords) do
			GameService.RecordWord(player, savedWord)
		end
		for _, savedBonusWord in ipairs(progressBonus) do
			GameService.RecordBonusWord(player, savedBonusWord)
		end
		for _, hinted in ipairs(hintedCells) do
			local row = tonumber(hinted and hinted.row)
			local col = tonumber(hinted and hinted.col)
			if row ~= nil and col ~= nil then
				LevelPayloadService.MarkHintedCell(session, row, col)
			end
		end
	end
	if session and isNormalModeSession(player, session) then
		DataService.saveNormalModeBoardSession(player, data, session)
	end

	local payload = getClientLevelData(data)
	payload.progressWords = progressWords
	payload.progressBonus = progressBonus
	payload.progressCells = LevelPayloadService.GetRevealCellsForWords(data, progressWords)
	payload.hintedCells = hintedCells
	return payload
end


RemoteRegistry:GetFunction("GetPlayerData").OnServerInvoke = function(player)
	-- DataStore load is async; wait up to 8 seconds for data to be ready
	local waited = 0
	while not DataService.getData(player) and waited < 8 do
		task.wait(0.25)
		waited += 0.25
	end

	local data = DataService.getData(player)
	grantExistingGroupRewardIfEligible(player)
	data = DataService.getData(player)

	-- Always return packs regardless of whether player data loaded
	local packs = getPackListForPlayer()

	if not data then
		return {
			hints = 3,
			coins = 100,
			progress = {},
			packs = packs,
			premiumOwned = playerOwnsPremiumPass(player),
			tutorialCompleted = false,
			musicEnabled = true,
			sfxEnabled = true,
			selectionHints = 0,
			rank = DataService.getRankState(player),
			skill = DataService.getSkillState(player),
			lastPack = 1,
			lastLevel = 1,
			groupRewardClaimed = false,
			favoritePromptShown = false,
		}
	end
	return {
		hints    = data.hints,
		coins    = data.coins,
		progress = data.progress,
		packs    = packs,
		premiumOwned = playerOwnsPremiumPass(player),
		tutorialCompleted = DataService.getTutorialCompleted(player),
		musicEnabled = true,
		sfxEnabled = true,
		selectionHints = DataService.getSelectionHints(player),
		rank = DataService.getRankState(player),
		skill = DataService.getSkillState(player),
		lastPack = data.lastPack or 1,
		lastLevel = data.lastLevel or 1,
		groupRewardClaimed = data.groupReward == true,
		favoritePromptShown = DataService.getFavoritePromptShown(player),
	}
end


RemoteRegistry:GetFunction("GetPvPPlayers").OnServerInvoke = function(player)
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local busy = (pvpMatchByPlayer[other.UserId] ~= nil)
				or (timedMatchByPlayer[other.UserId] ~= nil)
				or (hardcoreRunByPlayer[other.UserId] ~= nil)
			local rankState = DataService.getRankState(other)
			table.insert(list, {
				userId = other.UserId,
				name = other.Name,
				inMatch = busy,
				rankImageId = rankState and rankState.imageId or "rbxassetid://0",
				rankName = rankState and rankState.name or "Bronze 1",
			})
		end
	end
	table.sort(list, function(a, b)
		return string.lower(a.name) < string.lower(b.name)
	end)
	return list
end

RemoteRegistry:GetFunction("GetAdminPlayers").OnServerInvoke = function(player)
	if not isAdminPlayer(player) then
		return {}
	end

	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		table.insert(list, {
			userId = other.UserId,
			name = other.Name,
			displayName = other.DisplayName,
		})
	end
	table.sort(list, function(a, b)
		return string.lower(tostring(a.name or "")) < string.lower(tostring(b.name or ""))
	end)
	return list
end

RemoteRegistry:GetFunction("RunAdminAction").OnServerInvoke = function(player, actionKey, targetUserId)
	if not isAdminPlayer(player) then
		return { success = false, message = "not allowed" }
	end

	actionKey = tostring(actionKey or "")
	local action = ADMIN_ACTIONS[actionKey]
	if not action then
		return { success = false, message = "invalid action" }
	end

	local cooldownRemaining = getAdminCooldownRemaining(player, actionKey)
	if cooldownRemaining > 0 then
		return {
			success = false,
			message = "cooldown active",
			cooldownRemaining = cooldownRemaining,
		}
	end

	local targetId = tonumber(targetUserId)
	if not targetId then
		return { success = false, message = "invalid player" }
	end

	local targetPlayer = Players:GetPlayerByUserId(targetId)
	if not targetPlayer then
		return { success = false, message = "player not online" }
	end

	if action.coins then
		DataService.addCoins(targetPlayer, action.coins)
		safeFireClient("UpdateCoins", targetPlayer, DataService.getCoins(targetPlayer))
	end
	if action.hints then
		DataService.addHints(targetPlayer, action.hints)
		safeFireClient("UpdateHints", targetPlayer, DataService.getHints(targetPlayer))
	end
	if action.selectionHints then
		DataService.addSelectionHints(targetPlayer, action.selectionHints)
		safeFireClient("UpdateSelectionHints", targetPlayer, DataService.getSelectionHints(targetPlayer))
	end

	startAdminCooldown(player, actionKey)

	return {
		success = true,
		message = action.message,
		targetName = targetPlayer.Name,
		cooldownRemaining = ADMIN_ACTION_COOLDOWN,
	}
end

RemoteRegistry:GetFunction("SendPvPInvite").OnServerInvoke = function(player, targetUserId)
	if typeof(targetUserId) ~= "number" then
		return { success = false, message = "invalid target" }
	end
	if targetUserId == player.UserId then
		return { success = false, message = "cannot invite yourself" }
	end
	if pvpMatchByPlayer[player.UserId] then
		return { success = false, message = "you are already in a match" }
	end
	if timedMatchByPlayer[player.UserId] then
		return { success = false, message = "you are in a timed match" }
	end
	if hardcoreRunByPlayer[player.UserId] then
		return { success = false, message = "you are in a hardcore run" }
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return { success = false, message = "player not available" }
	end
	if pvpMatchByPlayer[targetUserId] then
		return { success = false, message = "target already in match" }
	end
	if timedMatchByPlayer[targetUserId] then
		return { success = false, message = "target already in match" }
	end
	if hardcoreRunByPlayer[targetUserId] then
		return { success = false, message = "target already in match" }
	end

	pvpInvitesByTarget[targetUserId] = pvpInvitesByTarget[targetUserId] or {}
	local existingInvite = pvpInvitesByTarget[targetUserId][player.UserId]
	if existingInvite then
		local age = os.time() - (tonumber(existingInvite.createdAt) or 0)
		if age < PVP_INVITE_EXPIRE_SECONDS then
			local remaining = math.max(PVP_INVITE_RESEND_COOLDOWN, PVP_INVITE_EXPIRE_SECONDS - age)
			return { success = false, message = "invite already pending (" .. tostring(remaining) .. "s)" }
		end
	end
	pvpInvitesByTarget[targetUserId][player.UserId] = {
		inviterUserId = player.UserId,
		targetUserId = targetUserId,
		createdAt = os.time(),
	}

	safeFireClient("PvPInviteReceived", targetPlayer, {
		inviterUserId = player.UserId,
		inviterName = player.Name,
		expiresIn = PVP_INVITE_EXPIRE_SECONDS,
	})

	return { success = true, message = "invite sent" }
end

RemoteRegistry:GetFunction("RespondPvPInvite").OnServerInvoke = function(player, inviterUserId, accept)
	if typeof(inviterUserId) ~= "number" then
		return { success = false, message = "invalid inviter" }
	end

	local invites = pvpInvitesByTarget[player.UserId]
	local invite = invites and invites[inviterUserId]
	if not invite then
		return { success = false, message = "invite not found" }
	end

	local age = os.time() - (invite.createdAt or 0)
	if age > PVP_INVITE_EXPIRE_SECONDS then
		invites[inviterUserId] = nil
		return { success = false, message = "invite expired" }
	end

	invites[inviterUserId] = nil
	if next(invites) == nil then
		pvpInvitesByTarget[player.UserId] = nil
	end

	local inviter = Players:GetPlayerByUserId(inviterUserId)
	if not inviter then
		return { success = false, message = "inviter left" }
	end

	if not accept then
		safeFireClient("PvPInviteStatus", inviter, {
			status = "declined",
			targetUserId = player.UserId,
			targetName = player.Name,
		})
		return { success = true, message = "declined" }
	end

	if pvpMatchByPlayer[player.UserId] then
		return { success = false, message = "you are already in a match" }
	end
	if pvpMatchByPlayer[inviterUserId] then
		return { success = false, message = "inviter already in a match" }
	end

	local ok, err = startPvPMatch(inviter, player)
	if not ok then
		return { success = false, message = err or "failed to start match" }
	end

	safeFireClient("PvPInviteStatus", inviter, {
		status = "accepted",
		targetUserId = player.UserId,
		targetName = player.Name,
	})
	return { success = true, message = "accepted" }
end

RemoteRegistry:GetFunction("LeavePvPMatch").OnServerInvoke = function(player)
	local match = getMatchForPlayer(player)
	if not match or match.completed then
		return { success = false, message = "no active match" }
	end
	local opponent = getOpponentInMatch(match, player.UserId)
	local winnerUserId = opponent and opponent.UserId or nil
	destroyMatch(match.matchId, winnerUserId, "opponent forfeited")
	return { success = true, message = "left match" }
end

RemoteRegistry:GetFunction("StartTimedMode").OnServerInvoke = function(player, modeKey)
	local key = tostring(modeKey or "classic"):lower()
	local mode = TIMED_MODES[key] or TIMED_MODES.classic
	if pvpMatchByPlayer[player.UserId] then
		return { success = false, message = "you are already in a pvp match" }
	end
	if timedMatchByPlayer[player.UserId] then
		return { success = false, message = "you are already in a timed match" }
	end
	if hardcoreRunByPlayer[player.UserId] then
		return { success = false, message = "you are already in a hardcore run" }
	end

	local levelData = chooseTimedLevel(mode)
	if not levelData then
		return { success = false, message = "no level available" }
	end
	DataService.logFunnelStep(player, "discovered_timed")

	timedMatchByPlayer[player.UserId] = {
		modeKey = key,
		rewardCoins = mode.rewardCoins or 0,
		modeDuration = mode.duration or 120,
		expiresAt = os.time() + (mode.duration or 120),
		packId = levelData.packId,
		levelId = levelData.levelId,
		solvedCount = 0,
	}
	DataService.recordTimedModePlayed(player)
	startSessionWithBoardSavePolicy(player, levelData.packId, levelData.levelId, levelData)
	return {
		success = true,
		modeKey = key,
		modeLabel = mode.label,
		duration = mode.duration,
		rewardCoins = mode.rewardCoins,
		solvedCount = 0,
		levelData = getClientLevelData(levelData),
	}
end

RemoteRegistry:GetFunction("GetTimedModeLevel").OnServerInvoke = function(player)
	local active = timedMatchByPlayer[player.UserId]
	if not active then
		return { success = false, message = "no active timed mode" }
	end
	local remaining = math.max(0, (active.expiresAt or os.time()) - os.time())
	if remaining <= 0 then
		return { success = false, expired = true, solvedCount = active.solvedCount or 0 }
	end

	local mode = TIMED_MODES[tostring(active.modeKey or "")] or TIMED_MODES.classic
	local levelData = chooseTimedLevel(mode)
	if not levelData then
		return { success = false, message = "no level available", solvedCount = active.solvedCount or 0 }
	end

	active.packId = levelData.packId
	active.levelId = levelData.levelId
	startSessionWithBoardSavePolicy(player, levelData.packId, levelData.levelId, levelData)

	return {
		success = true,
		levelData = getClientLevelData(levelData),
		remaining = remaining,
		solvedCount = active.solvedCount or 0,
	}
end

RemoteRegistry:GetFunction("FinishTimedMode").OnServerInvoke = function(player, didWin, _reportedSolvedCount)
	local active = timedMatchByPlayer[player.UserId]
	if not active then
		return { success = false, message = "no active timed mode", reward = 0, solvedCount = 0, coins = DataService.getCoins(player) }
	end

	timedMatchByPlayer[player.UserId] = nil
	local solvedCount = math.max(0, tonumber(active.solvedCount) or 0)
	local reward = solvedCount * 13
	if didWin == true and solvedCount > 0 then
		reward += math.max(0, tonumber(active.rewardCoins) or 0)
	end
	reward = select(1, applyRankedCoinReward(player, reward))
		if reward > 0 then
			DataService.addCoins(player, reward, "TimedModeReward", "Reward")
		end
	DataService.recordTimedModeScore(player, solvedCount)
	if solvedCount > 0 then
		addRankProgress(player, math.max(3, solvedCount * 2), "timed_mode")
	end
	GameService.EndSession(player)
	return {
		success = true,
		reward = reward,
		solvedCount = solvedCount,
		coins = DataService.getCoins(player),
		modeKey = active.modeKey,
	}
end

RemoteRegistry:GetFunction("StartHardcoreMode").OnServerInvoke = function(player)
	if pvpMatchByPlayer[player.UserId] or timedMatchByPlayer[player.UserId] then
		return { success = false, message = "finish current mode first" }
	end
	if hardcoreRunByPlayer[player.UserId] then
		return { success = false, message = "hardcore already active" }
	end
	local levelData = chooseHardcoreLevel()
	if not levelData then
		return { success = false, message = "no level available" }
	end
	DataService.logFunnelStep(player, "discovered_hardcore")
	hardcoreRunByPlayer[player.UserId] = { streak = 0 }
	startSessionWithBoardSavePolicy(player, levelData.packId, levelData.levelId, levelData)
	return {
		success = true,
		streak = 0,
		levelData = getClientLevelData(levelData),
	}
end

RemoteRegistry:GetFunction("GetHardcoreNextLevel").OnServerInvoke = function(player)
	local run = getHardcoreRun(player)
	if not run then
		return { success = false, message = "no hardcore run" }
	end
	local levelData = chooseHardcoreLevel()
	if not levelData then
		return { success = false, message = "no level available" }
	end
	startSessionWithBoardSavePolicy(player, levelData.packId, levelData.levelId, levelData)
	return {
		success = true,
		streak = tonumber(run.streak) or 0,
		levelData = getClientLevelData(levelData),
	}
end

RemoteRegistry:GetFunction("FinishHardcoreMode").OnServerInvoke = function(player)
	local run = hardcoreRunByPlayer[player.UserId]
	if not run then
		return {
			success = false,
			streak = 0,
			best = (DataService.getStats(player).hardcoreBestStreak or 0),
			coins = DataService.getCoins(player),
		}
	end
	hardcoreRunByPlayer[player.UserId] = nil
	GameService.EndSession(player)
	local streak = math.max(0, tonumber(run.streak) or 0)
	DataService.setHardcoreBest(player, streak)
	if streak > 0 then
		addRankProgress(player, (streak * 4) + 6, "hardcore_run")
	end
	task.spawn(updateLeaderboard, player)
	local best = tonumber(DataService.getStats(player).hardcoreBestStreak) or 0
	return {
		success = true,
		streak = streak,
		best = best,
		coins = DataService.getCoins(player),
	}
end

RemoteRegistry:GetEvent("SubmitWord").OnServerEvent:Connect(function(player, word, levelData)
	if typeof(word) ~= "string" then return end
	
	-- Use server-authoritative level data based on player's current session
	local session = GameService.GetSession(player.UserId)
	if not session then
		-- No active session, ignore submission
		return
	end
	if session.completionLocked == true then
		return
	end
	
	-- Get authoritative level data from server
	local authLevelData = getActiveLevelData(player, session)
	if not authLevelData then
		return
	end
	
	-- Validate word using authoritative level data (letters must match current level)
	local valid, isBonus, reason = GameService.ValidateWord(player, word, authLevelData)
	GameService.RecordAttempt(player, word, valid)
	local flagResult = FlagService.RecordSubmission(player, valid, word, {
		packId = session.packId,
		levelId = session.levelId,
		reason = reason,
	})
	if flagResult and flagResult.flagged then
		task.spawn(function()
			WebhookService.SendFlag(player, flagResult)
			updateLeaderboard(player)
		end)
	end
	
	if valid then
		if isBonus then
			GameService.RecordBonusWord(player, word)
		else
			GameService.RecordWord(player, word)
		end
		DataService.addWordFound(player, isBonus)
		
		-- Keep streak for feel, but avoid inflating coin output off of it.
		session.wordStreak = (session.wordStreak or 0) + 1
		local streakMult = math.clamp(1 + math.floor((session.wordStreak - 1) / 3), 1, 4)
		local baseCoinReward = isBonus and 0 or 1
		local coinReward = 0
		local rankInfo = nil
		if baseCoinReward > 0 then
			coinReward, rankInfo = applyRankedCoinReward(player, baseCoinReward)
			DataService.addCoins(player, coinReward, "WordReward", "Reward")
		end
		addRankProgress(player, isBonus and 2 or 1, "word")
		if coinReward > 0 then
			DailyQuestService.RecordProgress(player, "coinsEarned", coinReward)
		end
			if isBonus then
				DailyQuestService.RecordProgress(player, "bonusWords", 1)
			else
				DailyQuestService.RecordProgress(player, "wordsFound", 1)
			end
			if isNormalModeSession(player, session) then
				DataService.saveNormalModeBoardSession(player, authLevelData, session)
			end
			
			local revealedCells = nil
			if not isBonus then
			revealedCells = LevelPayloadService.GetRevealCells(authLevelData, word)
		end
		local filteredWord, wasFiltered, filteredCells = getFilteredWordPayload(player, word, revealedCells)

		RemoteRegistry:GetEvent("WordFound"):FireClient(player, {
			word = filteredWord,
			valid = true,
			isBonus = isBonus,
			revealedCells = filteredCells,
			wasFiltered = wasFiltered,
			coinsEarned = coinReward,
			rankMultiplier = rankInfo and rankInfo.coinMultiplier or 1,
			wordStreak = session.wordStreak or 1,
			streakMultiplier = streakMult,
		})

		local pvpMatch = getMatchForPlayer(player)
		if pvpMatch and not pvpMatch.completed then
			local upperWord = word:upper()
			if not pvpMatch.foundByPlayer[player.UserId][upperWord] then
				pvpMatch.foundByPlayer[player.UserId][upperWord] = true
				local opponent = getOpponentInMatch(pvpMatch, player.UserId)
				if opponent then
					for _, pos in ipairs(authLevelData.positions or {}) do
						if pos.word == upperWord then
							safeFireClient("PvPOppWordProgress", opponent, {
								word = upperWord,
								row = pos.row,
								col = pos.col,
								dir = pos.dir,
								length = #upperWord,
							})
							break
						end
					end
				end
			end
		end
		
		-- Check level complete using authoritative words list
		local requiredWords = authLevelData.words or {}
		
		if #requiredWords > 0 and (GameService.CheckComplete(player, requiredWords) or areRequiredCellsFullyCovered(session, authLevelData)) then
			if session.completionLocked == true then
				return
			end
			session.completionLocked = true
			local pvpMatch = getMatchForPlayer(player)
			if pvpMatch and not pvpMatch.completed then
				pvpMatch.completed = true
				destroyMatch(pvpMatch.matchId, player.UserId, "all words found")
				return
			end

			local levelStats = GameService.GetLevelStats(player, authLevelData)
			local bonusFound = levelStats.bonusFound or 0
			local bonusTotal = levelStats.bonusTotal or 0
			local perfectClear = isPerfectClearResult(levelStats)
			local usedHints = (session and tonumber(session.hintCount) or 0) > 0

			local perfectClearReward = 0
			if perfectClear then
				DataService.recordPerfectClear(player)
				perfectClearReward = select(1, applyRankedCoinReward(player, 8))
				DataService.addCoins(player, perfectClearReward, "PerfectClearReward", "Reward")
				DailyQuestService.RecordProgress(player, "coinsEarned", perfectClearReward)
				addRankProgress(player, 6, "perfect_clear")
			end

			local activeTimed = getTimedMatch(player)
			if activeTimed and idsMatch(activeTimed.packId, session.packId) and idsMatch(activeTimed.levelId, session.levelId) then
				activeTimed.solvedCount = (activeTimed.solvedCount or 0) + 1
			end
			local activeHardcore = getHardcoreRun(player)
			if activeHardcore then
				activeHardcore.streak = (activeHardcore.streak or 0) + 1
			end

			local eventReward = 0
			local eventCompleted = false

				if tonumber(session.packId) == -1 then
					local currentFreeplayStreak, highestFreeplayStreak = DataService.incrementFreeplayStreak(player)
					GameService.EndSession(player)
					levelStats.currentFreeplayStreak = currentFreeplayStreak
					levelStats.highestFreeplayStreak = highestFreeplayStreak
				else
					if isNormalModeSession(player, session) then
						DataService.clearNormalModeBoardSave(player, session.packId, session.levelId)
					end
					GameService.CompleteLevel(player, session.packId, session.levelId)
				end
			local skillState = DataService.recordCasualLevelResult(player, levelStats)
			addRankProgress(player, 12, "level_complete")
			DailyQuestService.RecordProgress(player, "levelsComplete", 1)
			DailyQuestService.RecordLevelResult(player, levelStats, {
				usedHints = usedHints,
				perfectClear = perfectClear,
				isDaily = false,
			})
			
			-- Give coins for level completion
			local levelCoinReward = select(1, applyRankedCoinReward(player, 6))
			DataService.addCoins(player, levelCoinReward, "LevelCompleteReward", "Reward")
			DailyQuestService.RecordProgress(player, "coinsEarned", levelCoinReward)

			local totalEarned = levelCoinReward + perfectClearReward + eventReward
			RemoteRegistry:GetEvent("LevelComplete"):FireClient(player, {
				packId = session.packId,
				levelId = session.levelId,
				hints = DataService.getHints(player),
				coins = DataService.getCoins(player),
				coinsEarned = totalEarned,
				perfectClear = perfectClear,
				perfectClearReward = perfectClearReward,
				eventReward = 0,
				eventCompleted = false,
				skill = skillState,
				stats = {
					timeSeconds = levelStats.timeSeconds or 0,
					attempts = levelStats.attempts or 0,
					validCount = levelStats.validCount or 0,
					wrongGuesses = levelStats.wrongGuesses or 0,
					bonusFound = bonusFound,
					bonusTotal = bonusTotal,
					accuracy = levelStats.accuracy or 0,
					currentFreeplayStreak = levelStats.currentFreeplayStreak or 0,
					highestFreeplayStreak = levelStats.highestFreeplayStreak or 0,
				},
			})
		end
	else
		if session then
			session.wordStreak = 0
		end
		RemoteRegistry:GetEvent("WordFound"):FireClient(player, {
			word = word,
			valid = false,
			isBonus = false,
			reason = reason or "invalid",
		})
	end
end)


RemoteRegistry:GetEvent("RequestHint").OnServerEvent:Connect(function(player)
	local session = GameService.GetSession(player.UserId)
	if not session then
		return
	end

	local pvpMatch = getMatchForPlayer(player)
	local isActivePvP = pvpMatch and not pvpMatch.completed
	local isDaily = tonumber(session.packId) == 0
	local hardcore = getHardcoreRun(player)
	if hardcore then
		return
	end

	local availableHints = DataService.getHints(player)
	if availableHints <= 0 then
		return
	end
	
	local ok, msg = GameService.UseHint(player)
	if not ok then
		return
	end
	DailyQuestService.RecordProgress(player, "hintsUsed", 1)

	if isActivePvP then
		if not grantPvPCellHint(player) then
			DataService.addHints(player, 1)
		end
		RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
		return
	end

	if isDaily then
		if not grantDailyCellHint(player) then
			DataService.addHints(player, 1)
		end
		RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
		return
	end

	local authLevelData = getActiveLevelData(player, session)
	local hintCells = LevelPayloadService.GetHintCells(authLevelData, session)
	if not authLevelData or #hintCells <= 0 then
		DataService.addHints(player, 1)
		RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
		return
	end
	for _, target in ipairs(hintCells) do
		local revealLetter = LevelPayloadService.GetLetterAtCell(authLevelData, target.row, target.col)
		if tostring(revealLetter or "") == "" then
			DataService.addHints(player, 1)
			RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
			return
		end
	end

	-- Reveal a large chunk of the board so hints feel materially stronger.
		for _, target in ipairs(hintCells) do
			LevelPayloadService.MarkHintedCell(session, target.row, target.col)
			RemoteRegistry:GetEvent("HintReveal"):FireClient(player, {
			row = target.row,
			col = target.col,
			letter = LevelPayloadService.GetLetterAtCell(authLevelData, target.row, target.col),
				mode = "hint",
			})
		end
		if isNormalModeSession(player, session) then
			DataService.saveNormalModeBoardSession(player, authLevelData, session)
		end
		
		-- Update hint count
		RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
end)

RemoteRegistry:GetFunction("PrepareSpecialHintPurchase").OnServerInvoke = function(player, kind, row, col)
	local key = tostring(kind or "")
	local session = GameService.GetSession(player.UserId)
	if not session then
		return { success = false, message = "no active level" }
	end

	if key == "pvp_row_hint" then
		local product = MonetizationConfig.HintProducts.pvpRowHint
		local match = getMatchForPlayer(player)
		if not product or (tonumber(product.id) or 0) <= 0 then
			return { success = false, message = "set pvpRowHint product id first" }
		end
		if not match or match.completed then
			return { success = false, message = "not in 1v1" }
		end
		pendingSpecialHintPurchaseByPlayer[player.UserId] = {
			kind = key,
			productId = tonumber(product.id),
			createdAt = os.time(),
		}
		return { success = true, productId = tonumber(product.id) }
	end

	if key == "pvp_hint" then
		local product = MonetizationConfig.HintProducts.pvpHint
		local match = getMatchForPlayer(player)
		if not product or (tonumber(product.id) or 0) <= 0 then
			return { success = false, message = "set pvpHint product id first" }
		end
		if not match or match.completed then
			return { success = false, message = "not in 1v1" }
		end
		pendingSpecialHintPurchaseByPlayer[player.UserId] = {
			kind = key,
			productId = tonumber(product.id),
			createdAt = os.time(),
		}
		return { success = true, productId = tonumber(product.id) }
	end

	if key == "daily_hint" then
		local product = MonetizationConfig.HintProducts.dailyHint
		if not product or (tonumber(product.id) or 0) <= 0 then
			return { success = false, message = "set dailyHint product id first" }
		end
		if tonumber(session.packId) ~= 0 then
			return { success = false, message = "not in daily" }
		end
		pendingSpecialHintPurchaseByPlayer[player.UserId] = {
			kind = key,
			productId = tonumber(product.id),
			createdAt = os.time(),
		}
		return { success = true, productId = tonumber(product.id) }
	end

	if key == "daily_pick_hint" then
		local product = MonetizationConfig.HintProducts.dailySelectionHint
		local rr = tonumber(row)
		local cc = tonumber(col)
		if not product or (tonumber(product.id) or 0) <= 0 then
			return { success = false, message = "set dailySelectionHint product id first" }
		end
		if tonumber(session.packId) ~= 0 then
			return { success = false, message = "not in daily" }
		end
		if rr == nil or cc == nil then
			return { success = false, message = "invalid cell" }
		end
		local levelData = getActiveLevelData(player, session)
		if not levelData or not isWordCell(levelData, rr, cc) then
			return { success = false, message = "invalid cell" }
		end
		pendingSpecialHintPurchaseByPlayer[player.UserId] = {
			kind = key,
			productId = tonumber(product.id),
			row = rr,
			col = cc,
			createdAt = os.time(),
		}
		return { success = true, productId = tonumber(product.id) }
	end

	return { success = false, message = "invalid purchase kind" }
end


RemoteRegistry:GetFunction("UseArrowOnCell").OnServerInvoke = function(player, row, col)
	local pvpMatch = getMatchForPlayer(player)
	local activeTimed = getTimedMatch(player)
	local arrowCost = ARROW_COST_COINS
	if pvpMatch and not pvpMatch.completed then
		arrowCost = PVP_ARROW_COST_COINS
	elseif activeTimed then
		arrowCost = TIMED_ARROW_COST_COINS
	end
	if getHardcoreRun(player) then
		return { success = false, message = "disabled in hardcore", coins = DataService.getCoins(player), cost = arrowCost }
	end

	if typeof(row) ~= "number" or typeof(col) ~= "number" then
		return { success = false, message = "invalid cell", coins = DataService.getCoins(player), cost = arrowCost }
	end

	local session = GameService.GetSession(player.UserId)
	if not session then
		return { success = false, message = "no active level", coins = DataService.getCoins(player), cost = arrowCost }
	end

	local authLevelData = getActiveLevelData(player, session)
	if not authLevelData or not isWordCell(authLevelData, row, col) then
		return { success = false, message = "invalid cell", coins = DataService.getCoins(player), cost = arrowCost }
	end

	local spendOk, usedToken = DataService.useSelectionHint(player, arrowCost)
	if not spendOk then
		return { success = false, message = "not enough coins", coins = DataService.getCoins(player), cost = arrowCost, selectionHints = DataService.getSelectionHints(player) }
	end

	LevelPayloadService.MarkHintedCell(session, row, col)
	if isNormalModeSession(player, session) then
		DataService.saveNormalModeBoardSession(player, authLevelData, session)
	end
	RemoteRegistry:GetEvent("HintReveal"):FireClient(player, {
		row = row,
		col = col,
		letter = LevelPayloadService.GetLetterAtCell(authLevelData, row, col),
		mode = "arrow",
	})
	RemoteRegistry:GetEvent("UpdateCoins"):FireClient(player, DataService.getCoins(player))
	RemoteRegistry:GetEvent("UpdateSelectionHints"):FireClient(player, DataService.getSelectionHints(player))

	return {
		success = true,
		message = "ok",
		cost = usedToken and 0 or arrowCost,
		usedAccuracyToken = usedToken,
		coins = DataService.getCoins(player),
		selectionHints = DataService.getSelectionHints(player),
	}
end


RemoteRegistry:GetFunction("BuyHintsWithCoins").OnServerInvoke = function(player, hintAmount, coinCost)
	if typeof(hintAmount) ~= "number" or typeof(coinCost) ~= "number" then
		return false
	end
	
	-- Validate the cost matches expected prices
	local validPrices = { [1] = NORMAL_HINT_REFILL_COIN_COST }
	local baseCost = validPrices[hintAmount]
	if not baseCost then
		return false
	end
	local expectedCost = baseCost
	if math.floor(coinCost + 0.5) ~= expectedCost then
		return false
	end
	
	-- Try to spend coins
	local success = DataService.spendCoins(player, expectedCost, "HintRefill", "Shop")
	if not success then
		return false
	end
	
	-- Add hints
	DataService.addHints(player, hintAmount)
	
	-- Notify client of updated values
	RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
	RemoteRegistry:GetEvent("UpdateCoins"):FireClient(player, DataService.getCoins(player))
	
	return true
end


local DataStoreService = game:GetService("DataStoreService")
local SolvesLeaderStore = DataStoreService:GetOrderedDataStore("Wordscapes_Leaderboard_Solves_v2")
local StreakLeaderStore = DataStoreService:GetOrderedDataStore("Wordscapes_Leaderboard_Streak_v2")
local LEADERBOARD_FLUSH_INTERVAL = 120
local removeLeaderboardEntries

flushLeaderboardForUserId = function(userId)
	local player = Players:GetPlayerByUserId(userId)
	local data = player and DataService.getData(player)
	if not data then
		return
	end
	if FlagService.IsLeaderboardHidden(player) then
		removeLeaderboardEntries(userId)
		return
	end
	local stats = data.stats or {}
	local solved = tonumber(data.solvedCount) or 0
	local bestStreak = tonumber(stats.highestFreeplayStreak) or 0
	pcall(function()
		SolvesLeaderStore:SetAsync(tostring(userId), solved)
		StreakLeaderStore:SetAsync(tostring(userId), bestStreak)
	end)
end

removeLeaderboardEntries = function(userId)
	local key = tostring(userId)
	pcall(function()
		SolvesLeaderStore:RemoveAsync(key)
		StreakLeaderStore:RemoveAsync(key)
	end)
end

local function applyManualSuppression(userId)
	local targetUserId = tonumber(userId)
	if not targetUserId then
		return
	end
	DataService.setLeaderboardSuppressedByUserId(
		targetUserId,
		true,
		"manual moderation",
		"Added to ModerationConfig.ManuallyHiddenUserIds"
	)
	removeLeaderboardEntries(targetUserId)
	local onlinePlayer = Players:GetPlayerByUserId(targetUserId)
	if onlinePlayer and DataService.getData(onlinePlayer) then
		DataService.setLeaderboardSuppressed(
			onlinePlayer,
			true,
			"manual moderation",
			"Added to ModerationConfig.ManuallyHiddenUserIds"
		)
	end
end

task.spawn(function()
	for _, userId in ipairs(ModerationConfig.ManuallyHiddenUserIds or {}) do
		applyManualSuppression(userId)
	end
end)

-- Update leaderboard when a level is completed (called in LevelComplete path)
updateLeaderboard = function(player)
	local data = DataService.getData(player)
	if not data then return end
	dirtyLeaderboardUsers[player.UserId] = true
end

-- Hook into the LevelComplete path to keep leaderboard in sync
local _origComplete = GameService.CompleteLevel
GameService.CompleteLevel = function(p, packId, levelId)
	_origComplete(p, packId, levelId)
	task.spawn(updateLeaderboard, p)
end

local function readLeaderboard(store, valueField)
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 50)
	end)
	if not ok or not pages then
		return {}
	end

	local results = {}
	local page = pages:GetCurrentPage()
	for rank, entry in ipairs(page) do
		local userIdKey = tostring(entry.key)
		if FlagService.IsLeaderboardHidden(tonumber(userIdKey)) then
			continue
		end
		local nameOk, name = pcall(function()
			return game:GetService("Players"):GetNameFromUserIdAsync(tonumber(userIdKey))
		end)
		table.insert(results, {
			rank   = #results + 1,
			userId = tonumber(userIdKey),
			name   = nameOk and name or ("Player " .. userIdKey),
			[valueField] = entry.value,
		})
		if #results >= 10 then
			break
		end
	end
	return results
end

local function readLiveLeaderboard(valueField)
	local live = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if FlagService.IsLeaderboardHidden(p) then
			continue
		end
		local data = DataService.getData(p)
		local stats = data and data.stats or {}
		local value = 0
		if valueField == "solved" then
			value = tonumber(data and data.solvedCount) or 0
		elseif valueField == "bestStreak" then
			value = tonumber(stats.highestFreeplayStreak) or 0
		end
		table.insert(live, {
			userId = p.UserId,
			name = p.Name,
			[valueField] = value,
		})
	end
	table.sort(live, function(a, b)
		return (a[valueField] or 0) > (b[valueField] or 0)
	end)
	local out = {}
	for i, entry in ipairs(live) do
		if i > 10 then
			break
		end
		out[i] = {
			rank = i,
			userId = entry.userId,
			name = entry.name,
			[valueField] = entry[valueField],
		}
	end
	return out
end

task.spawn(function()
	while true do
		task.wait(LEADERBOARD_FLUSH_INTERVAL)
		local batch = dirtyLeaderboardUsers
		dirtyLeaderboardUsers = {}
		for userId in pairs(batch) do
			flushLeaderboardForUserId(userId)
		end
	end
end)

RemoteRegistry:GetFunction("GetLeaderboard").OnServerInvoke = function(_player, _scope)
	local solves = readLeaderboard(SolvesLeaderStore, "solved")
	local streaks = readLeaderboard(StreakLeaderStore, "bestStreak")
	if #solves == 0 then solves = readLiveLeaderboard("solved") end
	if #streaks == 0 then streaks = readLiveLeaderboard("bestStreak") end
	return {
		scope = "all",
		solves = solves,
		streaks = streaks,
	}
end


local HINT_PRODUCTS = {}
local COIN_PRODUCTS = {}
local PRODUCT_WEBHOOK_INFO = {}
local SINGLE_HINT_PRODUCT_ID = MonetizationConfig.HintProducts
	and ((MonetizationConfig.HintProducts.singleHint and tonumber(MonetizationConfig.HintProducts.singleHint.id))
		or (MonetizationConfig.HintProducts.dailyHint and tonumber(MonetizationConfig.HintProducts.dailyHint.id)))
	or 0
local QUICK_RESCUE_PRODUCT_ID = MonetizationConfig.HintProducts
	and MonetizationConfig.HintProducts.quickRescue
	and tonumber(MonetizationConfig.HintProducts.quickRescue.id)
	or 0
local SUPER_BUNDLE_PRODUCT_ID = MonetizationConfig.HintProducts
	and MonetizationConfig.HintProducts.superBundle
	and tonumber(MonetizationConfig.HintProducts.superBundle.id)
	or 0

for _, product in ipairs(MonetizationConfig.CoinProducts or {}) do
	local productId = tonumber(product and product.id) or 0
	if productId > 0 then
		COIN_PRODUCTS[productId] = tonumber(product.coins) or 0
		PRODUCT_WEBHOOK_INFO[productId] = {
			title = "Coins Purchased",
			label = tostring(product.label or "Coins"),
			details = tostring(tonumber(product.coins) or 0) .. " coins",
		}
	end
end

for _, key in ipairs({ "hints10", "hints100" }) do
	local product = MonetizationConfig.HintProducts and MonetizationConfig.HintProducts[key]
	if product and (tonumber(product.id) or 0) > 0 then
		HINT_PRODUCTS[tonumber(product.id)] = tonumber(product.amount) or 0
		PRODUCT_WEBHOOK_INFO[tonumber(product.id)] = {
			title = "Hints Purchased",
			label = tostring(product.label or "Hints"),
			details = tostring(tonumber(product.amount) or 0) .. " hints",
		}
	end
end

for _, key in ipairs({ "quickRescue", "pvpHint", "pvpRowHint", "dailyHint", "dailySelectionHint", "superBundle" }) do
	local product = MonetizationConfig.HintProducts and MonetizationConfig.HintProducts[key]
	local productId = product and tonumber(product.id) or 0
	if productId > 0 and not PRODUCT_WEBHOOK_INFO[productId] then
		local details = ""
		if key == "quickRescue" then
			details = string.format(
				"%d hints, %d coins",
				tonumber(product.hints) or 0,
				tonumber(product.coins) or 0
			)
		elseif key == "pvpHint" then
			details = "1v1 single-cell hint"
		elseif key == "pvpRowHint" then
			details = "1v1 row hint"
		elseif key == "dailyHint" then
			details = "Daily single-cell hint"
		elseif key == "dailySelectionHint" then
			details = "Daily selection hint"
		elseif key == "superBundle" then
			details = string.format(
				"%d hints, %d selection hints, %d coins",
				tonumber(product.hints) or 0,
				tonumber(product.selectionHints) or 0,
				tonumber(product.coins) or 0
			)
		end
		PRODUCT_WEBHOOK_INFO[productId] = {
			title = "Special Purchase",
			label = tostring(product.label or key),
			details = details,
		}
	end
end

local function sendPurchaseWebhook(player, productId, fallbackInfo)
	local payload = PRODUCT_WEBHOOK_INFO[tonumber(productId)] or fallbackInfo
	if not payload then
		payload = {
			title = "Developer Product Purchased",
			label = "Product " .. tostring(productId),
			details = "",
		}
	end
	task.spawn(function()
		WebhookService.SendPurchase(player, payload)
	end)
end

filterTextForBroadcast = function(fromUserId, text)
	local rawText = tostring(text or "")
	if rawText == "" then
		return ""
	end
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(rawText, tonumber(fromUserId) or 0)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		warn("[ServerMain] Text filter failed:", filtered)
		return rawText
	end
	return tostring(filtered or rawText)
end

getFilteredWordPayload = function(player, word, revealedCells)
	local filteredWord = filterTextForBroadcast(player and player.UserId, tostring(word or ""):upper())
	local blocked = string.find(filteredWord, "#", 1, true) ~= nil
	return filteredWord, blocked, revealedCells
end

local function notifyDevProductPurchased(player, productId)
	if player and player.Parent == Players then
		RemoteRegistry:GetEvent("DevProductPurchased"):FireClient(player, {
			productId = productId,
		})
	end
end

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local amount = HINT_PRODUCTS[info.ProductId]
	if amount then
		DataService.addHints(player, amount)
		RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
		notifyDevProductPurchased(player, info.ProductId)
		sendPurchaseWebhook(player, info.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local pending = pendingSpecialHintPurchaseByPlayer[player.UserId]
	if pending and pending.productId == info.ProductId then
		pendingSpecialHintPurchaseByPlayer[player.UserId] = nil
		if pending.kind == "pvp_row_hint" then
			if not grantPvPRowHint(player) then
				DataService.addHints(player, 1)
				RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
			end
			notifyDevProductPurchased(player, info.ProductId)
			sendPurchaseWebhook(player, info.ProductId)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if pending.kind == "pvp_hint" then
			if not grantPvPCellHint(player) then
				DataService.addHints(player, 1)
				RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
			end
			notifyDevProductPurchased(player, info.ProductId)
			sendPurchaseWebhook(player, info.ProductId)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if pending.kind == "daily_hint" then
			if not grantDailyCellHint(player) then
				DataService.addHints(player, 1)
				RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
			end
			notifyDevProductPurchased(player, info.ProductId)
			sendPurchaseWebhook(player, info.ProductId)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if pending.kind == "daily_pick_hint" then
			if not grantDailySelectedCellHint(player, pending.row, pending.col) then
				DataService.addHints(player, 1)
				RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
			end
			notifyDevProductPurchased(player, info.ProductId)
			sendPurchaseWebhook(player, info.ProductId)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	if SINGLE_HINT_PRODUCT_ID > 0 and info.ProductId == SINGLE_HINT_PRODUCT_ID then
		DataService.addHints(player, 1)
		RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
		notifyDevProductPurchased(player, info.ProductId)
		sendPurchaseWebhook(player, info.ProductId, {
			title = "Hints Purchased",
			label = "1 Hint",
			details = "1 hint",
		})
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if QUICK_RESCUE_PRODUCT_ID > 0 and info.ProductId == QUICK_RESCUE_PRODUCT_ID then
		local bundle = MonetizationConfig.HintProducts and MonetizationConfig.HintProducts.quickRescue or {}
		DataService.addHints(player, tonumber(bundle.hints) or 0)
		DataService.addCoins(player, tonumber(bundle.coins) or 0, "QuickRescue", "IAP")
		RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
		RemoteRegistry:GetEvent("UpdateCoins"):FireClient(player, DataService.getCoins(player))
		notifyDevProductPurchased(player, info.ProductId)
		sendPurchaseWebhook(player, info.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if SUPER_BUNDLE_PRODUCT_ID > 0 and info.ProductId == SUPER_BUNDLE_PRODUCT_ID then
		local bundle = MonetizationConfig.HintProducts and MonetizationConfig.HintProducts.superBundle or {}
		DataService.addHints(player, tonumber(bundle.hints) or 0)
		DataService.addSelectionHints(player, tonumber(bundle.selectionHints) or 0)
		DataService.addCoins(player, tonumber(bundle.coins) or 0, "SuperBundle", "IAP")
		RemoteRegistry:GetEvent("UpdateHints"):FireClient(player, DataService.getHints(player))
		RemoteRegistry:GetEvent("UpdateSelectionHints"):FireClient(player, DataService.getSelectionHints(player))
		RemoteRegistry:GetEvent("UpdateCoins"):FireClient(player, DataService.getCoins(player))
		notifyDevProductPurchased(player, info.ProductId)
		sendPurchaseWebhook(player, info.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local coins = COIN_PRODUCTS[info.ProductId]
	if coins then
		DataService.addCoins(player, coins, "CoinBundle_" .. tostring(info.ProductId), "IAP")
		RemoteRegistry:GetEvent("UpdateCoins"):FireClient(player, DataService.getCoins(player))
		notifyDevProductPurchased(player, info.ProductId)
		sendPurchaseWebhook(player, info.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end


RemoteRegistry:GetFunction("GetDailyPuzzle").OnServerInvoke = function(player, startSession)
	local shouldStartSession = startSession == true
	if shouldStartSession then
		timedMatchByPlayer[player.UserId] = nil
		hardcoreRunByPlayer[player.UserId] = nil
	end
	local puzzle = DailyPuzzleService.GetTodaysPuzzle()
	local completed = DailyPuzzleService.HasCompletedToday(player)
	local streak = DailyPuzzleService.GetStreak(player)
	local savedProgress = { words = {}, bonus = {} }
	if shouldStartSession and not completed and puzzle then
		DataService.logFunnelStep(player, "discovered_daily")
		startSessionWithBoardSavePolicy(player, tonumber(puzzle.packId) or 0, tonumber(puzzle.levelId) or 1, puzzle)
		savedProgress = DailyPuzzleService.GetSavedProgress(player)
		for _, savedWord in ipairs(savedProgress.words or {}) do
			GameService.RecordWord(player, savedWord)
		end
		for _, savedBonusWord in ipairs(savedProgress.bonus or {}) do
			GameService.RecordBonusWord(player, savedBonusWord)
		end
	end
	
	return {
		puzzle = getClientLevelData(puzzle),
		completed = completed,
		claimed = completed,
		streak = streak,
		canPlay = not completed,
		progressWords = savedProgress.words or {},
		progressBonus = savedProgress.bonus or {},
		progressCells = LevelPayloadService.GetRevealCellsForWords(puzzle, savedProgress.words or {}),
	}
end


RemoteRegistry:GetFunction("GetDailyQuests").OnServerInvoke = function(player)
	return DailyQuestService.GetBoard(player, "daily")
end

RemoteRegistry:GetFunction("ClaimDailyQuest").OnServerInvoke = function(player, questId)
	local success, message, reward = DailyQuestService.ClaimQuest(player, "daily", questId)
	return {
		success = success,
		message = message,
		reward = reward,
		coins = DataService.getCoins(player),
		board = DailyQuestService.GetBoard(player, "daily"),
	}
end

RemoteRegistry:GetFunction("GetQuestBoard").OnServerInvoke = function(player, period)
	local key = (period == "weekly") and "weekly" or "daily"
	return DailyQuestService.GetBoard(player, key)
end

RemoteRegistry:GetFunction("ClaimQuestReward").OnServerInvoke = function(player, period, questId)
	local key = (period == "weekly") and "weekly" or "daily"
	local success, message, reward = DailyQuestService.ClaimQuest(player, key, questId)
	return {
		success = success,
		message = message,
		reward = reward,
		coins = DataService.getCoins(player),
		board = DailyQuestService.GetBoard(player, key),
	}
end

RemoteRegistry:GetFunction("GetDailyLoginReward").OnServerInvoke = function(player)
	local state = DailyLoginService.GetState(player)
	state.coins = DataService.getCoins(player)
	return state
end

RemoteRegistry:GetFunction("ClaimDailyLoginReward").OnServerInvoke = function(player)
	local success, message, reward, state = DailyLoginService.Claim(player)
	state.coins = DataService.getCoins(player)
	return {
		success = success,
		message = message,
		reward = reward,
		state = state,
	}
end


RemoteRegistry:GetEvent("SubmitDailyWord").OnServerEvent:Connect(function(player, word)
	if DailyPuzzleService.HasCompletedToday(player) then
		return
	end

	local session = GameService.GetSession(player.UserId)
	local authLevelData = session and session.levelData
	if not session or tonumber(session.packId) ~= 0 or not authLevelData then
		local todaysPuzzle = DailyPuzzleService.GetTodaysPuzzle()
		if not todaysPuzzle then
			return
		end
		startSessionWithBoardSavePolicy(player, tonumber(todaysPuzzle.packId) or 0, tonumber(todaysPuzzle.levelId) or 1, todaysPuzzle)
		session = GameService.GetSession(player.UserId)
		authLevelData = session and session.levelData or todaysPuzzle
		local savedProgress = DailyPuzzleService.GetSavedProgress(player)
		for _, savedWord in ipairs(savedProgress.words or {}) do
			GameService.RecordWord(player, savedWord)
		end
		for _, savedBonusWord in ipairs(savedProgress.bonus or {}) do
			GameService.RecordBonusWord(player, savedBonusWord)
		end
	end
	if not authLevelData then
		return
	end
	if not session then
		return
	end

	local valid, isBonus, reason = GameService.ValidateWord(player, word, authLevelData)

	if valid then
		DailyPuzzleService.RecordWordProgress(player, word, isBonus)
		session.wordStreak = (session.wordStreak or 0) + 1
		local streakMult = math.clamp(1 + math.floor((session.wordStreak - 1) / 3), 1, 4)
		local baseCoinReward = (isBonus and 3 or 1) * streakMult
		local coinReward, rankInfo = applyRankedCoinReward(player, baseCoinReward)
		DataService.addCoins(player, coinReward)
		addRankProgress(player, isBonus and 2 or 1, "daily_word")
		DailyQuestService.RecordProgress(player, "coinsEarned", coinReward)
		if isBonus then
			GameService.RecordBonusWord(player, word)
			DailyQuestService.RecordProgress(player, "bonusWords", 1)
		else
			GameService.RecordWord(player, word)
			DailyQuestService.RecordProgress(player, "wordsFound", 1)
		end

		local revealedCells = (not isBonus) and LevelPayloadService.GetRevealCells(authLevelData, word) or nil
		local filteredWord, wasFiltered, filteredCells = getFilteredWordPayload(player, word, revealedCells)
		RemoteRegistry:GetEvent("WordFound"):FireClient(player, {
			word = filteredWord,
			valid = true,
			isBonus = isBonus,
			revealedCells = filteredCells,
			wasFiltered = wasFiltered,
			coinsEarned = coinReward,
			rankMultiplier = rankInfo and rankInfo.coinMultiplier or 1,
			wordStreak = session.wordStreak or 1,
			streakMultiplier = streakMult,
		})

		-- Check if all required words found
		if GameService.CheckComplete(player, authLevelData.words) then
			local bonusCount = 0
			local activeSession = GameService.GetSession(player.UserId)
			for _, bonusWord in ipairs(authLevelData.bonus or {}) do
				local upperBonusWord = tostring(bonusWord or ""):upper()
				if upperBonusWord ~= "" and (activeSession and activeSession.bonusFound and activeSession.bonusFound[upperBonusWord]) then
					bonusCount += 1
				end
			end

			local levelStats = GameService.GetLevelStats(player, authLevelData)
			local usedHints = (activeSession and tonumber(activeSession.hintCount) or 0) > 0
			local perfectClear = isPerfectClearResult(levelStats)
			if perfectClear then
				DataService.recordPerfectClear(player)
			end

			local reward = DailyPuzzleService.CompleteDailyPuzzle(player, bonusCount)
			addRankProgress(player, 18, "daily_complete")
			DailyQuestService.RecordProgress(player, "coinsEarned", reward or 0)
			DailyQuestService.RecordLevelResult(player, levelStats, {
				usedHints = usedHints,
				perfectClear = perfectClear,
				isDaily = true,
			})
			GameService.EndSession(player)

			RemoteRegistry:GetEvent("DailyPuzzleComplete"):FireClient(player, {
				reward = reward,
				bonusWords = bonusCount,
				streak = DailyPuzzleService.GetStreak(player),
				coins = DataService.getCoins(player),
				stats = levelStats,
			})
		end
	else
		if session then
			session.wordStreak = 0
		end
		RemoteRegistry:GetEvent("WordFound"):FireClient(player, {
			word = word,
			valid = false,
			isBonus = false,
			reason = reason or "invalid",
		})
	end
end)


RemoteRegistry:GetFunction("GetPlayerStats").OnServerInvoke = function(player)
	local stats = DataService.getStats(player)
	local data = DataService.getData(player)
	
	return {
		stats = stats,
		coins = data and data.coins or 0,
		hints = data and data.hints or 0,
		solved = data and data.solvedCount or 0,
		rank = DataService.getRankState(player),
		skill = DataService.getSkillState(player),
	}
end

RemoteRegistry:GetFunction("GetAchievements").OnServerInvoke = function(player)
	return AchievementService.GetBoard(player)
end

RemoteRegistry:GetFunction("ClaimAchievementReward").OnServerInvoke = function(player, achievementId)
	local success, message, reward = AchievementService.ClaimReward(player, achievementId)
	return {
		success = success,
		message = message,
		reward = reward,
		coins = DataService.getCoins(player),
		board = AchievementService.GetBoard(player),
	}
end

RemoteRegistry:GetFunction("ClaimGroupReward").OnServerInvoke = function(player, _joinedViaPrompt)
	if DataService.getGroupRewardClaimed(player) then
		return {
			success = false,
			message = "already claimed",
			claimed = true,
			coins = DataService.getCoins(player),
			hints = DataService.getHints(player),
		}
	end

	local eligible = playerIsInRewardGroup(player)
	if not eligible then
		return {
			success = false,
			message = "join the group first",
			claimed = false,
			coins = DataService.getCoins(player),
			hints = DataService.getHints(player),
		}
	end

	local success = grantGroupReward(player)
	return {
		success = success == true,
		message = success and "granted" or "already claimed",
		claimed = DataService.getGroupRewardClaimed(player),
		coins = DataService.getCoins(player),
		hints = DataService.getHints(player),
	}
end

RemoteRegistry:GetFunction("MarkTutorialComplete").OnServerInvoke = function(player)
	DataService.setTutorialCompleted(player, true)
	task.spawn(function()
		savePlayerDataGuarded(player, "mark tutorial complete", {
			waitForInFlight = true,
			waitTimeoutSeconds = 2,
		})
	end)
	return { success = true }
end

RemoteRegistry:GetFunction("MarkFavoritePromptShown").OnServerInvoke = function(player)
	DataService.setFavoritePromptShown(player, true)
	task.spawn(function()
		savePlayerDataGuarded(player, "mark favorite prompt shown", {
			waitForInFlight = true,
			waitTimeoutSeconds = 2,
		})
	end)
	return { success = true }
end
