-- Run from the repository root: lune run tests/purchases.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local ProfilePersistence = require("../src/server/services/ProfilePersistence")
local PurchaseRewards = require("../src/server/services/PurchaseRewards")
local ReceiptProcessor = require("../src/server/services/ReceiptProcessor")
local TimedRewards = require("../src/server/services/TimedRewards")
local config = require("../src/shared/MonetizationConfig")

local passed = 0
local function test(name, callback)
	callback()
	passed += 1
	print("PASS", name)
end

local function encode(data)
	return serde.encode("json", data)
end
local function decode(value)
	if type(value) == "table" then
		return serde.decode("json", encode(value))
	end
	local ok, data = pcall(serde.decode, "json", value)
	return ok and data or nil
end
local function clone(data)
	return decode(encode(data))
end
local function storeMock()
	local store = { values = {}, fail = false, retryCallback = false }
	function store:UpdateAsync(key, callback)
		if self.fail then
			error("injected datastore outage")
		end
		if self.beforeUpdate then
			self.beforeUpdate()
		end
		if self.retryCallback then
			callback(self.values[key])
		end
		local nextValue = callback(self.values[key])
		if nextValue == nil then
			return nil
		end
		self.values[key] = nextValue
		if self.failAfterCommit then
			error("injected lost acknowledgement")
		end
		return nextValue
	end
	return store
end

local function defaults()
	return { coins = 100, hints = 0, selectionHints = 0, stats = {}, processedReceipts = {} }
end

test("profile load preserves legacy balances and excludes a second server", function()
	local store = storeMock()
	store.values["1"] = encode({ coins = 750, hints = 12 })
	local first = ProfilePersistence.new(store, encode, decode, defaults, function() return 100 end, function() return "A" end)
	local second = ProfilePersistence.new(store, encode, decode, defaults, function() return 100 end, function() return "B" end)
	local data = first:Load(1)
	assert(data.coins == 750 and data.hints == 12)
	assert(second:Load(1) == nil)
	assert(first:Save(1, data, true))
	assert(decode(store.values["1"])._session == nil)
	assert(second:Load(1).coins == 750)
end)

test("expired ownership cannot overwrite another server's purchase", function()
	local store = storeMock()
	local now = 100
	local first = ProfilePersistence.new(store, encode, decode, defaults, function() return now end, function() return "A" end)
	local second = ProfilePersistence.new(store, encode, decode, defaults, function() return now end, function() return "B" end)
	local stale = first:Load(1)
	now = 701
	local current = second:Load(1)
	PurchaseRewards.Stage(current, "receipt", 1, { coins = 200 })
	assert(second:Save(1, current))
	assert(not first:Save(1, stale))
	assert(decode(store.values["1"]).coins == 300)
end)

test("corrupt profiles and failed loads cannot create writable defaults", function()
	local store = storeMock()
	store.values["1"] = "broken JSON"
	local persistence = ProfilePersistence.new(store, encode, decode, defaults, os.time, function() return "A" end)
	assert(persistence:Load(1) == nil)
	assert(not persistence:Save(1, defaults()))
	assert(store.values["1"] == "broken JSON")
	store.fail = true
	assert(persistence:Load(2) == nil)
	assert(not persistence:Save(2, defaults()))
	assert(store.values["2"] == nil)
end)

-- Minimal Roblox instance tree for executing the actual DataService module.
local function instance(className)
	local object = { ClassName = className, children = {}, attributes = {} }
	function object:FindFirstChild(name)
		for _, child in ipairs(self.children) do
			if child.Name == name then return child end
		end
		return nil
	end
	function object:GetChildren() return self.children end
	function object:IsA(name) return self.ClassName == name end
	function object:GetAttribute(name) return self.attributes[name] end
	function object:Destroy()
		if self.Parent then
			local index = table.find(self.Parent.children, self)
			if index then table.remove(self.Parent.children, index) end
		end
	end
	return setmetatable(object, {
		__newindex = function(self, key, value)
			rawset(self, key, value)
			if key == "Parent" and value then table.insert(value.children, self) end
		end,
	})
end

local nextGuid = 0
local function dataService(store)
	local services = {
		DataStoreService = { GetDataStore = function() return store end },
		HttpService = {
			JSONEncode = function(_, value) return encode(value) end,
			JSONDecode = function(_, value) return serde.decode("json", value) end,
			GenerateGUID = function()
				nextGuid += 1
				return tostring(nextGuid)
			end,
		},
		AnalyticsService = {},
	}
	local modules = {
		RankService = { GetRankState = function() return {} end },
		ProfilePersistence = ProfilePersistence,
		PurchaseRewards = PurchaseRewards,
	}
	return luau.load(fs.readFile("src/server/services/DataService.luau"), {
		debugName = "DataService-under-test",
		environment = {
			game = { GetService = function(_, name) return assert(services[name]) end },
			script = { Parent = { RankService = "RankService", ProfilePersistence = "ProfilePersistence", PurchaseRewards = "PurchaseRewards" } },
			require = function(name) return assert(modules[name]) end,
			Instance = { new = instance },
			task = { wait = function() end },
			warn = function() end,
		},
	})()
