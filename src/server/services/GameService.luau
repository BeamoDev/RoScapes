-- GameService.luau
-- Runs server-side gameplay checks and session state.


local GameService = {}

local DataService = require(script.Parent.DataService)

-- Active sessions per player.
local sessions = {}

function GameService.StartSession(player, packId, levelId, levelData)
	local existing = sessions[player.UserId]
	if existing then
		local previousPackId = tonumber(existing.packId)
		if previousPackId and previousPackId > 0 then
			DataService.resetLevelStreak(player)
		elseif previousPackId == -1 and tonumber(packId) ~= -1 then
			DataService.resetFreeplayStreak(player)
		end
	elseif tonumber(packId) ~= -1 then
		DataService.resetFreeplayStreak(player)
	end
	sessions[player.UserId] = {
		packId     = packId,
		levelId    = levelId,
		levelData  = levelData,
		foundWords = {},
		bonusFound = {},
		hintedCells = {},
		hintCount  = 0,
		attempts   = 0,
		validCount = 0,
		startTime  = tick(),
	}
end

function GameService.GetSession(userId)
	return sessions[userId]
end

function GameService.EndSession(player)
	if not player then
		return
	end
	sessions[player.UserId] = nil
end

local function isRequiredWord(levelData, word)
	local upperWord = tostring(word or ""):upper()
	if upperWord == "" then
		return false
	end
	if levelData and levelData.requiredSet and levelData.requiredSet[upperWord] then
		return true
	end
	for _, requiredWord in ipairs(levelData and levelData.words or {}) do
		if tostring(requiredWord or ""):upper() == upperWord then
			return true
		end
	end
	for _, pos in ipairs(levelData and levelData.positions or {}) do
		if tostring(pos.word or ""):upper() == upperWord then
			return true
		end
	end
	return false
end

local function isBonusWord(levelData, word)
	local upperWord = tostring(word or ""):upper()
	if upperWord == "" then
		return false
	end
	for _, bonusWord in ipairs(levelData and levelData.bonus or {}) do
		if tostring(bonusWord or ""):upper() == upperWord then
			return true
		end
	end
	return false
end

-- Validate a word against the level data
-- Returns: isValid (bool), isBonus (bool), reason (string)
function GameService.ValidateWord(player, word, levelData)
	if not word or typeof(word) ~= "string" then
		return false, false, "invalid input"
	end

	word = word:upper()

	if #word < 2 then
		return false, false, "too short"
	end
	
	if #word > 20 then
		return false, false, "too long"
	end

	local session = sessions[player.UserId]
	if session and session.bonusFound[word] then
		return false, false, "already found"
	end
	if session and session.foundWords[word] then
		return false, false, "already found"
	end

	if isRequiredWord(levelData, word) then
		return true, false
	end
	if isBonusWord(levelData, word) then
		return true, true
	end

	-- Ensure only available letters are used (count-aware)
	local letterCount = {}
	for _, letter in ipairs(levelData.letters) do
		letterCount[letter] = (letterCount[letter] or 0) + 1
	end
	
	for i = 1, #word do
		local ch = word:sub(i, i)
		if not letterCount[ch] or letterCount[ch] <= 0 then
			return false, false, "invalid letters"
		end
		letterCount[ch] = letterCount[ch] - 1
	end

	-- Word uses valid letters but isn't in required or bonus list - reject it
	return false, false, "not in word list"
end

function GameService.RecordAttempt(player, word, wasValid)
	local session = sessions[player.UserId]
	if not session then
		return
	end
	if typeof(word) ~= "string" or #word < 3 then
		return
	end
	session.attempts = (session.attempts or 0) + 1
	if wasValid then
		session.validCount = (session.validCount or 0) + 1
	end
end

-- Record a found word in the active session
function GameService.RecordWord(player, word)
	local session = sessions[player.UserId]
	if not session then
		return
	end
	-- Don't re-record already found words (prevents duplicate animations)
	if not session.foundWords[word:upper()] then
		session.foundWords[word:upper()] = true
	end
end

function GameService.RecordBonusWord(player, word)
	local session = sessions[player.UserId]
	if not session then
		return
	end
	session.bonusFound[word:upper()] = true
end

function GameService.GetLevelStats(player, levelData)
	local session = sessions[player.UserId]
	if not session then
		return {
			packId = 0,
			levelId = 0,
			timeSeconds = 0,
			attempts = 0,
			validCount = 0,
			wrongGuesses = 0,
			accuracy = 0,
			bonusFound = 0,
			bonusTotal = 0,
			requiredWordCount = #(levelData and levelData.words or {}),
			letterCount = #(levelData and levelData.letters or {}),
		}
	end

	local bonusTotal = #(levelData and levelData.bonus or {})
	local requiredWordCount = #(levelData and levelData.words or {})
	local bonusFoundCount = 0
	for _, bonusWord in ipairs(levelData and levelData.bonus or {}) do
		if session.bonusFound[bonusWord:upper()] then
			bonusFoundCount += 1
		end
	end

	local attempts = session.attempts or 0
	local validCount = session.validCount or 0
	local wrongGuesses = math.max(0, attempts - validCount)
	local accuracy = attempts > 0 and math.floor((validCount / attempts) * 100 + 0.5) or 0

	return {
		packId = session.packId,
		levelId = session.levelId,
		timeSeconds = math.max(0, math.floor((tick() - (session.startTime or tick())) * 100 + 0.5) / 100),
		attempts = attempts,
		validCount = validCount,
		wrongGuesses = wrongGuesses,
		accuracy = accuracy,
		bonusFound = bonusFoundCount,
		bonusTotal = bonusTotal,
		requiredWordCount = requiredWordCount,
		letterCount = #(levelData and levelData.letters or {}),
	}
end

-- Returns true when all required words have been found
function GameService.CheckComplete(player, requiredWords)
	local session = sessions[player.UserId]
	if not session then
		return false
	end
	for _, word in ipairs(requiredWords) do
		if not session.foundWords[word:upper()] then
			return false
		end
	end
	return true
end

-- Spend one hint from the player's balance
-- Returns: success (bool), message (string)
function GameService.UseHint(player)
	if DataService.getHints(player) <= 0 then
		return false, "No hints available"
	end
	DataService.useHint(player)
	local session = sessions[player.UserId]
	if session then
		session.hintCount = session.hintCount + 1
	end
	return true, "OK"
end

-- Save completion, award bonus hints, clear session
function GameService.CompleteLevel(player, packId, levelId)
	if tonumber(packId) and tonumber(packId) > 0 then
		DataService.setProgress(player, packId, levelId, true)
	end

	-- Bonus hint every 5 completed levels
	local data = DataService.getData(player)
	if data and data.solvedCount > 0 and data.solvedCount % 5 == 0 then
		DataService.addHints(player, 1)
	end

	sessions[player.UserId] = nil
end

return GameService
