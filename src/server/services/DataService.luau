-- DataService.luau
-- Player data storage.


local DataService = {}

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local AnalyticsService = game:GetService("AnalyticsService")
local RankService = require(script.Parent.RankService)

local PlayerStore = DataStoreService:GetDataStore("Wordscapes_v2")
local SKILL_HISTORY_LIMIT = 12
local NORMAL_MODE_BOARD_SAVE_MAX_LEVEL = 1000

local function buildNormalModeBoardSaveKey(packId, levelId)
	local resolvedPackId = tonumber(packId)
	local resolvedLevelId = tonumber(levelId)
	if resolvedPackId == nil or resolvedLevelId == nil then
		return nil
	end
	return tostring(math.floor(resolvedPackId)) .. ":" .. tostring(math.floor(resolvedLevelId))
end

local function roundTo(value, decimals)
	local places = math.max(0, math.floor(tonumber(decimals) or 0))
	local factor = 10 ^ places
	return math.floor((tonumber(value) or 0) * factor + 0.5) / factor
end

local function ensureSkillHistory(stats)
	if type(stats.recentSkillSamples) ~= "table" then
		stats.recentSkillSamples = {}
	end
	return stats.recentSkillSamples
end

local function scoreToSkillLevel(score)
	local resolvedScore = math.max(0, math.min(100, tonumber(score) or 0))
	if resolvedScore >= 90 then
		return 5
	elseif resolvedScore >= 75 then
		return 4
	elseif resolvedScore >= 55 then
		return 3
	elseif resolvedScore >= 35 then
		return 2
	end
	return 1
end

local function rebuildSkillAverages(stats)
	local ratedLevels = math.max(0, math.floor(tonumber(stats.skillLevelsRated) or 0))
	if ratedLevels <= 0 then
		stats.averageSolveTimeSeconds = 0
		stats.averageGuessesPerLevel = 0
		stats.averageWrongGuessesPerLevel = 0
		stats.averageBonusWordsPerLevel = 0
		return
	end

	stats.averageSolveTimeSeconds = roundTo((tonumber(stats.totalSolveTimeSeconds) or 0) / ratedLevels, 2)
	stats.averageGuessesPerLevel = roundTo((tonumber(stats.totalGuessesTaken) or 0) / ratedLevels, 2)
	stats.averageWrongGuessesPerLevel = roundTo((tonumber(stats.totalWrongGuesses) or 0) / ratedLevels, 2)
	stats.averageBonusWordsPerLevel = roundTo((tonumber(stats.totalExtraWordsFound) or 0) / ratedLevels, 2)
end

local function calculateSkillSample(levelStats)
	local requiredWordCount = math.max(1, math.floor(tonumber(levelStats and levelStats.requiredWordCount) or 1))
	local bonusTotal = math.max(0, math.floor(tonumber(levelStats and levelStats.bonusTotal) or 0))
	local bonusFound = math.max(0, math.floor(tonumber(levelStats and levelStats.bonusFound) or 0))
	local attempts = math.max(0, math.floor(tonumber(levelStats and levelStats.attempts) or 0))
	local wrongGuesses = math.max(
		0,
		math.floor(tonumber(levelStats and levelStats.wrongGuesses) or (attempts - (tonumber(levelStats and levelStats.validCount) or 0)))
	)
	local solveTime = math.max(0, tonumber(levelStats and levelStats.timeSeconds) or 0)

	-- Grace window: only start reducing score after a generous number of guesses.
	local guessGraceThreshold = math.max(1, math.ceil(requiredWordCount * 2.5))
	local overflowAttempts = math.max(0, attempts - guessGraceThreshold)
	local overflowWrongGuesses = (attempts > guessGraceThreshold)
		and math.max(0, wrongGuesses - math.floor(requiredWordCount * 0.75))
		or 0

	-- Time is now based on word count and has a small capped impact.
	local targetTime = math.max(15, requiredWordCount * 15)
	local overtime = math.max(0, solveTime - targetTime)
	local timePenalty = math.min(8, (overtime / math.max(1, targetTime)) * 8)

	local attemptPenalty = math.min(18, overflowAttempts * 1.5)
	local wrongGuessPenalty = math.min(28, overflowWrongGuesses * 3.5)

	-- Bonus words now contribute more strongly to final score.
	local bonusRatio = (bonusTotal > 0) and math.clamp(bonusFound / bonusTotal, 0, 1) or 0
	local bonusReward = math.min(20, bonusFound * 2.5) + (bonusRatio * 12)

	local score = roundTo(math.clamp(100 - attemptPenalty - wrongGuessPenalty - timePenalty + bonusReward, 0, 100), 2)

	local level = scoreToSkillLevel(score)

	return {
		packId = tonumber(levelStats and levelStats.packId) or 0,
		levelId = tonumber(levelStats and levelStats.levelId) or 0,
		timeSeconds = roundTo(solveTime, 2),
		attempts = attempts,
		wrongGuesses = wrongGuesses,
		bonusFound = bonusFound,
		bonusTotal = bonusTotal,
		requiredWordCount = requiredWordCount,
		score = score,
		level = level,
		recordedAt = os.time(),
	}
end

local function rebuildSkillProfile(stats)
	local history = ensureSkillHistory(stats)
	local scoreTotal = 0
	local weightTotal = 0
	for index, sample in ipairs(history) do
		local weight = 0.65 + (index * 0.35)
		scoreTotal += (tonumber(sample and sample.score) or 0) * weight
		weightTotal += weight
	end

	local historyCount = #history
	local skillScore = (historyCount > 0 and weightTotal > 0) and roundTo(scoreTotal / weightTotal, 2) or 0
	local skillLevel = scoreToSkillLevel(skillScore)

	stats.skillScore = skillScore
	stats.skillLevel = skillLevel
	stats.bestSkillLevel = math.max(skillLevel, math.floor(tonumber(stats.bestSkillLevel) or 1))

	return {
		level = skillLevel,
		score = skillScore,
		bestLevel = tonumber(stats.bestSkillLevel) or skillLevel,
		recentLevelsTracked = historyCount,
		lastLevel = stats.lastLevelMetrics,
	}
end

local function deepMergeDefaults(target, defaults)
	target = target or {}
	for key, value in pairs(defaults) do
		if target[key] == nil then
			if type(value) == "table" then
				local copy = {}
				deepMergeDefaults(copy, value)
				target[key] = copy
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" then
			deepMergeDefaults(target[key], value)
		end
	end
	return target
end

local function defaultData()
	return {
		hints = 0,
		coins = 100,

		lastPack = 1,
		lastLevel = 1,
		solvedCount = 0,
		selectionHints = 0,
		groupReward = false,
		favoritePromptShown = false,

		progress = {},
		stats = {
			currentStreak = 0,
			highestStreak = 0,
			currentFreeplayStreak = 0,
			highestFreeplayStreak = 0,
			totalWordsFound = 0,
			totalBonusWords = 0,
			dailyStreak = 0,
			totalDailyCompleted = 0,
			totalLevelsCompleted = 0,
			fastestSolveSeconds = 0,
			totalHintsUsed = 0,
			totalCoinsEarned = 0,
			totalCoinsSpent = 0,
			perfectClearCount = 0,
			pvpWins = 0,
			pvpLosses = 0,
			pvpMatchesPlayed = 0,
			pvpCurrentStreak = 0,
			pvpBestStreak = 0,
			hardcoreBestStreak = 0,
			hardcoreRuns = 0,
			timedModesPlayed = 0,
			highestTimedScore = 0,
			rankPoints = 0,
			totalPlaytimeSeconds = 0,
			totalSolveTimeSeconds = 0,
			totalGuessesTaken = 0,
			totalWrongGuesses = 0,
			totalExtraWordsFound = 0,
			skillLevelsRated = 0,
			skillLevel = 1,
			bestSkillLevel = 1,
			skillScore = 0,
			averageSolveTimeSeconds = 0,
			averageGuessesPerLevel = 0,
			averageWrongGuessesPerLevel = 0,
			averageBonusWordsPerLevel = 0,
			lastLevelMetrics = {},
			recentSkillSamples = {},
		},

			dailyPuzzle = {
				date = nil,
				completed = false,
				bonusWords = 0,
				reward = 0,
				completedDayStamp = 0,
				progressWords = {},
				progressBonus = {},
			},
			normalModeBoardSaves = {},

			dailyQuests = {
			key = nil,
			progress = {
				wordsFound = 0,
				bonusWords = 0,
				levelsComplete = 0,
				hintsUsed = 0,
				coinsEarned = 0,
				speedClears = 0,
				noHintClears = 0,
				highAccuracyClears = 0,
				dailyPuzzleClears = 0,
				perfectClears = 0,
				comboCleanClears = 0,
			},
			claimed = {},
		},
		weeklyQuests = {
			key = nil,
			progress = {
				wordsFound = 0,
				bonusWords = 0,
				levelsComplete = 0,
				hintsUsed = 0,
				coinsEarned = 0,
				speedClears = 0,
				noHintClears = 0,
				highAccuracyClears = 0,
				dailyPuzzleClears = 0,
				perfectClears = 0,
				comboCleanClears = 0,
			},
			claimed = {},
		},
		dailyLogin = {
			lastClaimDay = 0,
			streak = 0,
			totalClaims = 0,
		},
		achievements = {
			unlocked = {},
			claimed = {},
		},
		tutorial = {
			completed = false,
		},
		analytics = {
			funnelSteps = {},
		},
		moderation = {
			leaderboardSuppressed = false,
			suppressionReason = "",
			suppressionDetails = "",
			flaggedAt = 0,
		},
	}
end

local cache = {}
local leaderboardSuppressionCacheByUserId = {}
local LEADERBOARD_SUPPRESSION_CACHE_TTL_SECONDS = 120

