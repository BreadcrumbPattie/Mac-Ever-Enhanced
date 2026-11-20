local _, ns = ...
local L = ns.L

local UI = ns.UI
local Benchmark = ns.Benchmark
local Solver = ns.Solver
local Registry = ns.Registry
local Text = ns.Text

local ROW_HEIGHT = 26
local SIDE = 14
local DRIFT_WARNING_PERCENT = 8

-- Results columns as shares of the width, so they fit any window size and never overlap
-- (legibility review, 2026-10-07): setting | now | recommended | cost. The setting
-- column is the widest, for the description; anything cut off is in the row's tooltip.
local COLUMNS = {
	setting = { x = 0, width = 0.40 },
	now = { x = 0.42, width = 0.17 },
	recommended = { x = 0.61, width = 0.22 },
	cost = { width = 0.15 },
}
local STRIPE_ALPHA = 0.04 -- every other row, so a row reads across at a glance
local TILE_HEIGHT = 74
local TILE_GAP = 10

-- Josh, 2026-10-16: the page read as cluttered, with warnings everywhere. It's three
-- numbered steps top to bottom (choose a goal, run, result), labels in one aligned
-- column, one page that scrolls as a whole. The risk is on Run's tooltip.
local LABEL_GAP = 12
local ROW_GAP = 8
local STEP_GAP = 18
local SETUP_BUTTON_WIDTH = 140

local HOW_TO = L("Stand still somewhere busy, out of combat.")

-- Shared with setup's frame-rate picker, so the same goal reads the same everywhere.
local GOAL_LABELS = {}
for _, goal in ipairs(ns.GOALS) do
	GOAL_LABELS[goal] = goal .. " fps"
end

UI.GOAL_LABELS = GOAL_LABELS

local function FormatTime(seconds)
	return seconds >= 90 and ("about %d minutes"):format(math.floor(seconds / 60 + 0.5)) or ("about %d seconds"):format(seconds)
end

