local _, ns = ...
local L = ns.L

-- Which Mac the player has, and the goals that suit it (Josh, 2026-10-10: "someone
-- who has a really powerful machine should absolutely have the ability to push their fps,
-- whereas someone like me, on a MacBook Pro M1 Pro, should have a little more realism").
--
-- The chip's generation and tier, the kind of Mac and its memory put it in one of four
-- classes. A class decides the highest goal Mac-ever recommends for the Mac and which goal is
-- tagged as its best fit; it never produces a frame rate. The System Check measures what's actually reachable.

local Devices = {}
ns.Devices = Devices

Devices.MACS = {
	{ id = "air", label = L("MacBook Air") },
	{ id = "mbp", label = L("MacBook Pro") },
	{ id = "neo", label = L("MacBook Neo") },
	{ id = "imac", label = "iMac" },
	{ id = "mini", label = L("Mac mini") },
	{ id = "studio", label = L("Mac Studio") },
	{ id = "macpro", label = "Mac Pro" },
}

-- Only 8 GB changes anything: the game shares it with the graphics, and it runs short.
Devices.MEMORY = {
	{ id = "8", label = "8 GB" },
	{ id = "16", label = L("16 GB or more") },
}

Devices.ENTRY, Devices.MID, Devices.HIGH, Devices.TOP = 1, 2, 3, 4

function Devices.Find(list, id)
	for _, item in ipairs(list) do
		if item.id == id then
			return item
		end
	end
end

-- "Apple M1 Pro" -> 1, "pro"; "Apple M4" -> 4, "base". nil for anything else.
function Devices.ParseChip(name)
	local generation, variant = (name or ""):match("Apple M(%d+)%s*(%a*)")
	if not generation then
		return nil
	end
	variant = variant:lower()
	if variant ~= "pro" and variant ~= "max" and variant ~= "ultra" then
		variant = "base"
	end
	return tonumber(generation), variant
end

-- The chip on its own. Agreed with Josh, 2026-10-10: an M1 Pro is the low end of Mid,
-- an M4 Pro the top of High. Chips newer than any listed count as the newest listed.
function Devices.ChipClass(generation, variant)
	if not generation then
		return Devices.ENTRY
	end
	if variant == "ultra" then
		return Devices.TOP
	elseif variant == "max" then
		return generation >= 4 and Devices.TOP or Devices.HIGH
	elseif variant == "pro" then
		if generation >= 5 then
			return Devices.TOP
		end
		return generation == 4 and Devices.HIGH or Devices.MID
	end
	return generation >= 4 and Devices.MID or Devices.ENTRY
end

-- The class for setup: a fanless Air and 8 GB of memory each count one class lower.
function Devices.Class(chipName, mac, memory)
	local class = Devices.ChipClass(Devices.ParseChip(chipName))
	if mac == "air" then
		class = class - 1
	end
	if memory == "8" then
		class = class - 1
	end
	return math.max(Devices.ENTRY, class)
end

-- The highest goal recommended for each class and the one tagged "Best fit for your Mac"
-- (Josh, 2026-10-18). Every goal is open to every Mac; above the highest one the player
-- accepts a warning first (Josh, 2026-11-07: "pass the responsibility onto them").
-- Re-check both against Blizzard thread 2354050 before each release.
Devices.MAX_GOAL = { [Devices.ENTRY] = 60, [Devices.MID] = 90, [Devices.HIGH] = 120, [Devices.TOP] = 165 }
Devices.BEST_FIT = { [Devices.ENTRY] = 45, [Devices.MID] = 60, [Devices.HIGH] = 90, [Devices.TOP] = 120 }

-- The player's class, from the graphics chip and the Mac and memory chosen in setup. A
-- MacBook Neo (picked in setup, or an "Apple A" chip, which only it has) is Entry. nil
-- when the chip isn't an M chip and the Mac isn't a Neo: no warning and no tag. Without a setup profile the chip alone decides.
-- `answers` ({ mac, memory }) stands in for the saved profile while setup is still asking.
function Devices.PlayerClass(answers)
	local chip = ns.ChipNames()
	local profile = answers or (ns.db and ns.db.profile)
	if profile and profile.mac == "neo" then
		return Devices.ENTRY
	end
	-- The MacBook Neo is the only Mac with an A-series chip ("Apple A18 Pro"), so the chip
	-- alone says it's Entry, even before setup or with another Mac picked (Josh, 2026-10-18).
	if (chip or ""):match("^Apple A%d") then
		return Devices.ENTRY
	end
	if not Devices.ParseChip(chip) then
		return nil
	end
	if profile then
		return Devices.Class(chip, profile.mac, profile.memory)
	end
	return Devices.ChipClass(Devices.ParseChip(chip))
end

-- Starting profiles (fork addition): what to try first on each class of Mac for a locked
-- 60 fps with the GPU well below full load, so the fans stay quiet. They are estimates, not
-- measurements: the System Check replaces them as soon as it has run. ssao and compute are
-- the game's own levels. View distance, environment and ground clutter (view, env, clutter)
-- are kept for reference only: they cost little frame rate, so profiles never change them.
Devices.START = {
	[Devices.ENTRY] = { scale = 0.50, shadows = 0, ssao = 0, compute = 0, view = 3, env = 3, clutter = 3 },
	[Devices.MID]   = { scale = 0.55, shadows = 2, ssao = 1, compute = 0, view = 4, env = 4, clutter = 5 },
	[Devices.HIGH]  = { scale = 0.60, shadows = 2, ssao = 1, compute = 1, view = 5, env = 5, clutter = 7 },
	[Devices.TOP]   = { scale = 0.65, shadows = 2, ssao = 2, compute = 2, view = 6, env = 6, clutter = 9 },
}

-- The changes and notes for this Mac's starting profile, or nil when the Mac's class isn't
-- known (not an M chip). answers: as in PlayerClass.
function Devices.StartChanges(answers)
	local class = Devices.PlayerClass(answers)
	local profile = class and Devices.START[class]
	if not profile then
		return nil
	end
	local notes = {}
	local scale = profile.scale
	if not ns.CVars.ResolutionAllowed() then
		-- Below 85% needs the player's permission (the resolution lock).
		scale = 0.85
		notes[#notes + 1] = ns.L("Turn on 'Let Mac-ever lower resolution to reach your goal' to use a lower render scale: it saves the most heat.")
	end
	local changes = {
		{ name = "RenderScale", value = scale },
		{ name = "graphicsSSAO", value = profile.ssao },
		{ name = "graphicsComputeEffects", value = profile.compute },
		{ name = "useMaxFPS", value = 1 },
		{ name = "maxFPS", value = 60 },
	}
	-- Shadows below M3 stay Low whatever is asked (Solver.TunesShadows).
	if ns.Solver.TunesShadows() then
		changes[#changes + 1] = { name = "graphicsShadowQuality", value = profile.shadows }
	end
	return { changes = changes, notes = notes }
end

function Devices.MaxGoal(answers)
	local class = Devices.PlayerClass(answers)
	return class and Devices.MAX_GOAL[class]
end

function Devices.Recommends(goal, answers)
	local max = Devices.MaxGoal(answers)
	return max == nil or goal <= max
end

function Devices.BestFit(answers)
	local class = Devices.PlayerClass(answers)
	return class and Devices.BEST_FIT[class]
end
