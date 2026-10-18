local ssu = require "::/gui/main/stylesheetutil.lua"

-- Per-section table in the expandable part of the Top Speed card
-- (top_speed.script.lua SectionsTable): speed bars like the game's worker
-- list, green when reached, the vehicle's current section framed.
function data()
	local result = {}
	local a = ssu.makeAdder(result)

	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data

	a("R::KampfmoehreTopSpeedSections TextView", {
		padding = { 1, 6, 1, 6 },
	})
	a("R::KampfmoehreTopSpeedSections ProgressBar!kampfmoehre-ts-bar", {
		gravity = { -1, 0.5 },
		backgroundColor1 = colorDefault.BaseVeryLight,
		color = colorDefault.AccentLight,
		margin = { 2, 4, 2, 4 },
		minSize = { 90, -1 },
	})
	a("!font-small R::KampfmoehreTopSpeedSections ProgressBar!kampfmoehre-ts-bar", { size = { -1, 20 } })
	a("!font-medium R::KampfmoehreTopSpeedSections ProgressBar!kampfmoehre-ts-bar", { size = { -1, 24 } })
	a("!font-large R::KampfmoehreTopSpeedSections ProgressBar!kampfmoehre-ts-bar", { size = { -1, 28 } })
	a("R::KampfmoehreTopSpeedSections ProgressBar!kampfmoehre-ts-ok", {
		color = colorDefault.Ok,
	})
	-- below 50 % of min(consist, track): yellow bar
	a("R::KampfmoehreTopSpeedSections ProgressBar!kampfmoehre-ts-slow", {
		color = colorDefault.Warning,
	})
	-- the track limit holds the consist back (an upgrade would help)
	-- (also used by the collapsed row, hence not scoped to the table)
	a("TextView!kampfmoehre-ts-limit", {
		color = colorDefault.AccentLight,
	})
	-- current section: a band over the whole row; cells fill their column
	-- (a table Row draws neither border nor background)
	a("R::KampfmoehreTopSpeedSections Component!kampfmoehre-ts-barcell", {
		gravity = { -1, -1 },
	})
	a("R::KampfmoehreTopSpeedSections TextView!kampfmoehre-ts-current", {
		gravity = { -1, -1 },
		backgroundColor = colorDefault.BaseLightMedium,
	})
	a("R::KampfmoehreTopSpeedSections Component!kampfmoehre-ts-current", {
		backgroundColor = colorDefault.BaseLightMedium,
	})

	return result
end
