local _, ns = ...
local L = ns.L

local CVars = ns.CVars
local Registry = ns.Registry

-- The System Check's maths, apart from running it (Benchmark.lua): what each setting
-- costs and adds to the picture, the best setup for a goal within a frame-time budget,
-- the same worked out again from a saved report for presets and Instance Settings, render
-- scale below its usual floor, and the statistics of a measurement. Nothing here changes
-- a setting or keeps state.
local Solver = {}
ns.Solver = Solver

local MEASURE_SLACK = 0.98          -- measurements wobble a little; don't fail a setup for 2%
local NOISE_FLOOR_SECONDS = 0.00015 -- costs below this, or 2% of a frame, are noise
local STEADY_PERCENT = 3            -- first and second halves within 3% of each other

-- Quality first: the player chooses how far below the goal the frame rate may dip to
-- keep graphics higher. Asked for by Josh after the check kept trading sharpness for
-- frame rate (2026-10-07).
Solver.TOLERANCES = { 0, 0.10, 0.15, 0.25 }
Solver.DEFAULT_TOLERANCE = 0.15

-- Headroom (fork addition): the cap stays at the goal (say 60), but graphics are only
-- raised until the UNCAPPED frame rate would still be goal x headroom (60 x 1.6 = 96).
-- The GPU then idles part of every frame, so the Mac stays cool and the fans stay quiet.
-- 1.0 is the original behaviour: use up everything the goal allows.
Solver.HEADROOMS = { 1.0, 1.25, 1.5, 1.6, 1.75 }
Solver.DEFAULT_HEADROOM = 1.6

-- The headroom in use: the player's choice, or the default.
function Solver.Headroom()
	local ui = ns.db and ns.db.ui
	local value = ui and ui.headroom
	if type(value) == "number" and value >= 1 and value <= 3 then
		return value
	end
	local profile = ns.db and ns.db.profile
	if profile and profile.mac == "air" then
		return 1.75 -- a fanless Air throttles as it warms up: leave it more room
	end
	return Solver.DEFAULT_HEADROOM
end

-- Lowest frame rate a goal accepts. This is what the settings are budgeted for; the
-- frame rate cap itself stays at the goal (ChangesFor / Solve write maxFPS = goal).
function Solver.Accepts(goal, tolerance, headroom)
	return goal * (headroom or Solver.Headroom()) * (1 - (tolerance or Solver.DEFAULT_TOLERANCE))
end

-- The measured frame rate a setup needs to count as holding the goal.
function Solver.Required(goal, tolerance, headroom)
	return Solver.Accepts(goal, tolerance, headroom) * MEASURE_SLACK
end

-- How small a cost counts as measurement noise, for a frame of frameTime seconds.
function Solver.Noise(frameTime)
	return math.max(NOISE_FLOOR_SECONDS, frameTime * 0.02)
end

-- The format of a System Check report (Benchmark writes it); Solve only reads its own.
-- 3: render scale floor 85%, anti-aliasing limited to off / FXAA High.
-- 4: quality first with a frame-rate tolerance; "everything at maximum" measured.
-- 5: hidden settings searched (extended levels, shadow map, sun shafts, animation).
-- 6: group testing; reflections, water, weather, light distance, object detail.
--    Later in 6: anti-aliasing measured level by level, up to CMAA 2 (settings.costs,
--    settings.quality). Earlier 6 reports have neither and still solve as before.
--    Later in 6: heat (report.heat). Earlier 6 reports have neither.
-- Reports from earlier versions were measured differently, so presets ignore them.
-- 7: v0.2.0 (shadows skip Fair, anti-aliasing levels measured one by one); older
-- reports' levels no longer match, so presets ask for a new check instead of using them.
-- 8: everything at maximum isn't measured on its own; report.max is the recommendation's
--    measurement when that's everything at maximum, otherwise predicted (max.predicted).
-- 9: only Standard Settings are tuned (Josh, 2026-10-18); the Hidden ones of reports 5 to 8
--    (extended levels, shadow map, sun shafts, water...) are never applied. settings.extras
--    replaces settings.extended.
-- 10: Shadow Quality is tuned on Top class Macs only, and every other Mac measures with the
--    fixed shadow values (Josh, 2026-10-19); version 9 reports budgeted for shadows there.
-- 11: Shadow Quality is tuned on M3 and later chips, whatever the class (Josh, 2026-11-07);
--    version 10 reports from those Macs never measured shadows, and M1/M2 Top ones did.
-- 14: fork; Render Scale is tuned between 50% and 70%.
-- 13: fork; View Distance, Environment Detail and Ground Clutter are no longer tuned.
-- 12: fork; Shadow Quality is only measured at Low and Good, and the System Check budgets
--    for goal x headroom (report.headroom). Version 11 reports have other shadow levels.
Solver.REPORT_VERSION = 14

