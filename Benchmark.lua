local _, ns = ...
local L = ns.L

local Registry = ns.Registry
local CVars = ns.CVars
local Solver = ns.Solver

-- System Check: finds the best-looking settings this Mac can run at the frame rate the
-- player asks for.
--
--   1. Measure the current settings, so the result can be compared with them.
--   2. Drop every tuned setting to a low floor and measure: the most frame rate this Mac
--      has to spend in this spot.
--   3. Raise one setting at a time to its maximum and measure, which gives what each
--      setting really costs on this Mac.
--   4. Spend the frame-time budget for the goal on the settings that improve the picture
--      most per millisecond they cost.
--   5. Apply that combination and measure it. If it misses the goal, drop the least
--      worthwhile upgrade and measure again.
--   6. Put everything back exactly as it was, and report.
--
-- Safety:
--   * nothing that restarts the renderer or switches the frame buffer format is touched
--   * every value is snapshotted first and restored at the end, on Stop, and if combat
--     starts (deferred until it ends), a loading screen appears or the player moves
--   * nothing is kept: the player chooses whether to apply the recommendation
--
-- This file runs the check; the maths (costs, the recommendation, solving a saved report
-- for another goal) is in Solver.lua. A driver calls Benchmark.Tick(elapsed) every frame
-- (UI.CreateCheckDriver), so the same code runs against a simulated clock in tests.

local Benchmark = {}
ns.Benchmark = Benchmark

-- Kept short: Josh asked for a faster check (2026-10-07).
local SETTLE_SECONDS = 2
local MEASURE_MIN_SECONDS = 2      -- a measurement stops early once the frame rate is steady
local MEASURE_MAX_SECONDS = 4
local MEASURE_MIN_FRAMES = 60

-- Group testing: settings are measured together, and a group that costs nothing marks
-- every setting in it free without testing each one. Only groups with a real cost are
-- split. Settings known to cost a lot on Macs are measured on their own from the start.
local GROUP_SIZE = 4
-- Josh, 2026-10-16: textures, view distance and environment detail are what players miss
-- most when lowered, so each gets its own measurement too, never a group's.
local MEASURE_ALONE = { renderscale = true, ssao = true, aa = true, pbrliquid = true, shadows = true, compute = true,
	textures = true, viewdistance = true, environment = true }
-- This run's measurement noise is the gap between two floor measurements taken back to
-- back (nothing changes between them), times this. A cost smaller than that is noise.
local NOISE_MULTIPLIER = 2

local MAX_VALIDATIONS = 6
-- How much faster the floor setup must have measured before a check that met nothing
-- recommends it instead (see FinishFastest).
local FLOOR_FALLBACK_MARGIN = 0.10
-- How much faster a ladder rung (see FinishFastest) must measure than the best setup that
-- kept its settings before those settings are given up: above the scene's own wobble
-- (Josh's Redridge check, 2026-10-16 14:57: everything at its lowest made 52.7 fps, the
-- rung that met the goal 53.8, so water, reflections and sun shafts went for noise).
local LADDER_MARGIN = 0.03

-- The goals themselves live in Core (ns.GOALS), so the presets can build from them.
Benchmark.GOALS = ns.GOALS
Benchmark.DEFAULT_GOAL = 60

-- While measuring: uncapped and unsynced so the true headroom shows, and nothing that
-- changes detail on its own. All restored afterwards.
-- VSync is left alone: changing it refreshes the game window, which can reset its size
-- (see Registry.RESOLUTION). With VSync on, measurements top out at the screen's refresh
-- rate, which is above every goal on a 120Hz ProMotion screen.
local CONDITIONS = {
	{ name = "useMaxFPS", value = 0 },
	{ name = "useTargetFPS", value = 0 },
	{ name = "DynamicRenderScale", value = 0 },
}

