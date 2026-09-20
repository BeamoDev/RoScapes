local ModerationConfig = {}

-- Optional server-only configuration, excluded from Git.
ModerationConfig.Webhooks = {
	purchases = "",
	flags = "",
	rejoin = "",
}
local privateWebhooks = script.Parent:FindFirstChild("ModerationWebhooksPrivate")
if privateWebhooks and privateWebhooks:IsA("ModuleScript") then
	ModerationConfig.Webhooks = require(privateWebhooks)
end

ModerationConfig.Detection = {
	fastInputWindowSeconds = 0.30,
	fastInputStreakToFlag = 6,
	perfectCorrectStreakToFlag = 45,
}

ModerationConfig.ManuallyHiddenUserIds = {
	-- Add reported or blocked player UserIds here.
	-- 123456789,
}

function ModerationConfig.IsManuallyHidden(userId)
	local target = tonumber(userId)
	if not target then
		return false
	end
	for _, listedUserId in ipairs(ModerationConfig.ManuallyHiddenUserIds) do
		if tonumber(listedUserId) == target then
			return true
		end
	end
	return false
end

return ModerationConfig
