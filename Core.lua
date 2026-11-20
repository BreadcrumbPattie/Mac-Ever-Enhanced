local addonName, ns = ...
local L = ns.L

ns.name = addonName
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version")

local DB_VERSION = 2

-- The frame-rate goals, shared by the System Check, setup, the goal presets and Places.
-- 144 and 165 are for high-refresh external displays (Josh, 2026-10-10). Like every goal,
-- one out of reach is still chased as far as the rules allow.
ns.GOALS = { 30, 45, 60, 90, 120, 144, 165 }

function ns.Print(message)
	print(L("|cff6fb8ffMac-ever|r: ") .. message)
end

-- Why a change didn't happen, in player-facing words. Keys are CVars.Apply details.
ns.REASONS = {
	combat = L("Graphics settings can't be changed in combat. Try again once combat ends."),
	unknown = "this version of the game doesn't have that setting",
	protected = "the game protects this setting from addons",
	locked = "the game has locked this setting",
	rejected = "the game didn't accept that value",
	blocked = L("Mac-ever never changes this setting, because changing it while the game runs can corrupt the screen"),
	resolution = L("Mac-ever is set not to change resolution settings (turn on \"Let Mac-ever lower resolution to reach your goal\" to allow it)"),
}

ns.Locale.OnReady(function()
	for key, text in pairs(ns.REASONS) do
		ns.REASONS[key] = ns.L(text)
	end
end)

-- Runs a handler, and if it fails, says so in chat instead of failing silently (the game
-- hides addon errors unless scriptErrors is on). The last error is kept for reports.
function ns.SafeCall(fn, ...)
	local ok, err = xpcall(fn, function(message)
		return tostring(message) .. "\n" .. (debugstack and debugstack(2, 8, 0) or "")
	end, ...)
	if not ok then
		if ns.db then
			ns.db.lastError = { time = time(), message = err }
		end
		ns.Print(L("|cffff8c8cSomething went wrong:|r ") .. (tostring(err):match("^[^\n]*") or "unknown error")
			.. ". Your settings may be partly changed: use Restore Originals, or type /macever restore.")
	end
	return ok
end

-- Wraps a script handler with SafeCall.
function ns.Safe(fn)
	return function(...)
		return ns.SafeCall(fn, ...)
	end
end

-- Text is either a plain string or { globalStringName, englishFallback }, or a function
-- returning one (a label that depends on the Mac). Using the client's global strings keeps
-- labels identical to the stock menu in every locale.
function ns.Text(text)
	if type(text) == "function" then
		text = text()
	end
	if type(text) == "table" then
		return _G[text[1]] or text[2]
	end
	return text
end

-- Saved data may come from an older version or have been edited by hand, so every
-- table and field the code relies on is checked for its type.
local function Table(parent, key)
	if type(parent[key]) ~= "table" then
		parent[key] = {}
	end
	return parent[key]
end

local function InitDB()
	if type(MaceverDB) ~= "table" then
		MaceverDB = {}
	end
	local db = MaceverDB
	db.version = DB_VERSION
	-- Pre-Mac-ever values, keyed by lowercased CVar name: { name = string, value = string }.
	local originals = Table(db, "originals")
	for key, original in pairs(originals) do
		if type(original) ~= "table" or type(original.name) ~= "string" or original.value == nil then
			originals[key] = nil
		else
			original.value = tostring(original.value)
			original.set = original.set ~= nil and tostring(original.set) or nil
		end
	end
	for key, kind in pairs({ lastCheck = "table", profile = "table", places = "table", checkRestore = "table" }) do
		if db[key] ~= nil and type(db[key]) ~= kind then
			db[key] = nil
		end
	end
	local ui = Table(db, "ui")
	for key, kind in pairs({ size = "table", scale = "number", goal = "number", tolerance = "number", headroom = "number", language = "string", locked = "table", lastGoal = "number",
		lastPreset = "string", appliedValues = "table", appliedCheck = "number", keepHidden = "boolean" }) do
		if ui[key] ~= nil and type(ui[key]) ~= kind then
			ui[key] = nil
		end
	end
	-- Ultra Uncapped (id "best") was removed (Josh, 2026-10-18), and the Mac Fixes preset
	-- ("macfixes") with the Mac fix switches at launch (Josh, 2026-11-04): forget them.
	ui.fixes, ui.unlocked, ui.optIn = nil, nil, nil
	if ui.lastPreset == "best" or ui.lastPreset == "macfixes" then
		ui.lastPreset, ui.appliedValues, ui.appliedCheck = nil, nil, nil
	end
	-- Goal presets are named by frame rate now (Josh, 2026-10-18): map the old ids across.
	local renamed = ns.Presets.LEGACY_IDS
	if ui.lastPreset == "battery" or ui.lastPreset == "cool" then
		-- Their settings changed with the new presets, so what's applied no longer matches
		-- either: forget it rather than show it as applied (Places choices still map across).
		ui.lastPreset, ui.appliedValues, ui.appliedCheck = nil, nil, nil
	elseif renamed[ui.lastPreset] then
		ui.lastPreset = renamed[ui.lastPreset]
	end
	if type(db.places) == "table" and type(db.places.choices) == "table" then
		for place, choice in pairs(db.places.choices) do
			if renamed[choice] then
				db.places.choices[place] = renamed[choice]
			end
		end
	end
	-- The minimap button's settings, as LibDBIcon keeps them. Before v0.2.0 Mac-ever's own
	-- button kept its position as angle, in the same degrees.
	local minimap = Table(ui, "minimap")
	if type(minimap.minimapPos) ~= "number" then
		minimap.minimapPos = type(minimap.angle) == "number" and minimap.angle or 225
	end
	minimap.angle = nil
	minimap.hide = minimap.hide == true
	ns.db = db
end

-- Lightweight event fan-out so each file can listen without its own frame.
local listeners = {}
local frame = CreateFrame("Frame")

function ns.On(event, callback)
	if not listeners[event] then
		listeners[event] = {}
		frame:RegisterEvent(event)
	end
	table.insert(listeners[event], callback)
end

-- Each listener runs on its own, so one failing can't stop the others (on PLAYER_LOGIN,
-- setting discovery, the minimap button and the Options panel all listen).
frame:SetScript("OnEvent", function(_, event, ...)
	for _, callback in ipairs(listeners[event]) do
		ns.SafeCall(callback, ...)
	end
end)

-- Runs fn once combat ends (straight away if not in combat).
local afterCombat = {}

function ns.OnceOutOfCombat(fn)
	if not InCombatLockdown() then
		return fn()
	end
	afterCombat[#afterCombat + 1] = fn
end

ns.On("PLAYER_REGEN_ENABLED", function()
	local queued = afterCombat
	afterCombat = {}
	for _, fn in ipairs(queued) do
		ns.SafeCall(fn)
	end
end)

ns.On("ADDON_LOADED", function(loadedName)
	if loadedName == addonName then
		InitDB()
		ns.Locale.Ready()
	end
end)
