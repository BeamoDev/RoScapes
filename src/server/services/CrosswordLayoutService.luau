local CrosswordLayoutService = {}

local MAX_LAYOUT_RETRIES = 100
local MAX_DROPPED_WORDS = 1
local MAX_RANDOM_PLACEMENT_CHOICES = 3

local CrosswordBuilder = {}
CrosswordBuilder.__index = CrosswordBuilder

function CrosswordBuilder.new()
	return setmetatable({
		grid = {},
		words = {},
	}, CrosswordBuilder)
end

function CrosswordBuilder:getCells(word, x, y, direction)
	local cells = {}
	if direction == "H" then
		for i = 1, #word do
			table.insert(cells, { x = x + (i - 1), y = y })
		end
	else
		for i = 1, #word do
			table.insert(cells, { x = x, y = y + (i - 1) })
		end
	end
	return cells
end

function CrosswordBuilder:isPerpendicularNeighborOccupied(x, y, direction)
	if direction == "H" then
		return self.grid[x .. ":" .. (y - 1)] ~= nil or self.grid[x .. ":" .. (y + 1)] ~= nil
	end
	return self.grid[(x - 1) .. ":" .. y] ~= nil or self.grid[(x + 1) .. ":" .. y] ~= nil
end

function CrosswordBuilder:canPlace(word, x, y, direction)
	if self.words[word] then
		return false
	end

	local cells = self:getCells(word, x, y, direction)
	local intersections = 0
	local newCells = 0
	local beforeKey
	local afterKey

	if direction == "H" then
		beforeKey = (x - 1) .. ":" .. y
		afterKey = (x + #word) .. ":" .. y
	else
		beforeKey = x .. ":" .. (y - 1)
		afterKey = x .. ":" .. (y + #word)
	end

	if self.grid[beforeKey] or self.grid[afterKey] then
		return false
	end

	for i, cell in ipairs(cells) do
		local key = cell.x .. ":" .. cell.y
		local existing = self.grid[key]
		local letter = word:sub(i, i)

		if existing then
			if existing ~= letter then
				return false
			end
			intersections += 1
		else
			newCells += 1
			if self:isPerpendicularNeighborOccupied(cell.x, cell.y, direction) then
				return false
			end
		end
	end

	if next(self.words) == nil then
		return true
	end
	if intersections == 0 or newCells == 0 then
		return false
	end
	if intersections >= (#word - 1) then
		return false
	end

	return true
end

function CrosswordBuilder:placeWord(word, x, y, direction)
	for i, cell in ipairs(self:getCells(word, x, y, direction)) do
		self.grid[cell.x .. ":" .. cell.y] = word:sub(i, i)
	end
	self.words[word] = {
		x = x,
		y = y,
		dir = direction,
	}
end

function CrosswordBuilder:scorePlacement(word, x, y, direction)
	local intersections = 0
	local minX, maxX, minY, maxY

	for key in pairs(self.grid) do
		local sx, sy = string.match(key, "([^:]+):([^:]+)")
		local gx = tonumber(sx) or 0
		local gy = tonumber(sy) or 0
		minX = minX and math.min(minX, gx) or gx
		maxX = maxX and math.max(maxX, gx) or gx
		minY = minY and math.min(minY, gy) or gy
		maxY = maxY and math.max(maxY, gy) or gy
	end

	for _, cell in ipairs(self:getCells(word, x, y, direction)) do
		local key = cell.x .. ":" .. cell.y
		if self.grid[key] then
			intersections += 1
		end
		minX = minX and math.min(minX, cell.x) or cell.x
		maxX = maxX and math.max(maxX, cell.x) or cell.x
		minY = minY and math.min(minY, cell.y) or cell.y
		maxY = maxY and math.max(maxY, cell.y) or cell.y
	end

	local width = (maxX - minX) + 1
	local height = (maxY - minY) + 1
	local area = width * height

	return (intersections * 100) + (#word * 5) - area - (math.abs(width - height) * 2)
end

function CrosswordBuilder:getCandidatePlacements(word)
	if next(self.grid) == nil then
		return {
			{ x = 0, y = 0, dir = "H", score = 0 },
		}
	end

	local seen = {}
	local placements = {}

	for key, gridLetter in pairs(self.grid) do
		local sx, sy = string.match(key, "([^:]+):([^:]+)")
		local gx = tonumber(sx) or 0
		local gy = tonumber(sy) or 0
		for i = 1, #word do
			if word:sub(i, i) == gridLetter then
				for _, dir in ipairs({ "H", "V" }) do
					local x = (dir == "H") and (gx - (i - 1)) or gx
					local y = (dir == "V") and (gy - (i - 1)) or gy
					local placementKey = x .. ":" .. y .. ":" .. dir
					if not seen[placementKey] and self:canPlace(word, x, y, dir) then
						seen[placementKey] = true
						table.insert(placements, {
							x = x,
							y = y,
							dir = dir,
							score = self:scorePlacement(word, x, y, dir),
						})
					end
				end
			end
		end
	end

	table.sort(placements, function(a, b)
		return a.score > b.score
	end)
	return placements
end

function CrosswordBuilder:toPositions(words)
	local minX, maxX, minY, maxY
	for key in pairs(self.grid) do
		local sx, sy = string.match(key, "([^:]+):([^:]+)")
		local x = tonumber(sx) or 0
		local y = tonumber(sy) or 0
		minX = minX and math.min(minX, x) or x
		maxX = maxX and math.max(maxX, x) or x
		minY = minY and math.min(minY, y) or y
		maxY = maxY and math.max(maxY, y) or y
	end

	local positions = {}
	for _, word in ipairs(words) do
		local placement = self.words[word]
		if placement then
			table.insert(positions, {
				word = word,
				row = placement.y - minY,
				col = placement.x - minX,
				dir = placement.dir,
			})
		end
	end

	local gridRows = (maxY - minY) + 1
	local gridCols = (maxX - minX) + 1
	return positions, gridRows, gridCols
end

local function shuffleWords(words)
	local shuffled = table.clone(words or {})
	for index = #shuffled, 2, -1 do
		local swapIndex = math.random(1, index)
		shuffled[index], shuffled[swapIndex] = shuffled[swapIndex], shuffled[index]
	end
	return shuffled
end

local function chooseAttemptOrder(requiredWords)
	local working = shuffleWords(requiredWords or {})
	table.sort(working, function(a, b)
		if #a == #b then
			return a < b
		end
		return #a > #b
	end)
	if #working <= 1 then
		return working
	end

	local anchorIndex = math.random(1, #working)
	local anchorWord = table.remove(working, anchorIndex)
	local tail = shuffleWords(working)
	table.insert(tail, 1, anchorWord)
	return tail
end

function CrosswordLayoutService.Build(requiredWords, options)
	options = options or {}
	local minPlacedWords = math.max(1, tonumber(options.minPlacedWords) or 3)
	local maxRetries = math.max(1, tonumber(options.maxRetries) or MAX_LAYOUT_RETRIES)
	local placementChoiceCount = math.max(1, tonumber(options.placementChoiceCount) or MAX_RANDOM_PLACEMENT_CHOICES)

	for _ = 1, maxRetries do
		local builder = CrosswordBuilder.new()
		local failed = 0
		local attemptWords = chooseAttemptOrder(requiredWords)

		for index, word in ipairs(attemptWords) do
			if index == 1 then
				builder:placeWord(word, 0, 0, "H")
			else
				local placements = builder:getCandidatePlacements(word)
				if placements[1] then
					local choiceIndex = math.random(1, math.min(#placements, placementChoiceCount))
					local chosenPlacement = placements[choiceIndex]
					builder:placeWord(word, chosenPlacement.x, chosenPlacement.y, chosenPlacement.dir)
				else
					failed += 1
					if failed > MAX_DROPPED_WORDS then
						builder = nil
						break
					end
				end
			end
		end

		if builder and failed <= MAX_DROPPED_WORDS then
			local placed = {}
			for _, word in ipairs(requiredWords or {}) do
				if builder.words[word] then
					table.insert(placed, word)
				end
			end
			if #placed >= minPlacedWords then
				local positions, gridRows, gridCols = builder:toPositions(placed)
				return {
					words = placed,
					positions = positions,
					gridRows = gridRows,
					gridCols = gridCols,
				}
			end
		end
	end

	return nil
end

return CrosswordLayoutService
