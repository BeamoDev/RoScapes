local MonetizationConfig = {}

MonetizationConfig.CoinProducts = {
	{ id = 3553103564, label = "Coin Pack S", coins = 200, robux = 29 },
	{ id = 3553103607, label = "Coin Pack M", coins = 600, robux = 79 },
	{ id = 3553103673, label = "Coin Pack L", coins = 1500, robux = 149 },
}

MonetizationConfig.HintProducts = {
	quickRescue = {
		id = 3570241187,
		label = "Quick Rescue",
		robux = 29,
		hints = 2,
		coins = 200,
	},
	singleHint = {
		id = 3570237602,
		label = "1 Hint",
		amount = 1,
		robux = 9,
	},
	hints10 = {
		id = 3554157040,
		label = "10 Hints",
		amount = 10,
		robux = 79,
	},
	hints100 = {
		id = 3554178584,
		label = "100 Hints",
		amount = 100,
		robux = 499,
	},
	pvpHint = {
		id = 3553698461,
		label = "1v1 Hint",
		robux = 4,
	},
	pvpRowHint = {
		id = 3554157335,
		label = "1v1 Row Hint",
		robux = 19,
	},
	dailyHint = {
		id = 3554157723,
		label = "Daily Hint",
		robux = 9,
	},
	dailySelectionHint = {
		id = 3554157479,
		label = "Daily Selection Hint",
		robux = 9,
	},
	superBundle = {
		id = 3554182641,
		label = "Super Bundle",
		robux = 99,
		hints = 5,
		selectionHints = 5,
		coins = 1000,
	},
}

MonetizationConfig.Passes = {
	premium = {
		id = 1743713793,
		label = "Premium",
		robux = 299,
	},
}

MonetizationConfig.Badges = {
	welcome = 1503855916205099,
	ranks = {
		BRONZE_1 = 193871221986513,
		BRONZE_2 = 1136311842811755,
		BRONZE_3 = 4299599958540151,
		BRONZE_4 = 1569040020339703,
		BRONZE_5 = 1348785668218164,
		SILVER_1 = 4120888581749944,
		SILVER_2 = 897614925054123,
		SILVER_3 = 3968607771872752,
		SILVER_4 = 3862226133417492,
		SILVER_5 = 3615836893636511,
		GOLD_1 = 2120963229502635,
		GOLD_2 = 916681967868909,
		GOLD_3 = 385638094418875,
		GOLD_4 = 1270221808276545,
		GOLD_5 = 2514916413989644,
	},
}

function MonetizationConfig.GetFirstPremiumLevel(levelCount)
	return 0
end

function MonetizationConfig.GetLastFreeLevel(levelCount)
	return math.max(0, math.floor(tonumber(levelCount) or 0))
end

function MonetizationConfig.IsPremiumLevel(levelId, levelCount)
	return false
end

return MonetizationConfig