end

local function player()
	local p = instance("Player")
	p.Name = "Buyer"
	p.UserId = 1
	p.Parent = instance("Players")
	function p:Kick(reason) self.kicked = reason end
	return p
end

local function setup()
	local store = storeMock()
	local data = dataService(store)
	local buyer = player()
	assert(data.loadPlayerData(buyer))
	return store, data, buyer
end

local coinReceipt = { PurchaseId = "coins-1", ProductId = config.CoinProducts[1].id, PlayerId = 1 }
local coinReward = PurchaseRewards.Resolve(config, coinReceipt.ProductId)

test("purchase persists coins and receipt atomically, without duplicate grants", function()
	local store, data, buyer = setup()
	store.retryCallback = true
	local saved, first = data.processPurchase(buyer, coinReceipt, coinReward)
	assert(saved and first)
	local stored = decode(store.values["1"])
	assert(stored.coins == 300 and stored.processedReceipts[coinReceipt.PurchaseId] == coinReceipt.ProductId)
	local duplicate, newlyGranted = data.processPurchase(buyer, coinReceipt, coinReward)
	assert(duplicate and not newlyGranted and data.getCoins(buyer) == 300)
end)

test("failed writes defer receipts and retry without reapplying spent rewards", function()
	local store, data, buyer = setup()
	store.fail = true
	assert(not data.processPurchase(buyer, coinReceipt, coinReward))
	assert(decode(store.values["1"]).coins == 100)
	-- Simulate spending 50 coins while an acknowledgement is pending.
	buyer:FindFirstChild("leaderstats"):FindFirstChild("Coins").Value = 250
	store.fail = false
	assert(data.processPurchase(buyer, coinReceipt, coinReward))
	assert(decode(store.values["1"]).coins == 250)
end)

test("lost datastore response is safe to retry", function()
	local store, data, buyer = setup()
	store.failAfterCommit = true
	assert(not data.processPurchase(buyer, coinReceipt, coinReward))
	assert(decode(store.values["1"]).coins == 300)
	store.failAfterCommit = false
	assert(data.processPurchase(buyer, coinReceipt, coinReward))
	assert(decode(store.values["1"]).coins == 300)
end)

test("rejoining and redelivering a receipt never grants twice", function()
	local store, data, buyer = setup()
	assert(data.processPurchase(buyer, coinReceipt, coinReward))
	data.releasePlayerData(buyer)
	local nextServer = dataService(store)
	local nextPlayer = player()
	assert(nextServer.loadPlayerData(nextPlayer))
	local saved, first = nextServer.processPurchase(nextPlayer, coinReceipt, coinReward)
	assert(saved and not first and nextServer.getCoins(nextPlayer) == 300)
end)

