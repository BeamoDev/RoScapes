local LevelPayloadService = {}

local function buildRequiredSet(levelData)
	local requiredSet = {}
	for _, word in ipairs(levelData and levelData.words or {}) do
		requiredSet[tostring(word):upper()] = true
	end
	return requiredSet
end

local function getRequiredPositions(levelData)
	local positions = {}
	local requiredSet = buildRequiredSet(levelData)
	local wordOrder = {}
	for index, word in ipairs(levelData and levelData.words or {}) do
		wordOrder[tostring(word):upper()] = index
	end
	for _, pos in ipairs(levelData and levelData.positions or {}) do
		local word = tostring(pos.word or ""):upper()
		if requiredSet[word] then
			table.insert(positions, {
				word = word,
				row = tonumber(pos.row) or 0,
				col = tonumber(pos.col) or 0,
				dir = tostring(pos.dir or "H"),
				length = #word,
			})
		end
	end
	table.sort(positions, function(a, b)
		local aOrder = wordOrder[a.word] or math.huge
		local bOrder = wordOrder[b.word] or math.huge
		if aOrder ~= bOrder then
			return aOrder < bOrder
		end
		if a.row ~= b.row then
			return a.row < b.row
		end
		if a.col ~= b.col then
			return a.col < b.col
		end
		return a.word < b.word
	end)
	return positions
end

local function getOccupiedCellsFromPositions(positions)
	local occupiedMap = {}
	local occupiedCells = {}
	for _, pos in ipairs(positions or {}) do
		local length = tonumber(pos.length) or #(tostring(pos.word or ""))
		for i = 0, math.max(0, length - 1) do
			local row = (pos.dir == "V") and (pos.row + i) or pos.row
			local col = (pos.dir == "H") and (pos.col + i) or pos.col
			local key = tostring(row) .. ":" .. tostring(col)
			if not occupiedMap[key] then
				occupiedMap[key] = true
				table.insert(occupiedCells, {
					row = row,
					col = col,
				})
			end
		end
	end
	table.sort(occupiedCells, function(a, b)
		if a.row == b.row then
			return a.col < b.col
		end
		return a.row < b.row
	end)
	return occupiedCells
end

function LevelPayloadService.GetRevealCells(levelData, word)
	local upperWord = tostring(word or ""):upper()
	if upperWord == "" then
		return {}
	end

	for _, pos in ipairs(getRequiredPositions(levelData)) do
		if pos.word == upperWord then
			local cells = {}
			for i = 1, pos.length do
				local row = (pos.dir == "V") and (pos.row + (i - 1)) or pos.row
				local col = (pos.dir == "H") and (pos.col + (i - 1)) or pos.col
				table.insert(cells, {
					row = row,
					col = col,
					letter = upperWord:sub(i, i),
					index = i,
					dir = pos.dir,
				})
			end
			return cells
		end
	end

	return {}
end

function LevelPayloadService.GetRevealCellsForWords(levelData, words)
	local occupiedMap = {}
	local revealed = {}
	for _, word in ipairs(words or {}) do
		for _, cell in ipairs(LevelPayloadService.GetRevealCells(levelData, word)) do
			local key = tostring(cell.row) .. ":" .. tostring(cell.col)
			if not occupiedMap[key] then
				occupiedMap[key] = true
				table.insert(revealed, cell)
			end
		end
	end
	table.sort(revealed, function(a, b)
		if a.row == b.row then
			return a.col < b.col
		end
		return a.row < b.row
	end)
	return revealed
end

function LevelPayloadService.FindNextHintCell(levelData, session)
	if not levelData or not session then
		return nil
	end

	local hintedCells = session.hintedCells or {}
	for _, pos in ipairs(getRequiredPositions(levelData)) do
		if not session.foundWords[pos.word] then
			for i = 0, math.max(0, pos.length - 1) do
				local row = (pos.dir == "V") and (pos.row + i) or pos.row
				local col = (pos.dir == "H") and (pos.col + i) or pos.col
				local key = tostring(row) .. ":" .. tostring(col)
				if not hintedCells[key] then
					return {
						row = row,
						col = col,
					}
				end
			end
		end
	end

	return nil
end

function LevelPayloadService.GetHintCells(levelData, session)
	if not levelData or not session then
		return {}
	end

	local positions = getRequiredPositions(levelData)
	if #positions <= 0 then
		return {}
	end

	local hintedCells = session.hintedCells or {}
	local candidateWords = {}

	for _, pos in ipairs(positions) do
		if not session.foundWords[pos.word] then
			local hiddenCells = {}
			local hiddenMap = {}
			for i = 0, math.max(0, pos.length - 1) do
				local row = (pos.dir == "V") and (pos.row + i) or pos.row
				local col = (pos.dir == "H") and (pos.col + i) or pos.col
				local key = tostring(row) .. ":" .. tostring(col)
				if not hintedCells[key] and not hiddenMap[key] then
					hiddenMap[key] = true
					table.insert(hiddenCells, {
						row = row,
						col = col,
					})
				end
			end
			if #hiddenCells > 0 then
				table.insert(candidateWords, hiddenCells)
			end
		end
	end

	if #candidateWords <= 0 then
		return {}
	end

	return candidateWords[math.random(1, #candidateWords)]
end

function LevelPayloadService.MarkHintedCell(session, row, col)
	if not session then
		return
	end
	session.hintedCells = session.hintedCells or {}
	session.hintedCells[tostring(row) .. ":" .. tostring(col)] = true
end

function LevelPayloadService.GetLetterAtCell(levelData, row, col)
	row = tonumber(row) or row
	col = tonumber(col) or col
	local slots = {}
	if levelData and levelData.positions then
		slots = getRequiredPositions(levelData)
	elseif levelData and levelData.wordSlots then
		slots = levelData.wordSlots
	end

	for _, slot in ipairs(slots) do
		local word = tostring(slot.word or ""):upper()
		local baseRow = tonumber(slot.row) or 0
		local baseCol = tonumber(slot.col) or 0
		local dir = tostring(slot.dir or "H")
		for i = 1, #word do
			local rr = (dir == "V") and (baseRow + (i - 1)) or baseRow
			local cc = (dir == "H") and (baseCol + (i - 1)) or baseCol
			if rr == row and cc == col then
				return word:sub(i, i)
			end
		end
	end
	if levelData and typeof(levelData.grid) == "table" then
		local gridRow = levelData.grid[(tonumber(row) or 0) + 1]
		if typeof(gridRow) == "string" then
			local ch = gridRow:sub((tonumber(col) or 0) + 1, (tonumber(col) or 0) + 1)
			if ch ~= "" and ch ~= "." then
				return ch
			end
		end
	end
	return ""
end

function LevelPayloadService.BuildClientLevelData(levelData)
	if not levelData then
		return nil
	end

	local wordSlots = getRequiredPositions(levelData)
	local occupiedCells = getOccupiedCellsFromPositions(wordSlots)

	return {
		packId = levelData.packId,
		levelId = levelData.levelId,
		globalLevelId = levelData.globalLevelId,
		packName = levelData.packName,
		letters = levelData.letters,
		gridRows = levelData.gridRows,
		gridCols = levelData.gridCols,
		levelColor = levelData.levelColor,
		difficulty = levelData.difficulty,
		date = levelData.date,
		occupiedCells = occupiedCells,
		wordSlots = wordSlots,
		requiredWordCount = #(levelData.words or {}),
	}
end

return LevelPayloadService