local function setLeaderboardSuppressionCache(userId, suppressed)
	local resolvedUserId = tonumber(userId)
	if not resolvedUserId then
		return
	end
	leaderboardSuppressionCacheByUserId[resolvedUserId] = {
		value = suppressed == true,
		checkedAt = os.clock(),
	}
end

local function decodeStoredPlayerData(saved, userIdForWarn)
	if saved == nil then
		return nil
	end
	if typeof(saved) == "table" then
		return saved
	end
	if typeof(saved) ~= "string" then
		if userIdForWarn ~= nil then
			warn(string.format(
				"[DataService] Unexpected stored payload type for user %s: %s",
				tostring(userIdForWarn),
				typeof(saved)
			))
		end
		return nil
	end
	if saved == "" then
		return nil
	end
	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(saved)
	end)
	if not decodeOk or typeof(decoded) ~= "table" then
		if userIdForWarn ~= nil then
			warn(string.format(
				"[DataService] Failed to decode player data for user %s: %s",
				tostring(userIdForWarn),
				tostring(decoded)
			))
		end
		return nil
	end
	return decoded
end

local function buildFunnelStepDefs()
	local defs = {
		joined = { step = 1, name = "Joined" },
		completed_tutorial = { step = 2, name = "Completed Tutorial" },
	}

	local nextStep = 3
	for solvedCount = 1, 25 do
		defs["solved_" .. tostring(solvedCount)] = {
			step = nextStep,
			name = "Solved " .. tostring(solvedCount),
		}
		nextStep += 1
	end

	defs.solved_50 = { step = nextStep, name = "Solved 50" }
	nextStep += 1
	defs.discovered_daily = { step = nextStep, name = "Discovered Daily" }
	nextStep += 1
	defs.discovered_timed = { step = nextStep, name = "Discovered Timed" }
	nextStep += 1
	defs.discovered_1v1 = { step = nextStep, name = "Discovered 1v1" }
	nextStep += 1
	defs.discovered_hardcore = { step = nextStep, name = "Discovered Hardcore" }

	return defs
end

local FUNNEL_STEP_DEFS = buildFunnelStepDefs()

local function ensureAnalyticsState(data)
	data.analytics = data.analytics or {}
	data.analytics.funnelSteps = data.analytics.funnelSteps or {}
	return data.analytics
end

local function getTransactionTypeName(flowType, provided)
	if typeof(provided) == "EnumItem" then
		return provided.Name
	end
	if type(provided) == "string" and provided ~= "" then
		local normalized = string.lower(provided)
		if normalized == "reward" or normalized == "timedreward" or normalized == "dailyreward" then
			return Enum.AnalyticsEconomyTransactionType.TimedReward.Name
		end
		if normalized == "iap" then
			return Enum.AnalyticsEconomyTransactionType.IAP.Name
		end
		if normalized == "shop" or normalized == "gameplay" then
			return Enum.AnalyticsEconomyTransactionType.Shop.Name
		end
		return provided
	end
	if flowType == Enum.AnalyticsEconomyFlowType.Source then
		return Enum.AnalyticsEconomyTransactionType.TimedReward.Name
	end
	return Enum.AnalyticsEconomyTransactionType.Shop.Name
end

local function logCoinEconomyEvent(player, flowType, amount, balanceAfter, transactionType, itemSku)
	if not player then
		return
	end
	local value = math.max(0, math.floor(tonumber(amount) or 0))
	if value <= 0 then
		return
	end
	local resolvedBalance = math.max(0, math.floor(tonumber(balanceAfter) or 0))
	local resolvedSku = tostring(itemSku or (flowType == Enum.AnalyticsEconomyFlowType.Source and "GenericSource" or "GenericSink"))
	local resolvedTransactionType = getTransactionTypeName(flowType, transactionType)
	pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			flowType,
			"Coins",
			value,
			resolvedBalance,
			resolvedTransactionType,
			resolvedSku
		)
	end)
end

local function stripDeprecatedKeys(data)
	if typeof(data) ~= "table" then
		return data
	end

	data.bonusFound = nil
	data.achievements = data.achievements or { unlocked = {}, claimed = {} }
	data.achievements.claimed = data.achievements.claimed or {}
	data.firstLogin = nil
	data.lastLogin = nil

	data.stats = data.stats or {}
	data.stats.perfectLevels = nil
	data.stats.playTime = nil
	data.stats.averageSolveSeconds = nil
	data.stats.bestAccuracy = nil
	data.stats.biggestBonusBurst = nil
	data.stats.lastSolveSeconds = nil
	data.stats.lastAccuracy = nil
	data.stats.pvpHighestStreak = nil
	data.stats.pvpCurrentRating = nil
	data.stats.pvpHighestRating = nil
	data.stats.pvpFastestWinSeconds = nil
	data.stats.pvpTotalRoundsWon = nil
	data.stats.pvpTotalRoundsLost = nil
	data.stats.pvpDraws = nil
	data.dailyStats = nil
	local migratedSelectionHints = tonumber(data.selectionHints)
	if migratedSelectionHints == nil then
		migratedSelectionHints = tonumber(data.accuracyTokens) or 0
	end
	if data.liveOps and data.liveOps.adRewards then
		local legacyTokens = tonumber(data.liveOps.adRewards.accuracyTokens) or 0
		if legacyTokens > migratedSelectionHints then
			migratedSelectionHints = legacyTokens
		end
	end
	data.selectionHints = migratedSelectionHints
	data.favoritePromptShown = data.favoritePromptShown == true
	ensureAnalyticsState(data)
	data.stats.lastLevelMetrics = type(data.stats.lastLevelMetrics) == "table" and data.stats.lastLevelMetrics or {}
	local history = ensureSkillHistory(data.stats)
	while #history > SKILL_HISTORY_LIMIT do
		table.remove(history, 1)
	end
	rebuildSkillAverages(data.stats)
	rebuildSkillProfile(data.stats)
	if data.normalModeBoardSaves ~= nil and typeof(data.normalModeBoardSaves) ~= "table" then
		data.normalModeBoardSaves = {}
	end
	data.normalModeBoardSaves = data.normalModeBoardSaves or {}
	if typeof(data.normalModeBoardSave) == "table" then
		local legacyKey = buildNormalModeBoardSaveKey(data.normalModeBoardSave.packId, data.normalModeBoardSave.levelId)
		if legacyKey and typeof(data.normalModeBoardSaves[legacyKey]) ~= "table" then
			data.normalModeBoardSaves[legacyKey] = data.normalModeBoardSave
		end
	end
	for saveKey, savedEntry in pairs(data.normalModeBoardSaves) do
		if typeof(savedEntry) ~= "table" then
			data.normalModeBoardSaves[saveKey] = nil
		else
			local canonicalKey = buildNormalModeBoardSaveKey(savedEntry.packId, savedEntry.levelId)
			if not canonicalKey then
				data.normalModeBoardSaves[saveKey] = nil
			elseif canonicalKey ~= tostring(saveKey) then
				local existing = data.normalModeBoardSaves[canonicalKey]
				if typeof(existing) ~= "table"
					or (tonumber(savedEntry.savedAt) or 0) >= (tonumber(existing.savedAt) or 0) then
					data.normalModeBoardSaves[canonicalKey] = savedEntry
				end
				data.normalModeBoardSaves[saveKey] = nil
			end
		end
	end
	data.normalModeBoardSave = nil
	data.accuracyTokens = nil
	data.codes = nil
	data.liveOps = nil
	data.freeplay = nil

	return data
end

local function getOrCreate(parent, className, name)
	local obj = parent:FindFirstChild(name)
	if not obj then
		obj = Instance.new(className)
		obj.Name = name
		obj.Parent = parent
	end
	return obj
end

local function getSelectionHintsValue(player, data)
	local cached = math.max(0, math.floor(tonumber(data and data.selectionHints) or 0))
	if not player then
		return cached
	end
	local dataFolder = player:FindFirstChild("Data")
	local currencyFolder = dataFolder and dataFolder:FindFirstChild("Currency")
	local selectionHints = currencyFolder and currencyFolder:FindFirstChild("SelectionHints")
	if selectionHints and selectionHints:IsA("IntValue") then
		local value = math.max(0, math.floor(tonumber(selectionHints.Value) or 0))
		if data then
			data.selectionHints = value
		end
		return value
	end
	return cached
end

local function setSelectionHintsValue(player, data, value)
	local nextValue = math.max(0, math.floor(tonumber(value) or 0))
	if data then
		data.selectionHints = nextValue
	end
	if not player then
		return nextValue
	end
	local dataFolder = player:FindFirstChild("Data")
	local currencyFolder = dataFolder and dataFolder:FindFirstChild("Currency")
	local economyFolder = dataFolder and dataFolder:FindFirstChild("Economy")
	local selectionHints = currencyFolder and currencyFolder:FindFirstChild("SelectionHints")
	local accuracyTokens = economyFolder and economyFolder:FindFirstChild("AccuracyTokens")
	if selectionHints and selectionHints:IsA("IntValue") then
		selectionHints.Value = nextValue
	end
	if accuracyTokens and accuracyTokens:IsA("IntValue") then
		accuracyTokens:Destroy()
	end
	return nextValue
end

local function encodeMapKeys(map)
	local keys = {}
	for key, value in pairs(map or {}) do
		if value == true then
			table.insert(keys, tostring(key))
		end
	end
	table.sort(keys)
	return HttpService:JSONEncode(keys)
end

local function decodeMapKeys(encoded)
	local result = {}
	if typeof(encoded) ~= "string" or encoded == "" then
		return result
	end
	local ok, list = pcall(function()
		return HttpService:JSONDecode(encoded)
	end)
	if not ok or typeof(list) ~= "table" then
		return result
	end
	for _, item in ipairs(list) do
		result[tostring(item)] = true
	end
	return result
end

local function cloneStringArray(values)
	local out = {}
	for _, value in ipairs(values or {}) do
		local text = tostring(value or ""):upper()
		if text ~= "" then
			table.insert(out, text)
		end
	end
	return out
