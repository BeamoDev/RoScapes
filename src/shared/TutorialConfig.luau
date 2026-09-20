local TutorialConfig = {
	OwnerReplayUserId = 1790165114,
}

function TutorialConfig.ShouldReplayForUserId(userId)
	return tonumber(userId) == TutorialConfig.OwnerReplayUserId
end

function TutorialConfig.ShouldStart(completed, userId, forceTesting)
	return forceTesting == true or TutorialConfig.ShouldReplayForUserId(userId) or completed ~= true
end

return TutorialConfig
