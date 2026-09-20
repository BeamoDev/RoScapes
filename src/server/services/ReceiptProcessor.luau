local ReceiptProcessor = {}
ReceiptProcessor.__index = ReceiptProcessor

function ReceiptProcessor.new(options)
	return setmetatable({ options = options, busy = {} }, ReceiptProcessor)
end

function ReceiptProcessor:Process(info)
	local purchaseId = tostring(info.PurchaseId or "")
	if purchaseId == "" or self.busy[purchaseId] then
		return false
	end
	local player = self.options.findPlayer(info.PlayerId)
	local reward = self.options.resolveReward(info.ProductId)
	if not player or not reward then
		return false
	end
	self.busy[purchaseId] = true
	local ok, saved, newlyGranted = pcall(self.options.processPurchase, player, info, reward)
	if ok and saved and newlyGranted then
		-- UI, analytics, and transient reveals must not invalidate a durable purchase.
		local notified, reason = pcall(self.options.onGranted, player, info, reward)
		if not notified then
			warn("[ReceiptProcessor] Post-purchase feedback failed:", reason)
		end
	end
	self.busy[purchaseId] = nil
	if not ok then
		warn("[ReceiptProcessor] Purchase will be retried:", saved)
	end
	return ok and saved == true
end

return ReceiptProcessor
