local _, ns = ...

local Registry = ns.Registry

-- Every graphics change Mac-ever makes goes through this file. Before a CVar is first
-- changed, its pre-Mac-ever value is recorded so RestoreOriginals can always undo it.
local CVars = {}
ns.CVars = CVars

-- The client hands back floats with noise ("1.1000000238419" for 1.1).
local function SameValue(a, b)
	if a == b then
		return true
	end
	local na, nb = tonumber(a), tonumber(b)
	return na ~= nil and nb ~= nil and math.abs(na - nb) < 1e-4
end
CVars.SameValue = SameValue

-- Returns current value and default, or nil and the reason it can't be changed.
function CVars.Inspect(name)
	local value, default, _, _, isLocked, isSecure, isReadOnly = C_CVar.GetCVarInfo(name)
	if value == nil then
		return nil, "unknown"
	end
	if isSecure then
		return nil, "protected"
	end
	if isReadOnly or isLocked then
		return nil, "locked"
	end
	return value, default
end

-- Current value in comparable form (MSAAQuality reads back as "samples,coverage").
function CVars.Read(name)
	return Registry.Normalize(name, C_CVar.GetCVar(name))
end

-- Whether Mac-ever may change resolution-related settings (see Registry.RESOLUTION).
function CVars.ResolutionAllowed()
	return ns.db ~= nil and ns.db.ui.allowResolution == true
end

