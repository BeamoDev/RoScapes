-- DailyQuestService.luau
-- Daily and weekly quest progress.


local DailyQuestService = {}

local DataService = require(script.Parent.DataService)

local function scaleCoinReward(amount)
	local value = math.max(0, tonumber(amount) or 0)
	if value <= 0 then
		return 0
	end
	return math.max(1, math.floor((value * 0.25) + 0.5))
end

local DAILY_QUESTS = {
	{ id = "d_words_easy", title = "Find 6 words", metric = "wordsFound", target = 6, reward = 24, tier = "Easy" },
	{ id = "d_bonus_easy", title = "Find 2 bonus words", metric = "bonusWords", target = 2, reward = 28, tier = "Easy" },
	{ id = "d_levels_easy", title = "Complete 2 levels", metric = "levelsComplete", target = 2, reward = 40, tier = "Easy" },
	{ id = "d_coins_easy", title = "Earn 80 coins", metric = "coinsEarned", target = 80, reward = 34, tier = "Easy" },
	{ id = "d_hintless", title = "Clear 1 level with no hints", metric = "noHintClears", target = 1, reward = 55, tier = "Medium" },
	{ id = "d_accuracy", title = "Get 90%+ accuracy in 1 level", metric = "highAccuracyClears", target = 1, reward = 60, tier = "Medium" },
	{ id = "d_daily", title = "Complete today's daily puzzle", metric = "dailyPuzzleClears", target = 1, reward = 70, tier = "Medium" },
}

local WEEKLY_QUESTS = {
	{ id = "w_words", title = "Find 45 words", metric = "wordsFound", target = 45, reward = 90, tier = "Easy" },
	{ id = "w_bonus", title = "Find 10 bonus words", metric = "bonusWords", target = 10, reward = 100, tier = "Easy" },
	{ id = "w_levels", title = "Complete 10 levels", metric = "levelsComplete", target = 10, reward = 130, tier = "Easy" },
	{ id = "w_coins", title = "Earn 500 coins", metric = "coinsEarned", target = 500, reward = 120, tier = "Easy" },
	{ id = "w_no_hint", title = "Clear 3 levels with no hints", metric = "noHintClears", target = 3, reward = 150, tier = "Medium" },
	{ id = "w_accuracy", title = "Get 90%+ accuracy in 3 levels", metric = "highAccuracyClears", target = 3, reward = 165, tier = "Medium" },
	{ id = "w_daily", title = "Complete 3 daily puzzles", metric = "dailyPuzzleClears", target = 3, reward = 180, tier = "Medium" },
}

local WEEKLY_ELITE_ROTATION = {
	{ id = "we_speed_elite", title = "Elite: clear 3 levels under 45s", metric = "speedClears", target = 3, reward = 280, tier = "Elite" },
	{ id = "we_perfect_elite", title = "Elite: perfect clear 2 levels", metric = "perfectClears", target = 2, reward = 320, tier = "Elite" },
	{ id = "we_combo_elite", title = "Elite: 4 clean combo clears", metric = "comboCleanClears", target = 4, reward = 340, tier = "Elite" },
	{ id = "we_daily_elite", title = "Elite: complete 4 daily puzzles", metric = "dailyPuzzleClears", target = 4, reward = 360, tier = "Elite" },
}

local function dayKey()
	return os.date("%Y-%m-%d")
end

local function weekKey()
	return os.date("%Y-W%W")
end

local function secondsUntilNextUtcDay()
	local now = os.time()
	local t = os.date("!*t", now)
	local nextUtcMidnight = os.time({
		year = t.year,
		month = t.month,
		day = t.day + 1,
		hour = 0,
		min = 0,
		sec = 0,
	})
	return math.max(1, nextUtcMidnight - now)
end

local function secondsUntilNextUtcWeek()
	local now = os.time()
	local t = os.date("!*t", now)
	local daysUntilMonday = (9 - t.wday) % 7
	if daysUntilMonday == 0 then
		daysUntilMonday = 7
	end
	local nextUtcWeek = os.time({
		year = t.year,
		month = t.month,
		day = t.day + daysUntilMonday,
		hour = 0,
		min = 0,
		sec = 0,
	})
	return math.max(1, nextUtcWeek - now)
end