test("rejoin in the same server creates a fresh writable session", function()
	local store, data, buyer = setup()
	assert(data.processPurchase(buyer, coinReceipt, coinReward))
	data.releasePlayerData(buyer)
	local nextPlayer = player()
	assert(data.loadPlayerData(nextPlayer))
	assert(data.getCoins(nextPlayer) == 300)
	assert(data.savePlayerData(nextPlayer))
	assert(#data.getLoadedPlayers() == 1)
	assert(decode(store.values["1"]).processedReceipts[coinReceipt.PurchaseId])
end)

test("receipt arriving during an older autosave is not prematurely acknowledged", function()
	local store, data, buyer = setup()
	local inside = false
	store.beforeUpdate = function()
		if inside then return end
		inside = true
		assert(not data.processPurchase(buyer, coinReceipt, coinReward))
	end
	assert(data.savePlayerData(buyer))
	assert(decode(store.values["1"]).coins == 100)
	store.beforeUpdate = nil
	assert(data.processPurchase(buyer, coinReceipt, coinReward))
	assert(decode(store.values["1"]).coins == 300)
end)

test("autosave confirming a failed purchase does not lose its feedback", function()
	local store, data, buyer = setup()
	store.fail = true
	assert(not data.processPurchase(buyer, coinReceipt, coinReward))
	store.fail = false
	assert(data.savePlayerData(buyer))
	local saved, first = data.processPurchase(buyer, coinReceipt, coinReward)
	assert(saved and first)
	local _, duplicate = data.processPurchase(buyer, coinReceipt, coinReward)
	assert(not duplicate)
end)

test("unloaded player and failed data load cannot acknowledge purchases", function()
	local store = storeMock()
	store.fail = true
	local data, buyer = dataService(store), player()
	assert(not data.processPurchase(buyer, coinReceipt, coinReward))
	assert(data.loadPlayerData(buyer) == nil and buyer.kicked)
	assert(data.getData(buyer) == nil)
	assert(not data.processPurchase(buyer, coinReceipt, coinReward))
	assert(store.values["1"] == nil)
end)

test("every configured product persists the expected currency or fallback", function()
	for _, group in ipairs({ config.CoinProducts, config.HintProducts }) do
		for key, product in pairs(group) do
			local store, data, buyer = setup()
			local info = { PurchaseId = tostring(product.id), ProductId = product.id }
			local reward = assert(PurchaseRewards.Resolve(config, product.id))
			assert(data.processPurchase(buyer, info, reward))
			local stored = decode(store.values["1"])
			assert(stored.coins == 100 + (product.coins or 0))
			assert(stored.selectionHints == (product.selectionHints or 0))
			local special = key == "pvpHint" or key == "pvpRowHint" or key == "dailyHint" or key == "dailySelectionHint"
			assert(stored.hints == (special and 1 or (product.amount or product.hints or 0)))
		end
	end
end)

test("receipt processor defers unknown products and contains feedback failures", function()
	local _, data, buyer = setup()
	local notifications = 0
	local processor = ReceiptProcessor.new({
		findPlayer = function(id) return id == 1 and buyer or nil end,
		resolveReward = function(id) return PurchaseRewards.Resolve(config, id) end,
		processPurchase = data.processPurchase,
		onGranted = function()
			notifications += 1
			error("injected UI failure")
		end,
	})
	assert(not processor:Process({ PurchaseId = "unknown", ProductId = -1, PlayerId = 1 }))
	assert(not processor:Process({ PurchaseId = "absent", ProductId = coinReceipt.ProductId, PlayerId = 2 }))
	assert(processor:Process(coinReceipt))
	assert(processor:Process(coinReceipt))
	assert(notifications == 1)
end)

test("simultaneous duplicate receipt is deferred while the first is in flight", function()
	local processor
	local calls = 0
	processor = ReceiptProcessor.new({
		findPlayer = function() return {} end,
		resolveReward = function() return {} end,
		processPurchase = function()
			calls += 1
			assert(not processor:Process(coinReceipt))
			return true, true
		end,
		onGranted = function() end,
	})
	assert(processor:Process(coinReceipt) and calls == 1)
end)

test("timed reward ignores forged win flags and claimed solved counts", function()
	for _, solved in ipairs({ 0, 1, 5 }) do
		local active = { solvedCount = solved, rewardCoins = 110 }
		assert(TimedRewards.Calculate(active, true, 99999) == solved * 13)
		assert(TimedRewards.Calculate(active, false, 0) == solved * 13)
	end
end)

test("actual timed finish handler consumes the match once and ignores forged arguments", function()
	local source = fs.readFile("src/server/ServerMain.server.luau")
	local start = assert(source:find('RemoteRegistry:GetFunction("FinishTimedMode").OnServerInvoke = ', 1, true))
	local finish = assert(source:find('RemoteRegistry:GetFunction("StartHardcoreMode")', start, true))
	local handlerSource = source:sub(start, finish - 1)
	local remote = {}
	local matches = { [1] = { solvedCount = 2, rewardCoins = 110, modeKey = "brutal" } }
	local coins, finished = 0, 0
	luau.load(handlerSource, {
		environment = {
			RemoteRegistry = { GetFunction = function() return remote end },
			timedMatchByPlayer = matches,
			TimedRewards = TimedRewards,
			DataService = {
				getCoins = function() return coins end,
				addCoins = function(_, amount) coins += amount end,
				recordTimedModeScore = function(_, count) assert(count == 2) end,
			},
			applyRankedCoinReward = function(_, amount) return amount end,
			addRankProgress = function() end,
			GameService = { EndSession = function() finished += 1 end },
		},
	})()
	local result = remote.OnServerInvoke({ UserId = 1 }, true, 99999)
	assert(result.success and result.reward == 26 and result.solvedCount == 2)
	assert(coins == 26 and finished == 1)
	local replay = remote.OnServerInvoke({ UserId = 1 }, true, 99999)
	assert(not replay.success and replay.reward == 0 and coins == 26 and finished == 1)
end)

test("special hint saved before a crash remains available on rejoin", function()
	local store, data, buyer = setup()
	local info = { PurchaseId = "special", ProductId = config.HintProducts.pvpRowHint.id }
	local reward = PurchaseRewards.Resolve(config, info.ProductId)
	assert(data.processPurchase(buyer, info, reward))
	data.releasePlayerData(buyer)
	local nextServer, nextPlayer = dataService(store), player()
	assert(nextServer.loadPlayerData(nextPlayer))
	local saved, first = nextServer.processPurchase(nextPlayer, info, reward)
	assert(saved and not first and nextServer.getHints(nextPlayer) == 1)
end)

test("changed server and client entrypoints compile", function()
	for _, path in ipairs({
		"src/server/ServerMain.server.luau",
		"src/server/services/DataService.luau",
		"src/client/ClientMain.local.luau",
		"src/client/gameplay/ModeFlows.luau",
	}) do
		assert(luau.compile(fs.readFile(path)))
	end
end)

print(string.format("%d tests passed", passed))