-- The settings the check tunes: only Standard Settings (the game's own Graphics menu).
-- Hidden settings left the check (Josh, 2026-10-18): one measurement spot can't price
-- effects that depend on the scene (water, reflections and draw distance cost almost
-- nothing with none in view), and the Standard sliders derive most of them anyway.
-- weight is Mac-ever's judgement of how much each one improves the picture when raised
-- from its floor to its top, on a Retina MacBook.
-- floor is the lowest level the check will recommend; levels, where given, are the only
-- values it will choose between.
-- extras are Josh's fixed Hidden values (2026-10-18), written at every level of their
-- slider (the slider re-derives them on every write) so every measurement includes them.
-- Secondary Lighting is deliberately never tuned by the check: raising it live crashed
-- M5 Max Macs on build 70338 (v0.2.2 reports, 2026-10-13). Nor is Depth Effects: switching
-- it to High mid-check crashed an M5 Pro's GPU driver twice on build 70790, and held still
-- the same check finished (2026-11-05). Both stay at the player's own value.
local DIMENSIONS = {
	-- Sharpness affects every pixel on a Retina screen, so render scale weighs by far the
	-- most and never goes below 85%: at 70% an M1 Pro picture looked bad in testing
	-- (2026-10-07), even though it ran much faster. The top level is 99%, not 100%: the
	-- game only runs FidelityFX (upscaling plus a sharpening pass) below 100%, so 99%
	-- looks crisper than native (community-known trick; Josh confirmed it on his Mac).
	{ id = "renderscale", name = "RenderScale", levels = { 0.50, 0.55, 0.60, 0.65, 0.70 }, weight = 40 }, -- fork: 50-70%, FidelityFX upscaling
	-- Fork: View Distance, Environment Detail and Ground Clutter are untuned too: they cost
	-- little frame rate, so the check never lowers them below the player's own values.
	-- Fork: textures cost about 3 fps and mostly use memory, so the check never lowers them:
	-- untuned settings stay at the player's own value (like Secondary Lighting).
	{ id = "textures", name = "graphicsTextureResolution", floor = 0, weight = 9, untuned = true },
	{ id = "viewdistance", name = "graphicsViewDistance", floor = 1, weight = 8, untuned = true },
	{ id = "environment", name = "graphicsEnvironmentDetail", floor = 1, weight = 7, untuned = true,
		extras = { { name = "doodadLodScale", value = 200 } } },
	{ id = "ssao", name = "graphicsSSAO", floor = 0, weight = 6 },
	{ id = "filtering", name = "textureFilteringMode", floor = 2, weight = 5 },
	{ id = "clutter", name = "graphicsGroundClutter", floor = 0, weight = 4, untuned = true,
		extras = { { name = "groundEffectDensity", value = 128 }, { name = "groundEffectDist", value = 200 } } },
	{ id = "liquid", name = "graphicsLiquidDetail", floor = 0, weight = 4 },
	{ id = "pbrliquid", name = "graphicsPBRLiquidDetail", floor = 0, weight = 4 },
	-- Anti-aliasing modes are different techniques, not a ladder, so their costs don't
	-- spread evenly: CMAA 2 cost about 56 fps on an M1 Pro (75.9 -> ~20 fps, Wetlands,
	-- 2026-10-07) while FXAA High is cheap. So each level is measured on its own
	-- (measureEach) and CMAA 2 is only chosen when the goal can afford it; it's only
	-- offered where the game supports it. quality: FXAA High keeps the value it had as
	-- the top level (6 of 8); CMAA 2 adds a little on top.
	{ id = "aa", name = "ffxAntiAliasingMode", levels = { 0, 2, 4 }, weight = 8, measureEach = true,
		quality = { [0] = 0, [2] = 0.75, [4] = 1 } },
	-- Particle Density's lowest is Low, never Disabled (it hides combat effects). The game
	-- numbers Low 0 on Macs with Secondary Lighting and 1 on others (build 70532).
	{ id = "particles", name = "graphicsParticleDensity", weight = 3,
		floor = function() return C_VideoOptions.IsSecondaryLightingSupported() and 0 or 1 end },
	-- Fork: Shadow Quality tops out at Good (2); High and above cost a lot for little gain.
	-- Shadow Quality skips Fair: on Fair, buildings and terrain stop casting shadows (thread 2354050, fault 9), so it
	-- looks worse than Low's cost suggests. Tuned only where Solver.TunesShadows says (M3 and
	-- later; Josh, 2026-11-07): other Macs get the fixed shadow values (Solver.FixedChanges).
	{ id = "shadows", name = "graphicsShadowQuality", levels = { 0, 2 }, weight = 8, shadowRule = true },
	{ id = "compute", name = "graphicsComputeEffects", floor = 0, weight = 4 },
}
Benchmark.DIMENSIONS = DIMENSIONS
Benchmark.MAX_VALIDATIONS = MAX_VALIDATIONS -- tests lower it to run out of attempts

