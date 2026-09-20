-- DailyPuzzleService.luau
-- Daily puzzle rotation.


local DailyPuzzleService = {}
local WordDictionaryService = require(script.Parent.WordDictionaryService)

local levelsFolder = script.Parent.Parent:WaitForChild("Levels")
local dailyModule = levelsFolder:WaitForChild("Daily")
local dailyPackData = nil
local parsedDailyLevels = nil
local computedBonusByLevelIndex = {}

local function todayKeyUtc()
	return os.date("!%Y-%m-%d")
end

local function toRequiredSet(words)
	local set = {}
	for _, w in ipairs(words or {}) do
		set[tostring(w or ""):upper()] = true
	end
	return set
end

local function buildMergedBonusWords(letters, requiredWords, authoredBonusWords)
	local requiredSet = toRequiredSet(requiredWords)
	local merged = {}
	local seen = {}

	local function addWord(word)
		local upper = tostring(word or ""):upper()
		if upper == "" or requiredSet[upper] or seen[upper] then
			return
		end
		seen[upper] = true
		table.insert(merged, upper)
	end

	for _, word in ipairs(authoredBonusWords or {}) do
		addWord(word)
	end

	for _, word in ipairs(WordDictionaryService.GetWordsFormedByLetters(letters or {}, {
		bucketName = "All",
		minLength = 3,
		maxLength = #(letters or {}),
	})) do
		addWord(word)
	end

	table.sort(merged, function(a, b)
		if #a == #b then
			return a < b
		end
		return #a > #b
	end)

	return merged
end

local function parseGrid(gridRows, wordSet)
	local results = {}
	local rows = #gridRows
	local cols = gridRows[1] and #gridRows[1] or 0

	local function cell(r, c)
		local row = gridRows[r + 1]
		if not row then
			return "."
		end
		return row:sub(c + 1, c + 1)
	end

	for r = 0, rows - 1 do
		local c = 0
		while c < cols do
			if cell(r, c) ~= "." then
				local startC = c
				local letters = {}
				while c < cols and cell(r, c) ~= "." do
					table.insert(letters, cell(r, c))
					c += 1
				end
				if #letters >= 2 then
					local w = table.concat(letters)
					if wordSet[w] then
						table.insert(results, { word = w, row = r, col = startC, dir = "H" })
					end
				end
			else
				c += 1
			end
		end
	end

	for c = 0, cols - 1 do
		local r = 0
		while r < rows do
			if cell(r, c) ~= "." then
				local startR = r
				local letters = {}
				while r < rows and cell(r, c) ~= "." do
					table.insert(letters, cell(r, c))
					r += 1
				end
				if #letters >= 2 then
					local w = table.concat(letters)
					if wordSet[w] then
						table.insert(results, { word = w, row = startR, col = c, dir = "V" })
					end
				end
			else
				r += 1
			end
		end
	end

	return results
end

local function loadDailyPack()
	if parsedDailyLevels then
		return parsedDailyLevels, dailyPackData
	end

	local ok, data = pcall(require, dailyModule)
	if not ok or typeof(data) ~= "table" then
		warn("[DailyPuzzleService] Failed to load Daily pack:", data)
		parsedDailyLevels = {}
		dailyPackData = { packName = "Daily Challenge", levelColors = {} }
		computedBonusByLevelIndex = {}
		return parsedDailyLevels, dailyPackData
	end

	dailyPackData = data
	parsedDailyLevels = {}
	computedBonusByLevelIndex = {}

	for _, lvl in ipairs(data.levels or {}) do
		local allWords = {}
		for _, w in ipairs(lvl.words or {}) do
			table.insert(allWords, w)
		end
		for _, w in ipairs(lvl.bonus or {}) do
			table.insert(allWords, w)
		end

		local positions = parseGrid(lvl.grid or {}, toRequiredSet(allWords))
		local gridRows = #(lvl.grid or {})
		local gridCols = (lvl.grid and lvl.grid[1]) and #lvl.grid[1] or 0

		table.insert(parsedDailyLevels, {
			letters = lvl.letters or {},
			words = lvl.words or {},
			bonus = lvl.bonus or {},
			positions = positions,
			requiredSet = toRequiredSet(lvl.words or {}),
			gridRows = gridRows,
			gridCols = gridCols,
		})
	end

	return parsedDailyLevels, dailyPackData
end

local function getDayStamp()
	return math.floor(os.time() / 86400)
end

local function ensureTodayState(data)
	local today = todayKeyUtc()
	data.dailyPuzzle = data.dailyPuzzle or {}
	if data.dailyPuzzle.date ~= today then
		data.dailyPuzzle = {
			date = today,
			completed = false,
			bonusWords = 0,
			reward = 0,
			completedDayStamp = tonumber(data.dailyPuzzle and data.dailyPuzzle.completedDayStamp) or 0,
			progressWords = {},
			progressBonus = {},
		}
	end
	data.dailyPuzzle.progressWords = data.dailyPuzzle.progressWords or {}
	data.dailyPuzzle.progressBonus = data.dailyPuzzle.progressBonus or {}
	return data.dailyPuzzle