local function questList(period)
	if period ~= "weekly" then
		return DAILY_QUESTS
	end
	local list = {}
	for _, q in ipairs(WEEKLY_QUESTS) do
		table.insert(list, q)
	end
	local wk = weekKey()
	local sum = 0
	for i = 1, #wk do
		sum += string.byte(wk, i)
	end
	local elite = WEEKLY_ELITE_ROTATION[(sum % #WEEKLY_ELITE_ROTATION) + 1]
	table.insert(list, elite)
	return list
end

local function periodKey(period)
	return period == "weekly" and weekKey() or dayKey()
end

local function dataKey(period)
	return period == "weekly" and "weeklyQuests" or "dailyQuests"
end

local function ensurePeriodData(data, period)
	local keyName = dataKey(period)
	local currentKey = periodKey(period)
	local quests = questList(period)

	data[keyName] = data[keyName] or {}
	local bucket = data[keyName]
	if bucket.key ~= currentKey then
		bucket.key = currentKey
		bucket.progress = {
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
		}
		bucket.claimed = {}
	end

	bucket.progress = bucket.progress or {}
	bucket.claimed = bucket.claimed or {}
	for _, quest in ipairs(quests) do
		if bucket.progress[quest.metric] == nil then
			bucket.progress[quest.metric] = 0
		end
	end

	return bucket
end

local function ensureData(player, period)
	local data = DataService.getData(player)
	if not data then
		return nil
	end
	return ensurePeriodData(data, period)
end

local function addProgressAcrossPeriods(player, metric, amount)
	if typeof(metric) ~= "string" or metric == "" then
		return
	end
	local delta = math.max(0, tonumber(amount) or 0)
	if delta <= 0 then
		return
	end

	local touched = false
	for _, period in ipairs({ "daily", "weekly" }) do
		local bucket = ensureData(player, period)
		if bucket and bucket.progress[metric] ~= nil then
			bucket.progress[metric] = math.floor((bucket.progress[metric] or 0) + delta)
			touched = true
		end
	end
	return touched
end

function DailyQuestService.RecordProgress(player, metric, amount)
	local touched = addProgressAcrossPeriods(player, metric, amount)
	if touched then
		DataService.refreshPlayerDataFolder(player)
	end
end

function DailyQuestService.RecordLevelResult(player, levelStats, context)
	context = (typeof(context) == "table") and context or {}

	local touched = false
	local timeSeconds = tonumber(levelStats and levelStats.timeSeconds) or math.huge
	local accuracy = tonumber(levelStats and levelStats.accuracy) or 0
	local usedHints = context.usedHints == true
	local perfectClear = context.perfectClear == true
	local isDaily = context.isDaily == true

	if timeSeconds <= 45 then
		touched = addProgressAcrossPeriods(player, "speedClears", 1) or touched
	end
	if not usedHints then
		touched = addProgressAcrossPeriods(player, "noHintClears", 1) or touched
	end
	if accuracy >= 90 then
		touched = addProgressAcrossPeriods(player, "highAccuracyClears", 1) or touched
	end
	if (not usedHints) and accuracy >= 90 then
		touched = addProgressAcrossPeriods(player, "comboCleanClears", 1) or touched
	end
	if perfectClear then
		touched = addProgressAcrossPeriods(player, "perfectClears", 1) or touched
	end
	if isDaily then
		touched = addProgressAcrossPeriods(player, "dailyPuzzleClears", 1) or touched
	end

	if touched then
		DataService.refreshPlayerDataFolder(player)
	end
end

function DailyQuestService.GetBoard(player, period)
	period = (period == "weekly") and "weekly" or "daily"
	local bucket = ensureData(player, period)
	local quests = questList(period)
	if not bucket then
		return { period = period, key = periodKey(period), quests = {}, completed = 0, total = #quests }
	end

	local items = {}
	local completed = 0
	for _, quest in ipairs(quests) do
		local progress = math.floor(tonumber(bucket.progress[quest.metric]) or 0)
		local done = progress >= quest.target
		if done then
			completed += 1
		end
		table.insert(items, {
			id = quest.id,
			title = quest.title,
			progress = progress,
			target = quest.target,
			reward = scaleCoinReward(quest.reward),
			tier = quest.tier or "Normal",
			completed = done,
			claimed = bucket.claimed[quest.id] == true,
		})
	end

	return {
		period = period,
		key = bucket.key,
		quests = items,
		completed = completed,
		total = #quests,
		resetsIn = (period == "weekly") and secondsUntilNextUtcWeek() or secondsUntilNextUtcDay(),
	}
end

function DailyQuestService.ClaimQuest(player, period, questId)
	period = (period == "weekly") and "weekly" or "daily"
	if typeof(questId) ~= "string" then
		return false, "invalid quest", 0
	end

	local bucket = ensureData(player, period)
	if not bucket then
		return false, "no data", 0
	end

	local chosen = nil
	for _, quest in ipairs(questList(period)) do
		if quest.id == questId then
			chosen = quest
			break
		end
	end
	if not chosen then
		return false, "quest not found", 0
	end
	if bucket.claimed[questId] then
		return false, "already claimed", 0
	end

	local progress = tonumber(bucket.progress[chosen.metric]) or 0
	if progress < chosen.target then
		return false, "quest not complete", 0
	end

	bucket.claimed[questId] = true
	local reward = scaleCoinReward(chosen.reward)
	DataService.addCoins(player, reward)
	DataService.refreshPlayerDataFolder(player)
	return true, "claimed", reward
end

return DailyQuestService
