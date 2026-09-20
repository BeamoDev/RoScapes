local WordDictionaryService = {}

local root = script.Parent.Parent
local dictionariesFolder = root:FindFirstChild("Dictionary")

local cache = {}
local LENGTH_FILE_NAMES = {
	[3] = "ThreeLetters",
	[4] = "FourLetters",
	[5] = "FiveLetters",
	[6] = "SixLetters",
	[7] = "SevenLetters",
	[8] = "EightLetters",
}

local function normalizeWord(word)
	local upper = string.upper(tostring(word or ""))
	if upper:match("^[A-Z]+$") then
		return upper
	end
	return nil
end

local function getBucketFolder(bucketName)
	if not dictionariesFolder then
		return nil
	end
	local resolvedName = tostring(bucketName or "Common")
	local folder = dictionariesFolder:FindFirstChild(resolvedName)
	if folder then
		return folder
	end
	local lowered = string.lower(resolvedName)
	for _, child in ipairs(dictionariesFolder:GetChildren()) do
		if string.lower(child.Name) == lowered then
			return child
		end
	end
	return nil
end

local function loadBucketLength(bucketName, length)
	cache[bucketName] = cache[bucketName] or {}
	if cache[bucketName][length] then
		return cache[bucketName][length]
	end

	local words = {}
	local folder = getBucketFolder(bucketName)
	local moduleName = LENGTH_FILE_NAMES[length] or tostring(length)
	local moduleScript = folder and folder:FindFirstChild(moduleName)
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local ok, data = pcall(require, moduleScript)
		if ok and typeof(data) == "table" then
			for _, word in ipairs(data) do
				local normalized = normalizeWord(word)
				if normalized and #normalized == length then
					table.insert(words, normalized)
				end
			end
		end
	end

	table.sort(words)
	cache[bucketName][length] = words
	return words
end

local function canFormWord(word, letters)
	local counts = {}
	for _, letter in ipairs(letters or {}) do
		local upper = normalizeWord(letter)
		if upper then
			counts[upper] = (counts[upper] or 0) + 1
		end
	end

	for i = 1, #word do
		local ch = word:sub(i, i)
		local remaining = counts[ch] or 0
		if remaining <= 0 then
			return false
		end
		counts[ch] = remaining - 1
	end

	return true
end

function WordDictionaryService.GetWords(bucketName, length)
	length = tonumber(length) or 0
	if length < 1 then
		return {}
	end
	return loadBucketLength(bucketName, length)
end

function WordDictionaryService.GetWordsFormedByLetters(letters, options)
	options = options or {}
	local bucketName = options.bucketName or "Common"
	local minLength = math.max(3, tonumber(options.minLength) or 3)
	local maxLength = math.max(minLength, tonumber(options.maxLength) or #letters)
	local seen = {}
	local results = {}

	for length = minLength, maxLength do
		for _, word in ipairs(loadBucketLength(bucketName, length)) do
			if not seen[word] and canFormWord(word, letters) then
				seen[word] = true
				table.insert(results, word)
			end
		end
	end

	table.sort(results, function(a, b)
		if #a == #b then
			return a < b
		end
		return #a > #b
	end)
	return results
end

return WordDictionaryService
