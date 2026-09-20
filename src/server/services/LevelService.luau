-- LevelService.luau
-- Loads and serves level data.


local LevelService = {}
local WordDictionaryService = require(script.Parent.WordDictionaryService)
local CrosswordLayoutService = require(script.Parent.CrosswordLayoutService)
local LevelPackConfig = require(script.Parent.LevelPackConfig)

local DEV_LEVEL_COLORS = {
	Color3.fromRGB(94, 158, 255),   -- blue
	Color3.fromRGB(255, 126, 196),  -- pink
	Color3.fromRGB(94, 214, 163),   -- mint
	Color3.fromRGB(255, 174, 92),   -- orange
	Color3.fromRGB(169, 125, 255),  -- violet
	Color3.fromRGB(255, 124, 140),  -- coral
	Color3.fromRGB(100, 204, 255),  -- sky
	Color3.fromRGB(255, 205, 82),   -- amber
	Color3.fromRGB(130, 226, 117),  -- lime
	Color3.fromRGB(115, 190, 255),  -- light blue
}
local function toSet(list)
	local s = {}
	for _, v in ipairs(list) do
		s[v] = true
	end
	return s
end

local templateCache = nil
local orderedLevelIds = nil
local beginnerTemplateCache = nil
local beginnerOrderedLevelIds = nil
local MAX_LEVEL_BUILD_ATTEMPTS = 100
local BEGINNER_TEMPLATE_MAX_LEVEL = 100
local BEGINNER_SCORE_THRESHOLD = 2
local BEGINNER_SKILL_PROFILE = {
	label = "Beginner Guided",
	maxWordTarget = 3,
	maxWordLength = 5,
	shortWordBias = 340,
	longWordPenalty = 240,
	allowTemplateOverride = false,
}
local ADAPTIVE_SKILL_PROFILES = {
	[1] = {
		label = "Guided",
		maxWordTarget = 4,
		maxWordLength = 5,
		shortWordBias = 260,
		longWordPenalty = 170,
		allowTemplateOverride = true,
	},
	[2] = {
		label = "Assisted",
		maxWordTarget = 5,
		maxWordLength = 6,
		shortWordBias = 160,
		longWordPenalty = 105,
		allowTemplateOverride = true,
	},
}
local EARLY_LEVEL_PREFERRED_WORDS = {
	[1] = "CAT",
	[2] = "DOG",
	[3] = "SUN",
	[4] = "TAP",
	[5] = "NOW",
	[6] = "BED",
	[7] = "BALL",
	[8] = "FISH",
	[9] = "BOOK",
	[10] = "CAKE",
	[11] = "TREE",
	[12] = "STAR",
	[13] = "HAND",
	[14] = "GAME",
	[15] = "MILK",
	[16] = "FROG",
	[17] = "HOUSE",
	[18] = "APPLE",
	[19] = "TRAIN",
	[20] = "BEACH",
}

local function normalizeLetters(rawLetters)
	local letters = {}
	if typeof(rawLetters) == "table" then
		for _, value in ipairs(rawLetters) do
			local upper = string.upper(tostring(value or ""))
			if upper ~= "" then
				table.insert(letters, upper)
			end
		end
	else
		for i = 1, #tostring(rawLetters or "") do
			table.insert(letters, string.upper(tostring(rawLetters):sub(i, i)))
		end
	end
	return letters
end

local function shouldUseBeginnerTemplate(skillState, globalLevelIndex)
	local score = tonumber(skillState and skillState.score)
	if score == nil then
		return false
	end
	if score >= BEGINNER_SCORE_THRESHOLD then
		return false
	end
	return math.max(1, tonumber(globalLevelIndex) or 1) <= BEGINNER_TEMPLATE_MAX_LEVEL
end

local function getSkillAdjustments(skillState, globalLevelIndex)
	if shouldUseBeginnerTemplate(skillState, globalLevelIndex) then
		local beginner = {}
		for key, value in pairs(BEGINNER_SKILL_PROFILE) do
			beginner[key] = value
		end
		beginner.skillLevel = 1
		return beginner
	end

	local skillLevel = math.clamp(math.floor(tonumber(skillState and skillState.level) or 5), 1, 5)
	local profile = ADAPTIVE_SKILL_PROFILES[skillLevel]
	if not profile then
		return nil
	end
	local resolved = {}
	for key, value in pairs(profile) do
		resolved[key] = value
	end
	resolved.skillLevel = skillLevel
	return resolved
