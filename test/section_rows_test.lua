-- run: luajit test/section_rows_test.lua  (from the repo root)
package.path = "kampfmoehre_top_speed_1/content/gui/kampfmoehre_top_speed/?.lua;" .. package.path
local M = require "section_rows"

local failures = 0
local function check(name, cond, detail)
	if cond then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. (detail and (": " .. detail) or ""))
	end
end
local kmh = 1 / 3.6

-- rows: one per section 1 -> 2, 2 -> 3, ..., n -> 1; section k ends at the stop
-- with 0-based index k % n (TransportVehicle.stopIndex, track_limits' key)
local rows = M.rows(3, { [1] = 70 * kmh, [2] = 65 * kmh, [0] = 99 * kmh }, { [1] = 100 * kmh, [0] = 100 * kmh }, 100 * kmh, 0.97)
check("one row per section", #rows == 3, tostring(#rows))
check("row 1 is 1 -> 2", rows[1].from == 1 and rows[1].to == 2)
check("row 3 is 3 -> 1", rows[3].from == 3 and rows[3].to == 1)
check("row 1 reached", math.abs(rows[1].reached - 70 * kmh) < 1e-9)
check("row 1 track", math.abs(rows[1].track - 100 * kmh) < 1e-9)
check("row 1 not green (70 of 100)", not rows[1].ok)
check("row 2 has no track", rows[2].track == nil)
check("row 2 not green without a known limit", not rows[2].ok)
check("row 3 green (99 of 100, track 100 = top)", rows[3].ok)
-- green only when the consist's own top speed is reached; at a lower track
-- limit the section is "track limited" (an upgrade would help), not green
rows = M.rows(2, { [1] = 59 * kmh, [0] = 59 * kmh }, { [1] = 60 * kmh, [0] = 160 * kmh }, 100 * kmh, 0.97)
check("at a lower track limit: not green", not rows[1].ok)
check("at a lower track limit: track limited", rows[1].trackLimited)
check("below the consist top on a fast track: neither", not rows[2].ok and not rows[2].trackLimited)
rows = M.rows(1, { [0] = 100 * kmh }, { [0] = 100 * kmh }, 115 * kmh, 0.97)
check("100 of 115 on a 100 track: track limited", rows[1].trackLimited and not rows[1].ok)
rows = M.rows(1, { [0] = 69 * kmh }, { [0] = 100 * kmh }, 70 * kmh, 0.97)
check("69 of 70 on a 100 track: green", rows[1].ok and not rows[1].trackLimited)
-- unmeasured section
rows = M.rows(2, {}, { [1] = 60 * kmh }, 100 * kmh, 0.97)
check("unmeasured row", rows[1].reached == nil and not rows[1].ok)
check("no stops -> no rows", #M.rows(0, {}, {}, 1, 0.97) == 0)

-- per-section maximum per vehicle
local rec = {}
M.record(rec, 1, 10)
M.record(rec, 1, 8)
M.record(rec, 0, 12)
check("record keeps the max", rec[1] == 10 and rec[0] == 12)
-- line: max over vehicles
local merged = M.merge({ { [1] = 10, [2] = 5 }, { [1] = 12 }, nil })
check("merge max per section", merged[1] == 12 and merged[2] == 5)

-- extra: grade per section, current section, bar fill
rows = M.rows(3, { [1] = 50 * kmh, [0] = 99 * kmh }, { [1] = 100 * kmh }, 70 * kmh, 0.97,
	{ grade = { [1] = 0.12, [2] = 0.002 }, current = 2 })
check("grade carried", rows[1].grade == 0.12)
check("tiny grade dropped", rows[2].grade == nil)
check("current section marked", rows[2].current and not rows[1].current and not rows[3].current)
check("fill = reached / min(top, track)", math.abs(rows[1].fill - 50 / 70) < 1e-9)
check("fill without track uses top", math.abs(rows[3].fill - 1) < 1e-9)
check("fill unmeasured = 0", rows[2].fill == 0)

-- classify: shared by the table and the collapsed row
local c = M.classify(100 * kmh, 100 * kmh, 115 * kmh, 0.97)
check("classify: track limited", c.trackLimited and not c.ok)
c = M.classify(69 * kmh, 100 * kmh, 70 * kmh, 0.97)
check("classify: green", c.ok and not c.trackLimited)
c = M.classify(69 * kmh, nil, 70 * kmh, 0.97)
check("classify: green without a known track", c.ok)
c = M.classify(nil, 100 * kmh, 70 * kmh, 0.97)
check("classify: unmeasured", not c.ok and not c.trackLimited and not c.slow and c.fill == 0)

-- slow (< 50 % of min(top, track)) -> yellow bar
rows = M.rows(3, { [1] = 34 * kmh, [2] = 30 * kmh, [0] = 60 * kmh }, { [1] = 100 * kmh, [2] = 100 * kmh, [0] = 100 * kmh },
	70 * kmh, 0.97, { grade = { [1] = 0.12, [2] = 0.01, [0] = 0.12 } })
check("34 of 70 (49 %) is slow", rows[1].slow)
check("30 of 70 is slow", rows[2].slow)
check("60 of 70 is not slow", not rows[3].slow)
rows = M.rows(2, {}, { [1] = 100 * kmh }, 70 * kmh, 0.97, { grade = { [1] = 0.12 } })
check("unmeasured is not slow", not rows[1].slow)
rows = M.rows(1, { [0] = 36 * kmh }, { [0] = 100 * kmh }, 70 * kmh, 0.97, {})
check("36 of 70 (51 %) is not slow", not rows[1].slow)

-- steepest climb: mean grade over the steepest 200 m window, uphill only
local function profile(step, segments)
	local h = { 0 }
	for __, seg in ipairs(segments) do
		for _ = 1, math.floor(seg[1] / step + 0.5) do h[#h + 1] = h[#h] + seg[2] * step end
	end
	return { step = step, h = h }
end
local g = M.steepestClimb(profile(10, { { 500, 0 }, { 300, 0.12 }, { 500, -0.05 } }), 200)
check("steepest climb 12 %", g and math.abs(g - 0.12) < 1e-9, tostring(g))
check("downhill only -> nil", M.steepestClimb(profile(10, { { 1000, -0.05 } }), 200) == nil)
check("short section uses its length", math.abs(M.steepestClimb(profile(10, { { 100, 0.04 } }), 200) - 0.04) < 1e-9)
check("no profile -> nil", M.steepestClimb(nil, 200) == nil)

print(failures == 0 and "all tests passed" or (failures .. " test(s) failed"))
os.exit(failures == 0 and 0 or 1)
