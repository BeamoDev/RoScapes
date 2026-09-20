local FreeplayService = {}
local WordDictionaryService = require(script.Parent.WordDictionaryService)
local CrosswordLayoutService = require(script.Parent.CrosswordLayoutService)

local LETTER_COUNT_WEIGHTS = {
	{ count = 4, weight = 18 },
	{ count = 5, weight = 34 },
	{ count = 6, weight = 26 },
	{ count = 7, weight = 14 },
	{ count = 8, weight = 8 },
}

local FREEPLAY_PROFILES = {
	{ id = "easy", label = "Freeplay Easy", minLetters = 4, maxLetters = 5, minWords = 4, maxWords = 6, weight = 24 },
	{ id = "normal", label = "Freeplay Normal", minLetters = 5, maxLetters = 6, minWords = 6, maxWords = 8, weight = 34 },
	{ id = "hard", label = "Freeplay Hard", minLetters = 6, maxLetters = 7, minWords = 8, maxWords = 10, weight = 26 },
	{ id = "expert", label = "Freeplay Expert", minLetters = 7, maxLetters = 8, minWords = 10, maxWords = 12, weight = 16 },
}

local LETTER_WEIGHTS = {
	A = 82, B = 15, C = 28, D = 43, E = 127, F = 22, G = 20, H = 61, I = 70, J = 2,
	K = 8, L = 40, M = 24, N = 67, O = 75, P = 19, Q = 1, R = 60, S = 63, T = 91,
	U = 28, V = 10, W = 24, X = 2, Y = 20, Z = 1,
}

local LEVEL_COLORS = {
	Color3.fromRGB(94, 158, 255),
	Color3.fromRGB(255, 126, 196),
	Color3.fromRGB(94, 214, 163),
	Color3.fromRGB(255, 174, 92),
	Color3.fromRGB(169, 125, 255),
	Color3.fromRGB(255, 124, 140),
	Color3.fromRGB(100, 204, 255),
	Color3.fromRGB(255, 205, 82),
	Color3.fromRGB(130, 226, 117),
}
local MAX_LETTER_RETRIES = 100
local LOW_SKILL_FREEPLAY = {
	[1] = {
		profileWeights = {
			easy = 100,
		},
		maxLetterCount = 5,
		maxRequiredWords = 5,
		maxWordLength = 5,
		difficultyLabel = "Freeplay Guided",
	},
	[2] = {
		profileWeights = {
			easy = 78,
			normal = 22,
		},
		maxLetterCount = 6,
		maxRequiredWords = 6,
		maxWordLength = 6,
		difficultyLabel = "Freeplay Assisted",
	},
}

local function canFormWord(word, letters)
	local letterCounts = {}
	for _, letter in ipairs(letters or {}) do
		local upper = tostring(letter):upper()
		letterCounts[upper] = (letterCounts[upper] or 0) + 1
	end

	for i = 1, #word do
		local ch = word:sub(i, i)
		local count = letterCounts[ch] or 0
		if count <= 0 then
			return false
		end
		letterCounts[ch] = count - 1
	end

	return true
end

