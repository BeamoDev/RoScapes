-- RankConfig.luau
-- Rank thresholds and badge assets.


local RankConfig = {}

RankConfig.Ranks = {
	{ id = "BRONZE_1", name = "Bronze 1", tier = "Bronze", division = 1, pointsRequired = 0, coinMultiplier = 1.0, imageId = "rbxassetid://93975337407471" },
	{ id = "BRONZE_2", name = "Bronze 2", tier = "Bronze", division = 2, pointsRequired = 120, coinMultiplier = 1.02, imageId = "rbxassetid://78227984942803" },
	{ id = "BRONZE_3", name = "Bronze 3", tier = "Bronze", division = 3, pointsRequired = 250, coinMultiplier = 1.04, imageId = "rbxassetid://109189573658099" },
	{ id = "BRONZE_4", name = "Bronze 4", tier = "Bronze", division = 4, pointsRequired = 390, coinMultiplier = 1.06, imageId = "rbxassetid://119798264057908" },
	{ id = "BRONZE_5", name = "Bronze 5", tier = "Bronze", division = 5, pointsRequired = 540, coinMultiplier = 1.08, imageId = "rbxassetid://136573119441345" },

	{ id = "SILVER_1", name = "Silver 1", tier = "Silver", division = 1, pointsRequired = 700, coinMultiplier = 1.11, imageId = "rbxassetid://105961213733459" },
	{ id = "SILVER_2", name = "Silver 2", tier = "Silver", division = 2, pointsRequired = 870, coinMultiplier = 1.14, imageId = "rbxassetid://126589496382003" },
	{ id = "SILVER_3", name = "Silver 3", tier = "Silver", division = 3, pointsRequired = 1050, coinMultiplier = 1.17, imageId = "rbxassetid://121370927126154" },
	{ id = "SILVER_4", name = "Silver 4", tier = "Silver", division = 4, pointsRequired = 1240, coinMultiplier = 1.2, imageId = "rbxassetid://78825907622730" },
	{ id = "SILVER_5", name = "Silver 5", tier = "Silver", division = 5, pointsRequired = 1440, coinMultiplier = 1.23, imageId = "rbxassetid://71141620237079" },

	{ id = "GOLD_1", name = "Gold 1", tier = "Gold", division = 1, pointsRequired = 1650, coinMultiplier = 1.27, imageId = "rbxassetid://96006532131497" },
	{ id = "GOLD_2", name = "Gold 2", tier = "Gold", division = 2, pointsRequired = 1870, coinMultiplier = 1.31, imageId = "rbxassetid://123615900151040" },
	{ id = "GOLD_3", name = "Gold 3", tier = "Gold", division = 3, pointsRequired = 2100, coinMultiplier = 1.35, imageId = "rbxassetid://128926282037850" },
	{ id = "GOLD_4", name = "Gold 4", tier = "Gold", division = 4, pointsRequired = 2340, coinMultiplier = 1.39, imageId = "rbxassetid://114306976019263" },
	{ id = "GOLD_5", name = "Gold 5", tier = "Gold", division = 5, pointsRequired = 2590, coinMultiplier = 1.45, imageId = "rbxassetid://111799911373143" },
}

return RankConfig