end

function DailyPuzzleService.GetTodaysPuzzle()
	local levels, packData = loadDailyPack()
	local totalLevels = #levels
	if totalLevels == 0 then
		return nil
	end

	local dayStamp = getDayStamp()
	local levelIndex = ((dayStamp - 1) % totalLevels) + 1
	local level = levels[levelIndex]
	if not computedBonusByLevelIndex[levelIndex] then
		computedBonusByLevelIndex[levelIndex] = buildMergedBonusWords(level.letters or {}, level.words or {}, level.bonus or {})
	end
	local mergedBonusWords = computedBonusByLevelIndex[levelIndex]

	local levelColors = (packData and packData.levelColors) or {}
	local levelColor = levelColors[((levelIndex - 1) % math.max(1, #levelColors)) + 1] or Color3.fromRGB(84, 126, 255)

	local shuffled = { table.unpack(level.letters) }
	for i = #shuffled, 2, -1 do
		local j = math.random(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	return {
		letters = shuffled,
		words = level.words,
		bonus = mergedBonusWords,
		positions = level.positions,
		requiredSet = level.requiredSet,
		gridRows = level.gridRows,
		gridCols = level.gridCols,
		date = todayKeyUtc(),
		difficulty = "Daily Hard",
		packName = (packData and packData.packName) or "Daily Challenge",
		packId = 0,
		levelId = levelIndex,
		levelColor = levelColor,
	}
end

-- Check if player has completed today's puzzle
function DailyPuzzleService.HasCompletedToday(player)
	local DataService = require(script.Parent.DataService)
	local data = DataService.getData(player)
	if not data then return false end

	local daily = ensureTodayState(data)
	return daily and daily.completed == true
end

function DailyPuzzleService.GetSavedProgress(player)
	local DataService = require(script.Parent.DataService)
	local data = DataService.getData(player)
	if not data then
		return { words = {}, bonus = {} }
	end
	local daily = ensureTodayState(data)
	local words = {}
	local bonus = {}
	for w, v in pairs(daily.progressWords or {}) do
		if v == true then
			table.insert(words, tostring(w))
		end
	end
	for w, v in pairs(daily.progressBonus or {}) do
		if v == true then
			table.insert(bonus, tostring(w))
		end
	end
	table.sort(words)
	table.sort(bonus)
	return {
		words = words,
		bonus = bonus,
	}
end

function DailyPuzzleService.RecordWordProgress(player, word, isBonus)
	if typeof(word) ~= "string" then
		return
	end
	local DataService = require(script.Parent.DataService)
	local data = DataService.getData(player)
	if not data then
		return
	end
	local daily = ensureTodayState(data)
	if isBonus then
		daily.progressBonus[word:upper()] = true
	else
		daily.progressWords[word:upper()] = true
	end
end

-- Mark daily puzzle as completed
function DailyPuzzleService.CompleteDailyPuzzle(player, bonusWords)
	local DataService = require(script.Parent.DataService)
	local today = todayKeyUtc()
	local todayStamp = getDayStamp()
	local data = DataService.getData(player)
	local daily = data and data.dailyPuzzle or {}
	local previousCompletedStamp = (daily and daily.completed == true and tonumber(daily.completedDayStamp)) or 0
	local nextDailyStreak = 1
	if data then
		data.stats = data.stats or {}
		if previousCompletedStamp == (todayStamp - 1) then
			nextDailyStreak = math.max(1, (tonumber(data.stats.dailyStreak) or 0) + 1)
		elseif previousCompletedStamp == todayStamp then
			nextDailyStreak = math.max(1, tonumber(data.stats.dailyStreak) or 1)
		end
	end
	
	local reward = 10 -- Base reward
	if bonusWords and bonusWords > 0 then
		reward = reward + bonusWords
	end
	reward = reward + math.min(8, math.floor(nextDailyStreak * 0.5))
	
	DataService.addCoins(player, reward, "DailyPuzzleReward", "TimedReward")
	
	if data then
		data.dailyPuzzle = {
			date = today,
			completed = true,
			bonusWords = bonusWords or 0,
			reward = reward,
			completedDayStamp = todayStamp,
			progressWords = daily and daily.progressWords or {},
			progressBonus = daily and daily.progressBonus or {},
		}
		data.stats = data.stats or {}
		data.stats.dailyStreak = nextDailyStreak
		if previousCompletedStamp ~= todayStamp then
			data.stats.totalDailyCompleted = (tonumber(data.stats.totalDailyCompleted) or 0) + 1
		end
	end
	
	return reward
end

-- Get player's daily puzzle streak
function DailyPuzzleService.GetStreak(player)
	local DataService = require(script.Parent.DataService)
	local data = DataService.getData(player)
	if not data or not data.stats then return 0 end
	return data.stats.dailyStreak or 0
end

function DailyPuzzleService.ClaimDailyReward(player)
	return false, "daily rewards save automatically", 0, DailyPuzzleService.GetStreak(player)
end

return DailyPuzzleService
