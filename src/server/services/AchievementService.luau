-- AchievementService.luau
-- Achievement unlock rules.


local AchievementService = {}

local DataService = require(script.Parent.DataService)

local function scaleCoinReward(amount)
	local value = math.max(0, tonumber(amount) or 0)
	if value <= 0 then
		return 0
	end
	return math.max(1, math.floor((value * 0.25) + 0.5))
end

local ACHIEVEMENTS = {
	{ id = "a_first_level", title = "First Steps", desc = "Complete your first level", metric = "solved", target = 1, reward = 20 },
	{ id = "a_10_levels", title = "Warming Up", desc = "Complete 10 levels", metric = "solved", target = 10, reward = 40 },
	{ id = "a_50_levels", title = "Word Runner", desc = "Complete 50 levels", metric = "solved", target = 50, reward = 75 },
	{ id = "a_200_levels", title = "Word Master", desc = "Complete 200 levels", metric = "solved", target = 200, reward = 130 },
	{ id = "a_100_words", title = "Letter Hunter", desc = "Find 100 words", metric = "words", target = 100, reward = 35 },
	{ id = "a_500_words", title = "Vocabulary Rising", desc = "Find 500 words", metric = "words", target = 500, reward = 70 },
	{ id = "a_2k_words", title = "Lexicon Crafter", desc = "Find 2,000 words", metric = "words", target = 2000, reward = 130 },
	{ id = "a_bonus_10", title = "Bonus Scout", desc = "Find 10 bonus words", metric = "bonus", target = 10, reward = 30 },
	{ id = "a_bonus_100", title = "Bonus Seeker", desc = "Find 100 bonus words", metric = "bonus", target = 100, reward = 75 },
	{ id = "a_first_perfect", title = "Perfect Start", desc = "Get your first perfect clear", metric = "perfectClear", target = 1, reward = 40 },
	{ id = "a_10_perfect", title = "Perfect Clear X", desc = "Get 10 perfect clears", metric = "perfectClear", target = 10, reward = 90 },
	{ id = "a_streak_5", title = "On Fire", desc = "Reach a 5 level streak", metric = "bestStreak", target = 5, reward = 50 },
	{ id = "a_streak_15", title = "Unstoppable", desc = "Reach a 15 level streak", metric = "bestStreak", target = 15, reward = 100 },
	{ id = "a_daily_1", title = "Daily Start", desc = "Complete 1 daily puzzle", metric = "dailyComplete", target = 1, reward = 30 },
	{ id = "a_daily_10", title = "Daily Devotion", desc = "Complete 10 daily puzzles", metric = "dailyComplete", target = 10, reward = 80 },
	{ id = "a_daily_streak_7", title = "Weekly Rhythm", desc = "Reach a 7-day daily streak", metric = "dailyStreak", target = 7, reward = 90 },
	{ id = "a_hints_25", title = "Helper", desc = "Use 25 hints", metric = "hintsUsed", target = 25, reward = 35 },
	{ id = "a_hints_150", title = "Oracle", desc = "Use 150 hints", metric = "hintsUsed", target = 150, reward = 100 },
	{ id = "a_coins_5k", title = "Treasure Pouch", desc = "Earn 5,000 coins", metric = "coinsEarned", target = 5000, reward = 60 },
	{ id = "a_coins_25k", title = "Coin Captain", desc = "Earn 25,000 coins", metric = "coinsEarned", target = 25000, reward = 140 },
	{ id = "a_pvp_1", title = "First Duel", desc = "Win 1 PvP match", metric = "pvpWins", target = 1, reward = 40 },
	{ id = "a_pvp_15", title = "Arena Veteran", desc = "Win 15 PvP matches", metric = "pvpWins", target = 15, reward = 120 },
	{ id = "a_pvp_matches_25", title = "Duelist", desc = "Play 25 PvP matches", metric = "pvpMatches", target = 25, reward = 90 },
	{ id = "a_pvp_streak_5", title = "PvP Streak", desc = "Reach a PvP win streak of 5", metric = "pvpBestStreak", target = 5, reward = 120 },
	{ id = "a_hardcore_5", title = "Hardcore Cadet", desc = "Reach hardcore streak 5", metric = "hardcoreBest", target = 5, reward = 120 },
	{ id = "a_hardcore_15", title = "Hardcore Pro", desc = "Reach hardcore streak 15", metric = "hardcoreBest", target = 15, reward = 220 },
}