-- Returns a status ("changed", "unchanged", "adjusted", "failed"), a detail (the value
-- the client settled on for "adjusted", the reason for "failed") and the previous value.
-- force: when the value already matches, still call SetCVar (status stays "unchanged",
-- no original is recorded). The game re-derives a Standard slider's Hidden children on
-- every SetCVar, even a same-value one (Josh's probe, 2026-10-18, build 70450).
-- base: what the setting read before its batch, when an earlier write in the batch moved
-- it (a slider re-deriving it); its original and previous value are that, not the value
-- the slider left it at a moment ago.
local function Write(name, value, record, chosen, force, base)
	if Registry.NEVER_WRITE[Registry.Key(name)] then
		return "failed", "blocked"
	end
	-- record = false means putting back an earlier value (restore, undo, System Check
	-- clean-up), which is always allowed. So is a change the player asked for by name
	-- (chosen), such as Switch to Windowed: the lock is about Mac-ever choosing for them.
	if record and not chosen and Registry.IsResolution(name) and not CVars.ResolutionAllowed() then
		return "failed", "resolution"
	end
	local current, reason = CVars.Inspect(name)
	if current == nil then
		return "failed", reason
	end
	current = Registry.Normalize(name, current)
	local before = base or current
	local target = Registry.Normalize(name, value)
	if SameValue(current, target) then
		if force then
			pcall(C_CVar.SetCVar, name, value)
		end
		return "unchanged", nil, before
	end

	local originals = ns.db.originals
	local key = Registry.Key(name)
	-- Changed elsewhere since Mac-ever last set it: what it is now is the new "before
	-- Mac-ever" value, so Restore Originals never goes back past someone else's choice.
	local old = originals[key]
	if old and old.set ~= nil and not SameValue(before, old.set) then
		originals[key] = nil
	end
	local recorded = false
	if record and originals[key] == nil then
		originals[key] = { name = name, value = before }
		recorded = true
	end

	-- SetCVar raises an error for CVars that aren't public rather than returning false.
	local called, accepted = pcall(C_CVar.SetCVar, name, value)
	local actual = CVars.Read(name)

	-- What Mac-ever last set, so Restore Originals can tell its own changes from later
	-- ones made by the player or another addon (see CVars.Owns).
	if called and accepted and SameValue(actual, target) then
		if originals[key] then
			originals[key].set = actual
		end
		return "changed", nil, before
	end
	if actual ~= nil and not SameValue(actual, current) then
		-- The client clamped the value; it still changed, so the original stays recorded.
		if originals[key] then
			originals[key].set = actual
		end
		return "adjusted", actual, before
	end
	if recorded then
		originals[key] = nil
	end
	return "failed", "rejected", before
end

local function SortChanges(changes)
	local sorted = {}
	for i, change in ipairs(changes) do
		sorted[i] = change
	end
	table.sort(sorted, function(a, b)
		-- first: written ahead of everything else, Registry order among themselves.
		if (a.first == true) ~= (b.first == true) then
			return a.first == true
		end
		local orderA, indexA = Registry.SortKey(a.name)
		local orderB, indexB = Registry.SortKey(b.name)
		if orderA ~= orderB then
			return orderA < orderB
		end
		if indexA ~= indexB then
			return indexA < indexB
		end
		return a.name:lower() < b.name:lower()
	end)
	return sorted
end

-- Settings written after the rest of a batch, each stage on a later frame of its own.
-- The game crashed (ASSERT(!GxFrameStarted()), M1 Pro, 2026-10-07 17:16) when Restore
-- Originals switched HDR Output and renderer-restart settings, then restarted the
-- renderer, in the same moment as dozens of other changes. The stock menu never does that.
--   1: HDR Output (switches the picture's output format)
--   2: renderer settings (restart "gx")
-- then the window refresh, each on a later frame.
--
-- Mac-ever never restarts the renderer (Josh, 2026-10-11). Renderer settings take effect
-- the next time the game starts. v0.1.0 restarted it on every preset, because it changed
-- Triple Buffering and the Compatibility settings, and an M5 Pro player's
-- game crashed on every preset; the System Check, which restarts nothing, ran fine.
local function Stage(name)
	if Registry.Key(name) == "hdroutput" then
		return 1
	end
	if Registry.RestartKind(name) == "gx" then
		return 2
	end
	return 0
end

local function Later(callback)
	C_Timer.After(0, callback)
end

-- C_Timer only takes Lua functions: handing it the game's own UpdateWindow directly
-- fails with "Usage: C_Timer.After(seconds, callback)" (Forever 70338, 2026-10-13).
local function RefreshWindow()
	UpdateWindow()
end

-- changes: list of { name, value, chosen?, first?, force? }.
--   chosen: a change the player asked for by name, which the resolution lock lets through.
--   first: written before every change without it (Registry order among the first ones).
--     Registry order puts Hidden settings after Standard ones, but the game re-derives a
--     slider's Hidden children whenever the slider is set, so a Hidden reset must go first.
--   force: SetCVar is called even when the value already matches, so a slider already at
--     the right value still re-derives its Hidden children. Status stays "unchanged".
--     Josh's probe, 2026-10-18, build 70450: farclip under graphicsViewDistance read
--     "after set: 1234", "same: 10000", "at 5: 6000", "at 9: 10000".
-- Staged settings (HDR Output, renderer restart) ignore both flags.
--   kept: a Hidden setting kept at the player's value (Solver.KeepChanges); its result
--     carries it, for CVars.UndoFor and Instance Settings.
-- record = false skips recording originals (used when restoring them).
-- onResult(result), if given, runs after each write, so callers can keep their own
-- records accurate even if something later in the batch fails. It sees a first change's
-- status as written, before the end-of-batch correction below; only restores (record =
-- false, which get no correction) pass one.
-- Returns a list of { name, value, status, detail, previous } and the follow-up effects
-- ({ gx, window, client } booleans), or nil and "combat" if the player is in combat.
-- Staged settings come back with status "staged" and finish over the next few frames.
-- Counts batches of new choices (record isn't false): presets, Apply, the player's own
-- edits. Putting values back (restore, undo, the System Check) doesn't count, so the
-- check can tell whether anything new was chosen after it put settings back.
CVars.generation = 0

function CVars.Apply(changes, record, onResult)
	if InCombatLockdown() then
		return nil, "combat"
	end
	if record ~= false then
		CVars.generation = CVars.generation + 1
	end

	local results = {}
	local effects = {}
	local stages = { {}, {} }
	local function Track(result)
		local kind = Registry.RestartKind(result.name)
		if kind and CVars.DidChange(result) then
			effects[kind] = true
		end
	end

	-- A first change (the Hidden reset) is usually re-derived by a slider later in the same
	-- batch (Josh's probe, 2026-10-18): farclip 1234 is reset to 1000, then View Distance 9
	-- makes it 10000. So for a recorded batch its original is the player's value even when
	-- the reset itself changed nothing, and what Mac-ever set is the value at the end of
	-- the batch; otherwise Restore Originals would see 10000, not 1000, take it as someone
	-- else's change and leave it, or have nothing to restore. resets: key -> recorded here.
	-- The same goes for a change a slider earlier in the batch already moved (a fixed
	-- Hidden value, Josh 2026-10-19: Shadow Quality re-derives Shadow Mode, then Shadow
	-- Mode is set on top): its original and previous value are what it read before the
	-- batch (batchStart), and its status is what the whole batch did to it.
	local originals = ns.db and ns.db.originals
	local resets, resetResults = {}, {}
	local batchStart = {}
	if record ~= false then
		for _, change in ipairs(changes) do
			local key = Registry.Key(change.name)
			if batchStart[key] == nil and Stage(change.name) == 0 then
				batchStart[key] = CVars.Read(change.name) or false
			end
		end
	end
	-- Hidden settings the batch doesn't set but a slider in it may re-derive (Game Defaults,
	-- a Standard Settings edit): read first, and one the batch moved is
	-- recorded like a reset (its original what it read, set what it ended at), so Restore
	-- Originals puts it back with its slider, and a Hidden setting with no original is
	-- unchanged or the player's own (reviewer probes, 2026-10-19). Solver.KeptNames is the
	-- set the sliders re-derive.
	local watched = {}
	if record ~= false and originals and ns.Solver and ns.Benchmark then
		for _, name in ipairs(ns.Solver.KeptNames()) do
			local key = Registry.Key(name)
			local value = batchStart[key] == nil and CVars.Read(name)
			if value then
				watched[key] = { name = name, value = value }
			end
		end
	end

	for _, change in ipairs(SortChanges(changes)) do
		local value = tostring(change.value)
		local stage = Stage(change.name)
		local result
		if stage == 0 then
			local key = Registry.Key(change.name)
			local start = batchStart[key] or nil
			local moved = start ~= nil and not change.first and not SameValue(CVars.Read(change.name), start)
			local resetting = (change.first or moved) and record ~= false
			local before = resetting and originals[key]
			local status, detail, previous = Write(change.name, value, record ~= false, change.chosen, change.force,
				moved and start or nil)
			if resetting and status ~= "failed" then
				if status == "unchanged" then
					local old = originals[key]
					-- As in Write: changed elsewhere since Mac-ever set it, so that's the original now.
					if old and old.set ~= nil and not SameValue(previous, old.set) then
						originals[key] = nil
					end
					if originals[key] == nil and previous ~= nil then
						originals[key] = { name = change.name, value = previous }
					end
				end
				if originals[key] then
					resets[key] = originals[key] ~= before
				end
			end
			result = { name = change.name, value = value, status = status, detail = detail, previous = previous,
				kept = change.kept }
			if resetting and status ~= "failed" then
				resetResults[#resetResults + 1] = result
			end
			if onResult then
				onResult(result)
			end
		else
			-- Decide now whether it will change, so the caller can report and undo it.
			local current, reason = CVars.Inspect(change.name)
			current = current and Registry.Normalize(change.name, current)
			if current == nil then
				result = { name = change.name, value = value, status = "failed", detail = reason }
			elseif SameValue(current, Registry.Normalize(change.name, value)) then
				result = { name = change.name, value = value, status = "unchanged", previous = current }
				if onResult then
					onResult(result)
				end
			else
				result = { name = change.name, value = value, status = "staged", previous = current, chosen = change.chosen }
				table.insert(stages[stage], result)
			end
		end
		results[#results + 1] = result
		Track(result)
	end

	-- A reset's status is what the whole batch did to it, so counts ("Changed N settings",
	-- the keep countdown, "Your settings already match") and undo lists are honest: reset
	-- from 10000 to 1000, then re-derived back to 10000, is no change; already at its
	-- default, then re-derived away from it, is one (undone to its previous value).
	for _, result in ipairs(resetResults) do
		local final = CVars.Read(result.name)
		if final ~= nil and result.previous ~= nil then
			local same = SameValue(final, result.previous)
			if same and CVars.DidChange(result) then
				result.status, result.detail = "unchanged", nil
			elseif not same and result.status == "unchanged" then
				result.status = "changed"
			end
		end
	end

	-- What the batch left each reset setting at. One that ended where the player had it is
	-- no change at all, so a record made by this batch is dropped.
	for key, recordedHere in pairs(resets) do
		local original = originals[key]
		local final = original and CVars.Read(original.name)
		if final ~= nil then
			if recordedHere and SameValue(final, original.value) then
				originals[key] = nil
			else
				original.set = final
			end
		end
	end

	-- What the batch's sliders did to the watched Hidden settings (see above).
	for key, item in pairs(watched) do
		local final = CVars.Read(item.name)
		if final ~= nil and not SameValue(final, item.value) then
			local old = originals[key]
			-- As in Write: changed elsewhere since Mac-ever set it, so that's the original now.
			if old and old.set ~= nil and not SameValue(item.value, old.set) then
				originals[key] = nil
			end
			if originals[key] == nil then
				originals[key] = { name = item.name, value = item.value }
			end
			if SameValue(final, originals[key].value) then
				originals[key] = nil -- back where it was before Mac-ever
			else
				originals[key].set = final
			end
		end
	end

	local function Finish()
		if effects.window then
			Later(RefreshWindow)
		end
	end

	local function RunStage(index)
		-- Combat can start in the frames between stages: finish once it ends.
		if InCombatLockdown() then
			ns.OnceOutOfCombat(function()
				RunStage(index)
			end)
			return
		end
		local stage = stages[index]
		if not stage then
			return Finish()
		end
		for _, result in ipairs(stage) do
			result.status, result.detail = Write(result.name, result.value, record ~= false, result.chosen)
			if result.status == "failed" then
				ns.Print(("%s wasn't changed: %s"):format(result.name, ns.REASONS[result.detail] or result.detail))
			end
			if onResult then
				onResult(result)
			end
		end
		Later(function()
			RunStage(index + 1)
		end)
	end

	if #stages[1] > 0 or #stages[2] > 0 then
		Later(function()
			RunStage(1)
		end)
	elseif effects.window then
		Later(RefreshWindow)
	end
	return results, effects
end

-- Whether a result changed (or will change, once staged) the setting.
function CVars.DidChange(result)
	return result.status == "changed" or result.status == "adjusted" or result.status == "staged"
end

-- Undo list for a batch: the previous value of everything that actually changed.
-- Keep my Hidden Settings (Solver.KeepChanges, kept): a kept Hidden setting goes in even
-- when the batch left it as it was, since undoing a slider re-derives it again; written
-- after the sliders, it puts the player's value back (a no-op when nothing moved it).
function CVars.UndoFor(results)
	local undo = {}
	for _, result in ipairs(results) do
		if (CVars.DidChange(result) or (result.kept and result.status ~= "failed")) and result.previous ~= nil then
			undo[#undo + 1] = { name = result.name, value = result.previous }
		end
	end
	return undo
end

-- Whether a recorded setting is still as Mac-ever left it. Once the player (in the
-- game's menu) or another addon has changed it, it's theirs, and Restore Originals leaves
-- it alone (Josh, 2026-10-11: undo only what Mac-ever did, for fewer clashes with other
-- addons). Records from before Mac-ever kept what it set (develop before 2026-10-11)
-- count as Mac-ever's.
function CVars.Owns(original)
	return original.set == nil or SameValue(CVars.Read(original.name), original.set)
end

-- Puts every setting Mac-ever has changed, and nothing has changed since, back to its
-- pre-Mac-ever value. Settings changed since by the player or another addon are left as
-- they are and named in chat. Entries that can't be restored yet stay recorded so a later
-- attempt can finish the job.
function CVars.RestoreOriginals()
	if InCombatLockdown() then
		return nil, "combat"
	end
	local originals = ns.db.originals
	local changes, skipped = {}, {}
	for key, original in pairs(originals) do
		if Registry.NEVER_WRITE[key] then
			-- Left at whatever the game has now: writing it is what's dangerous.
			originals[key] = nil
		elseif not CVars.Owns(original) then
			originals[key] = nil
			skipped[#skipped + 1] = original.name
		else
			changes[#changes + 1] = { name = original.name, value = original.value }
		end
	end
	if #skipped > 0 then
		table.sort(skipped)
		ns.Print(("Left as they are, because they were changed after Mac-ever (in the game's menu or by another addon): %s."):format(
			table.concat(skipped, ", ")))
	end

	-- Putting a slider back re-derives its Hidden settings (Josh, 2026-10-19). One with no
	-- original to restore (kept by Keep my Hidden Settings, or changed since by the player)
	-- holds its value now: written back after the sliders, it's no change, so not counted.
	local held = {}
	if #changes > 0 then
		local restoring = {}
		for _, change in ipairs(changes) do
			restoring[Registry.Key(change.name)] = true
		end
		for _, name in ipairs(ns.Solver.KeptNames()) do
			local key = Registry.Key(name)
			local value = not restoring[key] and CVars.Inspect(name)
			if value then
				changes[#changes + 1] = { name = name, value = value }
				held[key] = value
			end
		end
	end

	-- Each record is cleared the moment it's restored, so a failure partway through
	-- leaves an accurate list of what still needs restoring.
	local results, effects = CVars.Apply(changes, false, function(result)
		-- "unknown" means a patch removed the CVar, so there's nothing left to restore.
		if result.status == "changed" or result.status == "unchanged" or result.detail == "unknown" then
			originals[Registry.Key(result.name)] = nil
		end
	end)
	if not results then
		return results, effects
	end
	-- A held setting back at its value isn't a restore: left out of the results.
	local restored = {}
	for _, result in ipairs(results) do
		local value = held[Registry.Key(result.name)]
		if not (value and SameValue(CVars.Read(result.name), Registry.Normalize(result.name, value))) then
			restored[#restored + 1] = result
		end
	end
	return restored, effects
end

-- Resets the stock Graphics menu settings (Standard Settings) to the client defaults,
-- like the menu's own Defaults button. Hidden and discovered settings are never touched:
-- the game derives many of them from the menu settings, and resetting them all at once
-- is what preceded the screen corruption on 2026-10-07. Advanced settings are left alone.
-- Originals are recorded, so RestoreOriginals undoes this.
function CVars.DefaultChanges()
	local changes = {}
	for _, entry in ipairs(Registry.entries) do
		local group = Registry.GetGroup(entry.group)
		if group and group.tab == "standard" and entry.risk ~= "advanced" then
			local value, default = CVars.Inspect(entry.name)
			if value ~= nil and default ~= nil then
				changes[#changes + 1] = { name = entry.name, value = Registry.Normalize(entry.name, default) }
			end
		end
	end
	return changes
end

function CVars.ResetToDefaults()
	return CVars.Apply(CVars.DefaultChanges(), true)
end

-- Returns the CVars Mac-ever has changed as a sorted list of { name, original, current }.
-- Settings Mac-ever has changed and that are still as it left them: what Restore
-- Originals would put back.
function CVars.ListChanged()
	local list = {}
	for _, original in pairs(ns.db.originals) do
		if CVars.Owns(original) then
			list[#list + 1] = {
				name = original.name,
				original = original.value,
				current = CVars.Read(original.name),
			}
		end
	end
	table.sort(list, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return list
end