-- How long a check with the current plan takes, in words (for the setup's last step).
function UI.CheckDuration()
	return FormatTime(Benchmark.EstimateSeconds(Benchmark.Plan()))
end

local function Describe(name, value)
	local entry = Registry.Get(name)
	if value == nil then
		return "?"
	end
	if entry.control == "choice" then
		for _, choice in ipairs(Registry.GetChoices(entry)) do
			if tonumber(choice.value) == tonumber(value) then
				return Text(choice.label)
			end
		end
	elseif entry.control == "slider" then
		local spec = Registry.GetSlider(entry)
		if spec.format then
			return spec.format(tonumber(value))
		end
	end
	return tostring(value)
end

-- The result in plain words: a headline on the goal, then one sentence on what Apply
-- Recommended does and, if the goal is out of reach, what the player could do next.
local GREEN, ORANGE = UI.HEX.green, UI.HEX.orange

local function Percent(scale)
	return math.floor(scale * 100 + 0.5)
end

local function Verdict(report)
	local goal = report.goal
	local measured = report.validated and report.validated.fps
	local low = report.lowResolution

	if report.reachable and measured then
		local allMax = true
		for _, setting in ipairs(report.settings) do
			if setting.recommendedIndex ~= #setting.levels then
				allMax = false
			end
		end
		local allowance = ""
		if measured < goal - 0.5 then
			allowance = (" That's within the dip you allowed (down to %.0f fps)."):format(Solver.Accepts(goal, report.tolerance))
		end
		if low and low.scale then
			return (GREEN .. "%d fps goal met by lowering resolution|r"):format(goal),
				(L("Measured %.0f fps with render scale at %d%% and every other setting at its lowest, so the 3D world looks softer.%s Apply Recommended to use this.")):format(
					measured, Percent(low.scale), allowance)
		elseif allMax then
			return (GREEN .. L("Everything at maximum holds %d fps|r")):format(goal),
				(L("Measured %.0f fps with every setting at its highest. Apply Recommended to use them.")):format(measured)
		end
		return (GREEN .. "%d fps goal met, graphics kept high|r"):format(goal),
			(L("Measured %.0f fps. Only the settings marked Lower are reduced.%s Apply Recommended to use these settings.")):format(
				measured, allowance)
	end

	local best = measured or (report.floor and report.floor.fps) or 0
	local headline = (ORANGE .. "%d fps is out of reach here|r"):format(goal)
	if low and low.scale then
		return headline, (L("Your Mac managed %.0f fps with render scale down to %d%% and every other setting at its lowest. Apply Recommended to get that, or pick a lower goal.")):format(
			best, Percent(low.scale))
	elseif low and low.helpless then
		return headline, (L("Your Mac managed %.0f fps at best. Lowering resolution wouldn't help: something else limits the frame rate here, most often the CPU. Apply Recommended to get that, or pick a lower goal.")):format(best)
	end
	local nextStep = ns.db.ui.allowResolution
		and " You've allowed lower resolution since: run the check again to use it."
		or " To go further, turn on \"" .. UI.RESOLUTION_SWITCH_LABEL .. "\" and run the check again."
	return headline, (L("Your Mac managed %.0f fps at best, with every setting at the lowest that keeps the picture sharp (render scale 85%%). Apply Recommended to get that, or pick a lower goal.%s")):format(
		best, nextStep)
end

-- What Apply Recommended does for this result, for its tooltip.
local function ApplyLines(report)
	local lines = { { text = L("Applies the recommended settings. Nothing changes until you press it.") } }
	if report.uncapped then
		lines[#lines + 1] = { text = L("No frame-rate cap: your Mac runs as fast as it can.") }
	else
		lines[#lines + 1] = { text = (L("Caps the frame rate at %d fps, so your Mac doesn't work harder than it needs to.")):format(report.goal) }
	end
	if report.lowResolution and report.lowResolution.scale then
		lines[#lines + 1] = { text = L("Render scale goes below 85%: the 3D world looks softer, but text and the interface stay sharp."), color = UI.COLORS.orange }
	end
	lines[#lines + 1] = { text = (L("You get %d seconds to keep the settings or switch back.")):format(UI.KEEP_SECONDS), color = UI.COLORS.green }
	return lines
end

UI.CheckVerdict = Verdict -- exported for tests

local function FillTiles(tiles, report)
	local now, recommended, max = tiles[1], tiles[2], tiles[3]
	local current = report.current
	now.Value:SetText(current and ("%.0f fps"):format(current.fps) or "?")
	now.Sub:SetText(current and ("%.0f fps in the slowest moments"):format(current.low) or "not measured")
	now.tip = L("Measured at the start of the check, with your settings exactly as they were. The slowest moments are the slowest 1% of frames, which is what stutter feels like.")

	local measured = report.validated
	recommended.Value:SetText(measured and ("%.0f fps"):format(measured.fps) or "?")
	-- Met or not in words too, not by colour alone.
	recommended.Value:SetTextColor((report.reachable and UI.COLORS.green or UI.COLORS.orange):GetRGB())
	recommended.Sub:SetText(((report.reachable and "goal met: " or "below the goal: ")
		.. (report.uncapped and "at least %d fps" or "%d fps")):format(report.goal))
	recommended.tip = L("Measured with the recommended settings in place, before your own settings were put back.")
		.. (report.uncapped and " Applying doesn't cap the frame rate." or " Applying caps the frame rate at the goal.")

	max.Value:SetText(report.max and ("%.0f fps"):format(report.max.fps) or "?")
	local predicted = report.max and report.max.predicted
	max.Sub:SetText(predicted and "predicted: everything at maximum" or "measured: everything at maximum")
	max.tip = predicted
		and L("Predicted from what each setting cost on your Mac: what everything at maximum would give you here. The check doesn't run everything at maximum just to measure it, so your Mac stays cooler.")
		or L("Measured with every setting Mac-ever tunes at its highest, which is what the check recommended.")
end

local function Notes(report)
	local lines = {}
	if report.refused and #report.refused > 0 then
		local names = {}
		for _, refused in ipairs(report.refused) do
			local entry = Registry.Get(refused.name)
			names[#names + 1] = ("%s %s"):format(entry and Text(entry.label) or refused.name, refused.value)
		end
		lines[#lines + 1] = UI.Colored("muted", (L("The game wouldn't accept %s, so those levels were left out.")):format(table.concat(names, ", ")))
	end
	local helpless = report.lowResolution and report.lowResolution.helpless
	if report.limited and not helpless then
		lines[#lines + 1] = UI.Colored("blue", L("Graphics settings barely change your frame rate here (something else, most often the CPU, is the limit), so quality costs little."))
	end
	if math.abs(report.drift or 0) >= DRIFT_WARNING_PERCENT then
		lines[#lines + 1] = UI.Colored("orange", (L("Your frame rate drifted %+.0f%% during the check, so the numbers are less reliable. Try Reload First and run it again.")):format(report.drift))
	end
	return table.concat(lines, "\n")
end

UI.CheckNotes = Notes -- exported for tests

-- Opens this tab and runs the check with the saved goal (used by the setup). Setup can
-- come before the window exists, so opening the tab builds it first.
local runFromSetup

function UI.StartSystemCheck()
	UI.SelectTab(L("System Check"))
	if runFromSetup then
		runFromSetup()
	end
end

UI.RegisterTab(L("System Check"), function(panel, frame)
	-- The whole page scrolls, so the result gets the window's full width and height.
	local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -2)
	scroll:SetPoint("BOTTOMRIGHT", -22, 2)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	local goldR, goldG, goldB = UI.COLORS.gold:GetRGB()

	-- A numbered step: a gold divider, then its title.
	local function Step(number, title)
		local step = { Line = content:CreateTexture(nil, "ARTWORK") }
		step.Line:SetHeight(1)
		step.Line:SetColorTexture(goldR, goldG, goldB, 0.3)
		step.Title = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		step.Title:SetJustifyH("LEFT")
		step.Title:SetWordWrap(false)
		step.title = ("%d.  %s"):format(number, title)
		step.Title:SetText(step.title)
		return step
	end

	-- The player's setup (which Mac, and the frame rate), with a way to change it.
	local setup = CreateFrame("Frame", nil, content)
	setup:SetHeight(24)
	setup.Text = setup:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	setup.Text:SetPoint("LEFT")
	setup.Text:SetPoint("RIGHT", -(SETUP_BUTTON_WIDTH + 10), 0)
	setup.Text:SetJustifyH("LEFT")
	setup.Text:SetWordWrap(false)
	setup.Button = CreateFrame("Button", nil, setup, "UIPanelButtonTemplate")
	setup.Button:SetSize(SETUP_BUTTON_WIDTH, 22)
	setup.Button:SetPoint("RIGHT")
	setup.Button:SetScript("OnClick", ns.Safe(UI.ShowSetup))
	UI.SetTooltip(setup.Button, "Setup", {
		{ text = L("Which Mac you have and the frame rate you want. You can also type /macever setup.") },
	})

	-- Step 1: the goal, how far it may dip, and the two switches under them.
	local step1 = Step(1, L("Choose your goal"))

	local goalLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	goalLabel:SetText("Goal")
	local goal = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
	goal:SetWidth(280)
	goal:SetupMenu(function(_, root)
		for _, fps in ipairs(Benchmark.GOALS) do
			root:CreateRadio(GOAL_LABELS[fps], function()
				return (ns.db.ui.goal or Benchmark.DEFAULT_GOAL) == fps
			end, function()
				UI.ConfirmGoal(fps, function()
					ns.db.ui.goal = fps
					goal:GenerateMenu() -- the player may have accepted after the menu closed
				end)
			end)
		end
	end)
	UI.SetTooltip(goal, "Goal", {
		{ text = L("The frame rate the System Check tunes for. Graphics stay as high as that frame rate allows.") },
		{ text = L("Higher goals suit high-refresh displays; lower ones keep your Mac cooler and quieter."), color = UI.COLORS.grey },
	})

	-- How far below the goal the frame rate may dip to keep graphics higher.
	local TOLERANCE_LABELS = {
		[0] = L("Hold the goal strictly"),
		[0.10] = L("May dip up to 10% below"),
		[0.15] = L("May dip up to 15% below (recommended)"),
		[0.25] = L("May dip up to 25% below"),
	}
	local toleranceLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	toleranceLabel:SetText("Quality")
	local tolerance = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
	tolerance:SetWidth(280)
	tolerance:SetupMenu(function(_, root)
		for _, value in ipairs(Solver.TOLERANCES) do
			root:CreateRadio(TOLERANCE_LABELS[value], function()
				return (ns.db.ui.tolerance or Solver.DEFAULT_TOLERANCE) == value
			end, function()
				ns.db.ui.tolerance = value
			end)
		end
	end)
	UI.SetTooltip(tolerance, "Quality", {
		{ text = L("How far below your goal the frame rate may dip, so graphics can stay higher. Holding the goal strictly lowers more settings.") },
	})

	-- Headroom (fork addition): graphics are budgeted for goal x headroom uncapped fps while
	-- the cap stays at the goal, so the GPU isn't pinned at 100% and the fans stay quiet.
	local HEADROOM_LABELS = {
		[1.0] = L("Off (use all the GPU allows)"),
		[1.25] = "x1.25 (a little cooler)",
		[1.5] = "x1.5 (cool)",
		[1.6] = "x1.6 (cool and quiet, recommended)",
		[1.75] = "x1.75 (coolest)",
	}
	local headroomLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	headroomLabel:SetText("Headroom")
	local headroom = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
	headroom:SetWidth(280)
	headroom:SetupMenu(function(_, root)
		for _, value in ipairs(Solver.HEADROOMS) do
			root:CreateRadio(HEADROOM_LABELS[value], function()
				return Solver.Headroom() == value
			end, function()
				ns.db.ui.headroom = value
			end)
		end
	end)
	UI.SetTooltip(headroom, "Headroom", {
		{ text = L("The frame rate stays capped at your goal, but graphics are only raised until the Mac could still reach goal x headroom without the cap (60 fps x 1.6 = about 96). The GPU then has spare time every frame, so it runs cooler and the fans stay quiet. Run the System Check again after changing it.") },
	})

	local capSwitch = UI.CreateUncappedSwitch(content, function()
		return ns.db.ui.uncapped
	end, function(on)
		ns.db.ui.uncapped = on or nil
	end)
	local resolutionSwitch = UI.CreateResolutionSwitch(content)

	-- Keep my Hidden Settings (Josh, 2026-10-19; label and tooltip approved, verbatim): the
	-- check and its results leave the Hidden Settings as the player set them
	-- (Solver.KeepsHidden). Only once a System Check of this version has finished (on the
	-- first, everything is at the game's defaults anyway) and not while one runs (the check
	-- fixes it when it starts): greyed then, its tooltip still shown.
	local KEEP_LABEL = L("Keep my Hidden Settings")
	-- Ticking it warns first, like a goal above the Mac's limit (Josh, 2026-11-07; verbatim).
	local KEEP_WARNING = L("Mac-ever can't guarantee all changes to hidden settings will result in improvements to graphics or performance. The preset may not work perfectly without using default hidden settings.")
	local keepSwitch = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	keepSwitch.Text:SetFontObject("GameFontHighlightSmall")
	keepSwitch.Text:SetText(KEEP_LABEL)
	keepSwitch:SetMotionScriptsWhileDisabled(true)
	function keepSwitch:Update()
		local open = Solver.HasCurrentCheck() and not Benchmark.IsRunning()
		self:SetChecked(ns.db.ui.keepHidden == true)
		self:SetEnabled(open)
		self.Text:SetFontObject(open and "GameFontHighlightSmall" or "GameFontDisableSmall")
	end
	keepSwitch:SetScript("OnShow", keepSwitch.Update)
	keepSwitch:SetScript("OnClick", ns.Safe(function(self)
		if not self:IsEnabled() then
			self:Update()
			return
		end
		if self:GetChecked() then
			self:SetChecked(false) -- until the player accepts
			UI.Confirm("Warning", KEEP_WARNING, L("I Accept"), function()
				ns.db.ui.keepHidden = true
				UI.Refresh()
			end)
			return
		end
		ns.db.ui.keepHidden = nil
		UI.Refresh()
	end))
	UI.SetTooltip(keepSwitch, KEEP_LABEL, {
		{ text = L("The System Check and its results leave your Hidden Settings as they are, and measure with them. Available after your first System Check.") },
	})

	-- Step 2: how to stand, Run and Reload First, then progress and status.
	local step2 = Step(2, L("Run the check"))
	local howTo = UI.Muted(content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	howTo:SetJustifyH("LEFT")
	howTo:SetText(HOW_TO)

	-- Fixed text, always shown (Josh, 2026-10-18; amended for Keep my Hidden Settings,
	-- 2026-10-19): what the check does to the Hidden Settings.
	local caveat = UI.Muted(content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	caveat:SetJustifyH("LEFT")
	caveat:SetText(L("The System Check sets Hidden Settings back to the game's defaults and tunes only Standard Settings, unless Keep my Hidden Settings is on."))

	local run = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	run:SetSize(170, 24)
	UI.SetTooltip(run, L("Run System Check"), function()
		if Benchmark.IsRunning() then
			return { { text = L("Stops the check and puts your settings back.") } }, "Stop"
		end
		return {
			{ text = L("Finds the best-looking settings your Mac can run at your goal: it measures what each setting costs where you stand, then puts your settings back exactly as they were. Nothing changes until you apply the result.") },
			{ text = L("Settings switch quickly while it runs, so stutter and glitches are normal and, rarely, the game crashes. The frame-rate cap is off, so your Mac will get warm."), color = UI.COLORS.orange },
			{ text = L("It measures the display mode you play in. Moving, combat or a loading screen stops the check."), color = UI.COLORS.grey },
		}
	end)

	local reload = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	reload:SetSize(120, 24)
	reload:SetText(L("Reload First"))
	reload:SetScript("OnClick", ReloadUI)
	UI.SetTooltip(reload, L("Reload First"), {
		{ text = L("Reloads the interface. Forever's frame rate on Macs can drop over a long session, so reloading first gives the cleanest measurement.") },
	})

	-- Only while the check runs.
	local progress = CreateFrame("StatusBar", nil, content)
	progress:SetHeight(12)
	progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	progress:SetStatusBarColor(0.25, 0.6, 1)
	progress:SetMinMaxValues(0, 1)
	progress.Background = progress:CreateTexture(nil, "BACKGROUND")
	progress.Background:SetAllPoints()
	progress.Background:SetColorTexture(1, 1, 1, 0.08)
	progress:Hide()

	local status = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	status:SetJustifyH("LEFT")

	-- Step 3: the result, or what to do to get one.
	local step3 = Step(3, "Result")
	local empty = UI.Muted(content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	empty:SetJustifyH("LEFT")
	empty:SetText(L("Run the check to see your result here. Nothing changes until you apply it."))

	-- The result, top to bottom (Josh, 2026-10-08: the old summary didn't make clear what
	-- it all meant): a verdict on the goal and what Apply Recommended does, three measured
	-- frame rates side by side, any notes, then the settings table.
	local verdict = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	verdict:SetJustifyH("LEFT")
	local detail = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	detail:SetJustifyH("LEFT")

	local tiles = {}
	for index, label in ipairs({ L("Your settings now"), "Recommended", L("Everything at maximum") }) do
		local tile = CreateFrame("Frame", nil, content)
		tile:SetHeight(TILE_HEIGHT)
		tile.Background = tile:CreateTexture(nil, "BACKGROUND")
		tile.Background:SetAllPoints()
		tile.Background:SetColorTexture(1, 1, 1, 0.05)
		tile.Value = tile:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
		tile.Value:SetPoint("TOPLEFT", 10, -9)
		tile.Label = tile:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		tile.Label:SetPoint("TOPLEFT", tile.Value, "BOTTOMLEFT", 0, -5)
		tile.Label:SetJustifyH("LEFT")
		tile.Label:SetWordWrap(false)
		tile.Label:SetText(label)
		tile.Sub = UI.Muted(tile:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
		tile.Sub:SetPoint("TOPLEFT", tile.Label, "BOTTOMLEFT", 0, -3)
		tile.Sub:SetJustifyH("LEFT")
		tile.Sub:SetWordWrap(false)
		tile:EnableMouse(true)
		tile:SetScript("OnEnter", function(self)
			if self.tip then
				UI.ShowTooltip(self, label, { { text = self.tip } })
			end
		end)
		tile:SetScript("OnLeave", GameTooltip_Hide)
		tiles[index] = tile
	end

	local notes = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	notes:SetJustifyH("LEFT")

	-- Part of the result's fixed layout (Josh, 2026-10-18).
	local afterNote = UI.Muted(content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	afterNote:SetJustifyH("LEFT")
	afterNote:SetText(L("Changing Hidden Settings after this can cost frame rate or picture quality."))
	-- The fixed values (Josh, 2026-10-19, wording approved): the shadow line only on Macs
	-- whose shadows the check doesn't tune (Solver.TunesShadows); the picture line only once
	-- the recommendation is applied (the green Applied button's state), since the check
	-- itself puts the player's picture back.
	local shadowsNote = UI.Muted(content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	shadowsNote:SetJustifyH("LEFT")
	shadowsNote:SetText(Registry.SHADOWS_DOWN_NOTE)
	local pictureNote = UI.Muted(content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	pictureNote:SetJustifyH("LEFT")
	pictureNote:SetText(L("Your picture settings were changed to Mac-ever's Standard picture. Use the sliders to discover your preference, or pick a picture look."))
	local leftOutNote = UI.Muted(content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	leftOutNote:SetJustifyH("LEFT")
	leftOutNote:SetText(L("Spell Density and Projected Textures aren't part of the check: they cost frame rate in big fights."))

	local tableTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	tableTitle:SetText(L("Recommended settings"))
	local tableHint = UI.Muted(content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	tableHint:SetText(L("Hover a row for the full details"))
	local resultParts = { verdict, detail, notes, afterNote, leftOutNote, tableTitle, tableHint, tiles[1], tiles[2], tiles[3] }

	-- Column headings in gold over a divider, like the settings lists' group headers.
	local columns = CreateFrame("Frame", nil, content)
	columns:SetHeight(20)
	columns.Line = columns:CreateTexture(nil, "ARTWORK")
	columns.Line:SetPoint("BOTTOMLEFT", SIDE, 0)
	columns.Line:SetPoint("BOTTOMRIGHT", -SIDE, 0)
	columns.Line:SetHeight(1)
	columns.Line:SetColorTexture(goldR, goldG, goldB, 0.3)
	local function Heading(text)
		local label = columns:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		label:SetWordWrap(false)
		label:SetText(text)
		return label
	end
	local headings = {
		setting = Heading("Setting"),
		now = Heading("Now"),
		recommended = Heading("Recommended"),
		cost = Heading(L("Costs at maximum")),
	}
	headings.cost:SetJustifyH("RIGHT")
	-- A heading can't be hovered, so its explanation sits on a frame over it.
	local costHover = UI.SetTooltip(CreateFrame("Frame", nil, columns), L("Costs at maximum"), {
		{ text = L("How much frame rate each setting takes at its highest level, measured on your Mac.") },
	})
	costHover:EnableMouse(true)
	costHover:SetAllPoints(headings.cost)

	local applyRecommended = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	applyRecommended:SetSize(170, 24)
	applyRecommended:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.FOOTER_RIGHT, 8)
	applyRecommended:SetText(L("Apply Recommended"))

	local rows = {}
	local report

	-- Like a preset's Apply: green and unclickable while this result's recommendation is
	-- applied as it was, the game's red button otherwise.
	local function UpdateApplyButton()
		local applied = ns.Presets.CheckApplied(report)
		UI.SetApplied(applyRecommended, applied, L("Apply Recommended"))
		-- Only when it must be off: enabling again would swap the red art back out.
		if not applied and (report == nil or Benchmark.IsRunning()) then
			applyRecommended:SetEnabled(false)
		end
	end
	UI.SetTooltip(applyRecommended, L("Apply Recommended"), function()
		return report and ApplyLines(report)
	end)

	local function Cell(row, font, justify)
		local cell = row:CreateFontString(nil, "ARTWORK", font)
		cell:SetJustifyH(justify or "LEFT")
		cell:SetWordWrap(false) -- cut off cleanly within its column; never spills
		return cell
	end

	-- Hovering a row shows everything in full: cells cut off long text to keep the
	-- columns tidy (Josh, 2026-10-07: descriptions were being cut off).
	local function ShowRowTooltip(row)
		local info = row.info
		if not info then
			return
		end
		local lines = {}
		if info.summary ~= "" then
			lines[#lines + 1] = { text = info.summary }
		end
		if info.details and info.details ~= "" and info.details ~= info.summary then
			lines[#lines + 1] = { text = info.details, color = UI.COLORS.grey }
		end
		lines[#lines + 1] = { text = " " }
		lines[#lines + 1] = { text = "Now: " .. info.now, color = UI.COLORS.white }
		lines[#lines + 1] = { text = L("Recommended: ") .. info.recommended, color = info.recommendedColor }
		lines[#lines + 1] = { text = L("Costs at maximum: ") .. info.cost, color = UI.COLORS.white }
		UI.ShowTooltip(row, info.label, lines)
	end

	local function GetRow(index)
		local row = rows[index]
		if row then
			return row
		end
		row = CreateFrame("Frame", nil, content)
		row:SetHeight(ROW_HEIGHT)
		row.Stripe = row:CreateTexture(nil, "BACKGROUND")
		row.Stripe:SetPoint("TOPLEFT", SIDE - 6, 0)
		row.Stripe:SetPoint("BOTTOMRIGHT", -(SIDE - 6), 0)
		row.Stripe:SetColorTexture(1, 1, 1, STRIPE_ALPHA)
		row.Stripe:SetShown(index % 2 == 0)
		row.Label = Cell(row, "GameFontHighlight")
		row.Now = Cell(row, "GameFontHighlightSmall")
		row.Recommended = Cell(row, "GameFontHighlightSmall")
		row.Cost = Cell(row, "GameFontHighlightSmall", "RIGHT")
		row:EnableMouse(true)
		row:SetScript("OnEnter", ShowRowTooltip)
		row:SetScript("OnLeave", GameTooltip_Hide)
		rows[index] = row
		return row
	end

	local function Place(region, x, y)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
	end

	local function PlaceStep(step, inner, y)
		step.Line:ClearAllPoints()
		step.Line:SetPoint("TOPLEFT", content, "TOPLEFT", SIDE, -y)
		step.Line:SetWidth(inner)
		step.Title:SetWidth(inner)
		Place(step.Title, SIDE, y + 8)
		return y + 8 + (step.Title:GetStringHeight() or 14) + 10
	end

	-- A label in the shared column, centred on its control.
	local function PlaceRow(label, control, controlX, y)
		Place(control, controlX, y)
		label:ClearAllPoints()
		label:SetPoint("RIGHT", control, "LEFT", -LABEL_GAP, 0)
		return y + (control:GetHeight() or 26) + ROW_GAP
	end

	-- Everything top to bottom for the current width.
	local function Layout()
		local width = scroll:GetWidth()
		if not width or width <= 0 then
			return
		end
		content:SetWidth(width)
		local inner = width - SIDE * 2
		local indent = SIDE + 12
		local y = 8

		setup:SetWidth(inner)
		Place(setup, SIDE, y)
		y = y + 24 + 6

		-- Step 1: labels right-aligned in one column, controls on one left edge.
		y = PlaceStep(step1, inner, y + 6)
		local labelWidth = math.max(goalLabel:GetStringWidth() or 40, toleranceLabel:GetStringWidth() or 60, headroomLabel:GetStringWidth() or 60)
		local controlX = indent + labelWidth + LABEL_GAP
		y = PlaceRow(goalLabel, goal, controlX, y)
		y = PlaceRow(toleranceLabel, tolerance, controlX, y)
		y = PlaceRow(headroomLabel, headroom, controlX, y)
		-- The two switches share a row when they fit, else the second goes under the first.
		Place(capSwitch, controlX - 4, y)
		local capWidth = UI.CHECK_SIZE + (capSwitch.Text:GetStringWidth() or 60) + 16
		local resolutionWidth = UI.CHECK_SIZE + (resolutionSwitch.Text:GetStringWidth() or 300)
		if controlX - 4 + capWidth + resolutionWidth <= SIDE + inner then
			Place(resolutionSwitch, controlX - 4 + capWidth, y)
		else
			y = y + UI.CHECK_SIZE
			Place(resolutionSwitch, controlX - 4, y)
		end
		y = y + UI.CHECK_SIZE
		Place(keepSwitch, controlX - 4, y)
		y = y + UI.CHECK_SIZE

		-- Step 2.
		y = PlaceStep(step2, inner, y + STEP_GAP)
		howTo:SetWidth(inner - 12)
		Place(howTo, indent, y)
		y = y + (howTo:GetStringHeight() or 12) + ROW_GAP
		caveat:SetWidth(inner - 12)
		Place(caveat, indent, y)
		y = y + (caveat:GetStringHeight() or 12) + ROW_GAP
		Place(run, indent, y)
		reload:ClearAllPoints()
		reload:SetPoint("LEFT", run, "RIGHT", 6, 0)
		y = y + 24 + ROW_GAP
		if progress:IsShown() then
			progress:SetWidth(inner - 12)
			Place(progress, indent, y)
			y = y + 12 + 6
		end
		status:SetWidth(inner - 12)
		Place(status, indent, y)
		y = y + (status:GetStringHeight() or 12)

		-- Step 3.
		y = PlaceStep(step3, inner, y + STEP_GAP)
		empty:SetShown(report == nil)
		if not report then
			empty:SetWidth(inner - 12)
			Place(empty, indent, y)
			y = y + (empty:GetStringHeight() or 12) + 10
		end
		if report then
			verdict:ClearAllPoints()
			verdict:SetPoint("TOPLEFT", content, "TOPLEFT", SIDE, -y)
			verdict:SetWidth(inner)
			y = y + (verdict:GetStringHeight() or 18) + 6
			detail:ClearAllPoints()
			detail:SetPoint("TOPLEFT", content, "TOPLEFT", SIDE, -y)
			detail:SetWidth(inner)
			y = y + (detail:GetStringHeight() or 30) + 12
			local tileWidth = (inner - TILE_GAP * (#tiles - 1)) / #tiles
			for index, tile in ipairs(tiles) do
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", content, "TOPLEFT", SIDE + (index - 1) * (tileWidth + TILE_GAP), -y)
				tile:SetWidth(tileWidth)
				tile.Label:SetWidth(tileWidth - 20)
				tile.Sub:SetWidth(tileWidth - 20)
			end
			y = y + TILE_HEIGHT + 12

			if notes:GetText() and notes:GetText() ~= "" then
				notes:ClearAllPoints()
				notes:SetPoint("TOPLEFT", content, "TOPLEFT", SIDE, -y)
				notes:SetWidth(inner)
				y = y + (notes:GetStringHeight() or 12) + 14
			end
			for _, note in ipairs({ afterNote, shadowsNote, pictureNote, leftOutNote }) do
				if note:IsShown() then
					note:ClearAllPoints()
					note:SetPoint("TOPLEFT", content, "TOPLEFT", SIDE, -y)
					note:SetWidth(inner)
					y = y + (note:GetStringHeight() or 12) + 6
				end
			end
			y = y + 8

			tableTitle:ClearAllPoints()
			tableTitle:SetPoint("TOPLEFT", content, "TOPLEFT", SIDE, -y)
			tableHint:ClearAllPoints()
			tableHint:SetPoint("TOPRIGHT", content, "TOPRIGHT", -SIDE, -(y + 2))
			y = y + 22
		end

		local function PlaceCell(region, parent, column, rowY)
			region:ClearAllPoints()
			if column.x then
				region:SetPoint("TOPLEFT", parent, "TOPLEFT", SIDE + inner * column.x, rowY)
			else
				region:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -SIDE, rowY)
			end
			region:SetWidth(inner * column.width)
		end
		columns:ClearAllPoints()
		columns:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		columns:SetPoint("RIGHT", content, "RIGHT")
		for key, heading in pairs(headings) do
			PlaceCell(heading, columns, COLUMNS[key], 0)
		end
		y = y + 20 + 4

		for index, row in ipairs(rows) do
			if row:IsShown() then
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + (index - 1) * ROW_HEIGHT))
				row:SetPoint("RIGHT", content, "RIGHT")
				PlaceCell(row.Label, row, COLUMNS.setting, -6)
				PlaceCell(row.Now, row, COLUMNS.now, -7)
				PlaceCell(row.Recommended, row, COLUMNS.recommended, -7)
				PlaceCell(row.Cost, row, COLUMNS.cost, -7)
			end
		end
		local shown = 0
		for _, row in ipairs(rows) do
			if row:IsShown() then
				shown = shown + 1
			end
		end
		content:SetHeight(y + shown * ROW_HEIGHT + 8)
	end
	scroll:SetScript("OnSizeChanged", Layout)

	-- One row of the table: changes stand out, everything in full is in its tooltip.
	local function FillRow(row, setting, entry)
		local info = {
			label = Text(entry.label),
			summary = entry.summary or "",
			details = entry.tooltip and Text(entry.tooltip) or nil,
			now = Describe(setting.name, setting.current),
		}
		-- Only changes stand out: an unchanged setting says so instead of repeating
		-- its value (Josh, 2026-10-07: the table read as too busy).
		local recommended = Describe(setting.name, setting.recommended)
		local same = setting.currentIndex == nil or setting.recommendedIndex == setting.currentIndex
		local lower = not same and setting.recommendedIndex < setting.currentIndex
		if setting.recommendedIndex == 0 then
			-- Below the usual floor (lower resolution): compare the values themselves.
			same = setting.current ~= nil and math.abs(setting.current - setting.recommended) < 0.005
			lower = not same
		end
		if same then
			info.recommended, info.recommendedColor = recommended .. " (no change)", UI.COLORS.muted
			row.Recommended:SetText(L("|cffccccccNo change|r"))
		elseif not lower then
			info.recommended, info.recommendedColor = "raise to " .. recommended, UI.COLORS.green
			row.Recommended:SetText(L("|cff40ff40Raise to ") .. recommended .. "|r")
		else
			info.recommended, info.recommendedColor = "lower to " .. recommended, UI.COLORS.orange
			row.Recommended:SetText(L("|cffff9933Lower to ") .. recommended .. "|r")
		end
		if setting.costFps then
			info.cost = setting.costFps < 1 and "almost nothing" or ("%.0f fps"):format(setting.costFps)
			row.Cost:SetText(setting.costFps < 1 and L("|cffccccccalmost nothing|r") or info.cost)
		else
			info.cost = "not measured"
			row.Cost:SetText(L("|cffccccccnot measured|r"))
		end
		row.info = info
		row.Label:SetText(info.label)
		row.Now:SetText(info.now)
	end

	local function ShowReport()
		for _, row in ipairs(rows) do
			row:Hide()
		end
		columns:SetShown(report ~= nil)
		UpdateApplyButton()
		for _, part in ipairs(resultParts) do
			part:SetShown(report ~= nil)
		end
		-- While Hidden Settings are kept, applying leaves the shadows as they are. The tick box
		-- as it is now decides, as it does for applying (2026-10-19).
		shadowsNote:SetShown(report ~= nil and not Solver.TunesShadows() and not Solver.KeepsHidden())
		pictureNote:SetShown(ns.Presets.CheckApplied(report))
		-- When the result was measured, beside step 3's title.
		step3.Title:SetText(report and report.time and ("%s   |cffb3b3b3%s|r"):format(step3.title, date("%d %b, %H:%M", report.time)) or step3.title)
		if not report then
			Layout()
			return
		end

		local verdictText, detailText = Verdict(report)
		verdict:SetText(verdictText)
		detail:SetText(detailText)
		FillTiles(tiles, report)
		notes:SetText(Notes(report))

		local index = 0
		for _, setting in ipairs(report.settings) do
			local entry = Registry.Get(setting.name) -- a setting this version no longer has is left out
			if entry then
				index = index + 1
				local row = GetRow(index)
				FillRow(row, setting, entry)
				row:Show()
			end
		end
		Layout()
	end

	applyRecommended:SetScript("OnClick", ns.Safe(function()
		if report and report.changes then
			local goalFps, uncapped, checkTime = report.goal, report.uncapped, report.time
			local changes = Solver.ForApply(report.changes)
			UI.Apply(changes, function(kept)
				if kept then
					-- Same thing as the goal preset for that frame rate, so the Presets tab shows it.
					local id = "check"
					for _, preset in ipairs(ns.Presets.list) do
						if preset.goal == goalFps and not uncapped then
							id = preset.id
						end
					end
					ns.Presets.MarkApplied(id, changes, checkTime)
					ns.db.ui.lastGoal = goalFps
					ns.db.ui.lastUncapped = uncapped or nil
				end
				UI.Refresh()
			end)
		end
	end))

	-- Under Run, kept short.
	local REASONS = {
		combat = L("Stopped: combat started. Your settings go back once combat ends."),
		moved = L("Stopped: you moved. Settings put back; stand still and try again."),
		loading = L("Stopped: a loading screen. Your settings have been put back."),
		unmeasurable = L("Stopped: too few frames to measure here. Your settings have been put back."),
		stopped = L("Stopped. Your settings have been put back."),
	}

	local function UpdateIdle()
		local summary = UI.SetupSummary()
		setup.Text:SetText(summary and ("%s %s"):format(UI.Colored("gold", L("Your setup:")), UI.Colored("white", summary))
			or ("%s %s"):format(UI.Colored("gold", L("Not set up yet:")), UI.Colored("white", L("Mac-ever can pick the goal for you."))))
		setup.Button:SetText(summary and L("Change Setup") or "Set Up")

		local plan = Benchmark.Plan()
		local count = #plan
		run:SetText(L("Run System Check"))
		run:SetEnabled(count > 0)
		goal:SetEnabled(true)
		tolerance:SetEnabled(true)
		headroom:SetEnabled(true)
		capSwitch:SetEnabled(true)
		reload:SetEnabled(true)
		capSwitch:Update()
		keepSwitch:Update()
		-- The setup can change these while this tab is built; show the saved values.
		goal:GenerateMenu()
		tolerance:GenerateMenu()
		headroom:GenerateMenu()
		progress:SetValue(0)
		progress:Hide()
		status:SetText((L("Tunes %d settings and takes %s.")):format(count, FormatTime(Benchmark.EstimateSeconds(plan))))
	end

	local driver = UI.CreateCheckDriver()

	local function OnUpdate(state)
		progress:SetValue(state.progress or 0)
		local height = status:GetStringHeight()
		status:SetText(("%s   |cffb3b3b3·|r   %.0f fps"):format(state.status or "", GetFramerate()))
		if status:GetStringHeight() ~= height then
			Layout() -- the status wrapped or unwrapped
		end
	end

	local function OnDone(state)
		driver:Hide()
		UpdateIdle()
		if state.aborted then
			status:SetText(REASONS[state.aborted] or REASONS.stopped)
		else
			report = state.report
			ns.Presets.ClearApplied() -- the presets are tailored from this result now
			status:SetText(L("Done. Your settings are exactly as they were. Apply Recommended to use the new ones."))
		end
		ShowReport()
		UI.Refresh()
	end

	local function StartCheck()
		UI.SettleKeep() -- the check starts from the settings as they are, so a pending batch is kept
		local ok, reason = Benchmark.Start(ns.db.ui.goal or Benchmark.DEFAULT_GOAL, { onUpdate = OnUpdate, onDone = OnDone },
			ns.db.ui.tolerance or Solver.DEFAULT_TOLERANCE, { uncapped = ns.db.ui.uncapped == true })
		if not ok then
			status:SetText(reason == "combat" and ns.REASONS.combat or L("The check couldn't start."))
			Layout()
			return
		end
		run:SetText("Stop")
		goal:SetEnabled(false)
		tolerance:SetEnabled(false)
		headroom:SetEnabled(false)
		capSwitch:SetEnabled(false)
		keepSwitch:Update() -- running: greyed
		-- A reload mid-check would leave the test settings until the next login puts them back.
		reload:SetEnabled(false)
		UI.SetApplied(applyRecommended, false, L("Apply Recommended"))
		applyRecommended:SetEnabled(false)
		progress:SetValue(0)
		progress:Show()
		Layout()
		driver:Show()
	end

	run:SetScript("OnClick", ns.Safe(function()
		if Benchmark.IsRunning() then
			Benchmark.Stop()
			return
		end
		StartCheck()
	end))

	runFromSetup = function()
		if not Benchmark.IsRunning() then
			UpdateIdle()
			StartCheck()
		end
	end

	function panel.OnShown()
		if not Benchmark.IsRunning() then
			UpdateIdle()
			report = report or ns.db.lastCheck
			if report and (report.version ~= Solver.REPORT_VERSION or type(report.settings) ~= "table") then
				report = nil -- saved by an older version of the check
			end
			ShowReport()
		end
	end
end)