end

local function getWordTargetForLevel(globalLevelIndex, letterCount, skillAdjustments)
	local levelNumber = math.max(1, tonumber(globalLevelIndex) or 1)
	local target = 0
	if levelNumber == 5 then
		target = 3
	elseif levelNumber <= 15 then
		target = 4
	elseif levelNumber <= 25 then
		target = 4
	elseif levelNumber <= 35 then
		target = 5
	elseif levelNumber <= 60 then
		target = 6
	elseif levelNumber <= 100 then
		target = 7
	elseif levelNumber <= 150 then
		target = 8
	elseif levelNumber <= 200 then
		target = 9
	else
		target = math.clamp(letterCount + 1, 3, 10)
	end
	if skillAdjustments and tonumber(skillAdjustments.maxWordTarget) then
		target = math.min(target, math.max(3, tonumber(skillAdjustments.maxWordTarget) or target))
	end
	return target
end

local function sortWordsForDifficulty(words, letterCount, globalLevelIndex, skillAdjustments)
	local levelNumber = math.max(1, tonumber(globalLevelIndex) or 1)
	local preferredWord = EARLY_LEVEL_PREFERRED_WORDS[levelNumber]
	table.sort(words, function(a, b)
		local aUpper = tostring(a or ""):upper()
		local bUpper = tostring(b or ""):upper()
		local function score(word)
			local s = 0
			if preferredWord and word == preferredWord then
				s += 10000
			end
			if #word == letterCount then
				if levelNumber <= 25 and letterCount >= 5 then
					s += 140
				else
					s += 500
				end
			end
			if levelNumber <= 25 then
				if #word <= 4 then
					s += 525
				elseif #word == 5 then
					s += 75
				end
			elseif levelNumber <= 30 then
				if #word <= 4 then
					s += 450
				elseif #word == 5 then
					s += 150
				end
			elseif levelNumber <= 75 then
				if #word <= 4 then
					s += 300
				elseif #word == 5 then
					s += 125
				end
			elseif levelNumber <= 150 and #word <= 5 then
				s += 150
			end
			if skillAdjustments then
				local maxWordLength = math.max(3, tonumber(skillAdjustments.maxWordLength) or #word)
				if #word <= maxWordLength then
					s += tonumber(skillAdjustments.shortWordBias) or 0
				else
					s -= (#word - maxWordLength) * (tonumber(skillAdjustments.longWordPenalty) or 0)
				end
			end
			s += math.max(0, 20 - #word)
			return s
		end
		local aScore = score(aUpper)
		local bScore = score(bUpper)
		if aScore ~= bScore then
			return aScore > bScore
		end
		if #aUpper ~= #bUpper then
			return #aUpper < #bUpper
		end
		return aUpper < bUpper
	end)
	return words
end

local function filterCandidatesForSkill(words, skillAdjustments)
	if not skillAdjustments or not tonumber(skillAdjustments.maxWordLength) then
		return words
	end
	local maxWordLength = math.max(3, tonumber(skillAdjustments.maxWordLength) or 20)
	local filtered = {}
	for _, word in ipairs(words or {}) do
		if #tostring(word or "") <= maxWordLength then
			table.insert(filtered, word)
		end
	end
	if #filtered >= 3 then
		return filtered
	end
	return words
end

local function mergePreferredWords(primaryWords, fallbackWords)
	local merged = {}
	local seen = {}
	for _, word in ipairs(primaryWords or {}) do
		local upperWord = tostring(word or ""):upper()
		if upperWord ~= "" and not seen[upperWord] then
			seen[upperWord] = true
			table.insert(merged, upperWord)
		end
	end
	for _, word in ipairs(fallbackWords or {}) do
		local upperWord = tostring(word or ""):upper()
		if upperWord ~= "" and not seen[upperWord] then
			seen[upperWord] = true
			table.insert(merged, upperWord)
		end
	end
	return merged
end

local function shuffleWords(words)
	local shuffled = table.clone(words or {})
	for index = #shuffled, 2, -1 do
		local swapIndex = math.random(1, index)
		shuffled[index], shuffled[swapIndex] = shuffled[swapIndex], shuffled[index]
	end
	return shuffled
end

local function buildAttemptPool(sourceWords, letterCount, globalLevelIndex, skillAdjustments)
	local ranked = sortWordsForDifficulty(
		table.clone(filterCandidatesForSkill(sourceWords or {}, skillAdjustments)),
		letterCount,
		math.max(1, tonumber(globalLevelIndex) or 1),
		skillAdjustments
	)
	local pool = {}
	for _, word in ipairs(ranked) do
		table.insert(pool, word)
	end
	return pool
end

local function chooseAttemptWords(sourceWords, requestedCount)
	local count = math.min(#(sourceWords or {}), math.max(1, tonumber(requestedCount) or 1))
	if count <= 0 then
		return {}
	end
	local subset = {}
	local shuffled = shuffleWords(sourceWords)
	for index = 1, count do
		table.insert(subset, shuffled[index])
	end
	table.sort(subset, function(a, b)
		if #a == #b then
			return a < b
		end
		return #a > #b
	end)
	return subset
end

local function tryBuildLayoutFromCandidates(candidates, letterCount, globalLevelIndex, skillAdjustments)
	local minPlacedWords = getWordTargetForLevel(globalLevelIndex, letterCount, skillAdjustments)
	local sources = {}
	local commonWords = buildAttemptPool(candidates, letterCount, globalLevelIndex, skillAdjustments)

	if #commonWords > 0 then
		table.insert(sources, commonWords)
	end
	if #sources == 0 then
		return nil
	end

	local attemptPlans = {}
	for _, source in ipairs(sources) do
		local sourceMinPlacedWords = math.min(minPlacedWords, #source)
		for requestedCount = #source, sourceMinPlacedWords, -1 do
			table.insert(attemptPlans, {
				source = source,
				requestedCount = requestedCount,
				minPlacedWords = sourceMinPlacedWords,
			})
		end
	end

	if #attemptPlans == 0 then
		return nil
	end

	for attempt = 1, MAX_LEVEL_BUILD_ATTEMPTS do
		local plan = attemptPlans[((attempt - 1) % #attemptPlans) + 1]
		local subset = chooseAttemptWords(plan.source, plan.requestedCount)
		if #subset >= plan.minPlacedWords and plan.minPlacedWords > 0 then
			local layout = CrosswordLayoutService.Build(subset, {
				minPlacedWords = plan.minPlacedWords,
				maxRetries = 1,
			})
			if layout and layout.words and #layout.words >= plan.minPlacedWords then
				return layout
			end
		end
	end

	return nil
end

local function buildOrderedLevelIds(data)
	local ids = {}
	for levelId in pairs(data) do
		if tonumber(levelId) then
			table.insert(ids, tonumber(levelId))
		end
	end
	table.sort(ids)
	return ids
end

local function loadTemplate()
	if templateCache and orderedLevelIds and #orderedLevelIds > 0 then
		return
	end
	local levelsFolder = script.Parent.Parent:FindFirstChild("Levels")
	local templateModule = levelsFolder and levelsFolder:FindFirstChild("LevelTemplate")
	if not templateModule then
		warn("[LevelService] LevelTemplate not found")
		templateCache = {}
		orderedLevelIds = {}
		return
	end

	local ok, data = pcall(require, templateModule)
	if not ok or typeof(data) ~= "table" then
		warn("[LevelService] Failed to load LevelTemplate:", data)
		templateCache = {}
		orderedLevelIds = {}
		return
	end

	templateCache = data
	orderedLevelIds = buildOrderedLevelIds(data)
end

local function loadBeginnerTemplate()
	if beginnerTemplateCache and beginnerOrderedLevelIds and #beginnerOrderedLevelIds > 0 then
		return
	end

	local levelsFolder = script.Parent.Parent:FindFirstChild("Levels")
	local templateModule = levelsFolder and levelsFolder:FindFirstChild("BeginnerLevelTemplate")
	if not templateModule then
		beginnerTemplateCache = {}
		beginnerOrderedLevelIds = {}
		return
	end

	local ok, data = pcall(require, templateModule)
	if not ok or typeof(data) ~= "table" then
		warn("[LevelService] Failed to load BeginnerLevelTemplate:", data)
		beginnerTemplateCache = {}
		beginnerOrderedLevelIds = {}
		return
	end

	beginnerTemplateCache = data
	beginnerOrderedLevelIds = buildOrderedLevelIds(data)
end

local function getTemplateEntry(levelIndex, useBeginnerTemplate)
	if useBeginnerTemplate then
		loadBeginnerTemplate()
		local beginnerTemplateId = beginnerOrderedLevelIds[levelIndex]
		if beginnerTemplateId and beginnerTemplateCache[beginnerTemplateId] then
			return beginnerTemplateCache[beginnerTemplateId], beginnerTemplateId, true
		end
	end
	loadTemplate()
	local templateId = orderedLevelIds[levelIndex]
	return templateId and templateCache[templateId] or nil, templateId, false
end

local function getRequestedWords(templateEntry)
	local requestedWords = {}
	for _, word in ipairs(templateEntry and (templateEntry.Words or {}) or {}) do
		local upperWord = tostring(word or ""):upper()
		if upperWord ~= "" then
			table.insert(requestedWords, upperWord)
		end
	end
	return requestedWords
end

local function filterWordsPreservingOrder(requestedWords, availableWords)
	if #(requestedWords or {}) <= 0 or #(availableWords or {}) <= 0 then
		return {}
	end

	local availableSet = toSet(availableWords)
	local filtered = {}
	for _, word in ipairs(requestedWords) do
		if availableSet[word] then
			table.insert(filtered, word)
		end
	end
	return filtered
end

local function buildLevelPayloadFromTemplateEntry(templateEntry, options)
	if not templateEntry then
		return nil, "Level template missing"
	end

	options = options or {}
	local letters = normalizeLetters(templateEntry.Letters or templateEntry.letters)
	local requestedWords = getRequestedWords(templateEntry)
	local commonWords = WordDictionaryService.GetWordsFormedByLetters(letters, {
		bucketName = "Common",
		minLength = 3,
		maxLength = #letters,
	})
	local allWords = WordDictionaryService.GetWordsFormedByLetters(letters, {
		bucketName = "All",
		minLength = 3,
		maxLength = #letters,
	})
	local curatedWords = filterWordsPreservingOrder(requestedWords, commonWords)
	local skillAdjustments = getSkillAdjustments(options.skillState, tonumber(options.globalLevelIndex) or 1)
	if #curatedWords > 0 and not (skillAdjustments and skillAdjustments.allowTemplateOverride) then
		commonWords = curatedWords
	elseif #curatedWords > 0 then
		commonWords = mergePreferredWords(curatedWords, commonWords)
	end
	local layout = tryBuildLayoutFromCandidates(
		commonWords,
		#letters,
		tonumber(options.globalLevelIndex) or 1,
		skillAdjustments
	)
	if not layout then
		return nil, "Could not generate grid"
	end

	local used = toSet(layout.words)
	local bonusWords = {}
	for _, word in ipairs(allWords) do
		if not used[word] then
			table.insert(bonusWords, word)
		end
	end

	local shuffled = {table.unpack(letters)}
	for i = #shuffled, 2, -1 do
		local j = math.random(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	local globalLevelIndex = tonumber(options.globalLevelIndex) or 1
	local levelColor = DEV_LEVEL_COLORS[((globalLevelIndex - 1) % #DEV_LEVEL_COLORS) + 1]

	return {
		packId = tonumber(options.packId) or 1,
		levelId = tonumber(options.levelId) or 1,
		globalLevelId = globalLevelIndex,
		templateId = options.templateId,
		packName = options.packName or LevelPackConfig.GetPackName(tonumber(options.packId) or 1),
		letters = shuffled,
		words = layout.words,
		bonus = bonusWords,
		positions = layout.positions,
		requiredSet = toSet(layout.words),
		gridRows = layout.gridRows,
		gridCols = layout.gridCols,
		levelColor = levelColor,
		difficulty = skillAdjustments and skillAdjustments.label or nil,
		preserveGeneratedWords = skillAdjustments and skillAdjustments.allowTemplateOverride == true,
	}
end

local function getTotalTemplateLevels()
	loadTemplate()
	return math.min(#orderedLevelIds, tonumber(LevelPackConfig.MaxPlayableLevels) or #orderedLevelIds)
end

local function getPackLevelBounds(packId)
	local resolvedPackId = math.max(1, tonumber(packId) or 1)
	local levelsPerPack = LevelPackConfig.LevelsPerPack
	local startIndex = ((resolvedPackId - 1) * levelsPerPack) + 1
	local endIndex = math.min(startIndex + levelsPerPack - 1, getTotalTemplateLevels())
	if startIndex > endIndex then
		return nil, nil
	end
	return startIndex, endIndex
end

local function getGlobalLevelIndex(packId, localLevelId)
	local startIndex, endIndex = getPackLevelBounds(packId)
	if not startIndex then
		return nil
	end
	local resolvedLevelId = math.max(1, tonumber(localLevelId) or 1)
	local globalIndex = startIndex + resolvedLevelId - 1
	if globalIndex > endIndex then
		return nil
	end
	return globalIndex
end

function LevelService.GetLevelData(packId, levelId, options)
	loadTemplate()
	options = (typeof(options) == "table") and options or {}
	local globalLevelIndex = getGlobalLevelIndex(packId, levelId)
	if not globalLevelIndex then
		return nil, "Pack not found: " .. tostring(packId)
	end

	local useBeginnerTemplate = shouldUseBeginnerTemplate(options.skillState, globalLevelIndex)
	local templateEntry, templateId, fromBeginnerTemplate = getTemplateEntry(globalLevelIndex, useBeginnerTemplate)
	if not templateEntry then
		return nil, "Level not found: " .. tostring(levelId)
	end
	local requestedTemplateId = templateId

	local data, err = buildLevelPayloadFromTemplateEntry(templateEntry, {
		packId = tonumber(packId) or 1,
		levelId = tonumber(levelId) or 1,
		globalLevelIndex = globalLevelIndex,
		templateId = templateId,
		packName = LevelPackConfig.GetPackName(tonumber(packId) or 1),
		skillState = options.skillState,
	})
	if not data then
		local totalLevels = getTotalTemplateLevels()
		for candidateIndex = globalLevelIndex + 1, totalLevels do
			local candidateTemplateEntry, candidateTemplateId, candidateFromBeginnerTemplate = getTemplateEntry(candidateIndex, useBeginnerTemplate)
			if candidateTemplateEntry then
				data, err = buildLevelPayloadFromTemplateEntry(candidateTemplateEntry, {
					packId = tonumber(packId) or 1,
					levelId = tonumber(levelId) or 1,
					globalLevelIndex = globalLevelIndex,
					templateId = candidateTemplateId,
					packName = LevelPackConfig.GetPackName(tonumber(packId) or 1),
					skillState = options.skillState,
				})
				if data then
					templateEntry = candidateTemplateEntry
					templateId = candidateTemplateId
					fromBeginnerTemplate = candidateFromBeginnerTemplate
					warn(string.format(
						"[LevelService] Skipped template %s for pack %s level %s; using template %s instead",
						tostring(requestedTemplateId),
						tostring(packId),
						tostring(levelId),
						tostring(candidateTemplateId)
					))
					break
				end
			end
		end
	end
	if not data then
		return nil, err
	end

	if fromBeginnerTemplate then
		data.difficulty = "Beginner Guided"
	end

	local requestedWords = getRequestedWords(templateEntry)
	if #requestedWords > 0 and data.preserveGeneratedWords ~= true then
		local existing = toSet(data.words)
		local ordered = {}
		for _, word in ipairs(requestedWords) do
			if existing[word] then
				table.insert(ordered, word)
			end
		end
		if #ordered > 0 then
			data.words = ordered
		end
	end

	return data
end

function LevelService.GetPackList()
	loadTemplate()
	local list = {}
	local totalLevels = getTotalTemplateLevels()
	local levelsPerPack = LevelPackConfig.LevelsPerPack
	local packCount = math.ceil(totalLevels / levelsPerPack)
	for packId = 1, packCount do
		local startIndex, endIndex = getPackLevelBounds(packId)
		if startIndex and endIndex then
			table.insert(list, {
				packId = packId,
				name = LevelPackConfig.GetPackName(packId),
				levelCount = (endIndex - startIndex) + 1,
				startLevel = startIndex,
				endLevel = endIndex,
			})
		end
	end
	return list
end

function LevelService.GetPackCount()
	return #LevelService.GetPackList()
end

function LevelService.GetLevelCount(packId)
	local startIndex, endIndex = getPackLevelBounds(packId)
	if not startIndex then
		return 0
	end
	return (endIndex - startIndex) + 1
end

return LevelService
