-- Owns one writable session per profile. Receipts and rewards share the same write.
local ProfilePersistence = {}
ProfilePersistence.__index = ProfilePersistence

function ProfilePersistence.new(store, encode, decode, defaults, now, newId)
	return setmetatable({
		store = store,
		encode = encode,
		decode = decode,
		defaults = defaults,
		now = now,
		newId = newId,
		sessions = {},
		leaseSeconds = 600,
	}, ProfilePersistence)
end

function ProfilePersistence:Load(userId)
	local session = self.sessions[userId]
	if not session then
		session = { id = self.newId(), busy = false }
		self.sessions[userId] = session
	end
	local reason = "profile is active in another server"
	local ok, result = pcall(function()
		return self.store:UpdateAsync(tostring(userId), function(saved)
			local data = saved ~= nil and self.decode(saved, userId) or nil
			if saved ~= nil and data == nil then
				reason = "stored profile could not be decoded"
				return nil
			end
			data = data or self.defaults()
			local owner = data._session
			if owner and owner.id ~= session.id and (tonumber(owner.expiresAt) or 0) > self.now() then
				return nil
			end
			data._session = { id = session.id, expiresAt = self.now() + self.leaseSeconds }
			return self.encode(data)
		end)
	end)
	if not ok then
		return nil, tostring(result)
	end
	if result == nil then
		return nil, reason
	end
	local data = self.decode(result, userId)
	if not data or not data._session or data._session.id ~= session.id then
		return nil, "profile ownership was not confirmed"
	end
	session.loaded = true
	return data
end

function ProfilePersistence:Save(userId, snapshot, release)
	local session = self.sessions[userId]
	if not session or not session.loaded or session.released then
		return false, "no writable session"
	end
	if session.busy then
		return false, "save in progress"
	end
	session.busy = true
	local reason = "profile ownership lost"
	local ok, result = pcall(function()
		return self.store:UpdateAsync(tostring(userId), function(saved)
			local current = self.decode(saved, userId)
			local owner = current and current._session
			if not owner or owner.id ~= session.id then
				return nil
			end
			-- Snapshot is detached from live data: UpdateAsync can retry this callback.
			snapshot._session = nil
			if not release then
				snapshot._session = { id = session.id, expiresAt = self.now() + self.leaseSeconds }
			end
			return self.encode(snapshot)
		end)
	end)
	session.busy = false
	if not ok then
		return false, tostring(result)
	end
	if result == nil then
		session.released = true
		return false, reason
	end
	if release then
		session.released = true
	end
	return true
end

function ProfilePersistence:Forget(userId)
	self.sessions[userId] = nil
end

return ProfilePersistence
