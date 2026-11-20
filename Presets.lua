local _, ns = ...
local L = ns.L

-- Presets. All of them aim to keep graphics as high as possible; none states a frame
-- rate it hasn't measured on this Mac:
--   (There is no everything-at-maximum preset: the game's own quality slider at 10 already
--     maxes everything, so Ultra Uncapped was removed - Josh, 2026-10-18.)
--   * goal presets: a frame-rate cap, with graphics kept as high as possible and only
--     lowered if the System Check measured the frame rate falling more than the chosen
--     tolerance below the cap; they need a System Check first
-- Every goal preset also brings the fixed values (Solver.FixedChanges, Josh 2026-10-19),
-- Mac-ever's Standard picture look among them.
local Presets = {}
ns.Presets = Presets

-- summary: the one line on the card. description: the full story, in the card's tooltip;
-- text, or a function returning it.
Presets.list = {}

-- One goal preset per frame rate (Josh, 2026-10-18: "remove the titles 'battery saver',
-- 'quiet and cool', 'smooth' etc., just make it purely FPS driven ... always looking to
-- maximise graphics quality at chosen fps level"). Each solves for its own goal.
local function LocalizeGoal(preset)
	local goal = preset.goal
	preset.summary = (L("Aims for %d fps, capped there, with graphics as high as that allows.")):format(goal)
	preset.description = (L("Aims for %d fps, capped there. Graphics stay as high as possible: settings are only lowered if your Mac would fall too far below %d.")):format(goal, goal)
end

for _, goal in ipairs(ns.GOALS) do
	local preset = { id = "fps" .. goal, kind = "goal", goal = goal, name = goal .. " fps" }
	LocalizeGoal(preset)
	Presets.list[#Presets.list + 1] = preset
end

-- The language is only known once the saved data has loaded.
ns.Locale.OnReady(function()
	for _, preset in ipairs(Presets.list) do
		if preset.kind == "goal" then
			LocalizeGoal(preset)
		end
	end
end)

-- The ids the goal presets had before they were named by frame rate, for saved data.
Presets.LEGACY_IDS = { battery = "fps30", cool = "fps45", smooth = "fps60", promotion = "fps120" }

local byId = {}
for _, preset in ipairs(Presets.list) do
	byId[preset.id] = preset
end

function Presets.Describe(preset)
	return type(preset.description) == "function" and preset.description() or preset.description
end

function Presets.Get(id)
	return byId[id]
end

-- What a preset would change. Returns the change list, or nil and "needs-check" when a
-- goal preset has no System Check to work from.
-- For goal presets, also returns the System Check solution (predictedFps, reachable, ...).
function Presets.Changes(preset)
	local solution = ns.Solver.Solve(ns.db.lastCheck, preset.goal, ns.db.ui.tolerance or ns.Solver.DEFAULT_TOLERANCE)
	if not solution then
		-- Fork: the 60 fps preset starts from a profile for this Mac's class until a System Check has run.
		local start = preset.goal == 60 and ns.Devices.StartChanges()
		if start then
			return ns.Solver.ForApply(start.changes), { start = true, notes = start.notes }
		end
		return nil, "needs-check"
	end
	for _, change in ipairs(solution.changes) do
		if change.name == "maxFPS" then
			change.value = preset.goal
		end
	end
	solution.predictedFps = math.min(preset.goal, solution.uncappedFps)
	return ns.Solver.ForApply(solution.changes), solution
end

-- Which preset is applied (Josh, 2026-10-16: its card shows a green Applied button until
-- the player changes something, then Apply comes back). Applying records what the game
-- settled on for each setting the preset set, read back once it's kept: the game adjusts
-- some values and the resolution lock skips others, so the preset's own targets can't be
-- compared. It stays applied while every recorded setting still reads the same, whether
-- changed here, in the game's menu or by another addon. id is a preset's id or "check"
-- (the System Check recommendation).
-- checkTime: the System Check result it came from (its time), when Apply Recommended
-- applied it, so that button can show it's applied too.
-- The picture (Brightness, Contrast, Gamma, Bloom Intensity) isn't recorded (Josh,
-- 2026-10-19): every result brings the Standard picture and invites the player to adjust
-- it, which shouldn't turn the preset back to Apply. Nor are the Hidden settings Keep my
-- Hidden Settings writes back (change.kept, 2026-10-19): they're the player's to tweak.
function Presets.IsPicture(name)
	local key = name:lower()
	if key == "bloomusermult" then
		return true
	end
	for _, picture in ipairs(Presets.PICTURE_SETTINGS) do
		if picture:lower() == key then
			return true
		end
	end
	return false
end

function Presets.MarkApplied(id, changes, checkTime)
	local values = {}
	for _, change in ipairs(changes) do
		if not Presets.IsPicture(change.name) and not change.kept then
			values[change.name] = ns.CVars.Read(change.name)
		end
	end
	ns.db.ui.lastPreset = id
	ns.db.ui.appliedValues = values
	ns.db.ui.appliedCheck = checkTime
end

-- The applied preset's id (or "check"), or nil once any of its settings has changed.
function Presets.Applied()
	local id, values = ns.db.ui.lastPreset, ns.db.ui.appliedValues
	if not id or type(values) ~= "table" then
		return nil
	end
	for name, value in pairs(values) do
		if not ns.CVars.SameValue(ns.CVars.Read(name), value) then
			return nil
		end
	end
	return id
end

-- A new System Check result tailors the presets afresh, so none is applied as it now is.
function Presets.ClearApplied()
	ns.db.ui.lastPreset = nil
	ns.db.ui.appliedValues = nil
	ns.db.ui.appliedCheck = nil
end

-- True while this System Check result's recommendation is what Apply Recommended applied
-- and none of its settings has changed since.
function Presets.CheckApplied(report)
	return report ~= nil and report.time ~= nil and ns.db.ui.appliedCheck == report.time
		and Presets.Applied() ~= nil
end

-- Picture looks: named combinations of the game's Brightness, Contrast and Gamma (the
-- last three sliders on its Graphics page). Screens, rooms and eyes differ far more than
-- graphics settings do, so these are separate from the presets above and never change
-- graphics settings. The other way round, Standard is Mac-ever's own picture and comes
-- with every System Check result and goal preset (Josh, 2026-10-19: Contrast 65,
-- Brightness 50, Gamma 0.9 and Bloom 0.4 "should be the 'standard' settings for the
-- picture presets, and this should apply on every system check"; Gamma raised to 1.0 on
-- 2026-11-05, Josh: 0.9 made night scenes too dark on an HDR screen); the check itself
-- measures with the player's picture. Only Standard sets Bloom Intensity (bloom): the
-- other looks leave it as it is, and a look is recognised by the three sliders alone.
-- Brightness and Contrast run 0-100 (default 50), Gamma 0.3-2.8 in steps of 0.1
-- (default 1.0; higher lifts the mid-tones and dark areas). Values are deliberately
-- moderate starting points, not measured: every look stays well inside the ranges.
Presets.PICTURE_SETTINGS = { "Brightness", "Contrast", "Gamma" }

