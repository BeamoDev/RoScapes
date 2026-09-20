local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local ModerationConfig = require(script.Parent.ModerationConfig)

local WebhookService = {}

local PURCHASE_FOOTER_ICON = "https://cdn.discordapp.com/attachments/1249313018593017906/1290138475323985940/v2.png"
local FLAG_FOOTER_ICON = "https://cdn.discordapp.com/attachments/1249313018593017906/1290138475080843264/bane.png"

local function getAvatarHeadshotUrl(userId)
	return string.format(
		"https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=150&height=150&format=png",
		tonumber(userId) or 0
	)
end

local function postWebhook(url, payload)
	if typeof(url) ~= "string" or url == "" then
		return false
	end
	local ok = pcall(function()
		HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = HttpService:JSONEncode(payload),
		})
	end)
	return ok
end

local function getPlayerName(player)
	local success, name = pcall(function()
		return Players:GetNameFromUserIdAsync(player.UserId)
	end)
	return success and name or player.Name
end

local function buildPlayerFields(player)
	local aestTime = os.date("!%Y-%m-%d %H:%M:%S", os.time() + (10 * 60 * 60))
	return {
		{
			name = "Account Age",
			value = tostring(tonumber(player and player.AccountAge) or 0) .. " days old",
			inline = true,
		},
		{
			name = "Account ID",
			value = tostring(player and player.UserId or 0),
			inline = true,
		},
		{
			name = "Time (AEST)",
			value = aestTime,
			inline = true,
		},
	}
end

function WebhookService.SendPurchase(player, purchaseInfo)
	if not player or typeof(purchaseInfo) ~= "table" then
		return false
	end

	local playerName = getPlayerName(player)
	local report = tostring(purchaseInfo.title or "Developer Product Purchased")
	if purchaseInfo.label and purchaseInfo.label ~= "" then
		report = tostring(purchaseInfo.label)
	end
	if purchaseInfo.details and purchaseInfo.details ~= "" then
		report = report .. "\n\n" .. tostring(purchaseInfo.details)
	end

	return postWebhook(ModerationConfig.Webhooks.purchases, {
		content = "",
		embeds = {
			{
				author = {
					name = "Purchase By " .. playerName,
					icon_url = getAvatarHeadshotUrl(player.UserId),
				},
				description = "```" .. report .. "```",
				color = 0x7FDBFF,
				fields = buildPlayerFields(player),
				footer = {
					text = "Purchase System",
					icon_url = PURCHASE_FOOTER_ICON,
				},
			},
		},
		attachments = {},
	})
end

function WebhookService.SendFlag(player, flagInfo)
	if not player or typeof(flagInfo) ~= "table" then
		return false
	end

	local playerName = getPlayerName(player)
	local report = tostring(flagInfo.reason or "suspicious activity")
	if flagInfo.details and flagInfo.details ~= "" then
		report = report .. "\n\n" .. tostring(flagInfo.details)
	end

	return postWebhook(ModerationConfig.Webhooks.flags, {
		content = "",
		embeds = {
			{
				author = {
					name = playerName .. " Was Found Cheating",
					icon_url = getAvatarHeadshotUrl(player.UserId),
				},
				description = "```" .. report .. "```",
				color = 0xFF6B6B,
				fields = buildPlayerFields(player),
				footer = {
					text = "Cheater System",
					icon_url = FLAG_FOOTER_ICON,
				},
			},
		},
		attachments = {},
	})
end

function WebhookService.SendRejoin(player)

	local playerName = getPlayerName(player)

	return postWebhook(ModerationConfig.Webhooks.rejoin, {
		content = "",
		embeds = {
			{
				author = {
					name = playerName,
					icon_url = getAvatarHeadshotUrl(player.UserId),
				},
				description = "```" .. "Sytem Rejoin" .. "```",
				color = 0xFF6B6B,
				fields = buildPlayerFields(player),
				footer = {
					text = "Rejoin System",
					icon_url = FLAG_FOOTER_ICON,
				},
			},
		},
		attachments = {},
	})
end
return WebhookService
