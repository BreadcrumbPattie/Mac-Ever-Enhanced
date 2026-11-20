local _, ns = ...
local L = ns.L

local UI = ns.UI
local Presets = ns.Presets

local COLUMNS = 2
local GAP = 10
local PAD = 12
local BUTTON_HEIGHT = 22
local MIN_CARD_WIDTH = 260 -- below this, goal cards go one per row
local TAG_ROOM = 90 -- the info button and the "Applied" tag, right of a card's name

local function Where(report)
	local zone = report.zone and report.zone ~= "" and report.zone or "where you ran it"
	return ("%s, %s"):format(zone, date("%d %b", report.time))
end

-- The honest status line for a card: only ever measured or predicted-from-measured
-- numbers, kept to one short sentence. Returns the line and any notes for the card's
-- tooltip. changes and solution are Presets.Changes(preset).
local function StatusFor(changes, solution)
	local report = ns.db.lastCheck
	-- Changes returns nil and a reason when there's nothing measured to work from.
	if not changes then
		return UI.Colored("gold", L("Needs a System Check to tailor it to your Mac.")), {}
	end
	if solution.start then
		return UI.Colored("gold", L("Starting point for your Mac, not measured yet. Run a System Check to fine-tune it.")), solution.notes
	end
	local notes = {}
	local text
	local lowScale = solution.lowScale and math.floor(solution.lowScale * 100 + 0.5)
	if lowScale and solution.reachable then
		text = (L("Predicted: about %.0f fps at %d%% render scale (%s).")):format(solution.predictedFps, lowScale, Where(report))
		notes[#notes + 1] = L("Render scale goes below 85% because you allowed lower resolution, so the 3D world looks softer.")
	elseif lowScale then
		text = UI.Colored("orange", (L("Out of reach here: about %.0f fps, even at %d%% render scale (%s).")):format(
			solution.uncappedFps, lowScale, Where(report)))
	elseif solution.reachable and solution.allMax then
		text = UI.Colored("green", (L("Everything stays at maximum: measured %.0f fps (%s).")):format(report.max.fps, Where(report)))
	elseif solution.reachable then
		text = (L("Predicted: about %.0f fps (%s).")):format(solution.predictedFps, Where(report))
	else
		text = UI.Colored("orange", (L("Out of reach here: Apply gives the fastest setup, about %.0f fps (%s).")):format(
			solution.floorFps, Where(report)))
		notes[#notes + 1] = L("The fastest setup within your rules: render scale stays at 85% or above unless you allow lower resolution.")
	end
	if report.limited then
		notes[#notes + 1] = L("Graphics settings barely affected your frame rate where you ran the check.")
	end
	return text, notes
end

local function Text(card, font)
	local fontString = card:CreateFontString(nil, "ARTWORK", font)
	fontString:SetJustifyH("LEFT")
	fontString:SetJustifyV("TOP")
	return fontString
end

-- A card: a light wash with a top edge, the name with an info button beside it, and a
-- one-line summary. infoLines (table or function) is the info button's tooltip.
local function NewCard(parent, name, summary, infoLines)
	local card = CreateFrame("Frame", nil, parent)

	card.Background = card:CreateTexture(nil, "BACKGROUND")
	card.Background:SetAllPoints()
	card.Background:SetColorTexture(1, 1, 1, 0.05)
	card.Edge = card:CreateTexture(nil, "BORDER")
	card.Edge:SetPoint("TOPLEFT")
	card.Edge:SetPoint("TOPRIGHT")
	card.Edge:SetHeight(1)
	card.Edge:SetColorTexture(1, 1, 1, 0.14)

	card.Name = Text(card, "GameFontNormalLarge")
	card.Name:SetPoint("TOPLEFT", PAD, -10)
	card.Name:SetWordWrap(false)
	card.Name:SetText(name)

	card.Info = UI.CreateInfoButton(card, name, infoLines)
	card.Info:SetPoint("LEFT", card.Name, "RIGHT", 6, 0)

	card.Description = Text(card, "GameFontHighlightSmall")
	card.Description:SetPoint("TOPLEFT", card.Name, "BOTTOMLEFT", 0, -6)
	card.Description:SetText(summary)
	return card
end

-- The name never runs into the info button and tag; then the summary's height.
local function FitTop(card, textWidth)
	card.Name:SetWidth(math.min(card.Name:GetUnboundedStringWidth() or textWidth, textWidth - TAG_ROOM))
	card.Description:SetWidth(textWidth)
	return 10 + (card.Name:GetStringHeight() or 16) + 6 + (card.Description:GetStringHeight() or 12)
end

local function KeepLine()
	return { text = (L("You get %d seconds to keep the settings or switch back.")):format(UI.KEEP_SECONDS), color = UI.COLORS.green }
end

local function CreateCard(parent, preset)
	local card
	card = NewCard(parent, preset.name, preset.summary, function()
		local lines = { { text = Presets.Describe(preset) } }
		for _, note in ipairs(card.notes or {}) do
			lines[#lines + 1] = { text = note, color = UI.COLORS.grey }
		end
		return lines
	end)
	card.preset = preset

	-- While applied (Josh, 2026-10-16: make it obvious): a green tick and word beside the
	-- name, a green bar down the left edge, a green wash, and the green Applied button.
	card.Tick = card:CreateTexture(nil, "ARTWORK")
	card.Tick:SetTexture(UI.TICK)
	card.Tick:SetSize(16, 16)
	card.Tick:SetPoint("LEFT", card.Info, "RIGHT", 8, 0)
	card.Active = Text(card, "GameFontNormal")
	card.Active:SetTextColor(UI.COLORS.green:GetRGB())
	card.Active:SetPoint("LEFT", card.Tick, "RIGHT", 3, 0)
	card.Active:SetText("Applied")
	card.Accent = card:CreateTexture(nil, "BORDER")
	card.Accent:SetPoint("TOPLEFT")
	card.Accent:SetPoint("BOTTOMLEFT")
	card.Accent:SetWidth(3)
	card.Accent:SetColorTexture(UI.COLORS.green:GetRGB())

	-- Best fit for this Mac's class (Josh, 2026-10-18): a gold line under the name, on its own
	-- row so it never meets the green Applied tick beside the name.
	card.BestFit = Text(card, "GameFontNormalSmall")
	card.BestFit:SetText(L("Best fit for your Mac"))
	card.BestFit:Hide()

	card.Status = UI.Muted(Text(card, "GameFontHighlightSmall"))
	card.Status:SetPoint("TOPLEFT", card.Description, "BOTTOMLEFT", 0, -8)

	card.Apply = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
	card.Apply:SetSize(110, BUTTON_HEIGHT)
	card.Apply:SetPoint("BOTTOMRIGHT", -10, 10)
	UI.SetTooltip(card.Apply, preset.name, function()
		if not card.changes then
			return { { text = (L("Opens the System Check with a %d fps goal. This preset is tailored from a measurement of your Mac, so it needs one first.")):format(preset.goal) } }, L("Measure First")
		end
		return { { text = (L("Applies %s.")):format(preset.name) }, KeepLine() }
	end)

	card.Apply:SetScript("OnClick", ns.Safe(function()
		UI.ConfirmGoal(preset.goal, function()
			local changes, reason = Presets.Changes(preset)
			if not changes and reason == "needs-check" then
				ns.db.ui.goal = preset.goal
				UI.SelectTab(L("System Check"))
				return
			end
			UI.Apply(changes, function(kept)
				if kept then
					Presets.MarkApplied(preset.id, changes)
				end
				UI.Refresh()
			end, (L("Your settings already match %s.")):format(preset.name))
		end)
	end))

	function card:Update()
		local changes, solution = Presets.Changes(preset)
		self.BestFit:SetShown(ns.Devices.BestFit() == preset.goal)
		local status, notes = StatusFor(changes, solution)
		self.changes, self.notes = changes, notes
		self.Status:SetText(status)
		local applied = changes ~= nil and Presets.Applied() == preset.id
		self.Tick:SetShown(applied)
		self.Active:SetShown(applied)
		self.Accent:SetShown(applied)
		if applied then
			self.Background:SetColorTexture(0.25, 1, 0.25, 0.08)
		else
			self.Background:SetColorTexture(1, 1, 1, 0.05)
		end
		UI.SetApplied(self.Apply, applied, not changes and L("Measure First") or "Apply")
	end

	-- Sets the width, then the height the text needs. Returns the height.
	function card:Fit(width)
		self:SetWidth(width)
		local textWidth = width - PAD * 2
		self.Status:SetWidth(textWidth)
		local top = FitTop(self, textWidth)
		self.Status:ClearAllPoints()
		if ns.Devices.BestFit() == preset.goal then
			self.BestFit:ClearAllPoints()
			self.BestFit:SetPoint("TOPLEFT", self.Description, "BOTTOMLEFT", 0, -6)
			self.Status:SetPoint("TOPLEFT", self.BestFit, "BOTTOMLEFT", 0, -6)
			top = top + 6 + (self.BestFit:GetStringHeight() or 12)
		else
			self.Status:SetPoint("TOPLEFT", self.Description, "BOTTOMLEFT", 0, -8)
		end
		local height = top + 8 + (self.Status:GetStringHeight() or 12) + 10 + BUTTON_HEIGHT + 10 + 6
		self:SetHeight(height)
		return height
	end
	return card
end

-- Picture looks (Brightness, Contrast, Gamma; Standard also sets Bloom Intensity). They
-- never change graphics settings. The other way round, every goal preset and System Check
-- result brings the Standard look (Josh, 2026-10-19), so the card says what it is.
local function PictureValues(read)
	local gamma = tonumber(read("Gamma"))
	return (L("Brightness %s%%, Contrast %s%%, Gamma %s")):format(
		tostring(math.floor((tonumber(read("Brightness")) or 0) + 0.5)),
		tostring(math.floor((tonumber(read("Contrast")) or 0) + 0.5)),
		gamma and ("%.2f"):format(gamma):gsub("0$", "") or "?")
end

local function CreatePictureCard(parent)
	local read = function(name) return C_CVar.GetCVar(name) end
	local card = NewCard(parent, "Picture", L("Brightness, Contrast and Gamma (Standard also sets Bloom): never your graphics settings."), {
		{ text = L("How bright and punchy the picture looks. Screens and rooms differ, so pick what suits yours.") },
		{ text = L("Hover a look in the list for what it does."), color = UI.COLORS.grey },
	})

	card.Label = Text(card, "GameFontNormal")
	card.Label:SetText("Look:")

	-- The look to apply. Starts on whichever look the settings already match.
	local selected
	local function Selected()
		return selected or Presets.CurrentLook(read) or Presets.pictureLooks[1]
	end

	card.Picker = CreateFrame("DropdownButton", nil, card, "WowStyle1DropdownTemplate")
	card.Picker:SetWidth(220)
	card.Picker:SetPoint("LEFT", card.Label, "RIGHT", 10, 0)
	card.Picker:SetupMenu(function(_, root)
		for _, look in ipairs(Presets.pictureLooks) do
			local radio = root:CreateRadio(look.name, function()
				return Selected() == look
			end, function()
				selected = look
				card:Update()
			end)
			radio:SetTooltip(function(tooltip)
				GameTooltip_SetTitle(tooltip, look.name)
				GameTooltip_AddNormalLine(tooltip, ns.L(look.description))
			end)
		end
	end)
	UI.SetTooltip(card.Picker, "Look", function()
		local look = Selected()
		return { { text = ns.L(look.description) } }, ns.L(look.name)
	end)

	card.Status = UI.Muted(Text(card, "GameFontHighlightSmall"))
	-- Fixed text (Josh, 2026-10-19, wording approved).
	card.StandardNote = UI.Muted(Text(card, "GameFontHighlightSmall"))
	card.StandardNote:SetText(L("Mac-ever's Standard picture is Contrast 65%, Brightness 50%, Gamma 1.0 and Bloom 0.4. Adjust them as you see fit."))

	card.Apply = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
	card.Apply:SetSize(110, BUTTON_HEIGHT)
	card.Apply:SetPoint("BOTTOMRIGHT", -10, 10)
	card.Apply:SetText("Apply")
	card.Apply:SetScript("OnClick", ns.Safe(function()
		local look = Selected()
		UI.Apply(Presets.LookChanges(look), function()
			UI.Refresh()
		end, (L("Your picture already matches %s.")):format(look.name))
	end))
	UI.SetTooltip(card.Apply, "Apply", function()
		local look = Selected()
		local settings = look.bloom and L("Brightness, Contrast, Gamma and Bloom Intensity") or L("Brightness, Contrast and Gamma")
		return { { text = (L("Sets %s for %s.")):format(settings, look.name) }, KeepLine() }
	end)

	function card:Update()
		local current = Presets.CurrentLook(read)
		self.Status:SetText((L("Now: %s (%s).")):format(current and current.name or "your own settings", PictureValues(read)))
		self.Picker:GenerateMenu()
	end

	function card:Fit(width)
		self:SetWidth(width)
		local textWidth = width - PAD * 2
		self.Status:SetWidth(textWidth)
		self.StandardNote:SetWidth(textWidth)
		local y = FitTop(self, textWidth) + 14
		-- The picker row: the dropdown is taller than its label.
		self.Label:ClearAllPoints()
		self.Label:SetPoint("TOPLEFT", PAD, -(y + 6))
		y = y + 26 + 8
		self.Status:ClearAllPoints()
		self.Status:SetPoint("TOPLEFT", PAD, -y)
		y = y + (self.Status:GetStringHeight() or 12) + 6
		self.StandardNote:ClearAllPoints()
		self.StandardNote:SetPoint("TOPLEFT", PAD, -y)
		y = y + (self.StandardNote:GetStringHeight() or 12) + 10 + BUTTON_HEIGHT + 10
		self:SetHeight(y)
		return y
	end
	return card
end

-- Instance Settings (see Places.lua; "By Location" until Josh, 2026-10-16): a switch, then a
-- picker per place.
local PLACE_LABEL_WIDTH = 190

local function CreatePlacesCard(parent)
	local Places = ns.Places
	local card = NewCard(parent, L("Instance Settings"), L("Different settings in dungeons, raids and battlegrounds."), {
		{ text = L("Mac-ever switches when the loading screen ends (or once combat ends), and puts your own settings back when you leave.") },
		{ text = L("Settings that restart the screen or the game window are left as they are."), color = UI.COLORS.grey },
	})

	card.Switch = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
	card.Switch.Text:SetFontObject("GameFontHighlight")
	card.Switch.Text:SetText(L("Switch settings in instances"))
	card.Switch:SetScript("OnClick", ns.Safe(function(self)
		Places.SetOn(self:GetChecked() == true)
		card:Update()
	end))
	UI.SetTooltip(card.Switch, L("Switch settings in instances"), {
		{ text = L("On: each place below uses the settings you pick for it.") },
		{ text = L("Off: your settings stay the same everywhere."), color = UI.COLORS.grey },
	})

	local choiceLines = {
		{ text = L("Your own settings: what you had before arriving, unchanged.") },
		{ text = L("System Check result: the last check's recommendation.") },
		{ text = L("A preset: that preset, tailored from your last System Check."), color = UI.COLORS.grey },
	}
	card.rows = {}
	for _, place in ipairs(Places.list) do
		local row = {}
		row.Label = Text(card, "GameFontNormal")
		row.Label:SetWidth(PLACE_LABEL_WIDTH)
		row.Label:SetText(place.label)
		row.Picker = CreateFrame("DropdownButton", nil, card, "WowStyle1DropdownTemplate")
		row.Picker:SetWidth(220)
		row.Picker:SetPoint("LEFT", row.Label, "RIGHT", 10, 0)
		row.Picker:SetupMenu(function(_, root)
			for _, choice in ipairs(Places.CHOICES) do
				root:CreateRadio(Places.ChoiceLabel(choice), function()
					return Places.Choice(place.id) == choice
				end, function()
					local preset = Presets.Get(choice)
					UI.ConfirmGoal(preset and preset.goal, function()
						Places.SetChoice(place.id, choice)
						if Places.IsOn() and Places.Current() == place then
							ns.SafeCall(Places.Switch)
						end
						card:Update()
					end)
				end)
			end
		end)
		UI.SetTooltip(row.Picker, place.label, choiceLines)
		row.place = place
		card.rows[#card.rows + 1] = row
	end

	card.Status = UI.Muted(Text(card, "GameFontHighlightSmall"))

	function card:Update()
		local on = Places.IsOn()
		self.Switch:SetChecked(on)
		for _, row in ipairs(self.rows) do
			row.Picker:SetEnabled(on)
			row.Picker:GenerateMenu()
			-- Greyed with its picker while switching is off.
			row.Label:SetTextColor((on and UI.COLORS.gold or UI.COLORS.grey):GetRGB())
		end
		local here = Places.Current()
		local status = on and (L("Now: %s, using %s.")):format(here.label, Places.ChoiceLabel(Places.Choice(here.id)))
			or L("Off: your settings stay the same everywhere.")
		if on and tonumber(C_CVar.GetCVar("RAIDsettingsEnabled")) == 1 then
			status = status .. " Raids and battlegrounds use the game's Raid & Battleground Settings."
		end
		self.Status:SetText(status)
	end

	function card:Fit(width)
		self:SetWidth(width)
		local textWidth = width - PAD * 2
		self.Status:SetWidth(textWidth)
		local y = FitTop(self, textWidth) + 8
		self.Switch:ClearAllPoints()
		self.Switch:SetPoint("TOPLEFT", PAD - 4, -y)
		y = y + UI.CHECK_SIZE + 4
		for _, row in ipairs(self.rows) do
			-- Each row is as tall as its dropdown, with the label centred on it.
			row.Label:ClearAllPoints()
			row.Label:SetPoint("TOPLEFT", PAD, -(y + 6))
			y = y + 26 + 4
		end
		y = y + 4
		self.Status:ClearAllPoints()
		self.Status:SetPoint("TOPLEFT", PAD, -y)
		y = y + (self.Status:GetStringHeight() or 12) + 10
		self:SetHeight(y)
		return y
	end
	return card
end

UI.RegisterTab("Presets", function(panel)
	-- Everything scrolls, so a small window or large text never clips a card.
	local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -2)
	scroll:SetPoint("BOTTOMRIGHT", -22, 2)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	local INTRO = L("Every preset keeps graphics as high as it can. Hover a card's i for the details.")
	local intro = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	intro:SetPoint("TOPLEFT", PAD, -10)
	intro:SetJustifyH("LEFT")

	-- What's applied, under the intro with a tick, while it's still in place; the System
	-- Check recommendation has no card, so this is where it shows.
	local applied = CreateFrame("Frame", nil, content)
	applied:SetHeight(20)
	applied.Tick = applied:CreateTexture(nil, "ARTWORK")
	applied.Tick:SetTexture(UI.TICK)
	applied.Tick:SetSize(18, 18)
	applied.Tick:SetPoint("LEFT")
	applied.Text = applied:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	applied.Text:SetPoint("LEFT", applied.Tick, "RIGHT", 4, 0)
	applied.Text:SetPoint("RIGHT")
	applied.Text:SetJustifyH("LEFT")
	applied.Text:SetWordWrap(false)
	applied.Text:SetTextColor(UI.COLORS.green:GetRGB())

	local function AppliedText()
		local id = Presets.Applied()
		if id == "check" then
			return (ns.db.ui.lastUncapped and L("Applied: System Check recommendation (at least %d fps, no cap)")
				or L("Applied: System Check recommendation (%d fps cap)")):format(ns.db.ui.lastGoal or 0)
		end
		local preset = id and Presets.Get(id)
		return preset and (L("Applied: %s")):format(preset.name)
	end

	local goals = {}
	for _, preset in ipairs(Presets.list) do
		goals[#goals + 1] = CreateCard(content, preset)
	end

	local places = CreatePlacesCard(content)
	local picture = CreatePictureCard(content)

	-- Lays everything out top to bottom for the current width; each row of goal cards
	-- is as tall as its tallest card.
	local function Layout(width)
		if not width or width <= 0 then
			return
		end
		content:SetWidth(width)
		local inner = width - PAD * 2
		intro:SetWidth(inner)
		local y = 10 + (intro:GetStringHeight() or 30) + 12
		if applied:IsShown() then
			applied:ClearAllPoints()
			applied:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -(y - 4))
			applied:SetWidth(inner)
			y = y + 20 + 8
		end

		local columns = inner >= MIN_CARD_WIDTH * COLUMNS + GAP and COLUMNS or 1
		local cardWidth = (inner - GAP * (columns - 1)) / columns
		for start = 1, #goals, columns do
			local rowHeight = 0
			for offset = 0, columns - 1 do
				local card = goals[start + offset]
				if card then
					rowHeight = math.max(rowHeight, card:Fit(cardWidth))
				end
			end
			for offset = 0, columns - 1 do
				local card = goals[start + offset]
				if card then
					card:SetHeight(rowHeight)
					card:ClearAllPoints()
					card:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + offset * (cardWidth + GAP), -y)
				end
			end
			y = y + rowHeight + GAP
		end

		places:ClearAllPoints()
		places:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -y)
		y = y + places:Fit(inner) + GAP

		picture:ClearAllPoints()
		picture:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -y)
		y = y + picture:Fit(inner) + GAP
		content:SetHeight(y)
	end
	scroll:SetScript("OnSizeChanged", function(_, width)
		Layout(width)
	end)

	function panel.OnShown()
		intro:SetText(INTRO)
		local text = AppliedText()
		applied.Text:SetText(text or "")
		applied:SetShown(text ~= nil)
		for _, card in ipairs(goals) do
			card:Update()
		end
		places:Update()
		picture:Update()
		Layout(scroll:GetWidth())
	end
end)
