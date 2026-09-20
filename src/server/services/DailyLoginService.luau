-- DailyLoginService.luau
-- Daily login rewards.


local DailyLoginService = {}

local DataService = require(script.Parent.DataService)

local REWARD_CYCLE = { 8, 12, 15, 20, 27, 34, 45 }

local function dayStamp()
	return math.floor(os.time() / 86400)
end

function DailyLoginService.GetState(player)
	local data = DataService.getData(player)
	if not data then
		return { canClaim = false, streak = 0, reward = REWARD_CYCLE[1], dayIndex = 1 }
	end

	data.dailyLogin = data.dailyLogin or {}
	local dl = data.dailyLogin
	local today = dayStamp()
	local last = tonumber(dl.lastClaimDay) or 0
	local streak = tonumber(dl.streak) or 0

	local canClaim = last < today
	local nextStreak = streak
	if last > 0 and today - last > 1 then
		nextStreak = 0
	end
	local dayIndex = (nextStreak % #REWARD_CYCLE) + 1
	return {
		canClaim = canClaim,
		streak = streak,
		dayIndex = dayIndex,
		reward = REWARD_CYCLE[dayIndex],
		lastClaimDay = last,
	}
end

function DailyLoginService.Claim(player)
	local data = DataService.getData(player)
	if not data then
		return false, "data unavailable", 0, DailyLoginService.GetState(player)
	end

	data.dailyLogin = data.dailyLogin or {}
	local dl = data.dailyLogin
	local today = dayStamp()
	local last = tonumber(dl.lastClaimDay) or 0
	local streak = tonumber(dl.streak) or 0

	if last >= today then
		return false, "already claimed today", 0, DailyLoginService.GetState(player)
	end

	if last > 0 then
		if today - last == 1 then
			streak += 1
		else
			streak = 1
		end
	else
		streak = 1
	end

	local idx = ((streak - 1) % #REWARD_CYCLE) + 1
	local reward = REWARD_CYCLE[idx]
	if idx == #REWARD_CYCLE then
		reward += 19
	end
	dl.lastClaimDay = today
	dl.streak = streak
	dl.totalClaims = (tonumber(dl.totalClaims) or 0) + 1

	DataService.addCoins(player, reward, "DailyLoginReward", "TimedReward")
	return true, "claimed", reward, DailyLoginService.GetState(player)
end

return DailyLoginService
