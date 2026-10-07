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
-- Loaded via react-plugin resources; .script.lua files export via data().

function data()
	local VERSION = "0.3.2"

	local SAMPLE_INTERVAL = 2   -- seconds between speed samples
	local LIST_INTERVAL = 10    -- seconds between refreshes of the vehicle list

	local react = ug_require "::/gui/main/react.lua"
	local builtin = ug_require "::/gui/main/builtin.lua"
	local content_card = ug_require "::/gui/main/content_card.tl"
	local lang_util = ug_require "::/scripts/lang_util.tl"
	local vehicle_store_util = ug_require "::/gui/line_vehicle_mgmt/vehicle_store_util.tl"

	-- measured >= this share of the consist's top speed counts as "reached"
	-- (samples every SAMPLE_INTERVAL s miss short peaks, so not 100 %)
	local REACHED_FRACTION = 0.97

	-- vehicle entity -> { speed = m/s, line = entity }
	local maxSpeed = {}
	local vehicles = {}        -- current list of player vehicles (entities)
	local vehicleLine = {}     -- vehicle -> line
	local sinceList = LIST_INTERVAL

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
			for _, part in ipairs_native(tv.transportVehicleConfig.vehicles) do
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
		if not ok then log.warning("[top_speed] top speed lookup failed: " .. tostring(err)) end
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
				log.message("[top_speed] v" .. VERSION .. " sampler started (every " .. SAMPLE_INTERVAL .. " s)")
			end)
			react.onStepTimer(function()
				local ok, err = pcall(sample)
				if not ok then log.warning("[top_speed] sample failed: " .. tostring(err)) end
			end, SAMPLE_INTERVAL)
			return builtin.BoxLayout{ children = {} }
		end)

	-- "131 km/h / 140 km/h" plus whether the top speed counts as reached
	local function speedLabel(measured, top)
		if measured <= 0 then return _("top_speed_na"), false end
		if top and top > 0 then
			return formatSpeed(measured) .. " / " .. formatSpeed(top), measured >= top * REACHED_FRACTION
		end
		return formatSpeed(measured), false
	end

	-- Vehicle window row
	M.VehiclePlugin = react.RegisterPluginRecipe(
		{ id = "::VehicleEowExtensionPoint" }, "KampfmoehreTopSpeedVehicle",
		function(params)
			local state = react.useState(0)
			react.onStepTimer(function()
				local rec = maxSpeed[params.entityId]
				local v = rec and rec.speed or 0
				if v ~= state:old() then state:set(v) end
			end, 1)
			local label, reached = speedLabel(state:old(), consistTopSpeed(params.entityId))
			return makeRow(_("Top speed reached") .. ": " .. label, _("top_speed_vehicle_tooltip"), params, reached)
		end)

	-- Line window row: max over the line's vehicles
	M.LinePlugin = react.RegisterPluginRecipe(
		{ id = "::LineEowExtensionPoint" }, "KampfmoehreTopSpeedLine",
		function(params)
			local function lineMax()
				local best, bestVehicle, top = 0, nil, 0
				local ok, vs = pcall(api.engine.system.transportVehicleSystem.getLineVehicles, params.entityId)
				if ok and type(vs) == "table" then
					for _, v in ipairs(vs) do
						local rec = maxSpeed[v]
						if rec and rec.speed > best then best, bestVehicle = rec.speed, v end
						local t = consistTopSpeed(v)
						if t and t > top then top = t end
					end
				end
				return { speed = best, vehicle = bestVehicle, top = top }
			end
			local state = react.useState(lineMax())
			react.onStepTimer(function()
				local now = lineMax()
				local old = state:old()
				if now.speed ~= old.speed or now.vehicle ~= old.vehicle or now.top ~= old.top then state:set(now) end
			end, 1)
			local s = state:old()
			local label, reached = speedLabel(s.speed, s.top)
			local tooltip = (s.speed > 0) and lang_util.format(_("top_speed_line_tooltip"), {
				speed = formatSpeed(s.speed), vehicle = entityName(s.vehicle) }) or _("top_speed_vehicle_tooltip")
			return makeRow(_("Top speed reached") .. ": " .. label, tooltip, params, reached)
		end)

	return M
end
