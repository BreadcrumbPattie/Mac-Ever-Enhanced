local _, ns = ...
local L = ns.L

local UI = ns.UI
local Registry = ns.Registry
local Model = ns.CustomModel
local CVars = ns.CVars
local Text = ns.Text

-- A scrolling list of settings with staged edits, used by the Hidden Settings and
-- Standard Settings tabs. Both tabs share one Model, so unapplied edits follow the
-- player between them.

-- Columns are fixed so nothing can overlap: name | control | tags.
local ROW_HEIGHT = 54       -- name and control on top, a one-line plain-English description below
local COMPACT_ROW_HEIGHT = 32 -- Standard Settings: one line per setting, like the game's menu
local TAGS_WIDTH = 92
local HEADER_HEIGHT = 34
local TOP_BAR_HEIGHT = 34
local LABEL_X = 16
local CONTROL_X = 300
local CONTROL_WIDTH = 180 -- leaves room for a slider's value label before the tag column
local TOGGLE_WIDTH = 30     -- a frame-rate cap's on/off switch, left of its slider

local RISKS = {
	caution = {
		label = "Caution",
		color = UI.COLORS.orange,
		detail = L("Can cause visual problems, or a brief black screen while the game window refreshes."),
	},
	advanced = {
		label = "Advanced",
		color = UI.COLORS.red,
		detail = L("Can make the game unstable or crash. Change one at a time, and keep a note of what you changed."),
	},
}

local RESTART_NOTES = {
	gx = L("Takes effect after you restart the game."),
	window = L("Applying this refreshes the game window."),
	client = L("Takes effect after you restart the game."),
}

local WARNING_TEXT = table.concat({
	L("These pages give you direct control over the game's graphics settings, including ones that can make the game unstable."),
	L("|cffff9933Caution|r settings can cause visual problems or refresh the game window. |cffff8c8cAdvanced|r settings can crash the game."),
	(L("Every change asks you to keep it, and switches back by itself after %d seconds if you don't. Restore Originals undoes Mac-ever's changes.")):format(UI.KEEP_SECONDS),
	L("If the game ever becomes hard to see, type |cffffffff/macever restore|r in chat."),
}, "\n\n")

local function Round(value, step)
	local decimals = step < 1 and math.ceil(-math.log10(step) - 1e-9) or 0
	return tonumber(("%." .. decimals .. "f"):format(value))
end

local function RaidSettingsOn()
	return tonumber(Model:Value(Registry.Get("RAIDsettingsEnabled"))) == 1
end

-- Player-facing form of a stored value, for tooltips.
local function DescribeValue(entry, value)
	if value == nil then
		return "?"
	end
	if entry.control == "toggle" then
		return tonumber(value) == 1 and "On" or "Off"
	elseif entry.control == "choice" then
		for _, choice in ipairs(Registry.GetChoices(entry)) do
			if CVars.SameValue(tostring(choice.value), value) then
				return Text(choice.label)
			end
		end
	elseif entry.control == "slider" then
		local spec = Registry.GetSlider(entry)
		local number = tonumber(value)
		if number and spec.format then
			return spec.format(entry.invert and entry.invert - number or number)
		end
	end
	return value
end

local function SearchText(entry)
	if not entry.searchText then
		entry.searchText = table.concat({
			Text(entry.label) or "", entry.name, entry.tooltip and Text(entry.tooltip) or "",
		}, " "):lower()
	end
	return entry.searchText
end

local List = {}
List.__index = List