local function chooseWeighted(list)
	local total = 0
	for _, entry in ipairs(list) do
		total += entry.weight
	end
	local roll = math.random() * total
	local running = 0
	for _, entry in ipairs(list) do
		running += entry.weight
		if roll <= running then
			return entry.count or entry.letter
		end
	end
	return list[#list].count or list[#list].letter
end

local weightedLetters = {}
for letter, weight in pairs(LETTER_WEIGHTS) do
	table.insert(weightedLetters, {
		letter = letter,
		weight = weight,
	})
end

local function withRuntimeFields(board)
	if not board then
		return nil
	end
	local copy = {}
	for key, value in pairs(board) do
		copy[key] = value
	end
	local colorIndex = math.clamp(tonumber(copy.colorIndex) or 1, 1, #LEVEL_COLORS)
	copy.levelColor = LEVEL_COLORS[colorIndex]
	return copy
end

local function getSkillAdjustments(skillState)
	local skillLevel = math.clamp(math.floor(tonumber(skillState and skillState.level) or 5), 1, 5)
	local profile = LOW_SKILL_FREEPLAY[skillLevel]
	if not profile then
		return nil
	end
	local resolved = {}
	for key, value in pairs(profile) do
		if type(value) == "table" then
			local copy = {}
			for innerKey, innerValue in pairs(value) do
				copy[innerKey] = innerValue
			end
			resolved[key] = copy
		else
			resolved[key] = value
		end
	end
	return resolved
end

local function chooseProfile(skillAdjustments)
	local weighted = {}
	for _, profile in ipairs(FREEPLAY_PROFILES) do
		local overrideWeight = skillAdjustments
			and skillAdjustments.profileWeights
			and skillAdjustments.profileWeights[profile.id]
		local weight = tonumber(overrideWeight) or profile.weight
		if weight > 0 then
		table.insert(weighted, {
			count = profile,
				weight = weight,
		})
		end
	end
	return chooseWeighted(weighted)
end

local function chooseLetterCount(profile, skillAdjustments)
	for _ = 1, 20 do
		local count = chooseWeighted(LETTER_COUNT_WEIGHTS)
		local maxLetters = tonumber(profile.maxLetters) or 8
		if skillAdjustments and tonumber(skillAdjustments.maxLetterCount) then
			maxLetters = math.min(maxLetters, tonumber(skillAdjustments.maxLetterCount) or maxLetters)
		end
		if count >= (profile.minLetters or 4) and count <= maxLetters then
			return count
		end
	end
	local fallbackMax = tonumber(profile.maxLetters) or 6
	if skillAdjustments and tonumber(skillAdjustments.maxLetterCount) then
		fallbackMax = math.min(fallbackMax, tonumber(skillAdjustments.maxLetterCount) or fallbackMax)
	end
	return math.clamp(fallbackMax, 4, 8)
end

local function chooseLetters(profile, skillAdjustments)
	local count = chooseLetterCount(profile, skillAdjustments)
	local letters = {}
	for _ = 1, count do
		table.insert(letters, chooseWeighted(weightedLetters))
	end
	table.sort(letters)
	return letters
end

local function getCandidatesForLetters(letters)
	return WordDictionaryService.GetWordsFormedByLetters(letters, {
		bucketName = "Common",
		minLength = 3,
		maxLength = #letters,
	})
end

local function isValidCandidateSet(candidates, profile, letters)
	if #candidates < math.max(3, tonumber(profile.minWords) or 3) then
		return false
	end
	local longEnough = 0
	for _, word in ipairs(candidates) do
		if #word >= math.max(3, #letters - 1) then
			longEnough += 1
		end
	end
	return longEnough >= math.max(1, math.floor((tonumber(profile.minWords) or 3) * 0.35))
end

local function chooseRequiredWords(candidates, profile, skillAdjustments)
	local minWords = math.max(3, tonumber(profile.minWords) or 3)
	local maxWords = math.max(minWords, tonumber(profile.maxWords) or minWords)
	local candidatePool = candidates or {}
	if skillAdjustments and tonumber(skillAdjustments.maxWordLength) then
		local filtered = {}
		local maxWordLength = math.max(3, tonumber(skillAdjustments.maxWordLength) or 20)
		for _, word in ipairs(candidatePool) do
			if #tostring(word or "") <= maxWordLength then
				table.insert(filtered, word)
			end
		end
		if #filtered >= minWords then
			candidatePool = filtered
		end
	end
	if skillAdjustments and tonumber(skillAdjustments.maxRequiredWords) then
		maxWords = math.min(maxWords, math.max(minWords, tonumber(skillAdjustments.maxRequiredWords) or maxWords))
	end
	minWords = math.min(minWords, #candidatePool)
	maxWords = math.min(math.max(minWords, maxWords), #candidatePool)
	if #candidatePool <= 0 or minWords <= 0 or maxWords <= 0 then
		return {}
	end
	local targetCount = math.clamp(math.random(minWords, maxWords), minWords, math.min(maxWords, #candidatePool))
	local required = {}
	for _, word in ipairs(candidatePool) do
		table.insert(required, word)
		if #required >= targetCount then
			break
		end
	end
	table.sort(required, function(a, b)
		if #a == #b then
			return a < b
		end
		return #a > #b
	end)
	return required
end

local function getPlacementTarget(totalWords)
	local wordCount = math.max(0, tonumber(totalWords) or 0)
	if wordCount <= 0 then
		return 0
	end
	return math.min(wordCount, math.max(3, math.ceil(wordCount * 0.9)))
end

function FreeplayService.GenerateBoard(skillState)
	local skillAdjustments = getSkillAdjustments(skillState)
	for _ = 1, MAX_LETTER_RETRIES do
		local profile = chooseProfile(skillAdjustments)
		local letters = chooseLetters(profile, skillAdjustments)
		local candidates = getCandidatesForLetters(letters)
		if isValidCandidateSet(candidates, profile, letters) then
			local requiredWords = chooseRequiredWords(candidates, profile, skillAdjustments)
			local minPlacedWords = getPlacementTarget(#requiredWords)
			local layout = CrosswordLayoutService.Build(requiredWords, {
				minPlacedWords = minPlacedWords,
			})
			if layout and layout.words then
				if #layout.words < minPlacedWords then
					continue
				end
				local used = {}
				for _, word in ipairs(layout.words) do
					used[word] = true
				end
				local allWords = WordDictionaryService.GetWordsFormedByLetters(letters, {
					bucketName = "All",
					minLength = 3,
					maxLength = #letters,
				})
				local bonusWords = {}
				for _, word in ipairs(allWords) do
					if not used[word] then
						table.insert(bonusWords, word)
					end
				end
				local requiredSet = {}
				for _, word in ipairs(layout.words) do
					requiredSet[word] = true
				end
				local board = {
					packId = -1,
					levelId = 1,
					packName = "Freeplay",
					letters = letters,
					words = layout.words,
					bonus = bonusWords,
					positions = layout.positions,
					requiredSet = requiredSet,
					gridRows = layout.gridRows,
					gridCols = layout.gridCols,
					colorIndex = 1,
					difficulty = (skillAdjustments and skillAdjustments.difficultyLabel) or profile.label,
				}
				board.colorIndex = math.random(1, #LEVEL_COLORS)
				board.boardKey = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
				return board
			end
		end
	end
	return nil
end

function FreeplayService.GetOrCreateBoard(player, DataService)
	local skillState = DataService and DataService.getSkillState and DataService.getSkillState(player) or nil
	local board = FreeplayService.GenerateBoard(skillState)
	return withRuntimeFields(board)
end

return FreeplayService