end

local function cloneWordPositions(positions)
	local out = {}
	for _, pos in ipairs(positions or {}) do
		local word = tostring(pos and pos.word or ""):upper()
		if word ~= "" then
			table.insert(out, {
				word = word,
				row = tonumber(pos and pos.row) or 0,
				col = tonumber(pos and pos.col) or 0,
				dir = tostring(pos and pos.dir or "H"),
			})
		end
	end
	return out
end

local function cloneHintedCells(cells)
	local out = {}
	for _, cell in ipairs(cells or {}) do
		local row = tonumber(cell and cell.row)
		local col = tonumber(cell and cell.col)
		if row ~= nil and col ~= nil then
			table.insert(out, {
				row = row,
				col = col,
			})
		end
	end
	return out
end

local function buildRequiredSet(words)
	local set = {}
	for _, word in ipairs(words or {}) do
		local upper = tostring(word or ""):upper()
		if upper ~= "" then
			set[upper] = true
		end
	end
	return set
end

local function mapKeysToSortedArray(map)
	local values = {}
	for key, value in pairs(map or {}) do
		if value == true then
			table.insert(values, tostring(key):upper())
		end
	end
	table.sort(values)
	return values
end

local function hintedMapToArray(hintedMap)
	local cells = {}
	for key, value in pairs(hintedMap or {}) do
		if value == true then
			local rowText, colText = string.match(tostring(key), "^(-?%d+):(-?%d+)$")
			local row = tonumber(rowText)
			local col = tonumber(colText)
			if row ~= nil and col ~= nil then
				table.insert(cells, { row = row, col = col })
			end
		end
	end
	table.sort(cells, function(a, b)
		if a.row == b.row then
			return a.col < b.col
		end
		return a.row < b.row
	end)
	return cells
end

local function shouldPersistNormalModeBoard(levelData)
	local packId = tonumber(levelData and levelData.packId) or 0
	local globalLevelId = tonumber(levelData and levelData.globalLevelId) or 0
	return packId > 0 and globalLevelId >= 1 and globalLevelId <= NORMAL_MODE_BOARD_SAVE_MAX_LEVEL
end

local function hasFullNormalModeBoardSaveAccess(player)
	if not player then
		return false
	end
	if player.MembershipType == Enum.MembershipType.Premium then
		return true
	end
	return player:GetAttribute("FullBoardSaveAccess") == true
end

local function keepOnlyNormalModeBoardSaveKey(data, keepKey)
	data.normalModeBoardSaves = data.normalModeBoardSaves or {}
	local saves = data.normalModeBoardSaves
	local resolvedKeepKey = (keepKey ~= nil) and tostring(keepKey) or nil
	for key in pairs(saves) do
		if resolvedKeepKey == nil or tostring(key) ~= resolvedKeepKey then
			saves[key] = nil
		end
	end
	return saves
end

local function getCurrentNormalModeBoardSaveKey(data)
	if typeof(data) ~= "table" then
		return nil
	end
	local currentPackId = tonumber(data.lastPack)
	local currentLevelId = tonumber(data.lastLevel)
	if currentPackId == nil or currentLevelId == nil then
		return nil
	end
	if currentPackId <= 0 or currentLevelId <= 0 then
		return nil
	end
	return buildNormalModeBoardSaveKey(currentPackId, currentLevelId)
end

local function serializeLevelColor(color)
	if typeof(color) ~= "Color3" then
		return nil
	end
	return {
		r = math.clamp(math.floor((color.R * 255) + 0.5), 0, 255),
		g = math.clamp(math.floor((color.G * 255) + 0.5), 0, 255),
		b = math.clamp(math.floor((color.B * 255) + 0.5), 0, 255),
	}
end

local function deserializeLevelColor(encoded)
	if typeof(encoded) ~= "table" then
		return nil
	end
	local r = tonumber(encoded.r)
	local g = tonumber(encoded.g)
	local b = tonumber(encoded.b)
	if r == nil or g == nil or b == nil then
		return nil
	end
	return Color3.fromRGB(
		math.clamp(math.floor(r + 0.5), 0, 255),
		math.clamp(math.floor(g + 0.5), 0, 255),
		math.clamp(math.floor(b + 0.5), 0, 255)
	)
end

