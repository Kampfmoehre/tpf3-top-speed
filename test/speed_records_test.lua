-- run: luajit test/speed_records_test.lua  (from the repo root)
package.path = "kampfmoehre_top_speed_1/content/gui/kampfmoehre_top_speed/?.lua;" .. package.path
local M = require "speed_records"

local failures = 0
local function check(name, cond, detail)
	if cond then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. (detail and (": " .. detail) or ""))
	end
end

-- update(rec, speedMps, consistKey, line) -> rec or nil, reset

-- a vehicle that has not moved yet gets no record
local rec, reset = M.update(nil, 0, "a", 1)
check("standing, no record: nothing", rec == nil and reset == false)

-- first movement creates the record with its consist key
rec, reset = M.update(nil, 10, "a", 1)
check("first sample creates record", rec and rec.speed == 10 and rec.key == "a" and rec.line == 1 and reset == false)
check("record has empty sections for its line", type(rec.sections) == "table" and next(rec.sections) == nil and rec.sectionsLine == 1)

-- higher speed raises the maximum, lower keeps it
local same = rec
rec, reset = M.update(rec, 12, "a", 1)
check("higher speed raises max", rec == same and rec.speed == 12)
rec, reset = M.update(rec, 5, "a", 1)
check("lower speed keeps max", rec == same and rec.speed == 12)

-- the bug of 0.5.1: a replaced vehicle stands at the terminal first (speed 0),
-- the record must go at once, not only when it moves again
rec, reset = M.update(same, 0, "b", 1)
check("replaced while standing: record dropped", rec == nil and reset == true)

-- replaced while moving: new record of the new consist
rec, reset = M.update(same, 3, "b", 1)
check("replaced while moving: fresh record", rec ~= same and rec.speed == 3 and rec.key == "b" and reset == true)

-- a failed component read gives an empty key; that is unknown, not a change
rec, reset = M.update(same, 0, "", 1)
check("unknown key: no reset", rec == same and reset == false)
rec, reset = M.update(same, 20, "", 1)
check("unknown key while moving: still the same record", rec == same and rec.speed == 20)

-- a record created without a key adopts the first known key instead of resetting
local blind = M.update(nil, 4, "", 1)
rec, reset = M.update(blind, 0, "c", 1)
check("blind record adopts the first key", rec == blind and rec.key == "c" and reset == false)

-- a vehicle moved to another line keeps its max but starts the sections over
same.sections[1] = 9
rec, reset = M.update(same, 1, "a", 2)
check("new line: sections reset, max kept", rec == same and next(rec.sections) == nil and rec.sectionsLine == 2 and rec.speed == 20 and rec.line == 1)

-- the line of the maximum follows the speed
rec, reset = M.update(same, 30, "a", 2)
check("new max on the new line: line follows", rec.line == 2)

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("all ok")