local FSR = 3

-- Lower resolution, only when the player allows it (ns.db.ui.allowResolution) and the
-- goal can't be reached within the usual rules: render scale goes below its 85% floor,
-- in 5% steps down to 50% (or the game's minimum, if higher), with every other setting
-- at its lowest. Render scale is used rather than the window's resolution: it saves the
-- same GPU work, keeps text and the interface sharp at full Retina resolution, and
-- doesn't refresh the game window (which has reset Macs to 1512x982 before).
-- Fork: the normal render scale levels are already 50-70% (Benchmark DIMENSIONS), so going
-- lower than the usual floor is switched off: a top below the minimum gives no levels.
local LOW_SCALE_TOP = 0.45
local LOW_SCALE_FLOOR = 0.5
local LOW_SCALE_STEP = 0.05

-- Render scale levels below the usual floor, sharpest first.
function Solver.LowScaleLevels()
	local minimum = math.max(LOW_SCALE_FLOOR, GetMinRenderScale and GetMinRenderScale() or LOW_SCALE_FLOOR)
	local levels = {}
	for step = 0, math.floor((LOW_SCALE_TOP - minimum) / LOW_SCALE_STEP + 1e-9) do
		levels[#levels + 1] = math.floor((LOW_SCALE_TOP - step * LOW_SCALE_STEP) * 100 + 0.5) / 100
	end
	return levels
end

-- Render scale model for going below the floor: frame time grows with the number of
-- pixels (scale squared). Fitted to the measured cost between the floor and the top.
-- Returns seconds per unit of scale squared, and the floor scale; nil if not measured.
function Solver.ScaleModel(dims)
	for _, dim in ipairs(dims) do
		if dim.id == "renderscale" and dim.cost and #dim.levels > 1 then
			local low, high = dim.levels[1], dim.levels[#dim.levels]
			return dim.cost / (high * high - low * low), low
		end
	end
end

-- The sharpest low scale predicted to reach targetTime, given the frame time at the
-- floor scale; the lowest one if none does. Returns its index in levels.
function Solver.PickLowScale(levels, perScale2, floorScale, floorTime, targetTime)
	local needed = floorScale * floorScale - (floorTime - targetTime) / perScale2
	for index, level in ipairs(levels) do
		if level * level <= needed then
			return index
		end
	end
	return #levels
end

-- Never forced: Texture Resolution reloads every texture when written and derives no
-- Hidden setting (spec, 2026-10-18), so it's only written when its value changes.
-- Secondary Lighting is never written just to re-derive either: changing it while the game
-- runs crashed M5 Max Macs on build 70338 (v0.2.2 reports, 2026-10-13), so it's only
-- written when a result sets it. Nor Depth Effects: switching it while the check ran
-- crashed an M5 Pro's GPU driver on build 70790 (2026-11-05), and a forced write flicks the
-- Hidden settings it derives (Sun Shafts, Refraction) off and back in one frame.
local NEVER_FORCED = {
	graphicstextureresolution = true, raidgraphicstextureresolution = true,
	graphicslightmode = true, raidgraphicslightmode = true,
	graphicsdeptheffects = true, raidgraphicsdeptheffects = true,
}

-- A Graphics Quality slider whose write makes the game re-derive its Hidden settings:
-- shown on this Mac (as Registry.QualityValues) and not in NEVER_FORCED.
local function Rederives(entry)
	return entry ~= nil and entry.group == "quality" and entry.quality == true and not entry.master
		and not NEVER_FORCED[Registry.Key(entry.name)] and Registry.IsShown(entry)
end

-- The changes that put a tuned setting at a level: the setting itself, FidelityFX
-- sharpening when render scale is below 100%, then the setting's fixed extras (Hidden
-- settings its slider re-derives on every write, so they go after it). A Graphics Quality
-- slider is forced: written even at its current value, so the game re-derives its
-- Hidden settings (the check's floor step moves them all, but applying a result doesn't).
function Solver.ChangesFor(dimension, value)
	local change = { name = dimension.name, value = value }
	if Rederives(Registry.Get(dimension.name)) then
		change.force = true
	end
	local changes = { change }
	if dimension.id == "renderscale" and value < 1 then
		changes[#changes + 1] = { name = "ResampleQuality", value = FSR }
	end
	for _, extra in ipairs(dimension.extras or {}) do
		changes[#changes + 1] = { name = extra.name, value = extra.value }
	end
	return changes
end

-- Fixed values (Josh, 2026-10-19): set the same way on every Mac, never tuned.
-- Shadows (Josh, 2026-11-07, replacing "only for the highest level mac chips"): where the
-- check doesn't tune Shadow Quality (see Solver.TunesShadows) it's Low, forced so the game
-- re-derives its Hidden shadow settings, and these go on top of what it derives.
local FIXED_SHADOWS = {
	{ name = "shadowMode", value = 0 },
	{ name = "shadowTextureSize", value = 1024 },
	{ name = "shadowNumCascades", value = 3 },
	{ name = "shadowSoft", value = 0 },
	{ name = "shadowBlendCascades", value = 0 },
	{ name = "entityShadowFadeScale", value = 10 },
}
-- On every Mac, while the check measures too: Full-Screen Glow off, and the strongest
-- sharpening ("max sharpness"; 0 is the strongest).
local FIXED_ALWAYS = {
	{ name = "ffxGlow", value = 0 },
	{ name = "ResampleSharpness", value = 0 },
}
-- Sharpening with every result (Josh, 2026-10-18): ResampleAlwaysSharpen only acts at 100%
-- render scale, which the check never picks, so it costs nothing and covers a player who
-- later moves render scale to 100%. DynamicRenderScale stays off, as the check measures
-- (its CONDITIONS turn it off while measuring).
local WITH_EVERY_RESULT = {
	{ name = "ResampleAlwaysSharpen", value = 1 },
	{ name = "DynamicRenderScale", value = 0 },
}

-- Whether the System Check tunes Shadow Quality on this Mac (Josh, 2026-11-07): on every
-- Apple Silicon Mac from M3 on, whatever its class, by the core frame-rate rules. M1 and M2
-- Macs keep the fixed shadows above, and so do the MacBook Neo's A-series chip and anything
-- that isn't Apple Silicon ("anything non-silicon should have shadows off": Low is the
-- game's lowest).
function Solver.TunesShadows()
	local generation = ns.Devices.ParseChip(ns.ChipNames())
	return generation ~= nil and generation >= 3
end

-- Fork: Texture Resolution suggested from the memory the player gave in setup (the game
-- can't report RAM). Textures cost little frame rate but use shared memory, so 8 GB gets
-- Fair (1) and 16 GB or more gets High (2). nil before setup: textures stay as they are.
function Solver.TextureSuggestion()
	local profile = ns.db and ns.db.profile
	local memory = profile and profile.memory
	if memory == "8" then
		return 1
	elseif memory == "16" then
		return 2
	end
end

-- The fixed values, world settings only: the check's floor step writes them (forCheck),
-- and every check result and goal preset (Solver.ForApply), which also brings Mac-ever's
-- Standard picture (Presets' Standard look, Bloom included) and the sharpening above. The
-- picture is a matter of taste, so the check measures with the player's own.
-- always: Solver.WithReset writes it even over the result's own value (see there).
function Solver.FixedChanges(forCheck)
	local list = {}
	if not Solver.TunesShadows() then
		list[#list + 1] = { name = "graphicsShadowQuality", value = 0, always = true }
		for _, change in ipairs(FIXED_SHADOWS) do
			list[#list + 1] = { name = change.name, value = change.value }
		end
	end
	for _, change in ipairs(FIXED_ALWAYS) do
		list[#list + 1] = { name = change.name, value = change.value }
	end
	if not forCheck then
		local texture = Solver.TextureSuggestion()
		if texture then
			list[#list + 1] = { name = "graphicsTextureResolution", value = texture }
		end
		for _, change in ipairs(ns.Presets.LookChanges(ns.Presets.GetLook("standard"))) do
			list[#list + 1] = change
		end
		for _, change in ipairs(WITH_EVERY_RESULT) do
			list[#list + 1] = { name = change.name, value = change.value }
		end
	end
	return list
end

-- Keep my Hidden Settings (Josh, 2026-10-19): "run a system check, the user then
-- customises their hidden settings, then can choose to maintain those if they want to run
-- another system check. But on first system check, everything should be default anyway."
-- On (ns.db.ui.keepHidden), and once a System Check of this version has finished, Mac-ever
-- changes nothing on the Hidden Settings page: no reset and no fixed Hidden value, the
-- check's fixed extras and the shadow values included (Josh's choice). The game still
-- re-derives a slider's Hidden settings on every write, so keeping them means writing the
-- player's own back after the sliders (Solver.KeepChanges), with every result and goal
-- preset and in every write of the check that moves a slider.
function Solver.KeepsHidden()
	return ns.db ~= nil and ns.db.ui.keepHidden == true and Solver.HasCurrentCheck()
end

-- Whether a System Check of this version has finished (ns.db.lastCheck).
function Solver.HasCurrentCheck()
	local last = ns.db and ns.db.lastCheck
	return type(last) == "table" and last.version == Solver.REPORT_VERSION
end

local function IsHidden(name)
	local entry = Registry.Get(name)
	local group = entry and Registry.GetGroup(entry.group)
	return group ~= nil and group.tab == "hidden"
end

-- changes without its Hidden settings, and unforced: nothing is reset, so no slider needs writing at its current value to
-- re-derive its Hidden settings, and a Hidden setting outside Solver.KeptNames (Everything
-- Else, componentTextureLevel) isn't re-derived for nothing (review, 2026-10-19).
local function WithoutHidden(changes)
	local kept = {}
	for _, change in ipairs(changes) do
		if not IsHidden(change.name) then
			if change.force then
				local copy = {}
				for field, value in pairs(change) do
					copy[field] = value
				end
				copy.force = nil
				change = copy
			end
			kept[#kept + 1] = change
		end
	end
	return kept
end

-- Every Hidden setting Mac-ever writes when it doesn't keep them: the reset set, the check's
-- fixed extras (Benchmark DIMENSIONS) and the fixed Hidden values, the shadow ones on every
-- Mac (one whose shadows the check tunes resets them instead).
function Solver.KeptNames()
	local names, seen = {}, {}
	local function Add(name)
		local key = Registry.Key(name)
		if not seen[key] and IsHidden(name) then
			seen[key] = true
			names[#names + 1] = name
		end
	end
	for _, name in ipairs(Registry.HiddenResetNames()) do
		Add(name)
	end
	for _, dimension in ipairs(ns.Benchmark.DIMENSIONS) do
		for _, extra in ipairs(dimension.extras or {}) do
			Add(extra.name)
		end
	end
	for _, list in ipairs({ FIXED_SHADOWS, FIXED_ALWAYS, WITH_EVERY_RESULT }) do
		for _, change in ipairs(list) do
			Add(change.name)
		end
	end
	return names
end

-- Solver.KeptNames as changes at the player's values: read now, before anything is
-- written, or taken from values (Registry.Key name -> value: the check's snapshot from its
-- start). No change flags, so Registry order writes them after the sliders. kept marks
-- them for Switch Back (CVars.UndoFor) and Instance Settings (Places), which write them
-- back after moving the sliders back. skip: Registry.Key names to leave out.
function Solver.KeepChanges(values, skip)
	local changes = {}
	for _, name in ipairs(Solver.KeptNames()) do
		local key = Registry.Key(name)
		local value
		if values then
			value = values[key]
		else
			value = CVars.Inspect(name) -- nil when this client hasn't it, or it can't be changed
		end
		if value ~= nil and not (skip and skip[key]) then
			changes[#changes + 1] = { name = name, value = value, kept = true }
		end
	end
	return changes
end

-- changes keeping the Hidden settings: its own Hidden ones dropped (the fixed extras that
-- Solver.ChangesFor adds, a saved report's included), keep (Solver.KeepChanges) after it.
function Solver.Keeping(changes, keep)
	local list, keys = WithoutHidden(changes), {}
	for _, change in ipairs(list) do
		keys[Registry.Key(change.name)] = true
	end
	for _, change in ipairs(keep) do
		if not keys[Registry.Key(change.name)] then
			list[#list + 1] = change
		end
	end
	return list
end

-- Changes with the Hidden reset set (Registry.HiddenResetChanges) put in front, and every
-- Graphics Quality slider written after it, so each Hidden setting ends where the game
-- itself puts it: at what its slider derives, or else its default (Josh, 2026-10-18).
-- A slider in changes is forced (it may already be at that value). A world slider changes doesn't set (one the check doesn't tune, such as Spell
-- Density or Projected Textures) is written at its current value, forced; rederive marks
-- it, so Instance Settings writes a raid copy at the raid copy's own value instead.
-- fixed (Solver.FixedChanges) joins changes first, so the reset never writes those
-- settings; Registry order puts the Hidden and Advanced ones after the sliders.
-- A setting changes already sets is left out of the rest, so its value wins.
-- The one exception is Shadow Quality where the check doesn't tune it (fixed.always): Low
-- even when the result says otherwise.
-- keep (Solver.KeepChanges, while Solver.KeepsHidden): no reset and no Hidden setting from
-- changes or fixed; sliders are written only when they change (no forced or re-derive-only
-- writes: nothing needs re-deriving), and keep goes after them.
function Solver.WithReset(changes, fixed, keep)
	if keep then
		changes = WithoutHidden(changes)
		fixed = fixed and WithoutHidden(fixed)
	end
	local keys = {}
	for _, change in ipairs(changes) do
		keys[Registry.Key(change.name)] = true
	end
	if fixed and #fixed > 0 then
		local always = {}
		for _, change in ipairs(fixed) do
			if change.always then
				always[Registry.Key(change.name)] = change.value
			end
		end
		local joined = {}
		for _, change in ipairs(changes) do
			local value = always[Registry.Key(change.name)]
			if value ~= nil then
				local copy = {}
				for field, fieldValue in pairs(change) do
					copy[field] = fieldValue
				end
				copy.value = value
				change = copy
			end
			joined[#joined + 1] = change
		end
		for _, change in ipairs(fixed) do
			local key = Registry.Key(change.name)
			if not keys[key] then
				joined[#joined + 1] = { name = change.name, value = change.value } -- without always
				keys[key] = true
			end
		end
		changes = joined
	end
	local list = keep and {} or Registry.HiddenResetChanges(keys)
	for _, change in ipairs(changes) do
		if not keep and not change.force and Rederives(Registry.Get(change.name)) then
			local forced = {}
			for field, value in pairs(change) do
				forced[field] = value
			end
			forced.force = true
			change = forced
		end
		list[#list + 1] = change
	end
	for _, entry in ipairs(keep and {} or Registry.entries) do
		if Rederives(entry) and not entry.raid and not keys[Registry.Key(entry.name)] then
			local value = CVars.Inspect(entry.name)
			if value ~= nil then
				list[#list + 1] = { name = entry.name, value = value, force = true, rederive = true }
			end
		end
	end
	if keep then
		for _, change in ipairs(keep) do
			if not keys[Registry.Key(change.name)] then
				list[#list + 1] = change
			end
		end
	end
	return list
end

-- What applying a check result or goal preset writes: Solver.WithReset with every fixed
-- value (shadows where the check doesn't tune them, glow, sharpness, the Standard picture and sharpening)
-- the result doesn't set already. Keep my Hidden Settings: the player's
-- Hidden settings instead of the reset and the fixed Hidden values.
function Solver.ForApply(changes)
	return Solver.WithReset(changes, Solver.FixedChanges(false), Solver.KeepsHidden() and Solver.KeepChanges() or nil)
end

-- Index in levels nearest to value.
function Solver.NearestIndex(levels, value)
	if value == nil then
		return nil
	end
	local best
	for index, level in ipairs(levels) do
		if not best or math.abs(level - value) < math.abs(levels[best] - value) then
			best = index
		end
	end
	return best
end

-- How far up its levels a choice is (0 to 1); a setting left with one level is 0.
function Solver.Fraction(index, count)
	if count <= 1 then
		return 0
	end
	return (math.min(index, count) - 1) / (count - 1)
end

function Solver.Summarise(sample)
	local count = #sample.frames
	if count < 10 or sample.total <= 0 then
		return nil
	end
	local sorted = {}
	for i, frameTime in ipairs(sample.frames) do
		sorted[i] = frameTime
	end
	table.sort(sorted)
	-- 1% low: the frame rate of the slowest 1% of frames, which is what stutter feels like.
	local worst = sorted[math.max(1, math.ceil(count * 0.99))]
	return { fps = count / sample.total, low = 1 / worst, frameTime = sample.total / count }
end

-- Recommendation ---------------------------------------------------------------------

-- Quality first: the budget is everything between the floor and the lowest frame rate
-- the goal accepts. Settings are raised best-value-per-millisecond first, which is the
-- same as starting from maximum and lowering the least valuable per millisecond first;
-- render scale weighs the most, so it's the last thing given up. Frame times add up far
-- better than frame rates do, so costs are in seconds per frame, spread evenly over
-- each setting's levels, except for settings measured level by level (dim.costs), whose
-- every step up is weighed on its own.
-- Dimensions that couldn't be measured (dim.cost == nil) keep the level in dim.keep.
-- runNoise: the smallest cost that wasn't noise in the check's own measurements (seconds).
function Solver.Recommend(dims, floorTime, goal, tolerance, runNoise)
	local budget = 1 / Solver.Accepts(goal, tolerance) - floorTime
	local noise = math.max(Solver.Noise(floorTime), runNoise or 0)
	local function Cost(dim)
		return dim.cost > noise and dim.cost or 0
	end
	-- From level index - 1 to index, for a setting measured level by level.
	local function RawStep(dim, index)
		return math.max(0, dim.costs[index] - dim.costs[index - 1])
	end
	local function StepCost(dim, index)
		local step = RawStep(dim, index)
		return step > noise and step or 0
	end
	-- One entry per setting, or per step up for a setting measured level by level. A step
	-- never ranks above the one before it, so steps are always taken in order.
	local order = {}
	for _, dim in ipairs(dims) do
		if dim.cost and dim.costs then
			local previous = math.huge
			for index = 2, #dim.levels do
				local gain = dim.weight * (Solver.LevelQuality(dim, index) - Solver.LevelQuality(dim, index - 1))
				local ratio = math.min(gain / math.max(StepCost(dim, index), 1e-6), previous * (1 - 1e-9))
				previous = ratio
				order[#order + 1] = { dim = dim, index = index, ratio = ratio }
			end
		elseif dim.cost then
			order[#order + 1] = { dim = dim, ratio = dim.weight / math.max(Cost(dim), 1e-6) }
		end
	end
	table.sort(order, function(a, b)
		return a.ratio > b.ratio
	end)

	local choice = {}
	for _, dim in ipairs(dims) do
		choice[dim.id] = dim.cost and 1 or (dim.keep or 1) -- level index; 1 is the floor
	end
	-- Near-free settings always go to their maximum, but what they do cost still comes
	-- out of the budget, so the plan doesn't over-promise.
	for _, dim in ipairs(dims) do
		if dim.cost and Cost(dim) == 0 then
			choice[dim.id] = #dim.levels
			budget = budget - dim.cost
		end
	end
	local reachable = budget >= 0
	for _, item in ipairs(order) do
		local dim = item.dim
		if Cost(dim) > 0 and item.index then
			local stepCost = StepCost(dim, item.index)
			local affordable = stepCost == 0 or math.floor(budget / stepCost + 1e-9) >= 1
			if choice[dim.id] == item.index - 1 and affordable then
				choice[dim.id] = item.index
				budget = budget - (stepCost > 0 and stepCost or RawStep(dim, item.index))
			end
		elseif Cost(dim) > 0 then
			local steps = #dim.levels - 1
			local stepCost = steps > 0 and Cost(dim) / steps or 0
			if stepCost > 0 then
				local take = math.max(0, math.min(steps, math.floor(budget / stepCost + 1e-9)))
				choice[dim.id] = 1 + take
				budget = budget - take * stepCost
			end
		end
	end
	return choice, reachable
end

-- How much a level adds to the picture, from 0 (floor) to 1 (top): dim.quality when the
-- levels aren't evenly spaced in value, otherwise evenly spread.
function Solver.LevelQuality(dim, index)
	local value = dim.quality and dim.levels[math.min(index, #dim.levels)]
	if value ~= nil and dim.quality[value] then
		return dim.quality[value]
	end
	return Solver.Fraction(index, #dim.levels)
end

-- What a level costs over the floor, in seconds per frame.
function Solver.LevelCost(dim, index)
	if dim.costs then
		return dim.costs[math.min(index, #dim.levels)] or 0
	end
	return dim.cost * Solver.Fraction(index, #dim.levels)
end

-- Works out the setup for another goal from a finished report's measurements, without
-- measuring again. Returns nil for reports from older versions of the check.
-- Result: { changes, predictedFps, reachable, floorFps }
function Solver.Solve(report, goal, tolerance)
	if not report or report.version ~= Solver.REPORT_VERSION or not report.floorTime then
		return nil
	end
	local dims = {}
	for _, setting in ipairs(report.settings) do
		dims[#dims + 1] = {
			id = setting.id, name = setting.name, levels = setting.levels, extras = setting.extras,
			weight = setting.weight, cost = setting.cost, costs = setting.costs, quality = setting.quality,
			keep = setting.keep,
		}
	end
	local overhead = report.floorTime + (report.correction or 0)
	local choice, reachable = Solver.Recommend(dims, overhead, goal, tolerance, report.noise)
	-- Measured: everything at maximum already meets this goal, so keep it all at maximum.
	-- A predicted maximum isn't taken as proof; the model decides then.
	local maxIsEnough = report.max and not report.max.predicted
		and report.max.fps >= Solver.Required(goal, tolerance)
	if maxIsEnough then
		for _, dim in ipairs(dims) do
			choice[dim.id] = #dim.levels
		end
		reachable = true
	end

	local frameTime = overhead
	for _, dim in ipairs(dims) do
		if dim.cost then
			frameTime = frameTime + Solver.LevelCost(dim, choice[dim.id])
		end
	end

	-- Out of reach and the player allows lower resolution: lower render scale the same way
	-- the check does. For the goal the check ran for, its measured answer; for any other
	-- goal, predicted from the render scale model.
	local lowScale
	local perScale2, floorScale = Solver.ScaleModel(dims)
	if not reachable and not maxIsEnough and perScale2 and CVars.ResolutionAllowed() then
		local low = report.lowResolution
		local levels = Solver.LowScaleLevels()
		local target = 1 / Solver.Required(goal, tolerance)
		if low and low.scale and goal == report.goal and tolerance == report.tolerance
			and (report.headroom or 1) == Solver.Headroom() and report.validated then
			lowScale, frameTime = low.scale, report.validated.frameTime
			reachable = report.reachable
		elseif #levels > 0 and not (low and low.helpless) then
			lowScale = levels[Solver.PickLowScale(levels, perScale2, floorScale, frameTime, target)]
			frameTime = frameTime - perScale2 * (floorScale * floorScale - lowScale * lowScale)
			reachable = frameTime <= target
		end
	end

	local changes = {}
	for _, dim in ipairs(dims) do
		local value = dim.levels[choice[dim.id]]
		if lowScale and dim.id == "renderscale" then
			value = lowScale
		end
		for _, change in ipairs(Solver.ChangesFor(dim, value)) do
			changes[#changes + 1] = change
		end
	end
	changes[#changes + 1] = { name = "useMaxFPS", value = 1 }
	changes[#changes + 1] = { name = "maxFPS", value = goal }
	return {
		changes = changes,
		predictedFps = math.min(goal, maxIsEnough and report.max.fps or 1 / frameTime),
		uncappedFps = maxIsEnough and report.max.fps or 1 / frameTime,
		reachable = reachable,
		floorFps = 1 / overhead,
		allMax = maxIsEnough or false,
		lowScale = lowScale,
	}
end

-- Measurement samples ---------------------------------------------------------------

-- Adds a frame to a measurement. The sum of its first half is kept as it grows, so the
-- steadiness test each frame doesn't rescan every frame so far.
function Solver.AddFrame(sample, frameTime)
	local frames = sample.frames
	frames[#frames + 1] = frameTime
	sample.total = sample.total + frameTime
	sample.half = sample.half or 0
	sample.firstSum = sample.firstSum or 0
	while sample.half < math.floor(#frames / 2) do
		sample.half = sample.half + 1
		sample.firstSum = sample.firstSum + frames[sample.half]
	end
end

-- True when the first and second halves of a measurement agree within STEADY_PERCENT.
function Solver.Steady(sample)
	local count, half = #sample.frames, sample.half or 0
	if half == 0 or half == count then
		return false
	end
	local first, second = sample.firstSum / half, (sample.total - sample.firstSum) / (count - half)
	return math.abs(first - second) / ((first + second) / 2) * 100 < STEADY_PERCENT
end
