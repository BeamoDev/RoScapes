local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)
local ModerationConfig = require(script.Parent.ModerationConfig)

local FlagService = {}

local runtimeStateByUserId = {}

local function getRuntimeState(userId)
	runtimeStateByUserId[userId] = runtimeStateByUserId[userId] or {
		lastSubmitAt = nil,
		fastInputStreak = 0,
		perfectCorrectStreak = 0,
	}
	return runtimeStateByUserId[userId]
end

function FlagService.ClearPlayer(player)
	if not player then
		return
	end
	runtimeStateByUserId[player.UserId] = nil
end

function FlagService.IsLeaderboardHidden(target)
	local userId = typeof(target) == "Instance" and target.UserId or tonumber(target)
	if not userId then
		return false
	end
	if ModerationConfig.IsManuallyHidden(userId) then
		return true
	end
	local player = typeof(target) == "Instance" and target or Players:GetPlayerByUserId(userId)
	if not player then
		return DataService.isLeaderboardSuppressedByUserId(userId)
	end
	return DataService.isLeaderboardSuppressed(player)
end

function FlagService.FlagPlayer(player, reason, details)
	if not player or ModerationConfig.IsManuallyHidden(player.UserId) then
		return {
			flagged = false,
			alreadyHidden = true,
			reason = reason,
			details = details,
		}
	end
	if DataService.isLeaderboardSuppressed(player) then
		return {
			flagged = false,
			alreadyHidden = true,
			reason = reason,
			details = details,
		}
	end
	DataService.setLeaderboardSuppressed(player, true, reason, details)
	return {
		flagged = true,
		alreadyHidden = false,
		reason = reason,
		details = details,
	}
end

function FlagService.RecordSubmission(player, valid, word, extra)
	if not player then
		return nil
	end

	local submittedWord = tostring(word or "")
	local reason = tostring(extra and extra.reason or "")
	if #submittedWord < 2 or reason == "too short" then
		return nil
	end

	local state = getRuntimeState(player.UserId)
	local now = os.clock()
	local detection = ModerationConfig.Detection or {}
	local fastWindow = tonumber(detection.fastInputWindowSeconds) or 0.35
	local fastThreshold = tonumber(detection.fastInputStreakToFlag) or 6
	local perfectThreshold = tonumber(detection.perfectCorrectStreakToFlag) or 30

	if state.lastSubmitAt ~= nil and (now - state.lastSubmitAt) <= fastWindow then
		state.fastInputStreak = (state.fastInputStreak or 0) + 1
	else
		state.fastInputStreak = 1
	end
	state.lastSubmitAt = now

	if valid then
		state.perfectCorrectStreak = (state.perfectCorrectStreak or 0) + 1
	else
		state.perfectCorrectStreak = 0
	end

	if state.fastInputStreak >= fastThreshold then
		return FlagService.FlagPlayer(
			player,
			"Fast inputs",
			string.format(
				"%d submissions in a row were at or under %.2fs. Last word: %s",
				state.fastInputStreak,
				fastWindow,
				tostring(word or "")
			)
		)
	end

	if state.perfectCorrectStreak >= perfectThreshold then
		return FlagService.FlagPlayer(
			player,
			"Perfect gameplay streak",
			string.format(
				"%d correct guesses in a row. Last word: %s. Pack=%s Level=%s",
				state.perfectCorrectStreak,
				tostring(word or ""),
				tostring(extra and extra.packId or "?"),
				tostring(extra and extra.levelId or "?")
			)
		)
	end

	return nil
end

return FlagService
