-- Pure reward staging; persistence must confirm the complete profile before acknowledgement.
local PurchaseRewards = {}

function PurchaseRewards.Resolve(config, productId)
	for _, product in ipairs(config.CoinProducts or {}) do
		if product.id == productId then
			return { coins = product.coins }
		end
	end
	for key, product in pairs(config.HintProducts or {}) do
		if product.id == productId then
			if key == "pvpHint" or key == "pvpRowHint" or key == "dailyHint" or key == "dailySelectionHint" then
				-- A delayed receipt still delivers a usable hint if its original board is gone.
				return { hints = 1, special = key }
			end
			return {
				hints = product.amount or product.hints or 0,
				coins = product.coins or 0,
				selectionHints = product.selectionHints or 0,
			}
		end
	end
	return nil
end

function PurchaseRewards.Stage(data, purchaseId, productId, reward)
	if data.processedReceipts[purchaseId] then
		return false
	end
	data.hints += reward.hints or 0
	data.coins += reward.coins or 0
	data.selectionHints += reward.selectionHints or 0
	data.stats.totalCoinsEarned = (data.stats.totalCoinsEarned or 0) + (reward.coins or 0)
	data.processedReceipts[purchaseId] = productId
	return true
end

return PurchaseRewards
