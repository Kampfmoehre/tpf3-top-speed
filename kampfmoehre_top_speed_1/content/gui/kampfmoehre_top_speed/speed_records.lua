-- Top Speed Reached: the per-vehicle record of the sampler, as a pure step so
-- it can be tested outside the game.
--
-- A record is { speed = m/s (session maximum), line = line of that maximum,
-- key = consist fingerprint (model ids), sections = { [stopIndex] = m/s },
-- sectionsLine = line the sections belong to }.
--
-- Replacing a vehicle keeps the entity but swaps the consist, so a changed
-- fingerprint means the maximum belongs to a different vehicle. 0.5.1 only
-- compared the fingerprint while the vehicle moved; a replaced vehicle stands
-- at the terminal first and kept showing the old maximum until it rolled.
local M = {}

-- rec: current record or nil; speedMps: current speed (>= 0); key: consist
-- fingerprint ("" = unknown, e.g. the component read failed); line: current line.
-- Returns the record to keep (nil = none) and whether the old one was dropped.
function M.update(rec, speedMps, key, line)
	local reset = false
	if rec ~= nil and key ~= "" then
		if rec.key == "" then
			rec.key = key -- created while the consist could not be read
		elseif rec.key ~= key then
			rec, reset = nil, true
		end
	end
	if speedMps > 0 then
		if rec == nil then
			rec = { speed = speedMps, line = line, key = key, sections = {}, sectionsLine = line }
		elseif speedMps > rec.speed then
			rec.speed, rec.line = speedMps, line
		end
		if rec.sectionsLine ~= line then
			rec.sections, rec.sectionsLine = {}, line
		end
	end
	return rec, reset
end

return M
