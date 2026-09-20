local LevelPackConfig = {}

LevelPackConfig.LevelsPerPack = 30
LevelPackConfig.MaxPackCount = 30
LevelPackConfig.MaxPlayableLevels = LevelPackConfig.LevelsPerPack * LevelPackConfig.MaxPackCount

LevelPackConfig.PackNames = {
	"Misty Peaks",
	"Riverwood",
	"Cloud Summit",
	"Dawnridge",
	"Foglake",
	"Greenwood",
	"Crimson Bloom",
	"Mossriver",
	"Wildflower",
	"Blossom Branch",
	"Pink Fields",
	"Deep Fogwoods",
	"Valley Dawn",
	"Frost Lake",
	"Glacier Bay",
	"Petal Grove",
	"Suncoast",
	"Canyonlands",
	"Silver Pines",
	"Golden Meadow",
	"Rainforest Falls",
	"Rose Valley",
	"Winter Hollow",
	"Seabreeze",
	"Amber Cliffs",
	"Moonlit Grove",
	"Crystal Ridge",
	"Ferntrail",
	"Blue Horizon",
	"Maple Mist",
}

function LevelPackConfig.GetPackName(packId)
	local resolved = tonumber(packId) or 1
	return LevelPackConfig.PackNames[resolved] or ("Pack " .. tostring(resolved))
end

return LevelPackConfig
