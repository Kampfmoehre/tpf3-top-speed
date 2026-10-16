-- Top Speed Reached for Transport Fever 3.
--
-- The game keeps no record of the speeds a vehicle reached, only its current
-- speed (api.engine.util.vehicle.getSpeed). This mod samples the speed of all
-- vehicles on the player's lines every SAMPLE_INTERVAL seconds while the game
-- UI is up and keeps the maximum per vehicle for the session. Two entity
-- window plugins show it: per vehicle, and per line (max over its vehicles).
--
-- Cost: one getSpeed() call per vehicle per sample; the vehicle list itself
-- is refreshed less often (LIST_INTERVAL). For ~400 vehicles that is ~200
-- calls/s, less than a single open line window spends on its emission row.
--
-- Track speed limit (param track_limit, default On): track_limits.lua reads
-- the speed limits of the sections the line's vehicles drive and the rows show
-- the highest one; "reached" then compares against min(consist, track). With
-- the param Off no path or transport-network data is read at all.
--
-- Loaded via react-plugin resources; .script.lua files export via data().

function data()
	local VERSION = "0.4.1"

	local SAMPLE_INTERVAL = 2   -- seconds between speed samples
	local LIST_INTERVAL = 10    -- seconds between refreshes of the vehicle list

	local react = ug_require "::/gui/main/react.lua"
	local builtin = ug_require "::/gui/main/builtin.lua"
	local content_card = ug_require "::/gui/main/content_card.tl"
	local lang_util = ug_require "::/scripts/lang_util.tl"
	local vehicle_store_util = ug_require "::/gui/line_vehicle_mgmt/vehicle_store_util.tl"
	local track_limits = ug_require "kampfmoehre_top_speed_1::/gui/kampfmoehre_top_speed/track_limits.lua"

	-- measured >= this share of the consist's top speed counts as "reached"
	-- (samples every SAMPLE_INTERVAL s miss short peaks, so not 100 %)
	local REACHED_FRACTION = 0.97

	-- vehicle entity -> { speed = m/s, line = entity }
	local maxSpeed = {}
	local vehicles = {}        -- current list of player vehicles (entities)
	local vehicleLine = {}     -- vehicle -> line
	local sinceList = LIST_INTERVAL
	local tracks = nil         -- shared track_limits collector, nil if the param is Off

	local function refreshVehicleList()
		local okP, player = pcall(api.engine.util.getPlayer)
		if not okP or player == nil then return end
		local okL, lines = pcall(api.engine.system.lineSystem.getLinesForPlayer, player)
		if not okL or type(lines) ~= "table" then return end
		local list, lineOf = {}, {}
		for _, line in ipairs(lines) do
			local okV, vs = pcall(api.engine.system.transportVehicleSystem.getLineVehicles, line)
			if okV and type(vs) == "table" then
				for _, v in ipairs(vs) do
					list[#list + 1] = v
					lineOf[v] = line
				end
			end
		end
		vehicles, vehicleLine = list, lineOf
		-- forget vehicles that are gone
		for v, _ in pairs(maxSpeed) do
			local ok, exists = pcall(api.engine.entityExists, v)
			if ok and not exists then maxSpeed[v] = nil end
		end
	end

	-- Fingerprint of a vehicle's consist (model ids). Replacing a vehicle keeps
	-- the entity but swaps the consist, so a changed fingerprint means the
	-- measured maximum belongs to a different vehicle and must be reset.
	local function consistKey(vehicle)
		local ids = {}
		pcall(function()
			local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
			if not tv then return end
			-- getComponent returns plain tables; ipairs_native expects a C++ vector
			-- (it calls :at) and would fail silently inside this pcall
			for _, part in ipairs(tv.transportVehicleConfig.vehicles) do
				ids[#ids + 1] = tostring(part.part.modelId)
			end
		end)
		return table.concat(ids, ",")
	end

	local topSpeedCache = {}

	local function sample()
		sinceList = sinceList + SAMPLE_INTERVAL
		if sinceList >= LIST_INTERVAL then
			sinceList = 0
			refreshVehicleList()
		end
		if tracks then tracks:step(vehicles, vehicleLine, os.time()) end
		for _, v in ipairs(vehicles) do
			local ok, speed = pcall(api.engine.util.vehicle.getSpeed, v)
			if ok and type(speed) == "number" and speed > 0 then
				local rec = maxSpeed[v]
				local key = consistKey(v)
				if rec ~= nil and rec.key ~= key then
					rec = nil -- consist was replaced/modified: start over
					topSpeedCache[v] = nil
				end
				if rec == nil then
					maxSpeed[v] = { speed = speed, line = vehicleLine[v], key = key }
				elseif speed > rec.speed then
					rec.speed = speed
					rec.line = vehicleLine[v]
				end
			end
		end
	end

	-- Top speed of a vehicle's consist incl. maintenance penalty, as the
	-- condition card shows it (vehicle_eow.script.tl VehicleInfoDetails).
	local function consistTopSpeed(vehicle)
		local cached = topSpeedCache[vehicle]
		if cached and cached.until_ > os.time() then return cached.speed end
		local speed = nil
		local ok, err = pcall(function()
			local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
			if not tv then return end
			local vehicles = vehicle_store_util.makeMultipleVehiclesFromParts({ tv.transportVehicleConfig.vehicles })
			local data = vehicle_store_util.collectVehicleData(vehicles, tv.modifiers)
			speed = data and (data.speedAdjusted or data.speed) or nil
			if speed == math.huge then speed = nil end
		end)
		if not ok then log.warning("[kampfmoehre_top_speed] top speed lookup failed: " .. tostring(err)) end
		topSpeedCache[vehicle] = { speed = speed, until_ = os.time() + 30 }
		return speed
	end

	local function formatSpeed(v)
		local ok, s = pcall(api.util.formatSpeed, v)
		return (ok and s) or string.format("%.0f km/h", v * 3.6)
	end

	local function entityName(e)
		local ok, n = pcall(api.engine.util.getEntityName, e)
		return (ok and n) or tostring(e)
	end

	-- a single compact row: icon left, text right (like the game's noise row)
	local function makeRow(label, tooltip, params, reached)
		return builtin.BoxLayout{
			meta = { class = "box-plugin-vertical-space" },
			orientation = builtin.type.Orientation.Vertical,
			children = {
				content_card.ContentCard{
					initialCalloutTextPermanent = "",
					extraChildrenPermanent = {
						builtin.Component{
							meta = { tooltip = tooltip },
							layout = builtin.BoxLayout{
								orientation = builtin.type.Orientation.Horizontal,
								children = {
									builtin.ImageView{
										path = "::/gui/line_vehicle_mgmt/icons/symbol_speed.tga",
										scaling = builtin.type.ImageViewScaling.AutoFit,
									},
									builtin.TextView{
										meta = { class = reached and "font-scale-body, success" or "font-scale-body" },
										text = "  " .. label,
									},
								},
							},
						},
					},
					gameCtx = params.gameCtx,
					showOnRightSide = params.showCalloutOnRightSide,
				},
			},
		}
	end

	local M = {}

	-- Sampler: lives in the game UI root, so it runs only while a game is loaded.
	M.EntryPlugin = react.RegisterPluginRecipe(
		{ id = "::ModEntryPointExtension" }, "KampfmoehreTopSpeedEntry",
		function()
			react.onMount(function()
				maxSpeed, vehicles, vehicleLine, sinceList = {}, {}, {}, LIST_INTERVAL
				local ok, all = pcall(api.engine.config.getModParams)
				local mine = ok and type(all) == "table" and all["kampfmoehre_top_speed_1"] or nil
				local trackEnabled = not (type(mine) == "table" and mine.track_limit == 1)
				tracks = nil
				if trackEnabled then
					local okT, shared = pcall(track_limits.getShared, builtin, track_limits.engineAdapter, "kampfmoehre_top_speed")
					if okT then
						tracks = shared
						tracks:reset()
					else
						log.warning("[kampfmoehre_top_speed] track limits unavailable: " .. tostring(shared))
					end
				end
				log.message("[kampfmoehre_top_speed] v" .. VERSION .. " sampler started (every " .. SAMPLE_INTERVAL .. " s), track limit: "
					.. tostring(tracks ~= nil) .. " (param track_limit=" .. tostring(type(mine) == "table" and mine.track_limit or mine) .. ")"
					.. (tracks and (", collector API " .. tostring(tracks.API_VERSION) .. " from " .. tostring(tracks.owner)) or ""))
			end)
			react.onStepTimer(function()
				local ok, err = pcall(sample)
				if not ok then log.warning("[kampfmoehre_top_speed] sample failed: " .. tostring(err)) end
			end, SAMPLE_INTERVAL)
			return builtin.BoxLayout{ children = {} }
		end)

	-- "131 / 140 km/h" (unit once if both strings end in the same unit)
	local function speedPair(a, b)
		local sa, sb = formatSpeed(a), formatSpeed(b)
		local num, unit = sa:match("^(.-)%s*(%a[%a/]*)$")
		if num and num ~= "" and unit and sb:sub(-#unit) == unit then return num .. " / " .. sb end
		return sa .. " / " .. sb
	end

	-- { max = m/s, known = n, total = n } of a line's track, nil if unknown or Off.
	-- Called by open windows, so their line's sections are read first.
	local function trackInfo(line)
		if not tracks or not line then return nil end
		pcall(tracks.want, tracks, line, os.time())
		local ok, max, known, total = pcall(tracks.lineTrackMax, tracks, line)
		if not ok or not max then return nil end
		return { max = max, known = known, total = total, complete = total ~= nil and known >= total }
	end

	local function sameTrack(a, b)
		if a == nil or b == nil then return a == b end
		return a.max == b.max and a.known == b.known and a.total == b.total
	end

	-- "131 / 140 km/h · track 120 km/h" plus whether the top speed counts as
	-- reached: against min(consist, track) once all sections are known
	local function speedLabel(measured, top, track)
		local label, reached
		if measured <= 0 then
			label, reached = _("top_speed_na"), false
		elseif top and top > 0 then
			local ref = top
			if track and track.complete and track.max < ref then ref = track.max end
			label, reached = speedPair(measured, top), measured >= ref * REACHED_FRACTION
		else
			label, reached = formatSpeed(measured), false
		end
		if track then
			label = label .. " · " .. lang_util.format(_(track.complete and "top_speed_track" or "top_speed_track_partial"),
				{ speed = formatSpeed(track.max) })
		end
		return label, reached
	end

	local function trackTooltip(track)
		if not track then return "" end
		return "\n" .. lang_util.format(_("top_speed_track_tooltip"), {
			speed = formatSpeed(track.max), known = track.known, total = track.total or "?" })
	end

	-- Vehicle window row
	M.VehiclePlugin = react.RegisterPluginRecipe(
		{ id = "::VehicleEowExtensionPoint" }, "KampfmoehreTopSpeedVehicle",
		function(params)
			local function current()
				local rec = maxSpeed[params.entityId]
				local line = vehicleLine[params.entityId] or (rec and rec.line)
				return { speed = rec and rec.speed or 0, track = trackInfo(line) }
			end
			local state = react.useState(current())
			react.onStepTimer(function()
				local now, old = current(), state:old()
				if now.speed ~= old.speed or not sameTrack(now.track, old.track) then state:set(now) end
			end, 1)
			local s = state:old()
			local label, reached = speedLabel(s.speed, consistTopSpeed(params.entityId), s.track)
			return makeRow(_("top_speed_reached_short") .. ": " .. label,
				_("top_speed_vehicle_tooltip") .. trackTooltip(s.track), params, reached)
		end)

	-- Line window row: max over the line's vehicles
	M.LinePlugin = react.RegisterPluginRecipe(
		{ id = "::LineEowExtensionPoint" }, "KampfmoehreTopSpeedLine",
		function(params)
			local function lineMax()
				local best, bestVehicle, top, count = 0, nil, 0, 0
				local ok, vs = pcall(api.engine.system.transportVehicleSystem.getLineVehicles, params.entityId)
				if ok and type(vs) == "table" then
					count = #vs
					for _, v in ipairs(vs) do
						local rec = maxSpeed[v]
						if rec and rec.speed > best then best, bestVehicle = rec.speed, v end
						local t = consistTopSpeed(v)
						if t and t > top then top = t end
					end
				end
				return { speed = best, vehicle = bestVehicle, top = top, count = count, track = trackInfo(params.entityId) }
			end
			local state = react.useState(lineMax())
			react.onStepTimer(function()
				local now = lineMax()
				local old = state:old()
				if now.speed ~= old.speed or now.vehicle ~= old.vehicle or now.top ~= old.top or now.count ~= old.count
					or not sameTrack(now.track, old.track) then state:set(now) end
			end, 1)
			local s = state:old()
			if s.count == 0 then
				return makeRow(_("top_speed_reached_short") .. ": " .. _("top_speed_no_vehicles"), _("top_speed_vehicle_tooltip"), params, false)
			end
			local label, reached = speedLabel(s.speed, s.top, s.track)
			local tooltip = (s.speed > 0) and lang_util.format(_("top_speed_line_tooltip"), {
				speed = formatSpeed(s.speed), vehicle = entityName(s.vehicle) }) or _("top_speed_vehicle_tooltip")
			return makeRow(_("top_speed_reached_short") .. ": " .. label, tooltip .. trackTooltip(s.track), params, reached)
		end)

	return M
end
