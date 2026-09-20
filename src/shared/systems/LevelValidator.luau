-- LevelValidator.luau
-- Checks that generated grids match their word data.


local LevelValidator = {}

-- Parse a grid and find all word positions
function LevelValidator.ParseGrid(gridRows)
	local results = {}
	local rows = #gridRows
	if rows == 0 then return results end
	local cols = #gridRows[1]
	
	local function cell(r, c)
		local row = gridRows[r + 1]
		if not row then return "." end
		return row:sub(c + 1, c + 1)
	end
	
	-- Horizontal runs
	for r = 0, rows - 1 do
		local c = 0
		while c < cols do
			local ch = cell(r, c)
			if ch ~= "." then
				local startC = c
				local letters = {}
				while c < cols and cell(r, c) ~= "." do
					table.insert(letters, cell(r, c))
					c = c + 1
				end
				if #letters >= 2 then
					table.insert(results, {
						word = table.concat(letters),
						row = r,
						col = startC,
						dir = "H"
					})
				end
			else
				c = c + 1
			end
		end
	end
	
	-- Vertical runs
	for c = 0, cols - 1 do
		local r = 0
		while r < rows do
			local ch = cell(r, c)
			if ch ~= "." then
				local startR = r
				local letters = {}
				while r < rows and cell(r, c) ~= "." do
					table.insert(letters, cell(r, c))
					r = r + 1
				end
				if #letters >= 2 then
					table.insert(results, {
						word = table.concat(letters),
						row = startR,
						col = c,
						dir = "V"
					})
				end
			else
				r = r + 1
			end
		end
	end
	
	return results
end

-- Validate a level - returns true/false and error message
function LevelValidator.ValidateLevel(level)
	-- Check required fields
	if not level.letters or #level.letters == 0 then
		return false, "Missing letters"
	end
	
	if not level.grid or #level.grid == 0 then
		return false, "Missing grid"
	end
	
	if not level.words or #level.words == 0 then
		return false, "Missing words"
	end
	
	-- Parse grid to find actual words
	local gridWords = LevelValidator.ParseGrid(level.grid)
	local gridWordSet = {}
	for _, gw in ipairs(gridWords) do
		gridWordSet[gw.word] = true
	end
	
	-- Check that all required words exist in grid
	local missingWords = {}
	for _, word in ipairs(level.words) do
		if not gridWordSet[word] then
			table.insert(missingWords, word)
		end
	end
	
	if #missingWords > 0 then
		return false, "Words not in grid: " .. table.concat(missingWords, ", ")
	end
	
	-- Check that letters can form all words
	local letterCount = {}
	for _, letter in ipairs(level.letters) do
		letter = letter:upper()
		letterCount[letter] = (letterCount[letter] or 0) + 1
	end
	
	for _, word in ipairs(level.words) do
		local needed = {}
		for i = 1, #word do
			local ch = word:sub(i, i)
			needed[ch] = (needed[ch] or 0) + 1
			if not letterCount[ch] or needed[ch] > letterCount[ch] then
				return false, "Word '" .. word .. "' cannot be formed from given letters"
			end
		end
	end
	
	return true, "OK"
end

-- Auto-fix a level by finding valid words from the grid
function LevelValidator.AutoFixLevel(level)
	local gridWords = LevelValidator.ParseGrid(level.grid)
	local validWords = {}
	
	-- Build letter count
	local letterCount = {}
	for _, letter in ipairs(level.letters) do
		letter = letter:upper()
		letterCount[letter] = (letterCount[letter] or 0) + 1
	end
	
	-- Check each grid word can be formed
	for _, gw in ipairs(gridWords) do
		local word = gw.word
		local needed = {}
		local canForm = true
		for i = 1, #word do
			local ch = word:sub(i, i)
			needed[ch] = (needed[ch] or 0) + 1
			if not letterCount[ch] or needed[ch] > letterCount[ch] then
				canForm = false
				break
			end
		end
		if canForm then
			table.insert(validWords, word)
		end
	end
	
	return validWords
end

return LevelValidator