-- Levels a dimension can take on this Mac, lowest first: the floor up to the highest
-- value the game says it supports. Nil if the setting isn't available.
local function Levels(dimension)
	local entry = Registry.Get(dimension.name)
	if not entry or not Registry.IsShown(entry) or CVars.Read(dimension.name) == nil then
		return nil
	end
	if dimension.levels then
		-- A copy, so dropping a refused level only lasts for this check. A choice setting
		-- only gets the values the game offers on this Mac (CMAA 2 isn't everywhere).
		local offered
		if entry.control == "choice" then
			offered = {}
			for _, choice in ipairs(Registry.GetChoices(entry)) do
				offered[tonumber(choice.value) or choice.value] = true
			end
		end
		local levels = {}
		for _, value in ipairs(dimension.levels) do
			if not offered or offered[value] then
				levels[#levels + 1] = value
			end
		end
		return #levels >= 2 and levels or nil
	end
	local top
	if entry.control == "slider" then
		top = Registry.GetSlider(entry).max
	else
		for _, choice in ipairs(Registry.GetChoices(entry)) do
			local value = tonumber(choice.value)
			if value and not Registry.UnsupportedReason(entry, value) and (not top or value > top) then
				top = value
			end
		end
	end
	local floor = dimension.floor
	if type(floor) == "function" then
		floor = floor()
	end
	if not top or top <= floor then
		return nil
	end
	local levels = {}
	for value = floor, top do
		levels[#levels + 1] = value
	end
	return levels
end

-- Dimensions the check tunes on this Mac, with their levels. Exported for the UI and tests.
function Benchmark.Plan()
	local plan = {}
	for _, dimension in ipairs(DIMENSIONS) do
		local allowed = not (Registry.IsResolution(dimension.name) and not CVars.ResolutionAllowed())
			and not (dimension.shadowRule and not Solver.TunesShadows())
			and not dimension.untuned
		local levels = allowed and Levels(dimension)
		if levels then
			plan[#plan + 1] = {
				id = dimension.id,
				name = dimension.name,
				weight = dimension.weight,
				levels = levels,
				extras = dimension.extras,
				quality = dimension.quality,
				measureEach = dimension.measureEach,
				entry = Registry.Get(dimension.name),
			}
		end
	end
	return plan
end

-- Run state ------------------------------------------------------------------------

local run
local pendingRestore

-- A setting's top level the game refuses (a researched maximum it won't accept) is
-- dropped for the rest of the check, so it's never recommended or applied.
local function DropRefusedLevels(results)
	for _, result in ipairs(results) do
		if result.status == "failed" and result.detail == "rejected" then
			for _, dim in ipairs(run.dims) do
				local top = dim.levels[#dim.levels]
				local refusedTop = Registry.Key(dim.name) == Registry.Key(result.name) and CVars.SameValue(tostring(top), result.value)
				if refusedTop and #dim.levels > 2 then
					table.remove(dim.levels)
					run.refused[#run.refused + 1] = { name = result.name, value = result.value }
				elseif refusedTop and #dim.levels == 2 then
					-- Nothing left to choose between: keep the setting where it is.
					dim.levels = { dim.levels[1] }
					run.refused[#run.refused + 1] = { name = result.name, value = result.value }
				end
			end
		end
	end
end

-- searching: a write of the check's own test values, whose refused levels are dropped;
-- putting the player's settings back never changes the plan.
local function Write(changes, searching)
	local results = CVars.Apply(changes, false)
	if results and searching and run then
		DropRefusedLevels(results)
	end
	return results ~= nil
end

-- Josh, 2026-10-16: on 70425 the game kept GI quality at the check's test value after a
-- finished check, though the restore had written it back (in tests it stayed). So a
-- second after putting settings back, each is read again and any that didn't stay is
-- written once more; one that still won't is named, with the way to fix it. Anything
-- chosen since (a preset, Apply Recommended) wins: then nothing is checked.
local VERIFY_DELAY = 1

local function NotBack(snapshot)
	local wrong = {}
	for _, item in ipairs(snapshot) do
		local now = C_CVar.GetCVar(item.name)
		if now ~= nil and not CVars.SameValue(Registry.Normalize(item.name, now), Registry.Normalize(item.name, item.value)) then
			wrong[#wrong + 1] = item
		end
	end
	return wrong
end

local function VerifyRestore(snapshot, attempt)
	local generation = CVars.generation
	C_Timer.After(VERIFY_DELAY, function()
		if Benchmark.IsRunning() or CVars.generation ~= generation or InCombatLockdown() then
			return
		end
		local wrong = NotBack(snapshot)
		if #wrong == 0 then
			return
		end
		if attempt < 2 then
			CVars.Apply(wrong, false)
			VerifyRestore(snapshot, attempt + 1)
			return
		end
		local names = {}
		for _, item in ipairs(wrong) do
			local entry = Registry.Get(item.name)
			names[#names + 1] = entry and ns.Text(entry.label) or item.name
		end
		ns.Print((L("System Check: %s didn't go back to how %s before the check. Restore Originals, or the game's own menu, puts %s back.")):format(
			table.concat(names, ", "), #names == 1 and ns.L("it was") or ns.L("they were"), #names == 1 and ns.L("it") or ns.L("them")))
	end)
end

local function Snapshot(names)
	local snapshot, seen = {}, {}
	for _, name in ipairs(names) do
		local key = Registry.Key(name)
		if not seen[key] then
			seen[key] = true
			local value = C_CVar.GetCVar(name)
			if value ~= nil then
				snapshot[#snapshot + 1] = { name = name, value = value }
			end
		end
	end
	return snapshot
end

-- Mac-ever doesn't change settings in combat, so a check stopped by combat finishes
-- putting things back as soon as combat ends. The settings to put back are also saved
-- (db.checkRestore) until they're back, so a reload or logout mid-check can't leave the
-- player on the check's test settings: the next login puts them back.
local function Restore()
	if run and run.snapshot then
		if Write(run.snapshot) then
			ns.db.checkRestore = nil
			VerifyRestore(run.snapshot, 1)
		else
			pendingRestore = run.snapshot
			ns.Print(L("System Check stopped for combat. Your settings go back as soon as combat ends."))
		end
		run.snapshot = nil
	end
end

ns.On("PLAYER_REGEN_ENABLED", function()
	if pendingRestore and Write(pendingRestore) then
		VerifyRestore(pendingRestore, 1)
		pendingRestore = nil
		ns.db.checkRestore = nil
		ns.Print(L("System Check: your settings are back as they were."))
	end
end)

ns.On("PLAYER_LOGIN", function()
	local saved = ns.db.checkRestore
	if type(saved) ~= "table" then
		ns.db.checkRestore = nil
		return
	end
	if Write(saved) then
		VerifyRestore(saved, 1)
		ns.db.checkRestore = nil
		ns.Print(L("The last System Check didn't finish, so your settings have been put back as they were."))
	else
		pendingRestore = saved
	end
end)

local function FloorChanges()
	local changes = {}
	for _, dim in ipairs(run.dims) do
		for _, change in ipairs(Solver.ChangesFor(dim, dim.levels[1])) do
			changes[#changes + 1] = change
		end
	end
	return changes
end

-- Keep my Hidden Settings (Solver.KeepsHidden, fixed for the run when it starts): every
-- write that moves a slider drops the check's own Hidden values and ends with the
-- player's, as they were at the start (run.kept), so each measurement runs with the
-- player's Hidden settings, whatever the sliders re-derive. report.changes stays as
-- Solver.ChangesFor makes it: applying it keeps them the same way (Solver.ForApply).
local function Measuring(changes)
	if not run.kept then
		return changes
	end
	return Solver.Keeping(changes, run.kept)
end

-- lowScale, when given, replaces the render scale level (lower resolution).
local function ChoiceChanges(choice, lowScale)
	local changes = {}
	for _, dim in ipairs(run.dims) do
		-- A level the game refused may have been dropped since this choice was made.
		local index = math.min(choice[dim.id], #dim.levels)
		local value = dim.levels[index]
		if lowScale and dim.id == "renderscale" then
			value = lowScale
		end
		for _, change in ipairs(Solver.ChangesFor(dim, value)) do
			changes[#changes + 1] = change
		end
	end
	return changes
end

-- Floor measurement nearest in time, so slow drift (heat, the long-session frame-rate
-- decay Forever has on Macs) isn't mistaken for a setting's cost.
-- The floor's frame time at a moment of the check, read off a straight line between the
-- floor measurements either side of it (they're taken at the start and the end): a
-- frame rate that drifts during the check would otherwise show up as a cost, or hide one.
local function FloorAt(time)
	local before, after
	for _, floor in ipairs(run.floors) do
		if floor.time <= time and (not before or floor.time > before.time) then
			before = floor
		end
		if floor.time >= time and (not after or floor.time < after.time) then
			after = floor
		end
	end
	if not (before and after) or after.time <= before.time then
		return before or after
	end
	local share = (time - before.time) / (after.time - before.time)
	local frameTime = before.frameTime + (after.frameTime - before.frameTime) * share
	return { time = time, frameTime = frameTime, fps = 1 / frameTime }
end

-- Smallest cost that isn't noise in this run (seconds per frame).
local function NoiseAt(frameTime)
	return math.max(Solver.Noise(frameTime), run.noise or 0)
end

local function Push(step)
	run.steps[#run.steps + 1] = step
end

-- How much the floor's frame rate changed from the first measurement to the last, in percent.
local function FloorDrift()
	local first, last = run.floors[1], run.floors[#run.floors]
	return (first and last) and (last.fps - first.fps) / first.fps * 100 or 0
end

local function PushMeasure(target, label, changes)
	if changes then
		Push({ kind = "apply", changes = changes, label = label })
	end
	Push({ kind = "settle", seconds = SETTLE_SECONDS, label = label })
	Push({ kind = "measure", target = target, label = label })
end

-- Steps to measure a group of settings at their maximum (everything else at the floor),
-- put them back, then judge the result. level: measure a single setting at that level
-- index instead of its maximum (settings measured level by level).
local function GroupSteps(group, level)
	local label
	if #group == 1 then
		label = L("Measuring the cost of ") .. ns.Text(group[1].entry.label)
	else
		label = (L("Measuring %d settings together")):format(#group)
	end
	local up, down = {}, {}
	for _, dim in ipairs(group) do
		for _, change in ipairs(Solver.ChangesFor(dim, dim.levels[level or #dim.levels])) do
			up[#up + 1] = change
		end
		for _, change in ipairs(Solver.ChangesFor(dim, dim.levels[1])) do
			down[#down + 1] = change
		end
	end
	local target = { group = group, level = level }
	return {
		{ kind = "apply", changes = Measuring(up), label = label },
		{ kind = "settle", seconds = SETTLE_SECONDS, label = label },
		{ kind = "measure", target = target, label = label },
		{ kind = "apply", changes = Measuring(down), label = label },
		{ kind = "assess", target = target, label = label },
	}
end

-- Inserts steps right after the current one (used when a group is split).
local function Insert(steps)
	for offset, step in ipairs(steps) do
		table.insert(run.steps, run.stepIndex + offset, step)
	end
end

local function BuildSteps()
	Push({ kind = "apply", changes = CONDITIONS, label = "Preparing" })
	PushMeasure("current", L("Measuring your current settings"))
	-- From the floor on, Hidden settings are where applying the result puts them (Josh,
	-- 2026-10-18): the reset set, then the sliders re-deriving theirs (Solver.WithReset),
	-- with the fixed shadow, glow and sharpness values on top (Josh, 2026-10-19), so every
	-- measurement includes them. Not the picture: it's taste, and costs nothing.
	-- After the current measurement, so that one is the player's real settings. They're
	-- in the snapshot, so they go back afterwards.
	-- Keep my Hidden Settings (run.kept): no reset and no fixed Hidden value, the player's
	-- own Hidden settings after the sliders instead (Josh, 2026-10-19).
	PushMeasure("floor", L("Measuring at the lowest settings"),
		Solver.WithReset(FloorChanges(), Solver.FixedChanges(true), run.kept))
	PushMeasure("floor", L("Measuring at the lowest settings again"))
	local grouped = {}
	for _, dim in ipairs(run.dims) do
		if dim.measureEach then
			dim.levelResults = {}
			for level = 2, #dim.levels do
				for _, step in ipairs(GroupSteps({ dim }, level)) do
					Push(step)
				end
			end
		elseif MEASURE_ALONE[dim.id] then
			for _, step in ipairs(GroupSteps({ dim })) do
				Push(step)
			end
		else
			grouped[#grouped + 1] = dim
		end
	end
	for start = 1, #grouped, GROUP_SIZE do
		local group = {}
		for index = start, math.min(start + GROUP_SIZE - 1, #grouped) do
			group[#group + 1] = grouped[index]
		end
		for _, step in ipairs(GroupSteps(group)) do
			Push(step)
		end
	end
	PushMeasure("floor", L("Re-measuring at the lowest settings"))
	Push({ kind = "recommend", label = L("Working out the best settings") })
end

-- A group costing nothing marks all its settings free; a single setting keeps its
-- measurement; otherwise the group is split in two and each half measured.
local function Assess(target)
	local summary = target.result
	if not summary then
		return -- not measured (e.g. too few frames): those settings keep their values
	end
	local floor = FloorAt(summary.time)
	local noise = NoiseAt(floor.frameTime)
	local group = target.group
	if target.level then
		group[1].levelResults[target.level] = summary
	elseif #group == 1 then
		group[1].result = summary
	elseif summary.frameTime - floor.frameTime <= noise then
		for _, dim in ipairs(group) do
			dim.result = { free = true, time = summary.time, frameTime = floor.frameTime, fps = floor.fps }
		end
	else
		local half = math.ceil(#group / 2)
		local first, second = {}, {}
		for index, dim in ipairs(group) do
			if index <= half then
				first[#first + 1] = dim
			else
				second[#second + 1] = dim
			end
		end
		local steps = GroupSteps(first)
		for _, step in ipairs(GroupSteps(second)) do
			steps[#steps + 1] = step
		end
		Insert(steps)
	end
end

local function AllAtTop(choice)
	for _, dim in ipairs(run.dims) do
		if choice[dim.id] < #dim.levels then
			return false
		end
	end
	return true
end

-- The frame rate with every tuned setting at its maximum. The check doesn't run everything
-- at maximum just to find out (Josh, 2026-10-11: less heat): when the recommendation is
-- everything at maximum, its own measurement is the answer; otherwise it's predicted from
-- what each setting cost on this Mac (predicted = true).
local function MaxResult()
	if run.validated and AllAtTop(run.choice) and not run.lowScale then
		return run.validated
	end
	local frameTime = run.floorTime + run.correction
	for _, dim in ipairs(run.dims) do
		if dim.cost then
			frameTime = frameTime + Solver.LevelCost(dim, #dim.levels)
		end
	end
	return { fps = 1 / frameTime, frameTime = frameTime, predicted = true }
end

local function Report()
	local report = {
		version = Solver.REPORT_VERSION,
		time = time(),
		zone = GetZoneText(),
		chip = ns.ChipNames(),
		goal = run.goal,
		tolerance = run.tolerance,
		headroom = Solver.Headroom(),
		uncapped = run.uncapped,
		keptHidden = run.keepHidden or nil, -- measured with the player's Hidden settings
		max = MaxResult(),
		current = run.current,
		floor = run.floors[1],
		reachable = run.reachable,
		validated = run.validated,
		floorTime = run.floorTime,
		correction = run.correction,
		noise = run.noise,
		refused = run.refused,
		lowResolution = run.low and {
			scale = run.lowScale,
			lowest = run.low.levels and run.low.levels[#run.low.levels],
			helpless = run.low.helpless,
		},
		settings = {},
	}
	report.drift = FloorDrift()
	for _, dim in ipairs(run.dims) do
		local current = run.currentValues[dim.id]
		local recommendedIndex = math.min(run.choice[dim.id], #dim.levels)
		local recommended = dim.levels[recommendedIndex]
		if run.lowScale and dim.id == "renderscale" then
			-- Below the floor: index 0 means "under the lowest level".
			recommendedIndex, recommended = 0, run.lowScale
		end
		report.settings[#report.settings + 1] = {
			id = dim.id,
			name = dim.name,
			current = current,
			recommended = recommended,
			-- positions in levels, compared to show Raise or Lower (a current value between levels
			-- counts as the nearest one; 0 is below the lowest, see above)
			currentIndex = Solver.NearestIndex(dim.levels, current),
			recommendedIndex = recommendedIndex,
			extras = dim.extras,
			-- frame rate this setting costs at its maximum, versus the floor
			costFps = dim.costFps,
			-- kept so presets can solve for other goals from the same measurements
			cost = dim.cost,
			costs = dim.costs,
			levels = dim.levels,
			quality = dim.quality,
			weight = dim.weight,
			keep = dim.keep,
		}
	end
	-- Graphics settings barely moving the frame rate means something else limits it here
	-- (most often the CPU), so quality can be raised at little or no cost.
	local biggest = 0
	for _, dim in ipairs(run.dims) do
		biggest = math.max(biggest, dim.costFps or 0)
	end
	local floorFps = report.floor and report.floor.fps or 0
	report.limited = floorFps > 0 and biggest < floorFps * 0.05
	report.changes = ChoiceChanges(run.choice, run.lowScale)
	if run.uncapped then
		-- The goal is a minimum, not a target: a fast Mac keeps every frame it can make.
		report.changes[#report.changes + 1] = { name = "useMaxFPS", value = 0 }
	else
		report.changes[#report.changes + 1] = { name = "useMaxFPS", value = 1 }
		report.changes[#report.changes + 1] = { name = "maxFPS", value = run.goal }
	end
	return report
end

local function Finish(reason)
	Restore()
	local finished = run
	run = nil
	finished.done = true
	finished.aborted = reason
	-- For Report a Problem: how the last check ended, and how far a stopped one got.
	ns.db.lastCheckEnd = {
		time = time(),
		zone = GetZoneText(),
		goal = finished.goal,
		uncapped = finished.uncapped,
		reason = reason,
		step = finished.status,
		progress = finished.progress,
		fps = not reason and finished.validated and finished.validated.fps or nil,
	}
	if not reason then
		finished.report = finished.reportData
		ns.db.lastCheck = finished.report
	end
	if finished.onDone then
		finished.onDone(finished)
	end
end

local Advance, FinishWith

local function Recommend()
	run.recommended = true
	local floor = run.floors
	for _, dim in ipairs(run.dims) do
		-- Measured level by level: each level's own cost over the floor. Its top level (after
		-- any refused one was dropped) is its cost at maximum, like any other setting.
		local costs
		if dim.levelResults then
			dim.result = dim.levelResults[#dim.levels]
			costs = { 0 }
			for level = 2, #dim.levels do
				local result = dim.levelResults[level]
				local base = result and FloorAt(result.time)
				if not (result and base) then
					costs = nil -- a level wasn't measured: spread the top's cost evenly instead
					break
				end
				costs[level] = math.max(0, result.frameTime - base.frameTime)
			end
		end
		local high = dim.result
		local base = high and FloorAt(high.time)
		if high and high.free then
			dim.cost, dim.costFps = 0, 0
		elseif high and base then
			dim.cost = math.max(0, high.frameTime - base.frameTime)
			dim.costFps = math.max(0, base.fps - high.fps)
			dim.costs = costs
		else
			-- Not measured: keep the current value rather than guess.
			dim.keep = 1
			local current = run.currentValues[dim.id]
			for index, value in ipairs(dim.levels) do
				if current and math.abs(value - current) < math.abs(dim.levels[dim.keep] - current) then
					dim.keep = index
				end
			end
		end
	end
	run.floorTime = floor[#floor].frameTime
	run.choice, run.reachable = Solver.Recommend(run.dims, run.floorTime, run.goal, run.tolerance, run.noise)

	-- Out of reach: always aim for the goal the player picked. Recommend has already
	-- lowered every costed setting to its floor (free ones stay at maximum), which is the
	-- fastest setup within the resolution and sharpness rules; the report says how close
	-- it got. (Josh, 2026-10-07: "it should still try hit 90fps as best it can".)
	PushMeasure("validate", L("Checking the recommended settings"), Measuring(ChoiceChanges(run.choice)))
	Push({ kind = "decide", label = L("Checking the recommended settings") })
end

local CORRECTION_DAMPING = 0.5

local function CopyChoice(choice)
	local copy = {}
	for id, index in pairs(choice) do
		copy[id] = index
	end
	return copy
end

local function ChoiceKey(choice)
	local parts = {}
	for _, dim in ipairs(run.dims) do
		parts[#parts + 1] = choice[dim.id]
	end
	return table.concat(parts, ",")
end

-- Frame time the cost model expects for a setup.
local function Predict(choice)
	local time = run.floorTime
	for _, dim in ipairs(run.dims) do
		if dim.cost then
			time = time + Solver.LevelCost(dim, choice[dim.id])
		end
	end
	return time
end

-- How good a setup looks, by Mac-ever's weights: what "best" means when comparing setups
-- that all meet the goal.
local function Quality(choice)
	local score = 0
	for _, dim in ipairs(run.dims) do
		score = score + dim.weight * Solver.LevelQuality(dim, choice[dim.id])
	end
	return score
end

local function Meets(measured)
	return measured ~= nil and measured.fps >= Solver.Required(run.goal, run.tolerance)
end

-- Ends the check on a setup and its measurement. Every Mac gets the same check: no
-- extra running time for a Mac that's warming up (Josh, 2026-10-11: if a MacBook Air
-- slows down in a long session, that's what it is).
function FinishWith(choice, measured)
	run.choice, run.validated = choice, measured
	-- Met or not by what was measured, never by the prediction (Josh's probe run,
	-- 2026-10-16: predicted 60, measured 35.6, reported as met).
	if measured then
		run.reachable = Meets(measured)
	end
	run.reportData = Report()
	run.finishing = true
	Push({ kind = "finish", label = "Finishing" })
end

local function PushLow(index)
	local low = run.low
	low.index = index
	local label = (L("Trying %d%% render scale")):format(math.floor(low.levels[index] * 100 + 0.5))
	PushMeasure("validate", label, Measuring(ChoiceChanges(low.choice, low.levels[index])))
	Push({ kind = "decideLow", label = label })
end

-- Goal still out of reach: if the player allows lower resolution, lower render scale
-- below the floor with everything else at its lowest, starting from the scale the model
-- predicts. Returns true if it queued that; false to finish as things are.
local function TryLowerResolution(measured)
	if run.low or Meets(measured) or not CVars.ResolutionAllowed() then
		return false
	end
	local perScale2, floorScale = Solver.ScaleModel(run.dims)
	local levels = Solver.LowScaleLevels()
	if not perScale2 or #levels == 0 then
		return false
	end
	-- The fastest setup within the rules: costed settings at their lowest, free ones at max.
	local fastest = Solver.Recommend(run.dims, run.floorTime + run.correction, math.huge, 0, run.noise)
	local floorTime = Predict(fastest) + run.correction
	local lowest = levels[#levels]
	local noise = Solver.Noise(floorTime)
	if perScale2 * (floorScale * floorScale - lowest * lowest) <= noise then
		-- Render scale barely changes the frame rate here, so lowering it can't help.
		run.low = { helpless = true }
		return false
	end
	run.low = { choice = fastest, levels = levels, tried = {} }
	local target = 1 / Solver.Required(run.goal, run.tolerance)
	PushLow(Solver.PickLowScale(levels, perScale2, floorScale, floorTime, target))
	return true
end

-- After measuring a low scale: step up while it meets the goal (sharper is better), down
-- while it doesn't, and end on the sharpest scale that met it (or the lowest tried).
local function DecideLow()
	local low, measured = run.low, run.validated
	local index = low.index
	low.tried[index] = measured
	if Meets(measured) then
		low.best = index
		if index > 1 and not low.tried[index - 1] then
			return PushLow(index - 1)
		end
	elseif not low.best and index < #low.levels and not low.tried[index + 1] then
		return PushLow(index + 1)
	end
	local final = low.best or index
	run.lowScale = low.levels[final]
	run.reachable = low.best ~= nil
	return FinishWith(low.choice, low.tried[final])
end

-- Every setting at its lowest: the floor setup, measured at the start and again later.
local function FloorChoice()
	local choice = {}
	for _, dim in ipairs(run.dims) do
		choice[dim.id] = 1
	end
	return choice
end

-- Clearly faster only (FLOOR_FALLBACK_MARGIN unless given): settings that each cost too
-- little to measure stay at their maximum even when together they cost a few percent.
local function ClearlyFaster(a, b, margin)
	return a ~= nil and (b == nil or a.fps >= b.fps * (1 + (margin or FLOOR_FALLBACK_MARGIN)))
end

-- Settings measured as free still cost a little each, and near a spot's limit those
-- add up (Josh's Redridge check, 2026-10-16: with them all at maximum it missed by 4 ms,
-- and the check fell straight to the floor, giving up view distance 10 -> 1). So they're
-- given back in batches, least valued first, each batch measured, and the first that
-- meets the goal while clearly faster (LADDER_MARGIN) wins: rung n lowers every free
-- setting weighted up to LADDER[n]. Render
-- scale is never part of it: sharpness is given up last, by the usual rules.
local LADDER = { 4, 5, 7, 9 }

local function LadderChoice(fastest, rung)
	local choice = CopyChoice(fastest)
	for _, dim in ipairs(run.dims) do
		if dim.id ~= "renderscale" and dim.cost and dim.weight <= LADDER[rung] and choice[dim.id] > 1 then
			choice[dim.id] = 1
		end
	end
	return choice
end

-- Measures the next ladder rung that changes anything. False when none is left.
local function PushLadder(fallback)
	for rung = fallback.rung + 1, #LADDER do
		local choice = LadderChoice(fallback.fastest, rung)
		local key = ChoiceKey(choice)
		if not run.tried[key] then
			run.tried[key] = true
			fallback.rung, fallback.choice = rung, choice
			PushMeasure("validate", L("Giving back the least visible settings"), Measuring(ChoiceChanges(choice)))
			Push({ kind = "decideFallback", label = L("Giving back the least visible settings") })
			return true
		end
	end
	return false
end

-- Nothing measured met the goal, yet the floor setup (everything at its lowest) measured
-- clearly faster: the model couldn't explain the miss (settings measured as free that add
-- up, or a frame rate that drifted during the check). Quality first: first the costly
-- settings at their lowest with the free ones at maximum, then the ladder, and only then
-- the floor.
local function FinishFastest(measured)
	local floor = run.floors[#run.floors]
	if ClearlyFaster(floor, measured) then
		local fastest = Solver.Recommend(run.dims, run.floorTime + run.correction, math.huge, 0, run.noise)
		local fallback = { fastest = fastest, rung = 0, best = measured and { choice = run.choice, measured = measured } }
		run.fallback = fallback
		local key = ChoiceKey(fastest)
		if not run.tried[key] then
			run.tried[key] = true
			fallback.choice = fastest
			PushMeasure("validate", L("Checking the fastest setup"), Measuring(ChoiceChanges(fastest)))
			Push({ kind = "decideFallback", label = L("Checking the fastest setup") })
			return
		end
		if PushLadder(fallback) then
			return
		end
	end
	if TryLowerResolution(measured) then
		return
	end
	if ClearlyFaster(floor, measured) then
		return FinishWith(FloorChoice(), floor)
	end
	return FinishWith(run.choice, measured)
end

-- After measuring a fallback setup (FinishFastest): done if it meets the goal, otherwise
-- the next rung of the ladder; with the ladder used up, lower resolution if allowed, then
-- the floor if it's clearly faster, else the best setup measured. A rung gives up
-- settings measured as free, so it only counts when it's clearly faster (LADDER_MARGIN)
-- than the best setup that kept them; otherwise its gain is noise and they stay.
local function DecideFallback()
	local measured, fallback = run.validated, run.fallback
	local best = fallback.best
	if fallback.rung == 0 then
		run.choice = fallback.choice
		if Meets(measured) then
			return FinishWith(fallback.choice, measured)
		end
		if measured and (not best or measured.fps > best.measured.fps) then
			fallback.best = { choice = fallback.choice, measured = measured }
		end
	elseif ClearlyFaster(measured, best and best.measured, LADDER_MARGIN) then
		run.choice = fallback.choice
		if Meets(measured) then
			return FinishWith(fallback.choice, measured)
		end
		fallback.best = { choice = fallback.choice, measured = measured }
	end
	if PushLadder(fallback) then
		return
	end
	best = fallback.best
	if best then
		run.choice = best.choice
	end
	if TryLowerResolution(best and best.measured or measured) then
		return
	end
	local floor = run.floors[#run.floors]
	if ClearlyFaster(floor, best and best.measured) then
		return FinishWith(FloorChoice(), floor)
	end
	return FinishWith(run.choice, best and best.measured or measured)
end

-- After measuring a setup. Settings rarely cost exactly the sum of their parts, so the
-- gap between measured and predicted frame time corrects the model, the setup is solved
-- again, and the new one is measured. Stops when the answer repeats or the attempts run
-- out, and always ends on the best measured setup that met the goal.
local function Decide()
	local measured = run.validated
	if not run.reachable and Meets(measured) then
		return FinishWith(run.choice, measured) -- out of reach by the model, met when measured
	end
	if not measured or not run.reachable then
		return FinishFastest(measured)
	end

	local meets = Meets(measured)
	if meets and (not run.best or Quality(run.choice) > Quality(run.best.choice)) then
		run.best = { choice = CopyChoice(run.choice), measured = measured }
	end
	run.tried[ChoiceKey(run.choice)] = true

	if run.validations < Benchmark.MAX_VALIDATIONS then
		-- Damped: correcting by the full error overshoots when the extra cost comes from two
		-- settings interacting, and disappears as soon as either is lowered.
		local err = measured.frameTime - (Predict(run.choice) + run.correction)
		run.correction = run.correction + CORRECTION_DAMPING * err
		local nextChoice = Solver.Recommend(run.dims, run.floorTime + run.correction, run.goal, run.tolerance, run.noise)
		if not run.tried[ChoiceKey(nextChoice)] then
			run.choice = nextChoice
			PushMeasure("validate", L("Fine-tuning the recommendation"), Measuring(ChoiceChanges(run.choice)))
			Push({ kind = "decide", label = L("Fine-tuning the recommendation") })
			return
		end
	end

	if run.best then
		return FinishWith(run.best.choice, run.best.measured)
	end
	return FinishFastest(measured)
end

-- Share of the check done: the timed steps (settling and measuring) finished, out of
-- those queued plus the checks of the recommendation still to come (about two before it
-- is worked out, one after). Split groups and extra checks add steps as the check runs,
-- so the share is recounted each step and never goes backwards.
local function UpdateProgress()
	local done, total = 0, 0
	for index, step in ipairs(run.steps) do
		if step.kind == "settle" or step.kind == "measure" then
			total = total + 1
			if index < run.stepIndex then
				done = done + 1
			end
		end
	end
	total = total + (run.finishing and 0 or run.recommended and 2 or 4)
	run.progress = math.max(run.progress, math.min(0.99, done / math.max(total, 1)))
end

function Advance()
	run.stepIndex = run.stepIndex + 1
	local step = run.steps[run.stepIndex]
	run.step = step
	run.elapsed = 0
	UpdateProgress()
	run.status = step.label
	if run.onUpdate then
		run.onUpdate(run)
	end

	-- Every floor measurement had too few frames: nothing to compare costs against.
	if (step.kind == "assess" or step.kind == "recommend") and #run.floors == 0 then
		return Finish("unmeasurable")
	end

	if step.kind == "apply" then
		if not Write(step.changes, true) then
			return Finish("combat")
		end
		return Advance()
	elseif step.kind == "recommend" then
		Recommend()
		return Advance()
	elseif step.kind == "decide" then
		run.validations = run.validations + 1
		Decide()
		return Advance()
	elseif step.kind == "decideLow" then
		DecideLow()
		return Advance()
	elseif step.kind == "decideFallback" then
		DecideFallback()
		return Advance()
	elseif step.kind == "assess" then
		Assess(step.target)
		return Advance()
	elseif step.kind == "measure" then
		step.sample = { frames = {}, total = 0 }
	elseif step.kind == "finish" then
		return Finish(nil)
	end
end

local function Record(step, summary)
	summary.time = run.clock
	local target = step.target
	if target == "current" then
		run.current = summary
	elseif target == "floor" then
		table.insert(run.floors, summary)
		if #run.floors == 2 then
			run.noise = NOISE_MULTIPLIER * math.abs(run.floors[2].frameTime - run.floors[1].frameTime)
		end
	elseif target == "validate" then
		run.validated = summary
	else
		target.result = summary
	end
end

-- Called every frame by the driver.
function Benchmark.Tick(elapsed)
	if not run then
		return
	end
	if InCombatLockdown() then
		return Benchmark.Stop("combat")
	end
	if (GetUnitSpeed("player") or 0) > 0 then
		return Benchmark.Stop("moved")
	end

	local step = run.step
	run.elapsed = run.elapsed + elapsed
	run.clock = run.clock + elapsed

	if step.kind == "settle" then
		if run.elapsed >= step.seconds then
			Advance()
		end
	elseif step.kind == "measure" then
		local sample = step.sample
		Solver.AddFrame(sample, elapsed)
		if run.elapsed >= MEASURE_MAX_SECONDS
			or (run.elapsed >= MEASURE_MIN_SECONDS and #sample.frames >= MEASURE_MIN_FRAMES and Solver.Steady(sample)) then
			local summary = Solver.Summarise(sample)
			if summary then
				Record(step, summary)
			end
			Advance()
		end
	end
end

function Benchmark.IsRunning()
	return run ~= nil
end

function Benchmark.Current()
	return run
end

-- Estimated length in seconds, for the intro text: current, two floors, the
-- groups (assuming most groups turn out free) and a check of the result.
function Benchmark.EstimateSeconds(plan)
	local dimensionCount = #plan
	local alone = 0
	for _, dim in ipairs(plan) do
		if dim.measureEach then
			alone = alone + #dim.levels - 1
		elseif MEASURE_ALONE[dim.id] then
			alone = alone + 1
		end
	end
	local groups = alone + math.ceil(math.max(0, dimensionCount - alone) / GROUP_SIZE) + 2
	local measures = 4 + groups + 1
	return measures * (SETTLE_SECONDS + (MEASURE_MIN_SECONDS + MEASURE_MAX_SECONDS) / 2)
end

-- Returns false and a reason if it can't start.
-- options.uncapped: the goal is a minimum; the result doesn't cap the frame rate.
function Benchmark.Start(goal, callbacks, tolerance, options)
	options = options or {}
	if run then
		return false, "running"
	end
	if InCombatLockdown() then
		return false, "combat"
	end
	local dims = Benchmark.Plan()
	if #dims == 0 then
		return false, "nothing"
	end

	local names = {}
	for _, condition in ipairs(CONDITIONS) do
		names[#names + 1] = condition.name
	end
	local currentValues = {}
	for _, dim in ipairs(dims) do
		names[#names + 1] = dim.name
		currentValues[dim.id] = tonumber(CVars.Read(dim.name))
		for _, extra in ipairs(dim.extras or {}) do
			names[#names + 1] = extra.name
		end
	end
	names[#names + 1] = "ResampleQuality"
	for _, name in ipairs(Registry.HiddenResetNames()) do
		names[#names + 1] = name
	end
	for _, change in ipairs(Solver.FixedChanges(true)) do
		names[#names + 1] = change.name
	end
	for _, name in ipairs(Solver.KeptNames()) do
		names[#names + 1] = name
	end
	local snapshot = Snapshot(names)

	-- Keep my Hidden Settings: the player's values at the start, from the snapshot. The
	-- measuring conditions still apply (Dynamic Render Scale stays off while measuring).
	local keepHidden = Solver.KeepsHidden()
	local kept
	if keepHidden then
		local values, conditions = {}, {}
		for _, item in ipairs(snapshot) do
			values[Registry.Key(item.name)] = item.value
		end
		for _, condition in ipairs(CONDITIONS) do
			conditions[Registry.Key(condition.name)] = true
		end
		kept = Solver.KeepChanges(values, conditions)
	end

	run = {
		goal = goal or Benchmark.DEFAULT_GOAL,
		tolerance = tolerance or Solver.DEFAULT_TOLERANCE,
		dims = dims,
		currentValues = currentValues,
		steps = {},
		stepIndex = 0,
		floors = {},
		refused = {},
		tried = {},
		correction = 0,
		validations = 0,
		progress = 0,
		clock = 0,
		elapsed = 0,
		snapshot = snapshot,
		onUpdate = callbacks and callbacks.onUpdate,
		onDone = callbacks and callbacks.onDone,
		uncapped = options.uncapped == true,
		keepHidden = keepHidden,
		kept = kept,
	}
	ns.db.checkRestore = run.snapshot
	BuildSteps()
	Advance()
	return true
end

-- reason: nil for a player Stop, or "combat" / "moved" / "loading" / "stopped".
function Benchmark.Stop(reason)
	if run then
		Finish(reason or "stopped")
	end
end

ns.On("PLAYER_REGEN_DISABLED", function()
	Benchmark.Stop("combat")
end)
ns.On("LOADING_SCREEN_ENABLED", function()
	Benchmark.Stop("loading")
end)
