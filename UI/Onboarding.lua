local _, ns = ...
local L = ns.L

local UI = ns.UI
local Benchmark = ns.Benchmark
local Devices = ns.Devices

-- First-run setup (Josh, 2026-10-10): which Mac and how much memory, then what matters
-- most, then the System Check with a goal to match. The game reports the chip ("Apple
-- M2") but not whether it's in an Air or a MacBook Pro, nor the memory, so Mac-ever asks.
-- Step 2 is a plain list of frame rates (Josh, 2026-10-18); the best fit is ticked, and
-- picking one above what Mac-ever recommends for this Mac warns first. Setup measures nothing (Josh,
-- 2026-10-11: a quick run at maximum settings "feels far too risky" for a first look);
-- the System Check, which the player starts at the end, does the measuring. Kept to three short
-- steps (Josh: "we don't want the onboarding to be arduous"). Shown once, the first time
-- the window opens; "Change Setup" on the System Check tab and /macever setup bring it back.

-- Shown at the last step to MacBook Air owners only: a cold Air may not slow down within
-- the check, which measures every Mac the same way. Josh's wording, as given (no full stop),
-- 2026-10-10; it was on the System Check page for everyone until setup asked which Mac.
local AIR_NOTE = L("|cffffd100MacBook Air:|r We recommend running System Check when your Mac has warmed up, as it gives a more accurate testing scenario for Mac-ever")

local WIDTH = 580
local SIDE = 24
local RADIO_HEIGHT = UI.CHECK_SIZE
local COLUMN_WIDTH = (WIDTH - SIDE * 2) / 2
local NOTE_X = SIDE + 30
local NOTE_WIDTH = WIDTH - NOTE_X - SIDE

local function GoalText(uncapped, goal)
	return uncapped and ("at least %d fps"):format(goal) or ("%d fps"):format(goal)
end

-- "MacBook Pro, 16 GB or more: 60 fps" for status lines, or nil before setup. Profiles saved
-- before setup asked for a frame rate also carry a named choice; the summary uses only the goal.
function UI.SetupSummary()
	local profile = ns.db.profile
	local mac = profile and Devices.Find(Devices.MACS, profile.mac)
	local memory = profile and Devices.Find(Devices.MEMORY, profile.memory)
	if not mac or not memory or not profile.goal then
		return nil
	end
	return ("%s, %s: %s"):format(mac.label, memory.label, GoalText(profile.uncapped, profile.goal))
end

local dialog
local answers = {}

local function Text(parent, font, width)
	local text = parent:CreateFontString(nil, "ARTWORK", font)
	text:SetJustifyH("LEFT")
	text:SetWidth(width or (WIDTH - SIDE * 2))
	return text
end

-- Single-choice switches. onPick(item) runs when one is ticked. Each shows its item's text
-- on hover, or tooltip when the items have none.
local function Radios(page, count, onPick, tooltip)
	local radios = {}
	for index = 1, count do
		local radio = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
		radio.Text:SetFontObject("GameFontNormal")
		-- A disabled CheckButton fires no OnEnter/OnLeave unless told to (as UI.SetApplied
		-- does), and its template doesn't grey the label: without both, a greyed radio
		-- looks clickable and its tooltip, which gives the reason, never shows.
		radio:SetMotionScriptsWhileDisabled(true)
		function radio:SetOpen(open)
			self:SetEnabled(open)
			self.Text:SetFontObject(open and "GameFontNormal" or "GameFontDisable")
		end
		radio.Note = UI.Muted(Text(page, "GameFontHighlightSmall", NOTE_WIDTH))
		radio:SetScript("OnClick", ns.Safe(function(self)
			if not self:IsEnabled() then
				return
			end
			for _, other in ipairs(radios) do
				other:SetChecked(other == self)
			end
			onPick(self.item)
		end))
		UI.SetTooltip(radio, nil, function(self)
			local item = self.item
			local tip = item and (item.text or tooltip)
			return tip and { { text = tip } }, item and item.label
		end)
		radios[index] = radio
	end
	function radios.SetItems(items)
		for index, radio in ipairs(radios) do
			radio.item = items[index]
			radio:SetShown(radio.item ~= nil)
			radio.Text:SetText(radio.item and radio.item.label or "")
		end
	end
	function radios.Select(id)
		for _, radio in ipairs(radios) do
			radio:SetChecked(radio.item ~= nil and radio.item.id == id)
		end
	end
	return radios
end

local function Create()
	dialog = UI.CreateDialog("MaceverSetup", WIDTH, L("Set Up Mac-ever"))
	dialog:SetPoint("CENTER", 0, 40)

	dialog.Step = Text(dialog, "GameFontHighlightLarge")
	dialog.Step:SetPoint("TOPLEFT", SIDE, -52)

	-- Step 1: which Mac and how much memory, on one page.
	local macPage = CreateFrame("Frame", nil, dialog)
	macPage:SetAllPoints()
	macPage.Intro = UI.Muted(Text(macPage, "GameFontHighlightSmall"))
	local function StepOneReady()
		dialog.Next:SetEnabled(answers.mac ~= nil and answers.memory ~= nil)
	end
	-- Every MacBook Neo has 8 GB (Josh, 2026-10-18): picking one ticks 8 GB and greys 16 GB.
	local function SyncMemory()
		if answers.mac == "neo" then
			answers.memory = "8"
		end
		macPage.memory.Select(answers.memory)
		for _, radio in ipairs(macPage.memory) do
			radio:SetOpen(not (answers.mac == "neo" and radio.item and radio.item.id ~= "8"))
		end
	end
	macPage.macs = Radios(macPage, #Devices.MACS, function(item)
		answers.mac = item.id
		SyncMemory()
		StepOneReady()
	end, L("The game reports the graphics chip, but not which Mac it's in. A MacBook Air has no fan, so it slows down as it warms up."))
	macPage.macs.SetItems(Devices.MACS)
	macPage.MemoryLabel = Text(macPage, "GameFontNormal", 80)
	macPage.MemoryLabel:SetText("Memory:")
	macPage.memory = Radios(macPage, #Devices.MEMORY, function(item)
		answers.memory = item.id
		StepOneReady()
	end, L("The graphics share your Mac's memory, so 8 GB leaves the game less room. With 16 GB or more, memory isn't the limit."))
	macPage.memory.SetItems(Devices.MEMORY)
	dialog.SyncMemory = SyncMemory
	macPage.MemoryHint = UI.Muted(Text(macPage, "GameFontHighlightSmall"))
	macPage.MemoryHint:SetText(L("Not sure? Choose About This Mac in the Apple menu."))

	-- Step 2: a frame rate. The tick stays where it was until a warned goal is accepted.
	local choicePage = CreateFrame("Frame", nil, dialog)
	choicePage:SetAllPoints()
	choicePage.Hint = UI.Muted(Text(choicePage, "GameFontHighlightSmall"))
	choicePage.Hint:SetText(L("Mac-ever keeps graphics as high as your chosen frame rate allows."))
	choicePage.radios = Radios(choicePage, #Benchmark.GOALS, function(item)
		choicePage.radios.Select("goal" .. dialog.Goal())
		local warned = not Devices.Recommends(item.goal, answers)
		UI.ConfirmGoal(item.goal, function()
			answers.goal = item.goal
			answers.accepted = warned and item.goal or answers.accepted
			if dialog:IsShown() then
				dialog:ShowPage(dialog.page) -- the warning doesn't block this window: Next may have moved on
			end
		end, answers)
	end)
	-- Capped at the frame rate unless the player lifts the cap here.
	choicePage.Uncapped = UI.CreateUncappedSwitch(choicePage, function()
		return answers.uncapped
	end, function(on)
		answers.uncapped = on or nil
	end)

	-- Step 3: what will happen, then run.
	local runPage = CreateFrame("Frame", nil, dialog)
	runPage:SetAllPoints()
	runPage.Summary = Text(runPage, "GameFontHighlight")
	runPage.Advice = UI.Muted(Text(runPage, "GameFontHighlightSmall"))
	runPage.Air = Text(runPage, "GameFontHighlightSmall")

	dialog.pages = { macPage, choicePage, runPage }

	dialog.Later = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	UI.SetTooltip(dialog.Later, "Later", {
		{ text = L("Opens Mac-ever without setting up. Set up any time with Change Setup on the System Check tab, or /macever setup.") },
	})
	dialog.Later:SetSize(110, 24)
	dialog.Later:SetPoint("BOTTOMLEFT", SIDE - 4, 18)
	dialog.Later:SetText("Later")
	dialog.Later:SetScript("OnClick", ns.Safe(function()
		dialog:Hide()
		UI.Show() -- the window, if setup came first
	end))

	dialog.Next = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	UI.SetTooltip(dialog.Next, L("Run System Check"), function()
		if dialog.page ~= 3 then
			return nil
		end
		local laptop = answers.mac == "air" or answers.mac == "mbp" or answers.mac == "neo"
		local lines = { { text = L("Measures every setting where you stand and finds the best-looking settings for your goal, then puts your settings back.") } }
		if laptop then
			lines[#lines + 1] = { text = L("On battery, macOS may slow the graphics down, so the results would be lower than when plugged in."), color = UI.COLORS.grey }
		end
		return lines
	end)
	dialog.Next:SetSize(160, 24)
	dialog.Next:SetPoint("BOTTOMRIGHT", -(SIDE - 4), 18)
	UI.MakeGreen(dialog.Next)

	dialog.Back = UI.Plain(CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate"))
	dialog.Back:SetSize(110, 24)
	dialog.Back:SetPoint("RIGHT", dialog.Next, "LEFT", -6, 0)
	dialog.Back:SetText("Back")
	dialog.Back:SetScript("OnClick", ns.Safe(function()
		dialog:ShowPage(dialog.page - 1)
	end))

	dialog.Next:SetScript("OnClick", ns.Safe(function()
		if dialog.page < 3 then
			dialog:ShowPage(dialog.page + 1)
			return
		end
		local goal = dialog.Goal()
		local tolerance = ns.Solver.DEFAULT_TOLERANCE
		ns.db.profile = {
			mac = answers.mac, memory = answers.memory, label = GoalText(false, goal),
			goal = goal, tolerance = tolerance, uncapped = answers.uncapped or nil,
		}
		ns.db.ui.goal = goal
		ns.db.ui.tolerance = tolerance
		ns.db.ui.uncapped = answers.uncapped or nil
		dialog:Hide()
		UI.StartSystemCheck()
	end))

	-- The goal in step 2: the player's pick if it's recommended for the Mac in the answers or
	-- they accepted the warning for it, else the best fit. With no best fit (a chip that isn't
	-- an M chip) the default goal.
	function dialog.Goal()
		if answers.goal and (answers.goal == answers.accepted or Devices.Recommends(answers.goal, answers)) then
			return answers.goal
		end
		return Devices.BestFit(answers) or Benchmark.DEFAULT_GOAL
	end

	-- Shows one step and sizes the dialog to it.
	function dialog:ShowPage(index)
		self.page = index
		for i, page in ipairs(self.pages) do
			page:SetShown(i == index)
		end
		local y = 52
		if index == 1 then
			self.Step:SetText(L("Step 1 of 3: Your Mac"))
			y = y + (self.Step:GetStringHeight() or 18) + 8
			macPage.Intro:SetText((L("Your graphics chip: %s. The game can't tell which kind of Mac it's in or how much memory it has, so Mac-ever asks.")):format(ns.ChipNames()))
			macPage.Intro:ClearAllPoints()
			macPage.Intro:SetPoint("TOPLEFT", macPage, "TOPLEFT", SIDE, -y)
			y = y + (macPage.Intro:GetStringHeight() or 24) + 10
			-- Two columns of Macs.
			local rows = math.ceil(#macPage.macs / 2)
			for i, radio in ipairs(macPage.macs) do
				local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
				radio:ClearAllPoints()
				radio:SetPoint("TOPLEFT", macPage, "TOPLEFT", SIDE - 4 + column * COLUMN_WIDTH, -(y + row * RADIO_HEIGHT))
			end
			y = y + rows * RADIO_HEIGHT + 12
			macPage.MemoryLabel:ClearAllPoints()
			macPage.MemoryLabel:SetPoint("TOPLEFT", macPage, "TOPLEFT", SIDE, -(y + 6))
			for i, radio in ipairs(macPage.memory) do
				radio:ClearAllPoints()
				radio:SetPoint("TOPLEFT", macPage, "TOPLEFT", SIDE + 76 + (i - 1) * 130, -y)
			end
			y = y + RADIO_HEIGHT + 2
			macPage.MemoryHint:ClearAllPoints()
			macPage.MemoryHint:SetPoint("TOPLEFT", macPage, "TOPLEFT", SIDE, -y)
			y = y + (macPage.MemoryHint:GetStringHeight() or 12) + 8
			self.Next:SetText("Next")
			self.Next:SetEnabled(answers.mac ~= nil and answers.memory ~= nil)
		elseif index == 2 then
			self.Step:SetText(L("Step 2 of 3: Choose your frame rate"))
			y = y + (self.Step:GetStringHeight() or 18) + 8
			choicePage.Hint:ClearAllPoints()
			choicePage.Hint:SetPoint("TOPLEFT", choicePage, "TOPLEFT", SIDE, -y)
			y = y + (choicePage.Hint:GetStringHeight() or 12) + 10

			local items = {}
			for position, fps in ipairs(Benchmark.GOALS) do
				items[position] = { id = "goal" .. fps, goal = fps, label = UI.GOAL_LABELS[fps] or GoalText(false, fps) }
			end
			choicePage.radios.SetItems(items)
			choicePage.radios.Select("goal" .. self.Goal())
			for _, radio in ipairs(choicePage.radios) do
				radio.Note:Hide()
				radio:ClearAllPoints()
				radio:SetPoint("TOPLEFT", choicePage, "TOPLEFT", SIDE - 4, -y)
				y = y + RADIO_HEIGHT
			end
			y = y + 8
			choicePage.Uncapped:ClearAllPoints()
			choicePage.Uncapped:SetPoint("TOPLEFT", choicePage, "TOPLEFT", SIDE - 4, -y)
			choicePage.Uncapped:Update()
			y = y + UI.CHECK_SIZE + 4
			self.Next:SetText("Next")
			self.Next:SetEnabled(true)
		else
			self.Step:SetText(L("Step 3 of 3: Run the System Check"))
			y = y + (self.Step:GetStringHeight() or 18) + 12
			local mac = Devices.Find(Devices.MACS, answers.mac)
			local memory = Devices.Find(Devices.MEMORY, answers.memory)
			local goal = self.Goal()
			runPage.Summary:SetText(("%s, %s, %s.\nGoal: %s.\n\nThe System Check takes %s. Nothing changes until you press Apply Recommended at the end."):format(
				mac.label, ns.ChipNames(), memory.label, GoalText(answers.uncapped, goal), UI.CheckDuration()))
			runPage.Summary:ClearAllPoints()
			runPage.Summary:SetPoint("TOPLEFT", runPage, "TOPLEFT", SIDE, -y)
			y = y + (runPage.Summary:GetStringHeight() or 60) + 10
			local laptop = mac.id == "air" or mac.id == "mbp" or mac.id == "neo"
			runPage.Advice:SetText(L("Stand still somewhere busy, out of combat, with the game in front.")
				.. (laptop and " Plug your MacBook in first." or ""))
			runPage.Advice:ClearAllPoints()
			runPage.Advice:SetPoint("TOPLEFT", runPage, "TOPLEFT", SIDE, -y)
			y = y + (runPage.Advice:GetStringHeight() or 24) + 8
			runPage.Air:SetShown(mac.id == "air")
			if mac.id == "air" then
				runPage.Air:SetText(AIR_NOTE)
				runPage.Air:ClearAllPoints()
				runPage.Air:SetPoint("TOPLEFT", runPage, "TOPLEFT", SIDE, -y)
				y = y + (runPage.Air:GetStringHeight() or 24) + 8
			end
			self.Next:SetText(L("Run System Check"))
			self.Next:SetEnabled(true)
		end
		self.Back:SetShown(index > 1)
		self:SetHeight(y + 18 + 24 + 18)
	end
end

function UI.ShowSetup()
	if not dialog then
		Create()
	end
	local profile = ns.db.profile or {}
	-- Answers from an older version that no longer match a Mac or memory size are asked again.
	local mac = Devices.Find(Devices.MACS, profile.mac) and profile.mac or nil
	local memory = Devices.Find(Devices.MEMORY, profile.memory) and profile.memory or nil
	answers = { mac = mac, memory = memory, goal = profile.goal, uncapped = ns.db.ui.uncapped }
	-- A saved goal above the limit was already accepted, so re-running setup doesn't warn again.
	if profile.goal and not Devices.Recommends(profile.goal, answers) then
		answers.accepted = profile.goal
	end
	dialog.pages[1].macs.Select(answers.mac)
	dialog.SyncMemory()
	ns.db.ui.setupSeen = true
	dialog:ShowPage(1)
	dialog:Show()
end

-- The first time Mac-ever opens, only the start-up message and setup show; the window
-- opens once setup runs the System Check, or on Later (Josh, 2026-10-11: setup over the
-- window "looks a bit silly").
function UI.NeedsSetup()
	return not ns.db.ui.setupSeen and not ns.db.profile
end

-- Shows setup the first time ever, after the start-up warning if that's showing.
function UI.MaybeShowSetup()
	if not UI.NeedsSetup() then
		return
	end
	local warning = _G.MaceverStartWarning
	if warning and warning:IsShown() then
		if not warning.showsSetup then
			warning.showsSetup = true
			warning:HookScript("OnHide", function()
				UI.MaybeShowSetup()
			end)
		end
		return
	end
	UI.ShowSetup()
end