local function applyToPlayer(player, data)
	local dataFolder = getOrCreate(player, "Folder", "Data")
	local currencyFolder = getOrCreate(dataFolder, "Folder", "Currency")
	local progressFolder = getOrCreate(dataFolder, "Folder", "Progress")
	local gameStatsFolder = getOrCreate(dataFolder, "Folder", "GameStats")
	local coreStatsFolder = getOrCreate(gameStatsFolder, "Folder", "Core")
	local pvpStatsFolder = getOrCreate(gameStatsFolder, "Folder", "PvP")
	local rankStatsFolder = getOrCreate(gameStatsFolder, "Folder", "Rank")
	local questsFolder = getOrCreate(dataFolder, "Folder", "Quests")
	local dailyQuestFolder = getOrCreate(questsFolder, "Folder", "Daily")
	local weeklyQuestFolder = getOrCreate(questsFolder, "Folder", "Weekly")
	local economyFolder = getOrCreate(dataFolder, "Folder", "Economy")
	local achievementsFolder = getOrCreate(dataFolder, "Folder", "Achievements")
	local tutorialFolder = getOrCreate(dataFolder, "Folder", "Tutorial")
	local moderationFolder = getOrCreate(dataFolder, "Folder", "Moderation")
	local stats = data.stats or {}

	getOrCreate(currencyFolder, "IntValue", "Hints").Value = data.hints or 0
	local legacyCoins = currencyFolder:FindFirstChild("Coins")
	if legacyCoins then
		legacyCoins:Destroy()
	end

	getOrCreate(progressFolder, "IntValue", "Solved").Value = data.solvedCount or 0
	getOrCreate(progressFolder, "IntValue", "LastPack").Value = data.lastPack or 1
	getOrCreate(progressFolder, "IntValue", "LastLevel").Value = data.lastLevel or 1

	getOrCreate(gameStatsFolder, "IntValue", "BestStreak").Value = stats.highestStreak or 0

	getOrCreate(coreStatsFolder, "IntValue", "CurrentStreak").Value = stats.currentStreak or 0
	getOrCreate(coreStatsFolder, "IntValue", "BestStreak").Value = stats.highestStreak or 0
	getOrCreate(coreStatsFolder, "IntValue", "CurrentFreeplayStreak").Value = stats.currentFreeplayStreak or 0
	getOrCreate(coreStatsFolder, "IntValue", "BestFreeplayStreak").Value = stats.highestFreeplayStreak or 0
	getOrCreate(coreStatsFolder, "NumberValue", "FastestSolveSeconds").Value = stats.fastestSolveSeconds or 0
	getOrCreate(coreStatsFolder, "IntValue", "TotalLevelsCompleted").Value = stats.totalLevelsCompleted or 0
	getOrCreate(coreStatsFolder, "IntValue", "TotalWordsFound").Value = stats.totalWordsFound or 0
	getOrCreate(coreStatsFolder, "IntValue", "TotalBonusWords").Value = stats.totalBonusWords or 0
	getOrCreate(coreStatsFolder, "IntValue", "PerfectLevels").Value = 0
	getOrCreate(coreStatsFolder, "IntValue", "PerfectClearCount").Value = stats.perfectClearCount or 0
	getOrCreate(coreStatsFolder, "IntValue", "TotalHintsUsed").Value = stats.totalHintsUsed or 0
	getOrCreate(coreStatsFolder, "IntValue", "TotalCoinsEarned").Value = stats.totalCoinsEarned or 0
	getOrCreate(coreStatsFolder, "IntValue", "TotalCoinsSpent").Value = stats.totalCoinsSpent or 0
	getOrCreate(coreStatsFolder, "IntValue", "DailyStreak").Value = stats.dailyStreak or 0
	getOrCreate(coreStatsFolder, "IntValue", "TotalDailyCompleted").Value = stats.totalDailyCompleted or 0
	getOrCreate(coreStatsFolder, "IntValue", "HardcoreBestStreak").Value = stats.hardcoreBestStreak or 0
	getOrCreate(coreStatsFolder, "IntValue", "HardcoreRuns").Value = stats.hardcoreRuns or 0
	getOrCreate(coreStatsFolder, "IntValue", "TotalPlaytimeSeconds").Value = stats.totalPlaytimeSeconds or 0

	getOrCreate(pvpStatsFolder, "IntValue", "Wins").Value = stats.pvpWins or 0
	getOrCreate(pvpStatsFolder, "IntValue", "Losses").Value = stats.pvpLosses or 0
	getOrCreate(pvpStatsFolder, "IntValue", "MatchesPlayed").Value = stats.pvpMatchesPlayed or 0
	getOrCreate(pvpStatsFolder, "IntValue", "CurrentStreak").Value = stats.pvpCurrentStreak or 0
	getOrCreate(pvpStatsFolder, "IntValue", "BestStreak").Value = stats.pvpBestStreak or 0

	local rankState = RankService.GetRankState(stats.rankPoints or 0)
	getOrCreate(rankStatsFolder, "IntValue", "Points").Value = tonumber(stats.rankPoints) or 0
	getOrCreate(rankStatsFolder, "StringValue", "Id").Value = tostring(rankState.id or "BRONZE_1")
	getOrCreate(rankStatsFolder, "StringValue", "Name").Value = tostring(rankState.name or "Bronze 1")
	getOrCreate(rankStatsFolder, "IntValue", "ProgressPercent").Value = tonumber(rankState.progressPercent) or 0
	getOrCreate(rankStatsFolder, "NumberValue", "CoinMultiplier").Value = tonumber(rankState.coinMultiplier) or 1

	data.dailyQuests = data.dailyQuests or {}
	data.dailyQuests.progress = data.dailyQuests.progress or {}
	data.dailyQuests.claimed = data.dailyQuests.claimed or {}
	getOrCreate(dailyQuestFolder, "StringValue", "Key").Value = tostring(data.dailyQuests.key or "")
	getOrCreate(dailyQuestFolder, "IntValue", "WordsFound").Value = tonumber(data.dailyQuests.progress.wordsFound) or 0
	getOrCreate(dailyQuestFolder, "IntValue", "BonusWords").Value = tonumber(data.dailyQuests.progress.bonusWords) or 0
	getOrCreate(dailyQuestFolder, "IntValue", "LevelsComplete").Value = tonumber(data.dailyQuests.progress.levelsComplete) or 0
	getOrCreate(dailyQuestFolder, "IntValue", "HintsUsed").Value = tonumber(data.dailyQuests.progress.hintsUsed) or 0
	getOrCreate(dailyQuestFolder, "IntValue", "CoinsEarned").Value = tonumber(data.dailyQuests.progress.coinsEarned) or 0
	getOrCreate(dailyQuestFolder, "IntValue", "SpeedClears").Value = tonumber(data.dailyQuests.progress.speedClears) or 0
	getOrCreate(dailyQuestFolder, "IntValue", "NoHintClears").Value = tonumber(data.dailyQuests.progress.noHintClears) or 0
	getOrCreate(dailyQuestFolder, "IntValue", "HighAccuracyClears").Value = tonumber(data.dailyQuests.progress.highAccuracyClears) or 0
	getOrCreate(dailyQuestFolder, "IntValue", "DailyPuzzleClears").Value = tonumber(data.dailyQuests.progress.dailyPuzzleClears) or 0
	getOrCreate(dailyQuestFolder, "IntValue", "PerfectClears").Value = tonumber(data.dailyQuests.progress.perfectClears) or 0
	getOrCreate(dailyQuestFolder, "IntValue", "ComboCleanClears").Value = tonumber(data.dailyQuests.progress.comboCleanClears) or 0
	getOrCreate(dailyQuestFolder, "StringValue", "ClaimedJson").Value = encodeMapKeys(data.dailyQuests.claimed)

	data.weeklyQuests = data.weeklyQuests or {}
	data.weeklyQuests.progress = data.weeklyQuests.progress or {}
	data.weeklyQuests.claimed = data.weeklyQuests.claimed or {}
	getOrCreate(weeklyQuestFolder, "StringValue", "Key").Value = tostring(data.weeklyQuests.key or "")
	getOrCreate(weeklyQuestFolder, "IntValue", "WordsFound").Value = tonumber(data.weeklyQuests.progress.wordsFound) or 0
	getOrCreate(weeklyQuestFolder, "IntValue", "BonusWords").Value = tonumber(data.weeklyQuests.progress.bonusWords) or 0
	getOrCreate(weeklyQuestFolder, "IntValue", "LevelsComplete").Value = tonumber(data.weeklyQuests.progress.levelsComplete) or 0
	getOrCreate(weeklyQuestFolder, "IntValue", "HintsUsed").Value = tonumber(data.weeklyQuests.progress.hintsUsed) or 0
	getOrCreate(weeklyQuestFolder, "IntValue", "CoinsEarned").Value = tonumber(data.weeklyQuests.progress.coinsEarned) or 0
	getOrCreate(weeklyQuestFolder, "IntValue", "SpeedClears").Value = tonumber(data.weeklyQuests.progress.speedClears) or 0
	getOrCreate(weeklyQuestFolder, "IntValue", "NoHintClears").Value = tonumber(data.weeklyQuests.progress.noHintClears) or 0
	getOrCreate(weeklyQuestFolder, "IntValue", "HighAccuracyClears").Value = tonumber(data.weeklyQuests.progress.highAccuracyClears) or 0
	getOrCreate(weeklyQuestFolder, "IntValue", "DailyPuzzleClears").Value = tonumber(data.weeklyQuests.progress.dailyPuzzleClears) or 0
	getOrCreate(weeklyQuestFolder, "IntValue", "PerfectClears").Value = tonumber(data.weeklyQuests.progress.perfectClears) or 0
	getOrCreate(weeklyQuestFolder, "IntValue", "ComboCleanClears").Value = tonumber(data.weeklyQuests.progress.comboCleanClears) or 0
	getOrCreate(weeklyQuestFolder, "StringValue", "ClaimedJson").Value = encodeMapKeys(data.weeklyQuests.claimed)

	getOrCreate(currencyFolder, "IntValue", "SelectionHints").Value = tonumber(data.selectionHints) or 0
	local legacyAccuracyTokens = economyFolder:FindFirstChild("AccuracyTokens")
	if legacyAccuracyTokens then
		legacyAccuracyTokens:Destroy()
	end

	data.dailyLogin = data.dailyLogin or {}
	getOrCreate(economyFolder, "IntValue", "DailyLoginLastDay").Value = tonumber(data.dailyLogin.lastClaimDay) or 0
	getOrCreate(economyFolder, "IntValue", "DailyLoginStreak").Value = tonumber(data.dailyLogin.streak) or 0
	getOrCreate(economyFolder, "IntValue", "DailyLoginTotalClaims").Value = tonumber(data.dailyLogin.totalClaims) or 0

	data.achievements = data.achievements or { unlocked = {}, claimed = {} }
	data.achievements.unlocked = data.achievements.unlocked or {}
	data.achievements.claimed = data.achievements.claimed or {}
	getOrCreate(achievementsFolder, "StringValue", "UnlockedJson").Value = encodeMapKeys(data.achievements.unlocked)
	getOrCreate(achievementsFolder, "StringValue", "ClaimedJson").Value = encodeMapKeys(data.achievements.claimed)

	data.tutorial = data.tutorial or {}
	getOrCreate(tutorialFolder, "BoolValue", "Completed").Value = data.tutorial.completed == true
	getOrCreate(dataFolder, "BoolValue", "groupreward").Value = data.groupReward == true
	getOrCreate(dataFolder, "BoolValue", "FavoritePromptShown").Value = data.favoritePromptShown == true
	data.moderation = data.moderation or {}
	getOrCreate(moderationFolder, "BoolValue", "LeaderboardSuppressed").Value = data.moderation.leaderboardSuppressed == true
	getOrCreate(moderationFolder, "StringValue", "SuppressionReason").Value = tostring(data.moderation.suppressionReason or "")
	getOrCreate(moderationFolder, "StringValue", "SuppressionDetails").Value = tostring(data.moderation.suppressionDetails or "")
	getOrCreate(moderationFolder, "IntValue", "FlaggedAt").Value = tonumber(data.moderation.flaggedAt) or 0

	local ls = getOrCreate(player, "Folder", "leaderstats")
	getOrCreate(ls, "IntValue", "Solved").Value = data.solvedCount or 0
	getOrCreate(ls, "IntValue", "Coins").Value = data.coins or 0
end

