-- RankService.luau
-- Rank progression and rewards.


local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RankService = {}

local RankConfig = require(ReplicatedStorage:WaitForChild("Shared").systems.RankConfig)
local RANKS = RankConfig.Ranks or {}

local function clampPoints(points)
	return math.max(0, math.floor(tonumber(points) or 0))
end

function RankService.GetRankState(points)
	local p = clampPoints(points)
	local current = RANKS[1]
	local nextRank = nil

	for i, rank in ipairs(RANKS) do
		if p >= (tonumber(rank.pointsRequired) or 0) then
			current = rank
			nextRank = RANKS[i + 1]
		else
			nextRank = rank
			break
		end
	end

	local currentReq = tonumber(current and current.pointsRequired) or 0
	local nextReq = tonumber(nextRank and nextRank.pointsRequired) or currentReq
	local needed = math.max(1, nextReq - currentReq)
	local into = math.max(0, p - currentReq)
	local progress = nextRank and math.clamp(into / needed, 0, 1) or 1

	return {
		id = current and current.id or "BRONZE_1",
		name = current and current.name or "Bronze 1",
		tier = current and current.tier or "Bronze",
		division = tonumber(current and current.division) or 1,
		imageId = current and current.imageId or "rbxassetid://0",
		coinMultiplier = tonumber(current and current.coinMultiplier) or 1,
		points = p,
		progress = progress,
		progressPercent = math.floor((progress * 100) + 0.5),
		pointsIntoRank = into,
		pointsForNext = nextRank and math.max(0, nextReq - p) or 0,
		nextRankId = nextRank and nextRank.id or nil,
		nextRankName = nextRank and nextRank.name or nil,
		nextRankImageId = nextRank and nextRank.imageId or (current and current.imageId) or "rbxassetid://0",
	}
end

function RankService.GetCoinReward(baseCoins, points)
	local base = math.max(0, math.floor(tonumber(baseCoins) or 0))
	local rank = RankService.GetRankState(points)
	local mult = tonumber(rank.coinMultiplier) or 1
	return math.max(0, math.floor((base * mult) + 0.5)), rank
end

return RankService
