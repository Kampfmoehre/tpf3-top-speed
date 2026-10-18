-- Per-section table of the line/vehicle window card (expanded part):
-- measured maximum and track limit per section of the line.
--
-- Sections are keyed like TransportVehicle.stopIndex and track_limits: the
-- 0-based index of the stop the section ends at. Row k (1-based) is stop
-- k -> k % n + 1 and has key k % n.
--
-- No game API, unit-tested with plain luajit (test/section_rows_test.lua).
local M = {}

M.MIN_GRADE = 0.005   -- climbs below this are shown as "-"
M.SLOW_FILL = 0.5     -- below this share of min(top, track): yellow bar

-- n stops, reached = { [key] = m/s }, track = { [key] = m/s }, top = consist
-- top speed (m/s or nil), fraction = share of min(top, track) that counts as
-- reached, extra = { grade = { [key] = fraction }, current = key }? ->
-- { { from, to, reached = m/s?, track = m/s?, fill = 0..1 (reached /
--     min(top, track)), grade = fraction?, current = bool,
--     ok = the consist's own top speed reached (green),
--     trackLimited = reached a track limit below the consist's top speed
--                    (an upgrade would help; not green),
--     slow = fill < SLOW_FILL (yellow) }, ... }
function M.rows(n, reached, track, top, fraction, extra)
	extra = extra or {}
	local out = {}
	for k = 1, n or 0 do
		local key = k % n
		local r, t = reached and reached[key], track and track[key]
		local g = extra.grade and extra.grade[key]
		if g ~= nil and g < M.MIN_GRADE then g = nil end
		local c = M.classify(r, t, top, fraction)
		out[k] = {
			from = k,
			to = k % n + 1,
			reached = r,
			track = t,
			ok = c.ok,
			trackLimited = c.trackLimited,
			fill = c.fill,
			slow = c.slow,
			grade = g,
			current = extra.current ~= nil and extra.current == key,
		}
	end
	return out
end

-- measured r, track limit t, consist top speed (all m/s, each may be nil) ->
-- { ok = the consist's own top speed reached (green), trackLimited = a track
--   limit below the top speed was reached (an upgrade would help, not green),
--   fill = r / min(top, t) (0..1), slow = fill < SLOW_FILL (yellow) }
function M.classify(r, t, top, fraction)
	if top ~= nil and top <= 0 then top = nil end
	local ref = top
	if t and (ref == nil or t < ref) then ref = t end
	local fill = (r ~= nil and ref ~= nil and ref > 0) and math.min(1, r / ref) or 0
	return {
		ok = (r ~= nil and top ~= nil and r >= top * fraction) or false,
		trackLimited = (r ~= nil and t ~= nil and top ~= nil and t < top * fraction and r >= t * fraction) or false,
		fill = fill,
		slow = (r ~= nil and ref ~= nil and fill < M.SLOW_FILL) or false,
	}
end

-- steepest mean uphill grade over a window of `window` metres (the whole
-- profile if shorter); profile = { step = m, h = { ... } } (track_limits).
-- nil without profile or without any climb
function M.steepestClimb(profile, window)
	if type(profile) ~= "table" or type(profile.h) ~= "table" or #profile.h < 2 or (profile.step or 0) <= 0 then return nil end
	local h, step = profile.h, profile.step
	local w = math.max(1, math.min(#h - 1, math.floor(window / step + 0.5)))
	local best = nil
	for i = 1, #h - w do
		local g = (h[i + w] - h[i]) / (w * step)
		if best == nil or g > best then best = g end
	end
	if best == nil or best <= 0 then return nil end
	return best
end

-- keep the maximum speed per section key
function M.record(sections, key, speed)
	if key == nil or type(speed) ~= "number" then return end
	if speed > (sections[key] or 0) then sections[key] = speed end
end

-- maximum per section over several vehicles' section tables (nil entries ok)
function M.merge(list)
	local out = {}
	for i = 1, #list do
		local s = list[i]
		if s then
			for key, v in pairs(s) do
				if v > (out[key] or 0) then out[key] = v end
			end
		end
	end
	return out
end

return M