local function syncFromPlayer(player, data)
	local dataFolder = player:FindFirstChild("Data")
	if not dataFolder then
		return
	end

	local currencyFolder = dataFolder:FindFirstChild("Currency")
	local progressFolder = dataFolder:FindFirstChild("Progress")
	local gameStatsFolder = dataFolder:FindFirstChild("GameStats")
	local coreStatsFolder = gameStatsFolder and gameStatsFolder:FindFirstChild("Core")
	local pvpStatsFolder = gameStatsFolder and gameStatsFolder:FindFirstChild("PvP")
	local rankStatsFolder = gameStatsFolder and gameStatsFolder:FindFirstChild("Rank")
	local questsFolder = dataFolder:FindFirstChild("Quests")
	local dailyQuestFolder = questsFolder and questsFolder:FindFirstChild("Daily")
	local weeklyQuestFolder = questsFolder and questsFolder:FindFirstChild("Weekly")
	local economyFolder = dataFolder:FindFirstChild("Economy")
	local achievementsFolder = dataFolder:FindFirstChild("Achievements")
	local tutorialFolder = dataFolder:FindFirstChild("Tutorial")
	local leaderstats = player:FindFirstChild("leaderstats")

	local hints = currencyFolder and currencyFolder:FindFirstChild("Hints")
	if hints then data.hints = hints.Value end
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins then data.coins = coins.Value end

	local solved = progressFolder and progressFolder:FindFirstChild("Solved")
	if solved then data.solvedCount = solved.Value end
	local lastPack = progressFolder and progressFolder:FindFirstChild("LastPack")
	if lastPack then data.lastPack = lastPack.Value end
	local lastLevel = progressFolder and progressFolder:FindFirstChild("LastLevel")
	if lastLevel then data.lastLevel = lastLevel.Value end

	data.stats = data.stats or {}
	local coreCurrentStreak = coreStatsFolder and coreStatsFolder:FindFirstChild("CurrentStreak")
	if coreCurrentStreak then data.stats.currentStreak = coreCurrentStreak.Value end
	local coreBestStreak = coreStatsFolder and coreStatsFolder:FindFirstChild("BestStreak")
	if coreBestStreak then data.stats.highestStreak = coreBestStreak.Value end
	local coreCurrentFreeplayStreak = coreStatsFolder and coreStatsFolder:FindFirstChild("CurrentFreeplayStreak")
	if coreCurrentFreeplayStreak then data.stats.currentFreeplayStreak = coreCurrentFreeplayStreak.Value end
	local coreBestFreeplayStreak = coreStatsFolder and coreStatsFolder:FindFirstChild("BestFreeplayStreak")
	if coreBestFreeplayStreak then data.stats.highestFreeplayStreak = coreBestFreeplayStreak.Value end
	local coreFastestSolve = coreStatsFolder and coreStatsFolder:FindFirstChild("FastestSolveSeconds")
	if coreFastestSolve then data.stats.fastestSolveSeconds = coreFastestSolve.Value end
	local coreTotalLevels = coreStatsFolder and coreStatsFolder:FindFirstChild("TotalLevelsCompleted")
	if coreTotalLevels then data.stats.totalLevelsCompleted = coreTotalLevels.Value end
	local coreWordsFound = coreStatsFolder and coreStatsFolder:FindFirstChild("TotalWordsFound")
	if coreWordsFound then data.stats.totalWordsFound = coreWordsFound.Value end
	local coreBonusFound = coreStatsFolder and coreStatsFolder:FindFirstChild("TotalBonusWords")
	if coreBonusFound then data.stats.totalBonusWords = coreBonusFound.Value end
	local corePerfectClear = coreStatsFolder and coreStatsFolder:FindFirstChild("PerfectClearCount")
	if corePerfectClear then data.stats.perfectClearCount = corePerfectClear.Value end
	local coreHintsUsed = coreStatsFolder and coreStatsFolder:FindFirstChild("TotalHintsUsed")
	if coreHintsUsed then data.stats.totalHintsUsed = coreHintsUsed.Value end
	local coreCoinsEarned = coreStatsFolder and coreStatsFolder:FindFirstChild("TotalCoinsEarned")
	if coreCoinsEarned then data.stats.totalCoinsEarned = coreCoinsEarned.Value end
	local coreCoinsSpent = coreStatsFolder and coreStatsFolder:FindFirstChild("TotalCoinsSpent")
	if coreCoinsSpent then data.stats.totalCoinsSpent = coreCoinsSpent.Value end
	local coreDailyStreak = coreStatsFolder and coreStatsFolder:FindFirstChild("DailyStreak")
	if coreDailyStreak then data.stats.dailyStreak = coreDailyStreak.Value end
	local coreDailyCompleted = coreStatsFolder and coreStatsFolder:FindFirstChild("TotalDailyCompleted")
	if coreDailyCompleted then data.stats.totalDailyCompleted = coreDailyCompleted.Value end
	local hardcoreBest = coreStatsFolder and coreStatsFolder:FindFirstChild("HardcoreBestStreak")
	if hardcoreBest then data.stats.hardcoreBestStreak = hardcoreBest.Value end
	local hardcoreRuns = coreStatsFolder and coreStatsFolder:FindFirstChild("HardcoreRuns")
	if hardcoreRuns then data.stats.hardcoreRuns = hardcoreRuns.Value end
	local corePlaytime = coreStatsFolder and coreStatsFolder:FindFirstChild("TotalPlaytimeSeconds")
	if corePlaytime then data.stats.totalPlaytimeSeconds = corePlaytime.Value end

	local pvpWins = pvpStatsFolder and pvpStatsFolder:FindFirstChild("Wins")
	if pvpWins then data.stats.pvpWins = pvpWins.Value end
	local pvpLosses = pvpStatsFolder and pvpStatsFolder:FindFirstChild("Losses")
	if pvpLosses then data.stats.pvpLosses = pvpLosses.Value end
	local pvpMatchesPlayed = pvpStatsFolder and pvpStatsFolder:FindFirstChild("MatchesPlayed")
	if pvpMatchesPlayed then data.stats.pvpMatchesPlayed = pvpMatchesPlayed.Value end
	local pvpCurrentStreak = pvpStatsFolder and pvpStatsFolder:FindFirstChild("CurrentStreak")
	if pvpCurrentStreak then data.stats.pvpCurrentStreak = pvpCurrentStreak.Value end
	local pvpBestStreak = pvpStatsFolder and pvpStatsFolder:FindFirstChild("BestStreak")
	if pvpBestStreak then data.stats.pvpBestStreak = pvpBestStreak.Value end
	local rankPoints = rankStatsFolder and rankStatsFolder:FindFirstChild("Points")
	if rankPoints then data.stats.rankPoints = rankPoints.Value end

	data.dailyQuests = data.dailyQuests or {}
	data.dailyQuests.progress = data.dailyQuests.progress or {}
	local dailyKey = dailyQuestFolder and dailyQuestFolder:FindFirstChild("Key")
	if dailyKey then data.dailyQuests.key = dailyKey.Value end
	local dWords = dailyQuestFolder and dailyQuestFolder:FindFirstChild("WordsFound")
	if dWords then data.dailyQuests.progress.wordsFound = dWords.Value end
	local dBonus = dailyQuestFolder and dailyQuestFolder:FindFirstChild("BonusWords")
	if dBonus then data.dailyQuests.progress.bonusWords = dBonus.Value end
	local dLevels = dailyQuestFolder and dailyQuestFolder:FindFirstChild("LevelsComplete")
	if dLevels then data.dailyQuests.progress.levelsComplete = dLevels.Value end
	local dHints = dailyQuestFolder and dailyQuestFolder:FindFirstChild("HintsUsed")
	if dHints then data.dailyQuests.progress.hintsUsed = dHints.Value end
	local dCoins = dailyQuestFolder and dailyQuestFolder:FindFirstChild("CoinsEarned")
	if dCoins then data.dailyQuests.progress.coinsEarned = dCoins.Value end
	local dSpeed = dailyQuestFolder and dailyQuestFolder:FindFirstChild("SpeedClears")
	if dSpeed then data.dailyQuests.progress.speedClears = dSpeed.Value end
	local dNoHint = dailyQuestFolder and dailyQuestFolder:FindFirstChild("NoHintClears")
	if dNoHint then data.dailyQuests.progress.noHintClears = dNoHint.Value end
	local dAccuracy = dailyQuestFolder and dailyQuestFolder:FindFirstChild("HighAccuracyClears")
	if dAccuracy then data.dailyQuests.progress.highAccuracyClears = dAccuracy.Value end
	local dDailyClear = dailyQuestFolder and dailyQuestFolder:FindFirstChild("DailyPuzzleClears")
	if dDailyClear then data.dailyQuests.progress.dailyPuzzleClears = dDailyClear.Value end
	local dPerfect = dailyQuestFolder and dailyQuestFolder:FindFirstChild("PerfectClears")
	if dPerfect then data.dailyQuests.progress.perfectClears = dPerfect.Value end
	local dCombo = dailyQuestFolder and dailyQuestFolder:FindFirstChild("ComboCleanClears")
	if dCombo then data.dailyQuests.progress.comboCleanClears = dCombo.Value end
	local dClaimed = dailyQuestFolder and dailyQuestFolder:FindFirstChild("ClaimedJson")
	data.dailyQuests.claimed = dClaimed and decodeMapKeys(dClaimed.Value) or (data.dailyQuests.claimed or {})

	data.weeklyQuests = data.weeklyQuests or {}
	data.weeklyQuests.progress = data.weeklyQuests.progress or {}
	local weeklyKey = weeklyQuestFolder and weeklyQuestFolder:FindFirstChild("Key")
	if weeklyKey then data.weeklyQuests.key = weeklyKey.Value end
	local wWords = weeklyQuestFolder and weeklyQuestFolder:FindFirstChild("WordsFound")
	if wWords then data.weeklyQuests.progress.wordsFound = wWords.Value end
	local wBonus = weeklyQuestFolder and weeklyQuestFolder:FindFirstChild("BonusWords")
	if wBonus then data.weeklyQuests.progress.bonusWords = wBonus.Value end
	local wLevels = weeklyQuestFolder and weeklyQuestFolder:FindFirstChild("LevelsComplete")
	if wLevels then data.weeklyQuests.progress.levelsComplete = wLevels.Value end
	local wHints = weeklyQuestFolder and weeklyQuestFolder:FindFirstChild("HintsUsed")
	if wHints then data.weeklyQuests.progress.hintsUsed = wHints.Value end
	local wCoins = weeklyQuestFolder and weeklyQuestFolder:FindFirstChild("CoinsEarned")
	if wCoins then data.weeklyQuests.progress.coinsEarned = wCoins.Value end
	local wSpeed = weeklyQuestFolder and weeklyQuestFolder:FindFirstChild("SpeedClears")
	if wSpeed then data.weeklyQuests.progress.speedClears = wSpeed.Value end
	local wNoHint = weeklyQuestFolder and weeklyQuestFolder:FindFirstChild("NoHintClears")
	if wNoHint then data.weeklyQuests.progress.noHintClears = wNoHint.Value end
	local wAccuracy = weeklyQuestFolder and weeklyQuestFolder:FindFirstChild("HighAccuracyClears")
	if wAccuracy then data.weeklyQuests.progress.highAccuracyClears = wAccuracy.Value end
	local wDailyClear = weeklyQuestFolder and weeklyQuestFolder:FindFirstChild("DailyPuzzleClears")
	if wDailyClear then data.weeklyQuests.progress.dailyPuzzleClears = wDailyClear.Value end
	local wPerfect = weeklyQuestFolder and weeklyQuestFolder:FindFirstChild("PerfectClears")
	if wPerfect then data.weeklyQuests.progress.perfectClears = wPerfect.Value end
	local wCombo = weeklyQuestFolder and weeklyQuestFolder:FindFirstChild("ComboCleanClears")
	if wCombo then data.weeklyQuests.progress.comboCleanClears = wCombo.Value end
	local wClaimed = weeklyQuestFolder and weeklyQuestFolder:FindFirstChild("ClaimedJson")
	data.weeklyQuests.claimed = wClaimed and decodeMapKeys(wClaimed.Value) or (data.weeklyQuests.claimed or {})

	local selectionHints = currencyFolder and currencyFolder:FindFirstChild("SelectionHints")
	local accuracyTokens = economyFolder and economyFolder:FindFirstChild("AccuracyTokens")
	if selectionHints then
		data.selectionHints = selectionHints.Value
	elseif accuracyTokens then
		data.selectionHints = accuracyTokens.Value
	end

	data.dailyLogin = data.dailyLogin or {}
	local dailyLoginLastDay = economyFolder and economyFolder:FindFirstChild("DailyLoginLastDay")
	if dailyLoginLastDay then data.dailyLogin.lastClaimDay = dailyLoginLastDay.Value end
	local dailyLoginStreak = economyFolder and economyFolder:FindFirstChild("DailyLoginStreak")
	if dailyLoginStreak then data.dailyLogin.streak = dailyLoginStreak.Value end
	local dailyLoginTotalClaims = economyFolder and economyFolder:FindFirstChild("DailyLoginTotalClaims")
	if dailyLoginTotalClaims then data.dailyLogin.totalClaims = dailyLoginTotalClaims.Value end

	data.achievements = data.achievements or { unlocked = {}, claimed = {} }
	local unlockedJson = achievementsFolder and achievementsFolder:FindFirstChild("UnlockedJson")
	data.achievements.unlocked = unlockedJson and decodeMapKeys(unlockedJson.Value) or (data.achievements.unlocked or {})
	local claimedJson = achievementsFolder and achievementsFolder:FindFirstChild("ClaimedJson")
	data.achievements.claimed = claimedJson and decodeMapKeys(claimedJson.Value) or (data.achievements.claimed or {})

	data.tutorial = data.tutorial or {}
	local tutorialCompleted = tutorialFolder and tutorialFolder:FindFirstChild("Completed")
	if tutorialCompleted then
		data.tutorial.completed = tutorialCompleted.Value
	end
	local groupRewardValue = dataFolder:FindFirstChild("groupreward")
	if groupRewardValue then
		data.groupReward = groupRewardValue.Value == true
	end
	local favoritePromptShownValue = dataFolder:FindFirstChild("FavoritePromptShown")
	if favoritePromptShownValue then
		data.favoritePromptShown = favoritePromptShownValue.Value == true
	end

	local moderationFolder = dataFolder:FindFirstChild("Moderation")
	data.moderation = data.moderation or {}
	local leaderboardSuppressed = moderationFolder and moderationFolder:FindFirstChild("LeaderboardSuppressed")
	if leaderboardSuppressed then
		data.moderation.leaderboardSuppressed = leaderboardSuppressed.Value == true
	end
	local suppressionReason = moderationFolder and moderationFolder:FindFirstChild("SuppressionReason")
	if suppressionReason then
		data.moderation.suppressionReason = suppressionReason.Value
	end
	local suppressionDetails = moderationFolder and moderationFolder:FindFirstChild("SuppressionDetails")
	if suppressionDetails then
		data.moderation.suppressionDetails = suppressionDetails.Value
	end
	local flaggedAt = moderationFolder and moderationFolder:FindFirstChild("FlaggedAt")
	if flaggedAt then
		data.moderation.flaggedAt = flaggedAt.Value
	end

