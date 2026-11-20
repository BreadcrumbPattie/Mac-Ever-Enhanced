local _, ns = ...
local L = ns.L

local CVars = ns.CVars
local Registry = ns.Registry

-- Settings by location, shown as Instance Settings (Josh, 2026-10-10, a tester asked for
-- it; renamed 2026-10-16): open world, dungeons, raids and battlegrounds want different
-- things, so each can use a preset or the System Check result. Off by default. The switch
-- happens when a loading screen ends (or once combat ends), and each location's changes
-- sit on top of the player's own settings: leaving puts back what the switch changed,
-- unless the player has changed it since. Settings that restart the renderer, the window
-- or the game are left out, so arriving never blacks out the screen, and so is the picture.

local Places = {}
ns.Places = Places

Places.list = {
	{ id = "world", label = L("Open world") },
	{ id = "dungeon", label = "Dungeons" },
	{ id = "raid", label = "Raids" },
	{ id = "pvp", label = L("Battlegrounds & arenas") },
}

-- What a location can use: its own settings, the System Check result, or a preset.
Places.CHOICES = { "none", "check" }
for _, goal in ipairs(ns.GOALS) do
	Places.CHOICES[#Places.CHOICES + 1] = "fps" .. goal
end

local INSTANCE_PLACES = {
	none = "world", party = "dungeon", scenario = "dungeon", raid = "raid", pvp = "pvp", arena = "pvp",
}

local function State()
	ns.db.places = ns.db.places or {}
	if type(ns.db.places.choices) ~= "table" then
		ns.db.places.choices = {}
	end
	return ns.db.places
end

local VALID = {}
for _, choice in ipairs(Places.CHOICES) do
	VALID[choice] = true
end

function Places.IsOn()
	return State().on == true
end

function Places.Get(id)
	for _, place in ipairs(Places.list) do
		if place.id == id then
			return place
		end
	end
end

-- Where the player is now.
function Places.Current()
	local _, instanceType = GetInstanceInfo()
	return Places.Get(INSTANCE_PLACES[instanceType or "none"] or "world")
end

-- A saved choice that's no longer offered (an old preset) counts as "none", so it can't
-- break every loading screen.
function Places.Choice(placeId)
	local choice = State().choices[placeId]
	if not VALID[choice] then
		return "none"
	end
	return choice
end

function Places.SetChoice(placeId, choice)
	State().choices[placeId] = choice ~= "none" and choice or nil
end

function Places.ChoiceLabel(choice)
	if choice == "none" then
		return L("Your own settings")
	elseif choice == "check" then
		return L("System Check result")
	end
	return ns.Presets.Get(choice).name
end

-- The game's "Raid & Battleground Settings": when on, the game draws raids and
-- battlegrounds with its RAID copies, so those are what a switch there must change.
local function UsesRaidCopies(place)
	return (place.id == "raid" or place.id == "pvp") and tonumber(C_CVar.GetCVar("RAIDsettingsEnabled")) == 1
end

-- The changes a choice makes at a place, or nil and "needs-check".
function Places.Changes(choice, place)
	local changes
	if choice == "none" then
		return {}
	elseif choice == "check" then
		local report = ns.db.lastCheck
		-- A check from before the current version may carry Hidden values the check no
		-- longer tunes (Standard-only, Josh 2026-10-18): never applied.
		if not report or not report.changes or report.version ~= ns.Solver.REPORT_VERSION then
			return nil, "needs-check"
		end
		changes = ns.Solver.ForApply(report.changes)
	else
		local reason
		changes, reason = ns.Presets.Changes(ns.Presets.Get(choice))
		if not changes then
			return nil, reason
		end
	end
	local raid = UsesRaidCopies(place)
	local kept, seen = {}, {}
	for _, change in ipairs(changes) do
		local name = change.name
		local entry = Registry.Get(name)
		if raid and entry and entry.raidName then
			name = entry.raidName
		end
		local key = Registry.Key(name)
		local value = change.value
		if (change.rederive or change.kept) and name ~= change.name then
			-- A slider written only to re-derive keeps the raid copy's own value, and so does
			-- a Hidden setting Keep my Hidden Settings keeps (Josh, 2026-10-19).
			value = C_CVar.GetCVar(name)
		end
		-- The picture comes with applying a result or preset, not with every place switch
		-- (Josh, 2026-10-19).
		if value ~= nil and not Registry.RestartKind(name) and not Registry.IsResolution(name)
			and not ns.Presets.IsPicture(name) and not seen[key] then
			-- The change flags keep the write order: Hidden reset, sliders, then the rest.
			kept[#kept + 1] = { name = name, value = value, first = change.first, force = change.force, kept = change.kept }
			seen[key] = true
		end
	end
	return kept
end

-- Puts back what the last switch changed, where the player hasn't changed it since.
local function Revert(state)
	local undo = {}
	for _, item in ipairs(state.undo or {}) do
		local current = C_CVar.GetCVar(item.name)
		if current ~= nil and CVars.SameValue(current, item.set) then
			undo[#undo + 1] = { name = item.name, value = item.value }
		end
	end
	state.undo = nil
	if #undo == 0 then
		return 0
	end
	local results = CVars.Apply(undo)
	local reverted = 0
	for _, result in ipairs(results or {}) do
		if ns.CVars.DidChange(result) then
			reverted = reverted + 1
		end
	end
	return reverted
end

local pending = false

-- Switches to the settings for a place (the current one by default). Returns what
-- happened: "switched", "same", "off", "combat", "busy" or "needs-check".
function Places.Switch(place)
	place = place or Places.Current()
	local state = State()
	if InCombatLockdown() then
		pending = true
		return "combat"
	end
	pending = false
	if ns.Benchmark.IsRunning() then
		return "busy"
	end
	local choice = Places.IsOn() and Places.Choice(place.id) or "none"
	if state.place == place.id and state.choice == choice then
		return "same"
	end

	-- Put back the last switch first: the changes are read from the settings as they are
	-- (a slider written only to re-derive keeps its current value), which must be the
	-- player's own, not the last place's.
	local reverted = Revert(state)
	local changes, reason = Places.Changes(choice, place)
	if not changes then
		ns.Print(("%s are set to use %s, but that needs a System Check first. Open /macever and run one."):format(
			place.label, Places.ChoiceLabel(choice)))
		changes = {}
	end

	local changed = 0
	if #changes > 0 then
		local results = CVars.Apply(changes)
		state.undo = {}
		for _, result in ipairs(results or {}) do
			if ns.CVars.DidChange(result) and result.previous ~= nil then
				changed = changed + 1
				state.undo[#state.undo + 1] = { name = result.name, value = result.previous, set = C_CVar.GetCVar(result.name) }
			elseif result.kept and result.status ~= "failed" and result.previous ~= nil then
				-- Kept as it was, but putting the sliders back re-derives it: written back too.
				state.undo[#state.undo + 1] = { name = result.name, value = result.previous, set = C_CVar.GetCVar(result.name) }
			end
		end
	end
	state.place, state.choice = place.id, choice

	if changed > 0 then
		ns.Print(("%s: using %s."):format(place.label, Places.ChoiceLabel(choice)))
	elseif reverted > 0 then
		ns.Print(("%s: back to your own settings."):format(place.label))
	end
	if ns.UI then
		ns.UI.Refresh()
	end
	return reason or (Places.IsOn() and "switched" or "off")
end

-- Turning the feature off puts the player's own settings back straight away.
function Places.SetOn(on)
	State().on = on or nil
	return Places.Switch()
end

ns.On("PLAYER_ENTERING_WORLD", function()
	-- A frame later, once the loading screen has gone.
	C_Timer.After(0, function()
		ns.SafeCall(Places.Switch)
	end)
end)

ns.On("PLAYER_REGEN_ENABLED", function()
	if pending then
		ns.SafeCall(Places.Switch)
	end
end)
