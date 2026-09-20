-- RemoteRegistry.luau
-- Shared remote setup.


local RemoteRegistry = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IS_SERVER = RunService:IsServer()
local remotesFolder = nil
local CLIENT_REMOTE_WAIT_SECONDS = 60

local REMOTE_SCHEMA = {
	Events = {
		"WordFound",
		"LevelComplete",
		"HintReveal",
		"SubmitWord",
		"RequestHint",
		"UpdateHints",
		"UpdateCoins",
		"UpdateSelectionHints",
		"SubmitDailyWord",
		"DailyPuzzleComplete",
		"PvPInviteReceived",
		"PvPInviteStatus",
		"PvPMatchStart",
		"PvPOppWordProgress",
		"PvPMatchEnd",
		"RankUpdated",
		"DevProductPurchased",
		"RejoinRemote",
	},
	Functions = {
		"GetLevelData",
		"GetPlayerData",
		"BuyHintsWithCoins",
		"UseArrowOnCell",
		"GetLeaderboard",
		"GetDailyPuzzle",
		"GetDailyQuests",
		"ClaimDailyQuest",
		"GetQuestBoard",
		"ClaimQuestReward",
		"GetDailyLoginReward",
		"ClaimDailyLoginReward",
		"GetPlayerStats",
		"GetPvPPlayers",
		"SendPvPInvite",
		"RespondPvPInvite",
		"LeavePvPMatch",
		"GetAchievements",
		"StartTimedMode",
		"GetTimedModeLevel",
		"FinishTimedMode",
		"StartHardcoreMode",
		"GetHardcoreNextLevel",
		"FinishHardcoreMode",
		"MarkTutorialComplete",
		"MarkFavoritePromptShown",
		"ClaimAchievementReward",
		"PrepareSpecialHintPurchase",
		"ClaimGroupReward",
		"GetAdminPlayers",
		"RunAdminAction",
	},
}

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

function RemoteRegistry.EnsureRemotes()
	assert(IS_SERVER, "[RemoteRegistry] EnsureRemotes() server only!")
	remotesFolder = ensureFolder(ReplicatedStorage, "Remotes")
	local eventsFolder = ensureFolder(remotesFolder, "Events")
	local functionsFolder = ensureFolder(remotesFolder, "Functions")

	for _, name in ipairs(REMOTE_SCHEMA.Events) do
		if not eventsFolder:FindFirstChild(name) then
			local re = Instance.new("RemoteEvent")
			re.Name = name
			re.Parent = eventsFolder
		end
	end

	for _, name in ipairs(REMOTE_SCHEMA.Functions) do
		if not functionsFolder:FindFirstChild(name) then
			local rf = Instance.new("RemoteFunction")
			rf.Name = name
			rf.Parent = functionsFolder
		end
	end
end

local function getRemotes()
	if remotesFolder then return remotesFolder end
	if IS_SERVER then
		remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
		assert(remotesFolder, "[RemoteRegistry] Remotes not created yet!")
	else
		remotesFolder = ReplicatedStorage:WaitForChild("Remotes", CLIENT_REMOTE_WAIT_SECONDS)
		assert(remotesFolder, "[RemoteRegistry] Remotes not found in time!")
	end
	return remotesFolder
end

local function waitForRemoteChild(parent, name)
	if IS_SERVER then
		return parent and parent:FindFirstChild(name)
	end
	local deadline = os.clock() + CLIENT_REMOTE_WAIT_SECONDS
	local child = parent and parent:FindFirstChild(name)
	while not child and os.clock() < deadline do
		child = parent and parent:WaitForChild(name, 2)
	end
	return child
end

function RemoteRegistry:GetEvent(name)
	local folder = IS_SERVER
		and getRemotes():FindFirstChild("Events")
		or waitForRemoteChild(getRemotes(), "Events")
	local event = IS_SERVER
		and folder:FindFirstChild(name)
		or waitForRemoteChild(folder, name)
	assert(event, "[RemoteRegistry] Event not found: " .. tostring(name))
	return event
end

function RemoteRegistry:GetFunction(name)
	local folder = IS_SERVER
		and getRemotes():FindFirstChild("Functions")
		or waitForRemoteChild(getRemotes(), "Functions")
	local func = IS_SERVER
		and folder:FindFirstChild(name)
		or waitForRemoteChild(folder, name)
	assert(func, "[RemoteRegistry] Function not found: " .. tostring(name))
	return func
end

return RemoteRegistry
