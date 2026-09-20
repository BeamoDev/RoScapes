local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BadgeAwardService = {}

local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MonetizationConfig"))

local function awardBadge(userId, badgeId)
	local resolvedBadgeId = tonumber(badgeId) or 0
	local resolvedUserId = tonumber(userId) or 0
	if resolvedBadgeId <= 0 or resolvedUserId <= 0 then
		return false
	end

	local ok, alreadyHas = pcall(function()
		return BadgeService:UserHasBadgeAsync(resolvedUserId, resolvedBadgeId)
	end)
	if ok and alreadyHas then
		return true
	end

	local grantOk = pcall(function()
		BadgeService:AwardBadge(resolvedUserId, resolvedBadgeId)
	end)
	return grantOk
end

function BadgeAwardService.AwardWelcome(player)
	if not player then
		return false
	end
	return awardBadge(player.UserId, MonetizationConfig.Badges and MonetizationConfig.Badges.welcome)
end

function BadgeAwardService.AwardRank(player, rankId)
	if not player then
		return false
	end
	local badges = MonetizationConfig.Badges and MonetizationConfig.Badges.ranks or {}
	return awardBadge(player.UserId, badges and badges[tostring(rankId or "")])
end

return BadgeAwardService