local function getMetricValue(player, key)
	local data = DataService.getData(player) or {}
	local stats = data.stats or {}
	if key == "solved" then
		return tonumber(data.solvedCount) or 0
	elseif key == "words" then
		return tonumber(stats.totalWordsFound) or 0
	elseif key == "bonus" then
		return tonumber(stats.totalBonusWords) or 0
	elseif key == "perfectClear" then
		return tonumber(stats.perfectClearCount) or 0
	elseif key == "bestStreak" then
		return tonumber(stats.highestStreak) or 0
	elseif key == "dailyComplete" then
		return tonumber(stats.totalDailyCompleted) or 0
	elseif key == "dailyStreak" then
		return tonumber(stats.dailyStreak) or 0
	elseif key == "hintsUsed" then
		return tonumber(stats.totalHintsUsed) or 0
	elseif key == "coinsEarned" then
		return tonumber(stats.totalCoinsEarned) or 0
	elseif key == "pvpWins" then
		return tonumber(stats.pvpWins) or 0
	elseif key == "pvpMatches" then
		return tonumber(stats.pvpMatchesPlayed) or 0
	elseif key == "pvpBestStreak" then
		return tonumber(stats.pvpBestStreak) or 0
	elseif key == "hardcoreBest" then
		return tonumber(stats.hardcoreBestStreak) or 0
	end
	return 0
end

function AchievementService.GetBoard(player)
	local unlockedMap = DataService.getUnlockedAchievements(player)
	local claimedMap = DataService.getClaimedAchievements(player)
	local out = {}
	local unlockedCount = 0

	for _, a in ipairs(ACHIEVEMENTS) do
		local progress = math.floor(getMetricValue(player, a.metric))
		local done = progress >= a.target
		if done then
			DataService.unlockAchievementById(player, a.id)
			unlockedMap[a.id] = true
		end
		local unlocked = unlockedMap[a.id] == true
		if unlocked then
			unlockedCount += 1
		end
		table.insert(out, {
			id = a.id,
			title = a.title,
			desc = a.desc,
			progress = progress,
			target = a.target,
			reward = scaleCoinReward(a.reward),
			unlocked = unlocked,
			claimed = claimedMap[a.id] == true,
		})
	end

	return {
		total = #ACHIEVEMENTS,
		unlocked = unlockedCount,
		achievements = out,
	}
end

function AchievementService.ClaimReward(player, achievementId)
	if typeof(achievementId) ~= "string" then
		return false, "invalid achievement", 0
	end

	local rewardAmount = 0
	local unlocked = false
	local claimedMap = DataService.getClaimedAchievements(player)

	for _, achievement in ipairs(ACHIEVEMENTS) do
		if achievement.id == achievementId then
			rewardAmount = scaleCoinReward(achievement.reward)
			local progress = math.floor(getMetricValue(player, achievement.metric))
			unlocked = progress >= achievement.target or DataService.getUnlockedAchievements(player)[achievement.id] == true
			break
		end
	end

	if rewardAmount <= 0 then
		return false, "achievement not found", 0
	end
	if not unlocked then
		return false, "achievement locked", 0
	end
	if claimedMap[achievementId] == true then
		return false, "already claimed", 0
	end
	if not DataService.claimAchievementReward(player, achievementId) then
		return false, "already claimed", 0
	end

	DataService.addCoins(player, rewardAmount)
	return true, "claimed", rewardAmount
end

return AchievementService