end

function DataService.loadPlayerData(player)
	local userId = player.UserId
	if cache[userId] then
		return cache[userId]
	end

	local ok, saved = pcall(function()
		return PlayerStore:GetAsync(tostring(userId))
	end)

	local data
	if ok and saved then
		local decoded = decodeStoredPlayerData(saved, userId)
		if decoded then
			data = deepMergeDefaults(decoded, defaultData())
		else
			data = defaultData()
		end
	else
		data = defaultData()
	end
	data = stripDeprecatedKeys(data)

	cache[userId] = data
	setLeaderboardSuppressionCache(userId, data.moderation and data.moderation.leaderboardSuppressed == true)
	applyToPlayer(player, data)
	return data
end

function DataService.savePlayerData(player)
	if not player then
		return false, "invalid player"
	end
	local userId = player.UserId
	local data = cache[userId]
	if not data then
		return false, "no cached data"
	end

	syncFromPlayer(player, data)
	stripDeprecatedKeys(data)

	local encodeOk, encoded = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	if not encodeOk then
		warn(string.format("[DataService] Failed to encode player data for %s (%d): %s", player.Name, userId, tostring(encoded)))
		return false, tostring(encoded)
	end

	local saveOk, saveErr = pcall(function()
		PlayerStore:SetAsync(tostring(userId), encoded)
	end)
	if not saveOk then
		warn(string.format("[DataService] Failed to save player data for %s (%d): %s", player.Name, userId, tostring(saveErr)))
		return false, tostring(saveErr)
	end
	return true
end

function DataService.clearPlayerData(player)
	cache[player.UserId] = nil
end

function DataService.getData(player)
	return cache[player.UserId]
end

function DataService.getSavedNormalModeBoard(player, packId, levelId)
	local data = cache[player.UserId]
	if not data then
		return nil
	end
	local saveKey = buildNormalModeBoardSaveKey(packId, levelId)
	if not saveKey then
		return nil
	end
	data.normalModeBoardSaves = data.normalModeBoardSaves or {}
	if not hasFullNormalModeBoardSaveAccess(player) then
		local currentSaveKey = getCurrentNormalModeBoardSaveKey(data)
		if currentSaveKey and saveKey ~= currentSaveKey and typeof(data.normalModeBoardSaves[currentSaveKey]) == "table" then
			return nil
		end
	end
	local saves = data.normalModeBoardSaves
	if typeof(saves) ~= "table" then
		return nil
	end
	local saved = saves[saveKey]
	if typeof(saved) ~= "table" then
		return nil
	end
	if tonumber(saved.packId) ~= tonumber(packId) or tonumber(saved.levelId) ~= tonumber(levelId) then
		return nil
	end

	local letters = cloneStringArray(saved.letters)
	local words = cloneStringArray(saved.words)
	local bonus = cloneStringArray(saved.bonus)
	local positions = cloneWordPositions(saved.positions)
	if #letters <= 0 or #words <= 0 or #positions <= 0 then
		return nil
	end

	local levelData = {
		packId = tonumber(saved.packId) or 1,
		levelId = tonumber(saved.levelId) or 1,
		globalLevelId = tonumber(saved.globalLevelId) or 1,
		templateId = saved.templateId,
		packName = tostring(saved.packName or ""),
		letters = letters,
		words = words,
		bonus = bonus,
		positions = positions,
		requiredSet = buildRequiredSet(words),
		gridRows = tonumber(saved.gridRows) or 0,
		gridCols = tonumber(saved.gridCols) or 0,
		difficulty = tostring(saved.difficulty or ""),
		levelColor = deserializeLevelColor(saved.levelColor),
	}
	if not shouldPersistNormalModeBoard(levelData) then
		return nil
	end

	return {
		levelData = levelData,
		progressWords = cloneStringArray(saved.progressWords),
		progressBonus = cloneStringArray(saved.progressBonus),
		hintedCells = cloneHintedCells(saved.hintedCells),
	}
end

function DataService.saveNormalModeBoardSession(player, levelData, session)
	local data = cache[player.UserId]
	if not data or not session or not shouldPersistNormalModeBoard(levelData) then
		return false
	end
	local saveKey = buildNormalModeBoardSaveKey(levelData and levelData.packId, levelData and levelData.levelId)
	if not saveKey then
		return false
	end

	local words = cloneStringArray(levelData.words)
	local positions = cloneWordPositions(levelData.positions)
	if #words <= 0 or #positions <= 0 then
		return false
	end

	data.normalModeBoardSaves = data.normalModeBoardSaves or {}
	if not hasFullNormalModeBoardSaveAccess(player) then
		local currentSaveKey = getCurrentNormalModeBoardSaveKey(data)
		local hasCurrentSave = currentSaveKey and typeof(data.normalModeBoardSaves[currentSaveKey]) == "table"
		if hasCurrentSave and saveKey ~= currentSaveKey then
			return false
		end
		keepOnlyNormalModeBoardSaveKey(data, hasCurrentSave and currentSaveKey or saveKey)
	end
	data.normalModeBoardSaves[saveKey] = {
		packId = tonumber(levelData.packId) or 1,
		levelId = tonumber(levelData.levelId) or 1,
		globalLevelId = tonumber(levelData.globalLevelId) or 1,
		templateId = levelData.templateId,
		packName = tostring(levelData.packName or ""),
		letters = cloneStringArray(levelData.letters),
		words = words,
		bonus = cloneStringArray(levelData.bonus),
		positions = positions,
		gridRows = tonumber(levelData.gridRows) or 0,
		gridCols = tonumber(levelData.gridCols) or 0,
		difficulty = tostring(levelData.difficulty or ""),
		levelColor = serializeLevelColor(levelData.levelColor),
		progressWords = mapKeysToSortedArray(session.foundWords),
		progressBonus = mapKeysToSortedArray(session.bonusFound),
		hintedCells = hintedMapToArray(session.hintedCells),
		savedAt = os.time(),
	}
	return true
end

function DataService.clearTransientNormalModeBoardSaves(player)
	local data = cache[player.UserId]
	if not data then
		return false
	end
	if hasFullNormalModeBoardSaveAccess(player) then
		return false
	end
	local saves = data.normalModeBoardSaves
	local hadAny = typeof(saves) == "table" and next(saves) ~= nil
	data.normalModeBoardSaves = {}
	data.normalModeBoardSave = nil
	return hadAny
end

function DataService.clearNormalModeBoardSave(player, packId, levelId)
	local data = cache[player.UserId]
	if not data then
		return false
	end
	local saves = data.normalModeBoardSaves
	if typeof(saves) ~= "table" then
		data.normalModeBoardSave = nil
		return false
	end

	if packId ~= nil and levelId ~= nil then
		local key = buildNormalModeBoardSaveKey(packId, levelId)
		if not key or typeof(saves[key]) ~= "table" then
			return false
		end
		saves[key] = nil
		data.normalModeBoardSave = nil
		return true
	end

	if packId == nil and levelId == nil then
		data.normalModeBoardSaves = {}
		data.normalModeBoardSave = nil
		return true
	end

	local cleared = false
	for key, saved in pairs(saves) do
		if typeof(saved) == "table" then
			local packMatches = (packId == nil) or (tonumber(saved.packId) == tonumber(packId))
			local levelMatches = (levelId == nil) or (tonumber(saved.levelId) == tonumber(levelId))
			if packMatches and levelMatches then
				saves[key] = nil
				cleared = true
			end
		else
			saves[key] = nil
		end
	end
	if cleared then
		data.normalModeBoardSave = nil
	end
	return cleared
