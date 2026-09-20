local TimedRewards = {}

function TimedRewards.Calculate(active)
	-- Endless timed mode pays per server-confirmed puzzle. There is no client-declared win.
	local solvedCount = math.max(0, math.floor(tonumber(active.solvedCount) or 0))
	return solvedCount * 13, solvedCount
end

return TimedRewards
