local function copyWords(words)
	local out = {}
	for _, word in ipairs(words or {}) do
		table.insert(out, tostring(word or ""):upper())
	end
	return out
end

local EARLY_SEEDS = {
	{ Letters = "EAST", Words = { "EAST", "SEAT", "EAT", "TEA" } },
	{ Letters = "NOTE", Words = { "NOTE", "TONE", "ONE", "TEN" } },
	{ Letters = "RATE", Words = { "RATE", "TEAR", "TARE", "EAT" } },
	{ Letters = "TEAM", Words = { "TEAM", "MEAT", "MATE", "TAME" } },
	{ Letters = "CARE", Words = { "CARE", "RACE", "ACRE", "CAR" } },
	{ Letters = "PEAR", Words = { "PEAR", "PARE", "REAP", "RAP" } },
	{ Letters = "STOP", Words = { "STOP", "SPOT", "POST", "TOP" } },
	{ Letters = "LATE", Words = { "LATE", "TALE", "TEAL", "LET" } },
	{ Letters = "COAT", Words = { "COAT", "TACO", "CAT", "ACT" } },
	{ Letters = "MEAL", Words = { "MEAL", "MALE", "LAME", "ALE" } },
}

local MID_SEEDS = {
	{ Letters = "STONE" },
	{ Letters = "TRAIN" },
	{ Letters = "HEART" },
	{ Letters = "WATER" },
	{ Letters = "SMILE" },
	{ Letters = "SHARE" },
	{ Letters = "PLANE" },
	{ Letters = "GRAIN" },
	{ Letters = "CREAM" },
	{ Letters = "HOUSE" },
}

local LATE_SEEDS = {
	{ Letters = "BRING" },
	{ Letters = "SOUND" },
	{ Letters = "LIGHT" },
	{ Letters = "FRAME" },
	{ Letters = "MONEY" },
	{ Letters = "CLOUD" },
	{ Letters = "RIVER" },
	{ Letters = "SWEAT" },
	{ Letters = "CRANE" },
	{ Letters = "TABLE" },
}

local function pickSeed(levelIndex)
	if levelIndex <= 40 then
		return EARLY_SEEDS[((levelIndex - 1) % #EARLY_SEEDS) + 1]
	end
	if levelIndex <= 70 then
		return MID_SEEDS[((levelIndex - 41) % #MID_SEEDS) + 1]
	end
	return LATE_SEEDS[((levelIndex - 71) % #LATE_SEEDS) + 1]
end

local module = {}
for levelIndex = 1, 100 do
	local seed = pickSeed(levelIndex)
	local entry = {
		Letters = seed.Letters,
	}
	if seed.Words then
		entry.Words = copyWords(seed.Words)
	end
	module[levelIndex] = entry
end

return module