end

function DataService.refreshPlayerDataFolder(player)
	local data = cache[player.UserId]
	if not data then
		return
	end
	applyToPlayer(player, data)
end

function DataService.setProgress(player, packId, levelId, complete)
	local data = cache[player.UserId]
	if not data then return end

	data.progress[tostring(packId)] = data.progress[tostring(packId)] or {}
	local alreadyComplete = data.progress[tostring(packId)][tostring(levelId)] == true
	data.progress[tostring(packId)][tostring(levelId)] = complete

	if complete and not alreadyComplete then
		data.solvedCount = (data.solvedCount or 0) + 1
		data.lastPack = packId
		data.lastLevel = levelId + 1
		data.stats = data.stats or {}
		data.stats.totalLevelsCompleted = (data.stats.totalLevelsCompleted or 0) + 1
		data.stats.currentStreak = (tonumber(data.stats.currentStreak) or 0) + 1
		if data.stats.currentStreak > (tonumber(data.stats.highestStreak) or 0) then
			data.stats.highestStreak = data.stats.currentStreak
		end
	end

	applyToPlayer(player, data)
	if complete and not alreadyComplete then
		local solvedCount = tonumber(data.solvedCount) or 0
		if solvedCount >= 1 and solvedCount <= 25 then
			DataService.logFunnelStep(player, "solved_" .. tostring(solvedCount))
		end
		if solvedCount == 50 then
			DataService.logFunnelStep(player, "solved_50")
		end
	end
end

function DataService.resetLevelStreak(player)
	local data = cache[player.UserId]
	if not data then
		return
	end
	data.stats = data.stats or {}
	if (tonumber(data.stats.currentStreak) or 0) == 0 then
		return
	end
	data.stats.currentStreak = 0
	applyToPlayer(player, data)
end

function DataService.incrementFreeplayStreak(player)
	local data = cache[player.UserId]
	if not data then
		return 0, 0
	end
	data.stats = data.stats or {}
	data.stats.currentFreeplayStreak = (tonumber(data.stats.currentFreeplayStreak) or 0) + 1
	if (tonumber(data.stats.currentFreeplayStreak) or 0) > (tonumber(data.stats.highestFreeplayStreak) or 0) then
		data.stats.highestFreeplayStreak = tonumber(data.stats.currentFreeplayStreak) or 0
	end
	applyToPlayer(player, data)
	return tonumber(data.stats.currentFreeplayStreak) or 0, tonumber(data.stats.highestFreeplayStreak) or 0
end

function DataService.resetFreeplayStreak(player)
	local data = cache[player.UserId]
	if not data then
		return
	end
	data.stats = data.stats or {}
	if (tonumber(data.stats.currentFreeplayStreak) or 0) == 0 then
		return
	end
	data.stats.currentFreeplayStreak = 0
	applyToPlayer(player, data)
end

function DataService.getProgress(player)
	local data = cache[player.UserId]
	return data and data.progress or {}
end

function DataService.addHints(player, amount)
	local data = cache[player.UserId]
	if not data then return end
	data.hints = (data.hints or 0) + amount
	applyToPlayer(player, data)
end

function DataService.useHint(player)
	local data = cache[player.UserId]
	if not data or (data.hints or 0) <= 0 then
		return false
	end
	data.hints = data.hints - 1
	data.stats = data.stats or {}
	data.stats.totalHintsUsed = (data.stats.totalHintsUsed or 0) + 1
	applyToPlayer(player, data)
	return true
end

function DataService.getHints(player)
	local data = cache[player.UserId]
	return data and data.hints or 0
end

function DataService.addCoins(player, amount, itemSku, transactionType)
	local data = cache[player.UserId]
	if not data then return end
	data.coins = (data.coins or 0) + amount
	data.stats = data.stats or {}
	if amount > 0 then
		data.stats.totalCoinsEarned = (data.stats.totalCoinsEarned or 0) + amount
	end
	applyToPlayer(player, data)
	logCoinEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, amount, data.coins, transactionType, itemSku)
end

function DataService.spendCoins(player, amount, itemSku, transactionType)
	local data = cache[player.UserId]
	if not data or (data.coins or 0) < amount then
		return false
	end
	data.coins = data.coins - amount
	data.stats = data.stats or {}
	if amount > 0 then
		data.stats.totalCoinsSpent = (data.stats.totalCoinsSpent or 0) + amount
	end
	applyToPlayer(player, data)
	logCoinEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, amount, data.coins, transactionType, itemSku)
	return true
end

function DataService.getCoins(player)
	local data = cache[player.UserId]
	return data and data.coins or 0
end

function DataService.addWordFound(player, isBonus)
	local data = cache[player.UserId]
	if not data then return end
	data.stats = data.stats or {}
	if isBonus then
		data.stats.totalBonusWords = (data.stats.totalBonusWords or 0) + 1
	else
		data.stats.totalWordsFound = (data.stats.totalWordsFound or 0) + 1
	end
end

function DataService.getStats(player)
	local data = cache[player.UserId]
	return data and data.stats or {}
end

function DataService.getSkillState(player)
	local stats = DataService.getStats(player)
	return {
		level = math.clamp(math.floor(tonumber(stats.skillLevel) or 1), 1, 5),
		score = roundTo(stats.skillScore or 0, 2),
		bestLevel = math.clamp(math.floor(tonumber(stats.bestSkillLevel) or 1), 1, 5),
		recentLevelsTracked = #ensureSkillHistory(stats),
		lastLevel = stats.lastLevelMetrics,
	}
end

function DataService.addPlaytime(player, amountSeconds)
	local data = cache[player.UserId]
	if not data then
		return
	end
	local delta = math.max(0, math.floor(tonumber(amountSeconds) or 0))
	if delta <= 0 then
		return
	end
	data.stats = data.stats or {}
	data.stats.totalPlaytimeSeconds = (data.stats.totalPlaytimeSeconds or 0) + delta
	applyToPlayer(player, data)
end

function DataService.recordPvPMatchResult(player, opponent, won)
	local data = cache[player.UserId]
	if not data then
		return
	end

	data.stats = data.stats or {}
	data.stats.pvpMatchesPlayed = (data.stats.pvpMatchesPlayed or 0) + 1

	if won == true then
		data.stats.pvpWins = (data.stats.pvpWins or 0) + 1
		data.stats.pvpCurrentStreak = (data.stats.pvpCurrentStreak or 0) + 1
		if data.stats.pvpCurrentStreak > (data.stats.pvpBestStreak or 0) then
			data.stats.pvpBestStreak = data.stats.pvpCurrentStreak
		end
	elseif won == false then
		data.stats.pvpLosses = (data.stats.pvpLosses or 0) + 1
		data.stats.pvpCurrentStreak = 0
	else
		data.stats.pvpCurrentStreak = 0
	end

	applyToPlayer(player, data)
end

function DataService.setHardcoreBest(player, streak)
	local data = cache[player.UserId]
	if not data then
		return
	end
	local value = math.max(0, math.floor(tonumber(streak) or 0))
	data.stats = data.stats or {}
	data.stats.hardcoreRuns = (data.stats.hardcoreRuns or 0) + 1
	if value > (data.stats.hardcoreBestStreak or 0) then
		data.stats.hardcoreBestStreak = value
	end
	applyToPlayer(player, data)
end

function DataService.recordCasualLevelResult(player, levelStats)
	local data = cache[player.UserId]
	if not data then
		return {
			level = 1,
			score = 0,
			bestLevel = 1,
			recentLevelsTracked = 0,
			lastLevel = nil,
		}
	end
	data.stats = data.stats or {}
	local solveTime = math.max(0, tonumber(levelStats and levelStats.timeSeconds) or 0)
	if solveTime > 0 then
		local currentBest = tonumber(data.stats.fastestSolveSeconds) or 0
		if currentBest <= 0 or solveTime < currentBest then
			data.stats.fastestSolveSeconds = math.floor(solveTime * 100 + 0.5) / 100
		end
	end
	local attempts = math.max(0, math.floor(tonumber(levelStats and levelStats.attempts) or 0))
	local wrongGuesses = math.max(
		0,
		math.floor(tonumber(levelStats and levelStats.wrongGuesses) or (attempts - (tonumber(levelStats and levelStats.validCount) or 0)))
	)
	local bonusFound = math.max(0, math.floor(tonumber(levelStats and levelStats.bonusFound) or 0))
	data.stats.totalSolveTimeSeconds = roundTo((tonumber(data.stats.totalSolveTimeSeconds) or 0) + solveTime, 2)
	data.stats.totalGuessesTaken = (tonumber(data.stats.totalGuessesTaken) or 0) + attempts
	data.stats.totalWrongGuesses = (tonumber(data.stats.totalWrongGuesses) or 0) + wrongGuesses
	data.stats.totalExtraWordsFound = (tonumber(data.stats.totalExtraWordsFound) or 0) + bonusFound
	data.stats.skillLevelsRated = (tonumber(data.stats.skillLevelsRated) or 0) + 1
	data.stats.lastLevelMetrics = calculateSkillSample(levelStats)

	local history = ensureSkillHistory(data.stats)
	table.insert(history, data.stats.lastLevelMetrics)
	while #history > SKILL_HISTORY_LIMIT do
		table.remove(history, 1)
	end

	rebuildSkillAverages(data.stats)
	local skillState = rebuildSkillProfile(data.stats)
	applyToPlayer(player, data)
	return skillState
end

function DataService.recordTimedModeScore(player, solvedCount)
	local data = cache[player.UserId]
	if not data then
		return 0
	end
	data.stats = data.stats or {}
	local score = math.max(0, math.floor(tonumber(solvedCount) or 0))
	if score > (tonumber(data.stats.highestTimedScore) or 0) then
		data.stats.highestTimedScore = score
	end
	applyToPlayer(player, data)
	return tonumber(data.stats.highestTimedScore) or 0