local function ShowRowTooltip(row)
	local entry = row.entry
	-- The row shows its description on one line; the tooltip has it in full, then the
	-- game's own description where that says more.
	local lines = {}
	if entry.summary then
		lines[#lines + 1] = { text = entry.summary }
	end
	local description = entry.tooltip and Text(entry.tooltip)
	if description and description ~= entry.summary then
		lines[#lines + 1] = { text = description, color = entry.summary and UI.COLORS.grey or nil }
	end
	if entry.raid then
		lines[#lines + 1] = { text = L("Used in raids and battlegrounds only."), color = UI.COLORS.grey }
	end
	local risk = RISKS[entry.risk]
	if risk then
		lines[#lines + 1] = { text = risk.label .. ": " .. risk.detail, color = risk.color }
	end
	if Registry.IsResolution(entry.name) and not CVars.ResolutionAllowed() then
		lines[#lines + 1] = { text = L("Locked: Mac-ever is set not to change display mode, notch mode or VSync, because that refreshes the game window and can reset your resolution. Turn on \"Let Mac-ever lower resolution to reach your goal\" on the System Check tab or in Options to change it here."), color = UI.COLORS.grey }
	end
	if entry.restart then
		lines[#lines + 1] = { text = RESTART_NOTES[entry.restart], color = UI.COLORS.grey }
	end
	if Model:IsModified(entry) then
		lines[#lines + 1] = { text = (L("Not applied yet. The game is currently using %s.")):format(DescribeValue(entry, Model:Current(entry))), color = UI.COLORS.gold }
	end
	local original = ns.db.originals[Registry.Key(entry.name)]
	if original and CVars.Owns(original) then
		lines[#lines + 1] = { text = (L("Before Mac-ever: %s")):format(DescribeValue(entry, original.value)), color = UI.COLORS.green }
	end
	lines[#lines + 1] = { text = entry.name, color = UI.COLORS.grey }
	UI.ShowTooltip(row, Text(entry.label), lines)
end

-- A row's control shows the row's tooltip too: it takes the mouse, so the row's own
-- OnLeave fires as the pointer moves onto it.
local function ShareRowTooltip(row, control)
	if not control then
		return
	end
	control:HookScript("OnEnter", function()
		ShowRowTooltip(row)
	end)
	control:HookScript("OnLeave", GameTooltip_Hide)
	control.rowTooltip = true
end

function List:UpdateFooter()
	local count = Model:Count()
	self.footer.Count:SetText(count == 0 and "" or ("%d unapplied change%s"):format(count, count == 1 and "" or ns.L("s")))
	self.footer.Apply:SetEnabled(count > 0)
	self.footer.Discard:SetEnabled(count > 0)
end

function List:UpdateRow(row)
	self.updating = true
	row.Update()
	self.updating = false

	local entry = row.entry
	local modified = Model:IsModified(entry) or (row.toggleEntry ~= nil and Model:IsModified(row.toggleEntry))
	row.Marker:SetShown(modified)
	if modified then
		row.Label:SetTextColor(UI.COLORS.gold:GetRGB())
	else
		row.Label:SetTextColor(UI.COLORS.white:GetRGB())
	end

	-- One tag at most, so it always fits its column: Locked beats an unapplied edit (said in words, not only by the gold label), which beats a risk level.
	local locked = Registry.IsResolution(entry.name) and not CVars.ResolutionAllowed()
	if row.SetControlEnabled then
		-- Greyed, not hidden, when the Anti-Aliasing mode doesn't use it (like the stock menu).
		row.SetControlEnabled(not locked and Model:IsModifiable(entry))
	end
	local tag = ""
	if locked then
		tag = UI.Colored("muted", "Locked")
	elseif modified then
		tag = UI.Colored("gold", L("Not applied"))
	elseif RISKS[entry.risk] then
		tag = RISKS[entry.risk].color:WrapTextInColorCode(RISKS[entry.risk].label)
	end
	row.Tags:SetText(tag)
end

-- Ignores collapsed sections, so a collapsed heading still shows when it has settings.
function List:IsRowVisible(row)
	local entry = row.entry
	if not Model:IsAvailable(entry) then
		return false
	end
	if entry.inList == false then
		return false
	end
	if self.options.scoped then
		-- The Base / Raid switch swaps settings that come in pairs; everything else
		-- applies everywhere and shows in both.
		if self.scope == "raid" then
			if not entry.raid and entry.raidName then
				return false
			end
		elseif entry.raid then
			return false
		end
	elseif entry.raid and not RaidSettingsOn() then
		return false
	end
	if self.query and self.query ~= "" and not SearchText(entry):find(self.query, 1, true) then
		return false
	end
	return true
end

function List:Layout()
	local visibleInGroup = {}
	for _, row in ipairs(self.rows) do
		if row.entry then
			local visible = self:IsRowVisible(row)
			if visible then
				visibleInGroup[row.group.id] = (visibleInGroup[row.group.id] or 0) + 1
			end
			row:SetShown(visible and not self:IsCollapsed(row.group))
		end
	end

	local width = self.content:GetWidth()
	local y = 0
	for _, row in ipairs(self.rows) do
		if not row.entry then
			local count = visibleInGroup[row.group.id]
			row:SetShown(count ~= nil)
			if row.Toggle then
				row.Toggle:SetText(self:IsCollapsed(row.group)
					and (L("|cffffd100+|r  Show %d setting%s")):format(count or 0, count == 1 and "" or ns.L("s"))
					or L("|cffffd100-|r  Hide"))
			end
			if count then
				local note = row.group.note
				if type(note) == "function" then
					note = note(function(name) return Model:Current(Registry.Get(name) or { name = name }) end)
				end
				row.Note:SetText(note or "")
				row.Note:SetWidth(math.max(100, width - 2 * LABEL_X))
				local noteHeight = note and ((row.Note:GetStringHeight() or 12) + 6) or 0
				row:SetHeight(HEADER_HEIGHT + noteHeight)
			end
		end
		if row:IsShown() and row.Summary then
			row.Summary:SetWidth(math.max(100, width - LABEL_X - 16))
		end
		if row:IsShown() then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
			row:SetPoint("RIGHT", self.content, "RIGHT")
			y = y + row:GetHeight()
		end
	end
	self.content:SetHeight(y + 8)
	self.Empty:SetShown(y == 0)
end

function List:IsCollapsed(group)
	return group.collapsible and not self.expanded[group.id]
end

function List:ToggleGroup(group)
	if not self:IsCollapsed(group) then
		self.expanded[group.id] = nil
		self:RefreshAll()
		return
	end
	local function Expand()
		self.expanded[group.id] = true
		self:RefreshAll()
	end
	if group.confirm then
		UI.Confirm(group.confirm.title, group.confirm.text, group.confirm.accept, Expand)
	else
		Expand()
	end
end

function List:RefreshAll()
	self:Layout()
	for _, row in ipairs(self.rows) do
		if row.entry and row:IsShown() then
			self:UpdateRow(row)
		end
	end
	self:UpdateFooter()
	if self.ScopeNotice then
		self.ScopeNotice:SetShown(self.scope == "raid" and not RaidSettingsOn())
	end
end

function List:OnValueChanged(row, value)
	if self.updating then
		return
	end
	ns.SafeCall(self.ChangeValue, self, row, value)
end

function List:ChangeValue(row, value)
	local entry = row.entry
	Model:Set(entry, value)
	if entry.master or entry.name == "RAIDsettingsEnabled" or entry.proxy or entry.parentModes then
		-- These move other settings, show/hide a section, or grey rows (the
		-- Anti-Aliasing mode and the rows under it).
		self:RefreshAll()
	else
		self:UpdateRow(row)
		self:UpdateFooter()
	end
end

-- Controls ------------------------------------------------------------------------

function List:CreateToggle(row)
	local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	check:SetPoint("LEFT", row, "TOPLEFT", CONTROL_X - 6, self.controlY)
	check:SetScript("OnClick", ns.Safe(function(button)
		self:OnValueChanged(row, button:GetChecked() and 1 or 0)
	end))
	ShareRowTooltip(row, check)
	function row.Update()
		local value = tonumber(Model:Value(row.entry))
		check:SetChecked(value ~= nil and value ~= 0)
	end
	function row.SetControlEnabled(enabled)
		check:SetEnabled(enabled)
	end
end

function List:CreateChoice(row)
	local entry = row.entry
	local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(CONTROL_WIDTH)
	dropdown:SetPoint("LEFT", row, "TOPLEFT", CONTROL_X, self.controlY)
	dropdown:SetupMenu(function(_, root)
		for _, choice in ipairs(Registry.GetChoices(entry)) do
			local value = tostring(choice.value)
			local label = Text(choice.label)
			local radio = root:CreateRadio(label, function()
				return CVars.SameValue(Model:Value(entry), value)
			end, function()
				self:OnValueChanged(row, value)
			end)
			local reason = Registry.UnsupportedReason(entry, choice.value)
			if reason then
				radio:SetEnabled(false)
			end
			local tip = choice.tooltip and Text(choice.tooltip)
			if tip or reason then
				radio:SetTooltip(function(tooltip)
					GameTooltip_SetTitle(tooltip, Text(choice.label))
					if tip then
						GameTooltip_AddNormalLine(tooltip, tip, true)
					end
					if reason then
						GameTooltip_AddColoredLine(tooltip, reason, UI.COLORS.red, true)
					end
				end)
			end
		end
	end)
	ShareRowTooltip(row, dropdown)
	function row.Update()
		-- Shown when the game's value isn't one of the listed options.
		dropdown:SetDefaultText((L("Custom (%s)")):format(Model:Value(entry) or "?"))
		dropdown:GenerateMenu()
	end
	function row.SetControlEnabled(enabled)
		dropdown:SetEnabled(enabled)
	end
end

function List:CreateSlider(row)
	local entry = row.entry
	local spec = Registry.GetSlider(entry)
	local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	slider:SetSize(CONTROL_WIDTH, 20)
	slider:SetPoint("LEFT", row, "TOPLEFT", CONTROL_X, self.controlY)

	-- invert: the stock menu shows some settings reversed (displayed = invert - stored).
	local function ToDisplay(value)
		value = tonumber(value) or spec.min
		value = math.min(spec.max, math.max(spec.min, value))
		return entry.invert and entry.invert - value or value
	end
	local function FromDisplay(value)
		value = Round(value, spec.step)
		return entry.invert and Round(entry.invert - value, spec.step) or value
	end

	local steps = math.max(1, math.floor((spec.max - spec.min) / spec.step + 0.5))
	local formatters = {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(value)
			value = Round(value, spec.step)
			return spec.format and spec.format(value) or tostring(value)
		end,
	}
	slider:Init(ToDisplay(Model:Value(entry)), spec.min, spec.max, steps, formatters)
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		self:OnValueChanged(row, FromDisplay(value))
	end, row)

	-- A frame-rate cap: its on/off switch sits left of the slider, like the game's menu.
	local toggleEntry = entry.toggle and Registry.Get(entry.toggle)
	local check
	if toggleEntry then
		check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		check:SetPoint("RIGHT", slider, "LEFT", -4, 0)
		check:SetScript("OnClick", ns.Safe(function(button)
			Model:Set(toggleEntry, button:GetChecked() and 1 or 0)
			self:UpdateRow(row)
			self:UpdateFooter()
		end))
		row.toggleEntry = toggleEntry
	end
	ShareRowTooltip(row, check)
	ShareRowTooltip(row, slider)
	ShareRowTooltip(row, slider.Slider)
	ShareRowTooltip(row, slider.Back)
	ShareRowTooltip(row, slider.Forward)

	local enabled = true
	function row.Update()
		slider:SetValue(ToDisplay(Model:Value(entry)))
		local on = true
		if check then
			on = tonumber(Model:Value(toggleEntry)) == 1
			check:SetChecked(on)
		end
		slider:SetEnabled(enabled and on)
	end
	function row.SetControlEnabled(value)
		enabled = value
		if check then
			check:SetEnabled(value)
		end
		slider:SetEnabled(value and (not check or check:GetChecked()))
	end
end

-- Free-form value for discovered console variables.
function List:CreateText(row)
	local entry = row.entry
	local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	box:SetSize(CONTROL_WIDTH - 10, 20)
	box:SetPoint("LEFT", row, "TOPLEFT", CONTROL_X + 6, self.controlY)
	box:SetAutoFocus(false)

	local function Commit()
		local text = box:GetText()
		if text ~= (Model:Value(entry) or "") then
			self:OnValueChanged(row, text)
		end
	end
	box:SetScript("OnEnterPressed", function()
		Commit()
		box:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function()
		box:SetText(Model:Value(entry) or "")
		box:ClearFocus()
	end)
	box:SetScript("OnEditFocusLost", Commit)
	ShareRowTooltip(row, box)

	function row.Update()
		box:SetText(Model:Value(entry) or "")
	end
end

local CONTROLS = {
	toggle = List.CreateToggle,
	choice = List.CreateChoice,
	slider = List.CreateSlider,
	text = List.CreateText,
}

function List:CreateSettingRow(entry, group)
	local row = CreateFrame("Frame", nil, self.content)
	row:SetHeight(self.rowHeight)
	row.entry = entry
	row.group = group
	row:EnableMouse(true)

	-- No hover highlight (Josh, 2026-10-07: not needed); hovering just shows the tooltip.
	row:SetScript("OnEnter", function()
		ShowRowTooltip(row)
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)

	row.Marker = row:CreateTexture(nil, "ARTWORK")
	row.Marker:SetPoint("LEFT", 4, 0)
	row.Marker:SetSize(3, self.rowHeight - 12)
	row.Marker:SetColorTexture(UI.COLORS.gold:GetRGB())

	row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.Label:SetPoint("LEFT", row, "TOPLEFT", LABEL_X, self.controlY)
	row.Label:SetWidth(CONTROL_X - LABEL_X - (entry.toggle and TOGGLE_WIDTH or 0) - 12)
	row.Label:SetJustifyH("LEFT")
	row.Label:SetWordWrap(false)
	row.Label:SetText(Text(entry.label))

	-- What the setting does, on one line (Josh, 2026-10-10: details in tooltips); a longer
	-- one ends in "..." and the row's tooltip has it in full. Compact rows keep it in the
	-- tooltip only, like the game's own menu.
	if not self.options.compact then
		row.Summary = UI.Muted(row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
		row.Summary:SetPoint("TOPLEFT", LABEL_X, -30)
		row.Summary:SetPoint("RIGHT", -16, 0)
		row.Summary:SetJustifyH("LEFT")
		row.Summary:SetWordWrap(false)
		local summary = entry.summary or (entry.tooltip and Text(entry.tooltip)) or ""
		if entry.raid then
			summary = L("Raids and battlegrounds only: ") .. summary -- first, so it's never cut off
		end
		row.Summary:SetText(summary)
	end

	row.Tags = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	row.Tags:SetPoint("RIGHT", row, "TOPRIGHT", -8, self.controlY)
	row.Tags:SetWidth(TAGS_WIDTH)
	row.Tags:SetJustifyH("RIGHT")
	row.Tags:SetWordWrap(false)

	CONTROLS[entry.control](self, row)
	return row
end

function List:CreateHeader(group)
	local row = CreateFrame("Frame", nil, self.content)
	row:SetHeight(HEADER_HEIGHT)
	row.group = group

	row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	row.Title:SetPoint("TOPLEFT", LABEL_X - 4, -12)
	row.Title:SetText(Text(group.label))

	row.Line = row:CreateTexture(nil, "ARTWORK")
	row.Line:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", -4, -4)
	row.Line:SetPoint("RIGHT", -8, 0)
	row.Line:SetHeight(1)
	local goldR, goldG, goldB = UI.COLORS.gold:GetRGB()
	row.Line:SetColorTexture(goldR, goldG, goldB, 0.3)

	row.Note = UI.Muted(row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	row.Note:SetPoint("TOPLEFT", row.Line, "BOTTOMLEFT", 4, -6)
	row.Note:SetJustifyH("LEFT")

	if group.collapsible then
		row.Toggle = CreateFrame("Button", nil, row)
		row.Toggle:SetSize(170, 20)
		row.Toggle:SetPoint("TOPRIGHT", -12, -10)
		row.Toggle:SetNormalFontObject("GameFontHighlight")
		row.Toggle:SetHighlightFontObject("GameFontNormal")
		row.Toggle:SetText("Show")
		row.Toggle:SetScript("OnClick", ns.Safe(function()
			self:ToggleGroup(group)
		end))
		UI.Plain(row.Toggle)
	end
	return row
end

function List:BuildRows()
	for _, group in ipairs(Registry.groups) do
		if group.tab == self.options.tab then
			self.rows[#self.rows + 1] = self:CreateHeader(group)
			local inGroup = {}
			for _, entry in ipairs(Registry.entries) do
				if entry.group == group.id then
					inGroup[#inGroup + 1] = entry
				end
			end
			-- listOrder follows the game's own menu where it's set.
			table.sort(inGroup, function(a, b)
				local oa, ob = a.listOrder or 1000, b.listOrder or 1000
				if oa ~= ob then
					return oa < ob
				end
				return a.index < b.index
			end)
			for _, entry in ipairs(inGroup) do
				self.rows[#self.rows + 1] = self:CreateSettingRow(entry, group)
			end
		end
	end
end

-- Top bar: search and the World / Raids scope picker. -------------------------------

function List:CreateTopBar(panel, below)
	local bar = CreateFrame("Frame", nil, panel)
	if below then
		bar:SetPoint("TOP", below, "BOTTOM", 0, -4)
		bar:SetPoint("LEFT", panel, "LEFT")
		bar:SetPoint("RIGHT", panel, "RIGHT")
	else
		bar:SetPoint("TOPLEFT", 0, 0)
		bar:SetPoint("TOPRIGHT", 0, 0)
	end
	bar:SetHeight(TOP_BAR_HEIGHT)

	local search = CreateFrame("EditBox", nil, bar, "SearchBoxTemplate")
	search:SetSize(240, 20)
	search:SetPoint("LEFT", 14, 0)
	UI.Plain(search)
	search:HookScript("OnTextChanged", function(box)
		self.query = box:GetText():lower()
		self:RefreshAll()
	end)

	if self.options.scoped then
		local scope = CreateFrame("DropdownButton", nil, bar, "WowStyle1DropdownTemplate")
		scope:SetWidth(240)
		scope:SetPoint("RIGHT", -12, 0)
		local choices = {
			{ value = "world", label = "Base" },
			{ value = "raid", label = L("Raids & battlegrounds") },
		}
		UI.SetTooltip(scope, L("Settings for"), {
			{ text = L("Base: the settings the game uses everywhere.") },
			{ text = L("Raids & battlegrounds: the copies the game uses there while its Raid & Battleground Settings are on.") },
		})
		scope:SetupMenu(function(_, root)
			for _, choice in ipairs(choices) do
				root:CreateRadio(choice.label, function()
					return self.scope == choice.value
				end, function()
					self.scope = choice.value
					self:RefreshAll()
				end)
			end
		end)

		self.ScopeNotice = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		self.ScopeNotice:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 16, -2)
		self.ScopeNotice:SetPoint("RIGHT", -16, 0)
		self.ScopeNotice:SetJustifyH("LEFT")
		self.ScopeNotice:SetText(L("Raid & Battleground Settings is off, so the Base values apply everywhere."))
		self.ScopeNotice:SetWordWrap(false)
		self.ScopeNotice:Hide()
	end
	return bar
end

function List:CreateWarning(panel)
	local warning = CreateFrame("Frame", nil, panel)
	warning:SetAllPoints()
	warning:SetFrameLevel(panel:GetFrameLevel() + 50)
	warning:EnableMouse(true)

	-- Opaque, so the settings underneath can't be read until the warning is accepted.
	warning.Background = UI.AddPanelBackground(warning, 0)

	warning.Title = warning:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	warning.Title:SetPoint("TOP", 0, -70)
	warning.Title:SetText(L("Full control, so please take care"))

	warning.Text = warning:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	warning.Text:SetPoint("TOP", warning.Title, "BOTTOM", 0, -18)
	warning.Text:SetWidth(480)
	warning.Text:SetJustifyH("LEFT")
	warning.Text:SetText(WARNING_TEXT)

	warning.Accept = UI.Plain(UI.MakeGreen(CreateFrame("Button", nil, warning, "UIPanelButtonTemplate")))
	warning.Accept:SetSize(150, 24)
	warning.Accept:SetPoint("TOP", warning.Text, "BOTTOM", 0, -24)
	warning.Accept:SetText(L("I Understand"))
	warning.Accept:SetScript("OnClick", ns.Safe(function()
		ns.db.ui.acceptedCustomWarning = true
		warning:Hide()
		self.footer.Frame:Show()
	end))
	return warning
end

-- options.tab: "hidden" or "standard"; options.scoped: World/Raids picker; options.search
function UI.CreateSettingsList(panel, frame, options)
	-- expanded lasts for the session, so collapsible sections start closed every login.
	local list = setmetatable({ rows = {}, footer = {}, options = options, scope = "world", query = "", expanded = {} }, List)
	list.rowHeight = options.compact and COMPACT_ROW_HEIGHT or ROW_HEIGHT
	list.controlY = options.compact and -COMPACT_ROW_HEIGHT / 2 or -15

	-- An optional warning banner sits above everything; the rest stacks below it, so the
	-- banner can grow with its text without covering anything.
	local banner
	if options.banner then
		banner = UI.CreateWarningBanner(panel, options.banner)
		banner:SetPoint("TOPLEFT", 10, -8)
		banner:SetPoint("TOPRIGHT", -10, -8)
	end

	-- An optional fixed line under the banner. Its height follows the text at the panel's
	-- width, and the rows below hang from it, so it never overlaps them.
	local note
	if options.note then
		note = CreateFrame("Frame", nil, panel)
		note:SetPoint("TOP", banner or panel, banner and "BOTTOM" or "TOP", 0, banner and -4 or -8)
		note:SetPoint("LEFT", panel, "LEFT")
		note:SetPoint("RIGHT", panel, "RIGHT")
		note.Text = UI.Muted(note:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
		note.Text:SetPoint("TOPLEFT", 14, -2)
		note.Text:SetJustifyH("LEFT")
		note.Text:SetText(options.note)
		note:SetScript("OnSizeChanged", function(self, width)
			self.Text:SetWidth(math.max(1, (width or 0) - 28))
			self:SetHeight((self.Text:GetStringHeight() or 14) + 6)
		end)
		note:SetHeight(20) -- until the first size change gives it a width
	end

	local bar
	local top = 2
	if options.search or options.scoped then
		bar = list:CreateTopBar(panel, note or banner)
		top = options.scoped and 14 or 2
	end

	local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
	local above = bar or note or banner
	if above then
		scroll:SetPoint("TOP", above, "BOTTOM", 0, -(bar and top or 8))
		scroll:SetPoint("LEFT", panel, "LEFT")
	else
		scroll:SetPoint("TOPLEFT", 0, -top)
	end
	scroll:SetPoint("BOTTOMRIGHT", -22, 2)

	list.content = CreateFrame("Frame", nil, scroll)
	list.content:SetSize(1, 1)
	scroll:SetScrollChild(list.content)
	scroll:SetScript("OnSizeChanged", function(_, width)
		list.content:SetWidth(width)
		list:Layout()
	end)

	list.Empty = UI.Muted(panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight"))
	list.Empty:SetPoint("TOP", scroll, "TOP", 0, -40)
	list.Empty:SetText(L("No settings match your search."))
	list.Empty:Hide()

	-- The footer sits in the window's bottom bar, but belongs to this tab.
	local footer = list.footer
	footer.Frame = CreateFrame("Frame", nil, panel)
	footer.Frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.FOOTER_RIGHT, 8)
	footer.Frame:SetSize(400, 24)

	footer.Apply = UI.MakeGreen(CreateFrame("Button", nil, footer.Frame, "UIPanelButtonTemplate"))
	footer.Apply:SetSize(110, 24)
	footer.Apply:SetPoint("RIGHT")
	footer.Apply:SetText("Apply")
	footer.Apply:SetScript("OnClick", ns.Safe(function()
		UI.Apply(Model:Changes())
	end))
	UI.SetTooltip(footer.Apply, "Apply", {
		{ text = L("Applies your unapplied changes on this page and the other settings page.") },
		{ text = (L("You get %d seconds to keep them or switch back.")):format(UI.KEEP_SECONDS), color = UI.COLORS.green },
	})

	footer.Discard = CreateFrame("Button", nil, footer.Frame, "UIPanelButtonTemplate")
	UI.SetTooltip(footer.Discard, "Discard", { { text = L("Drops your unapplied changes. Nothing in the game changes.") } })
	footer.Discard:SetSize(110, 24)
	footer.Discard:SetPoint("RIGHT", footer.Apply, "LEFT", -6, 0)
	footer.Discard:SetText("Discard")
	footer.Discard:SetScript("OnClick", ns.Safe(function()
		Model:Discard()
		list:RefreshAll()
	end))

	footer.Count = footer.Frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	footer.Count:SetPoint("RIGHT", footer.Discard, "LEFT", -10, 0)

	if Model:Count() == 0 then
		Model:Load()
	end
	list:BuildRows()

	local warning = list:CreateWarning(panel)

	-- A batch fires one CVAR_UPDATE per setting: the model follows each, the list is
	-- redrawn once on the next frame.
	local redrawQueued = false
	ns.On("CVAR_UPDATE", function(name)
		if panel:IsVisible() and type(name) == "string" then
			Model:Refresh(name)
			if not redrawQueued then
				redrawQueued = true
				C_Timer.After(0, function()
					redrawQueued = false
					ns.SafeCall(list.RefreshAll, list)
				end)
			end
		end
	end)

	-- Tab switches keep unapplied edits.
	function panel.OnShown()
		if Model:Count() == 0 then
			Model:Load()
		end
		list:RefreshAll()
		local accepted = ns.db.ui.acceptedCustomWarning
		warning:SetShown(not accepted)
		footer.Frame:SetShown(accepted)
	end

	-- After settings change from outside this tab, start again from the game's values.
	function panel:Reload()
		Model:Load()
		self:OnShown()
	end

	return list
end