Presets.pictureLooks = {
	{
		id = "standard",
		name = "Standard",
		brightness = 50, contrast = 65, gamma = 1.0, bloom = 0.4,
		description = L("Mac-ever's own picture: more contrast than the game's, with gentle bloom. System Check results and goal presets use it too."),
	},
	{
		id = "cinematic",
		name = "Cinematic",
		brightness = 48, contrast = 58, gamma = 0.85,
		description = L("Deep blacks and strong contrast for a moody, film-like look. Dark areas get harder to see."),
	},
	{
		id = "vivid",
		name = "Vivid",
		brightness = 50, contrast = 60, gamma = 0.9,
		description = L("Stronger contrast and richer mid-tones for a punchier picture."),
	},
	{
		id = "daylight",
		name = "Daylight",
		brightness = 55, contrast = 55, gamma = 1.2,
		description = L("Brighter, with a little extra contrast, to cut through glare in a bright room or outdoors."),
	},
	{
		id = "evening",
		name = "Evening",
		brightness = 45, contrast = 45, gamma = 0.9,
		description = L("Dimmer and softer, so it's easier on the eyes in a dark room."),
	},
	{
		id = "shadowdetail",
		name = L("Shadow Detail"),
		brightness = 50, contrast = 50, gamma = 1.4,
		description = L("Lifts the darkest areas so caves, dungeons and night-time zones are easier to see. Blacks look a little greyer."),
	},
}

local lookById = {}
for _, look in ipairs(Presets.pictureLooks) do
	lookById[look.id] = look
end

function Presets.GetLook(id)
	return lookById[id]
end

function Presets.LookChanges(look)
	local changes = {
		{ name = "Brightness", value = look.brightness },
		{ name = "Contrast", value = look.contrast },
		{ name = "Gamma", value = look.gamma },
	}
	if look.bloom then
		changes[#changes + 1] = { name = "bloomUserMult", value = look.bloom }
	end
	return changes
end

-- The look the current settings match, or nil for a custom picture.
-- readFn(name) returns a setting's current value.
function Presets.CurrentLook(readFn)
	local current = {}
	for _, name in ipairs(Presets.PICTURE_SETTINGS) do
		current[name] = tonumber(readFn(name))
		if not current[name] then
			return nil
		end
	end
	for _, look in ipairs(Presets.pictureLooks) do
		if math.abs(current.Brightness - look.brightness) < 0.5 and math.abs(current.Contrast - look.contrast) < 0.5
			and math.abs(current.Gamma - look.gamma) < 0.05 then
			return look
		end
	end
	return nil
end
