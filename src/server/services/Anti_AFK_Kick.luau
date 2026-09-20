local AntiAFKKick = {}

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local Events = game:WaitForChild("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Events")
local RejoinRemote = Events:WaitForChild("RejoinRemote")
local WebHook = require(script.Parent.WebhookService)

RejoinRemote.OnServerEvent:Connect(function(player)
	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions.ServerInstanceId = game.JobId
	teleportOptions:SetTeleportData({autoRejoin = true})

	local attemptIndex = 0
	local success

	repeat
		attemptIndex += 1
		success = pcall(function()
			TeleportService:Teleport(game.PlaceId, player, teleportOptions)
		end)

		if not success then
			task.wait(2)
		else
			local isPremium = player.MembershipType == Enum.MembershipType.Premium
			local color = isPremium and 0x000000 or 0xFF0000
			WebHook.SendRejoin(player)
		end
	until success or attemptIndex == 4
end)

Players.PlayerAdded:Connect(function(player)
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData
	if teleportData and teleportData.autoRejoin then
		warn(`[AFK] {player.Name} rejoined after AFK kick`)
	end
end)

return AntiAFKKick