end

function DataService.recordTimedModePlayed(player)
	local data = cache[player.UserId]
	if not data then
		return 0
	end
	data.stats = data.stats or {}
	data.stats.timedModesPlayed = (tonumber(data.stats.timedModesPlayed) or 0) + 1
	applyToPlayer(player, data)
	return tonumber(data.stats.timedModesPlayed) or 0
end

function DataService.setTutorialCompleted(player, completed)
	local data = cache[player.UserId]
	if not data then
		return
	end
	data.tutorial = data.tutorial or {}
	data.tutorial.completed = completed == true
	applyToPlayer(player, data)
	if completed == true then
		DataService.logFunnelStep(player, "completed_tutorial")
	end
end

function DataService.getTutorialCompleted(player)
	local data = cache[player.UserId]
	return data and data.tutorial and data.tutorial.completed == true
end

function DataService.setGroupRewardClaimed(player, claimed)
	local data = cache[player.UserId]
	if not data then
		return
	end
	data.groupReward = claimed == true
	applyToPlayer(player, data)
end

function DataService.getGroupRewardClaimed(player)
	local data = cache[player.UserId]
	return data and data.groupReward == true
end

function DataService.setFavoritePromptShown(player, shown)
	local data = cache[player.UserId]
	if not data then
		return
	end
	data.favoritePromptShown = shown == true
	applyToPlayer(player, data)
end

function DataService.getFavoritePromptShown(player)
	local data = cache[player.UserId]
	return data and data.favoritePromptShown == true
end

function DataService.logFunnelStep(player, stepKey)
	local data = cache[player.UserId]
	local def = FUNNEL_STEP_DEFS[stepKey]
	if not data or not def then
		return false
	end
	local analytics = ensureAnalyticsState(data)
	local funnelSteps = analytics.funnelSteps
	if funnelSteps[stepKey] == true then
		return false
	end
	funnelSteps[stepKey] = true
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, def.step, def.name)
	end)
	return true
end

function DataService.setLeaderboardSuppressed(player, suppressed, reason, details)
	local data = cache[player.UserId]
	if not data then
		return false
	end
	data.moderation = data.moderation or {}
	data.moderation.leaderboardSuppressed = suppressed == true
	data.moderation.suppressionReason = tostring(reason or "")
	data.moderation.suppressionDetails = tostring(details or "")
	data.moderation.flaggedAt = suppressed == true and os.time() or 0
	setLeaderboardSuppressionCache(player.UserId, suppressed == true)
	applyToPlayer(player, data)
	return true
end

function DataService.setLeaderboardSuppressedByUserId(userId, suppressed, reason, details)
	local targetUserId = tonumber(userId)
	if not targetUserId then
		return false
	end

	local cachedData = cache[targetUserId]
	if cachedData then
		cachedData.moderation = cachedData.moderation or {}
		cachedData.moderation.leaderboardSuppressed = suppressed == true
		cachedData.moderation.suppressionReason = tostring(reason or "")
		cachedData.moderation.suppressionDetails = tostring(details or "")
		cachedData.moderation.flaggedAt = suppressed == true and os.time() or 0
	end
	setLeaderboardSuppressionCache(targetUserId, suppressed == true)

	local ok = pcall(function()
		PlayerStore:UpdateAsync(tostring(targetUserId), function(saved)
			local decoded = decodeStoredPlayerData(saved)
			local data = stripDeprecatedKeys(deepMergeDefaults(decoded or {}, defaultData()))
			data.moderation = data.moderation or {}
			data.moderation.leaderboardSuppressed = suppressed == true
			data.moderation.suppressionReason = tostring(reason or "")
			data.moderation.suppressionDetails = tostring(details or "")
			data.moderation.flaggedAt = suppressed == true and os.time() or 0
			return HttpService:JSONEncode(data)
		end)
	end)

	return ok
end

function DataService.isLeaderboardSuppressed(player)
	local data = cache[player.UserId]
	return data and data.moderation and data.moderation.leaderboardSuppressed == true
end

function DataService.isLeaderboardSuppressedByUserId(userId)
	local targetUserId = tonumber(userId)
	if not targetUserId then
		return false
	end

	local cachedData = cache[targetUserId]
	if cachedData then
		local suppressed = cachedData.moderation and cachedData.moderation.leaderboardSuppressed == true
		setLeaderboardSuppressionCache(targetUserId, suppressed)
		return suppressed
	end

	local cached = leaderboardSuppressionCacheByUserId[targetUserId]
	if cached and (os.clock() - (tonumber(cached.checkedAt) or 0)) <= LEADERBOARD_SUPPRESSION_CACHE_TTL_SECONDS then
		return cached.value == true
	end

	local ok, saved = pcall(function()
		return PlayerStore:GetAsync(tostring(targetUserId))
	end)
	if not ok then
		return cached and cached.value == true or false
	end

	local decoded = decodeStoredPlayerData(saved, targetUserId)
	local suppressed = decoded and decoded.moderation and decoded.moderation.leaderboardSuppressed == true
	setLeaderboardSuppressionCache(targetUserId, suppressed)
	return suppressed == true
end

function DataService.getLeaderboardSuppressionInfo(player)
	local data = cache[player.UserId]
	if not data then
		return {
			leaderboardSuppressed = false,
			suppressionReason = "",
			suppressionDetails = "",
			flaggedAt = 0,
		}
	end
	data.moderation = data.moderation or {}
	return {
		leaderboardSuppressed = data.moderation.leaderboardSuppressed == true,
		suppressionReason = tostring(data.moderation.suppressionReason or ""),
		suppressionDetails = tostring(data.moderation.suppressionDetails or ""),
		flaggedAt = tonumber(data.moderation.flaggedAt) or 0,
	}
end

function DataService.recordPerfectClear(player)
	local data = cache[player.UserId]
	if not data then
		return 0
	end
	data.stats = data.stats or {}
	data.stats.perfectClearCount = (tonumber(data.stats.perfectClearCount) or 0) + 1
	applyToPlayer(player, data)
	return data.stats.perfectClearCount
end

function DataService.unlockAchievementById(player, achievementId)
	local data = cache[player.UserId]
	if not data or typeof(achievementId) ~= "string" then
		return false
	end
	data.achievements = data.achievements or { unlocked = {}, claimed = {} }
	data.achievements.unlocked = data.achievements.unlocked or {}
	if data.achievements.unlocked[achievementId] then
		return false
	end
	data.achievements.unlocked[achievementId] = true
	applyToPlayer(player, data)
	return true
end

function DataService.getUnlockedAchievements(player)
	local data = cache[player.UserId]
	if not data then
		return {}
	end
	data.achievements = data.achievements or { unlocked = {}, claimed = {} }
	data.achievements.unlocked = data.achievements.unlocked or {}
	return data.achievements.unlocked
end

function DataService.getClaimedAchievements(player)
	local data = cache[player.UserId]
	if not data then
		return {}
	end
	data.achievements = data.achievements or { unlocked = {}, claimed = {} }
	data.achievements.claimed = data.achievements.claimed or {}
	return data.achievements.claimed
end

function DataService.claimAchievementReward(player, achievementId)
	local data = cache[player.UserId]
	if not data or typeof(achievementId) ~= "string" then
		return false
	end
	data.achievements = data.achievements or { unlocked = {}, claimed = {} }
	data.achievements.claimed = data.achievements.claimed or {}
	if data.achievements.claimed[achievementId] then
		return false
	end
	data.achievements.claimed[achievementId] = true
	applyToPlayer(player, data)
	return true
end

function DataService.getRankState(player)
	local data = cache[player.UserId]
	local stats = data and data.stats or {}
	return RankService.GetRankState(stats.rankPoints or 0)
end

function DataService.addRankPoints(player, amount)
	local data = cache[player.UserId]
	if not data then
		return DataService.getRankState(player)
	end
	data.stats = data.stats or {}
	local delta = math.max(0, math.floor(tonumber(amount) or 0))
	data.stats.rankPoints = math.max(0, math.floor(tonumber(data.stats.rankPoints) or 0) + delta)
	applyToPlayer(player, data)
	return RankService.GetRankState(data.stats.rankPoints)
end

function DataService.getSelectionHints(player)
	local data = cache[player.UserId]
	if not data then
		return 0
	end
	return getSelectionHintsValue(player, data)
end

function DataService.addSelectionHints(player, amount)
	local data = cache[player.UserId]
	if not data then
		return
	end
	local delta = math.max(0, math.floor(tonumber(amount) or 0))
	if delta <= 0 then
		return
	end
	setSelectionHintsValue(player, data, getSelectionHintsValue(player, data) + delta)
	applyToPlayer(player, data)
end

function DataService.consumeSelectionHint(player)
	local data = cache[player.UserId]
	if not data then
		return false
	end
	local current = getSelectionHintsValue(player, data)
	if current <= 0 then
		return false
	end
	setSelectionHintsValue(player, data, current - 1)
	applyToPlayer(player, data)
	return true
end

function DataService.useSelectionHint(player, coinCost)
	local data = cache[player.UserId]
	if not data then
		return false, false
	end

	local dataFolder = player and player:FindFirstChild("Data")
	local currencyFolder = dataFolder and dataFolder:FindFirstChild("Currency")
	local currentFree = getSelectionHintsValue(player, data)
	if currentFree > 0 then
		setSelectionHintsValue(player, data, currentFree - 1)
		applyToPlayer(player, data)
		return true, true
	end

	local resolvedCost = math.max(0, math.floor(tonumber(coinCost) or 0))
	if resolvedCost <= 0 then
		return true, false
	end
	if not DataService.spendCoins(player, resolvedCost, "SelectionHint", "Shop") then
		return false, false
	end

	return true, false
end

return DataService
