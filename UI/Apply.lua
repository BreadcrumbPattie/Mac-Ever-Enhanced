local _, ns = ...
local L = ns.L

local CVars = ns.CVars

local UI = {}
ns.UI = UI

UI.ICON = "Interface\\Icons\\Trade_Engineering"

-- The game's dialog frame is see-through, so text over bright scenery becomes
-- unreadable (Josh, 2026-10-07). A flat near-black fill fixed that but looked too harsh
-- (Josh, 2026-10-07), so pop-ups use the stone texture of the game's own panels (the
-- one behind the main window), which is opaque. The dialog border's own see-through
-- black layer is hidden so it doesn't darken the stone.
UI.PANEL_TEXTURE = "Interface\\FrameGeneral\\UI-Background-Rock"

function UI.UsePanelTexture(texture)
	texture:SetTexture(UI.PANEL_TEXTURE, "REPEAT", "REPEAT")
	texture:SetHorizTile(true)
	texture:SetVertTile(true)
	return texture
end

function UI.AddPanelBackground(frame, inset)
	inset = inset or 6
	local background = UI.UsePanelTexture(frame:CreateTexture(nil, "BACKGROUND", nil, -7))
	background:SetPoint("TOPLEFT", inset, -inset)
	background:SetPoint("BOTTOMRIGHT", -inset, inset)
	if frame.Border and frame.Border.Bg then
		frame.Border.Bg:Hide()
	end
	return background
end

-- Secondary text. The game's "disabled" grey is hard to read on dark backgrounds, so
-- muted text uses a lighter grey (Josh, 2026-10-07: legibility review).
function UI.Muted(fontString)
	fontString:SetTextColor(0.8, 0.8, 0.8)
	return fontString
end

-- The positive choice: the game's own panel button, in green. A custom flat green
-- button was too garish (Josh, 2026-10-07); it should match Switch Back. The game has
-- no green version of this button. Tinting the red art can't work (a tint only darkens:
-- red turns brown, and desaturated red is near-black), so this uses the same button's
-- neutral grey art (the game's disabled look) tinted with the game's standard green
-- (GREEN_FONT_COLOR). Measured from the game art, it comes out as bright as the red
-- button. The template swaps the art on press, show, enable and disable, so it's set
-- again after each: grey "down" art while pressed, and the plain grey disabled look
-- when the button is disabled.
local GREY_ART = "Interface\\Buttons\\UI-Panel-Button-Disabled"
local GREY_ART_PRESSED = "Interface\\Buttons\\UI-Panel-Button-Disabled-Down"
local RED_ART = "Interface\\Buttons\\UI-Panel-Button-Up"
local WOW_GREEN = GREEN_FONT_COLOR or CreateColor(0.1, 1, 0.1)
local BUTTON_ART = { "Left", "Middle", "Right" }

-- self.green is off for a button UI.SetGreen has turned back to red: the template's own
-- art is left alone. self.greenWhenDisabled keeps a disabled button green (Applied).
local function Tint(self, pressed)
	if not self.green then
		return
	end
	local enabled = self:IsEnabled()
	for _, key in ipairs(BUTTON_ART) do
		local art = self[key]
		if art then
			if enabled or self.greenWhenDisabled then
				art:SetTexture(pressed and enabled and GREY_ART_PRESSED or GREY_ART)
				art:SetVertexColor(WOW_GREEN:GetRGB())
			else
				art:SetVertexColor(1, 1, 1)
			end
		end
	end
end

function UI.MakeGreen(button)
	button.green = true
	if not button.greenHooked then
		button.greenHooked = true
		button:HookScript("OnMouseDown", function(self)
			Tint(self, true)
		end)
		for _, script in ipairs({ "OnMouseUp", "OnShow", "OnEnable", "OnDisable" }) do
			button:HookScript(script, function(self)
				Tint(self, false)
			end)
		end
	end
	Tint(button, false)
	return button
end

-- An Apply button that turns into a green, unclickable "Applied" while what it applies is
-- in place, and back into the red Apply when it isn't (Josh, 2026-10-16). Its tooltip
-- still shows while disabled.
function UI.SetApplied(button, applied, label)
	if button.SetMotionScriptsWhileDisabled then
		button:SetMotionScriptsWhileDisabled(true)
	end
	button:SetText(applied and "Applied" or (label or "Apply"))
	button:SetDisabledFontObject(applied and "GameFontHighlight" or "GameFontDisable")
	if applied then
		button.greenWhenDisabled = true
		button:SetEnabled(false)
		UI.MakeGreen(button)
		return
	end
	button.green = false
	button.greenWhenDisabled = nil
	button:SetEnabled(true)
	for _, key in ipairs(BUTTON_ART) do
		local art = button[key]
		if art then
			art:SetTexture(RED_ART)
			art:SetVertexColor(1, 1, 1)
		end
	end
end

-- Text colours. Each one is at least WCAG AA (4.5:1) against the brightest 1% of the
-- stone background, including the preset cards' lighter wash (audit, 2026-10-07; the
-- hex codes used inline elsewhere match these). Red and grey were raised to pass.
UI.COLORS = {
	gold = CreateColor(1, 0.82, 0),
	green = CreateColor(0.25, 1, 0.25),
	orange = CreateColor(1, 0.6, 0.2),
	red = CreateColor(1, 0.55, 0.55),
	grey = CreateColor(0.7, 0.7, 0.7),
	muted = CreateColor(0.8, 0.8, 0.8),
	white = CreateColor(1, 1, 1),
	blue = CreateColor(0.435, 0.722, 1), -- information, not a warning (about 9:1 on the stone)
}

-- The same colours as inline markup: UI.HEX.green .. text .. "|r".
UI.HEX = {}
for key, color in pairs(UI.COLORS) do
	local r, g, b = color:GetRGB()
	UI.HEX[key] = ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function UI.Colored(key, text)
	return UI.HEX[key] .. text .. "|r"
end

-- The game's check box template is 32 pixels square; rows of switches are spaced by it.
UI.CHECK_SIZE = 32
UI.TICK = "Interface\\RaidFrame\\ReadyCheck-Ready" -- the game's green ready-check tick

-- Right inset of the window's bottom-right buttons: clear of the 16-pixel resize grip in
-- the corner, so a click near the button's edge never starts a resize.
UI.FOOTER_RIGHT = 26

-- Text sits on the page only where the player needs it to act; how things work, why, and
-- the caveats are in tooltips (Josh, 2026-10-10: "better utilise tooltip text rather than
-- having all text out on the page"). Every control has one.

-- lines: { { text, color } } or a function(frame) returning lines (and optionally a
-- title), for text that depends on the current state. Hooked, so a template's own
-- highlight scripts keep working.
function UI.SetTooltip(frame, title, lines)
	frame:HookScript("OnEnter", function(self)
		local shown, heading = lines, title
		if type(lines) == "function" then
			local fnTitle
			shown, fnTitle = lines(self)
			heading = fnTitle or title
		end
		if shown then
			UI.ShowTooltip(self, heading, shown)
		end
	end)
	frame:HookScript("OnLeave", GameTooltip_Hide)
	return frame
end

-- Marks a control whose label already says everything (Close, Back, a search box), so it
-- needs no tooltip; the UI tests check every other control has one.
function UI.Plain(frame)
	frame.plain = true
	return frame
end

-- The game's small "i" button, for the details behind a card or heading.
function UI.CreateInfoButton(parent, title, lines)
	return UI.SetTooltip(CreateFrame("Button", nil, parent, "UIPanelInfoButton"), title, lines)
end

-- Drives a System Check every frame. An error would repeat
-- every frame, so it stops the check instead, which puts the settings back.
function UI.CreateCheckDriver(parent)
	local driver = CreateFrame("Frame", nil, parent)
	driver:Hide()
	driver:SetScript("OnUpdate", function(self, elapsed)
		if not ns.SafeCall(ns.Benchmark.Tick, elapsed) then
			self:Hide()
			ns.Benchmark.Stop("stopped")
		end
	end)
	return driver
end

-- Pop-ups: the game's dialog border over the stone, closed by Escape, and scaled with
-- the window (Options > Window Size), so a player who enlarged Mac-ever can read them too.
UI.DIALOGS = {}

function UI.CreateDialog(name, width, title, strata)
	local dialog = CreateFrame("Frame", name, UIParent)
	dialog:SetWidth(width)
	dialog:SetFrameStrata(strata or "DIALOG")
	dialog:SetToplevel(true)
	dialog:SetClampedToScreen(true)
	dialog:EnableMouse(true)
	dialog:SetScale(ns.db.ui.scale or 1)
	table.insert(UISpecialFrames, name)
	dialog.Border = CreateFrame("Frame", nil, dialog, "DialogBorderTemplate")
	dialog.Border:SetAllPoints()
	UI.AddPanelBackground(dialog)
	if title then
		dialog.Title = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		dialog.Title:SetPoint("TOP", 0, -22)
		dialog.Title:SetWidth(width - 48)
		dialog.Title:SetText(title)
	end
	UI.DIALOGS[#UI.DIALOGS + 1] = dialog
	return dialog
end

-- Every change made from the window goes through UI.Apply: it applies the batch, then
-- asks the player to keep it. Doing nothing switches back automatically, like macOS does
-- after a display change, so a setting that makes the game unreadable undoes itself.
local KEEP_SECONDS = 15
UI.KEEP_SECONDS = KEEP_SECONDS

local dialog
local ticker
local undoBatch
local onFinished
local revertAfterCombat

local function Revert(undo)
	if InCombatLockdown() then
		revertAfterCombat = undo
		ns.Print(L("You're in combat, so the previous settings come back as soon as combat ends."))
		return
	end
	local results, effects = CVars.Apply(undo, false)
	if ns.ReportResults(results, effects) > 0 then
		ns.Print(L("Switched back to your previous settings."))
	end
end

ns.On("PLAYER_REGEN_ENABLED", function()
	if revertAfterCombat then
		local undo = revertAfterCombat
		revertAfterCombat = nil
		Revert(undo)
		UI.Refresh()
	end
end)

-- Sized to its text.
local function FitKeepDialog()
	local countdown = dialog.Countdown:GetText()
	local hasCountdown = countdown ~= nil and countdown ~= ""
	dialog.Countdown:SetShown(hasCountdown)
	dialog:SetHeight(22 + (dialog.Text:GetStringHeight() or 14)
		+ (hasCountdown and 10 + (dialog.Countdown:GetStringHeight() or 14) or 0) + 18 + 24 + 18)
end

local function Finish(keep)
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	dialog:Hide()

	local undo, callback = undoBatch, onFinished
	undoBatch, onFinished = nil, nil
	if not keep and undo and #undo > 0 then
		Revert(undo)
		UI.Refresh()
	end
	if callback then
		callback(keep)
	end
end

local function CreateDialog()
	local frame = UI.CreateDialog("MaceverKeepDialog", 400, nil, "FULLSCREEN_DIALOG")
	frame:SetPoint("TOP", 0, -140)

	frame.Text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.Text:SetPoint("TOP", 0, -22)
	frame.Text:SetWidth(360)

	frame.Countdown = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.Countdown:SetPoint("TOP", frame.Text, "BOTTOM", 0, -10)

	-- Switch Back on the left, Keep Settings (green) on the right.
	frame.Keep = UI.MakeGreen(CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"))
	frame.Keep:SetSize(150, 24)
	frame.Keep:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 6, 18)
	frame.Keep:SetText(L("Keep Settings"))
	frame.Keep:SetScript("OnClick", ns.Safe(function()
		Finish(true)
	end))

	frame.Revert = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.Revert:SetSize(150, 24)
	frame.Revert:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -6, 18)
	frame.Revert:SetText(L("Switch Back"))
	frame.Revert:SetScript("OnClick", ns.Safe(function()
		Finish(false)
	end))

	-- Escape while the countdown runs means Switch Back (Finish cancels the ticker before
	-- hiding, so its own Hide doesn't come back here).
	frame:SetScript("OnHide", ns.Safe(function()
		if frame.mode == "keep" and ticker then
			Finish(false)
		end
	end))

	frame:Hide()
	return frame
end

-- A batch still waiting on Keep or Switch Back is kept: the player moved on (a new batch,
-- or a System Check that must start from the settings as they are now).
function UI.SettleKeep()
	if dialog and dialog:IsShown() and dialog.mode == "keep" then
		Finish(true)
	end
end

local function ConfirmKeep(undo, changed, callback)
	dialog = dialog or CreateDialog()
	UI.SettleKeep()

	dialog.mode = "keep"
	dialog.Keep:SetText(L("Keep Settings"))
	dialog.Revert:SetText(L("Switch Back"))
	undoBatch, onFinished = undo, callback
	dialog.Text:SetText((L("Mac-ever changed %d setting%s. Keep them?")):format(changed, changed == 1 and "" or ns.L("s")))

	local remaining = KEEP_SECONDS
	local function Update()
		dialog.Countdown:SetText((L("Switching back in %d second%s.")):format(remaining, remaining == 1 and "" or ns.L("s")))
	end
	Update()
	FitKeepDialog()
	ticker = C_Timer.NewTicker(1, ns.Safe(function()
		remaining = remaining - 1
		if remaining <= 0 then
			Finish(false)
		else
			Update()
		end
	end), KEEP_SECONDS)
	dialog:Show()
end

-- callback(kept) runs once the player keeps or switches back, or straight away (kept)
-- when the settings already matched. It isn't called if the batch couldn't run.
-- emptyMessage replaces "Nothing needed changing." when nothing changed.
-- Whether settings may change now. Not during a System Check: it puts back the settings
-- it started from, which would silently undo the change.
function UI.CanChange()
	if ns.Benchmark.IsRunning() then
		ns.Print(L("A System Check is running. Stop it or let it finish, then try again."))
		return false
	end
	return true
end

function UI.Apply(changes, callback, emptyMessage)
	if not UI.CanChange() then
		return 0
	end
	local results, effects = CVars.Apply(changes)
	local changed = ns.ReportResults(results, effects, emptyMessage)
	if not results then
		return 0 -- in combat: nothing ran, so unapplied edits stay as they are
	end
	UI.Refresh()
	if changed > 0 then
		ConfirmKeep(CVars.UndoFor(results), changed, callback)
	elseif callback then
		callback(true)
	end
	return changed
end

function UI.ShowTooltip(owner, title, lines)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, title)
	for _, line in ipairs(lines) do
		if line.color then
			GameTooltip_AddColoredLine(GameTooltip, line.text, line.color, true)
		else
			GameTooltip_AddNormalLine(GameTooltip, line.text, true)
		end
	end
	GameTooltip:Show()
end

-- A simple yes/no dialog. onAccept runs only if the player confirms. With onDontShow it also
-- has a "Don't show this again" tick box; onDontShow runs if it's ticked when they confirm.
local confirm

function UI.Confirm(title, text, acceptLabel, onAccept, onDontShow)
	if not confirm then
		confirm = UI.CreateDialog("MaceverConfirmDialog", 440, "", "FULLSCREEN_DIALOG")
		confirm:SetPoint("CENTER", 0, 80)

		confirm.Text = confirm:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		confirm.Text:SetPoint("TOP", confirm.Title, "BOTTOM", 0, -12)
		confirm.Text:SetWidth(390)
		confirm.Text:SetJustifyH("LEFT")

		confirm.DontShow = UI.Plain(CreateFrame("CheckButton", nil, confirm, "UICheckButtonTemplate"))
		confirm.DontShow:SetPoint("TOPLEFT", confirm.Text, "BOTTOMLEFT", -4, -10)
		confirm.DontShow.Text:SetFontObject("GameFontHighlight")
		confirm.DontShow.Text:SetText(L("Don't show this again"))

		-- Cancel on the left, the choice being confirmed on the right (like Keep Settings).
		-- Not green: what it confirms is a risk.
		confirm.Accept = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate")
		confirm.Accept:SetSize(150, 24)
		confirm.Accept:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 6, 18)

		confirm.Cancel = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate")
		confirm.Cancel:SetSize(150, 24)
		confirm.Cancel:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -6, 18)
		confirm.Cancel:SetText(CANCEL or "Cancel")
		confirm.Cancel:SetScript("OnClick", ns.Safe(function()
			confirm:Hide()
		end))
	end

	confirm.Title:SetText(title)
	confirm.Text:SetText(text)
	confirm.DontShow:SetChecked(false)
	confirm.DontShow:SetShown(onDontShow ~= nil)
	confirm:SetHeight(22 + (confirm.Title:GetStringHeight() or 18) + 12 + (confirm.Text:GetStringHeight() or 60)
		+ (onDontShow and 10 + UI.CHECK_SIZE or 0) + 20 + 24 + 18)
	confirm.Accept:SetText(acceptLabel)
	confirm.Accept:SetScript("OnClick", ns.Safe(function()
		confirm:Hide()
		if onDontShow and confirm.DontShow:GetChecked() then
			onDontShow()
		end
		onAccept()
	end))
	confirm:Show()
end

-- Every goal is open to every Mac, and picking one above what Mac-ever recommends for this
-- Mac asks first (Josh, 2026-11-07; wording verbatim). onPick runs straight away for any
-- other goal, for no goal at all (`goal` nil), or once the player has turned the warning off.
-- The tick box that does that shows on the 2nd warning ever and no other (Josh, 2026-11-07).
-- `answers` stands in for the saved profile while setup is still asking.
local GOAL_WARNING = L("Mac-ever does not recommend you use this preset for this Apple Silicon Mac. If graphical performance or FPS is inadequate you accept that this is your decision and not reflective of Mac-ever's recommendation.")

function UI.ConfirmGoal(goal, onPick, answers)
	if not goal or ns.db.ui.hideGoalWarning or ns.Devices.Recommends(goal, answers) then
		onPick()
		return
	end
	local count = (ns.db.ui.goalWarningCount or 0) + 1
	ns.db.ui.goalWarningCount = count
	UI.Confirm("Warning", GOAL_WARNING, L("I Accept"), onPick, count == 2 and function()
		ns.db.ui.hideGoalWarning = true
	end or nil)
end

-- The "lower resolution" switch, used on the System Check tab and in Options. Off by
-- default. On, it lets the System Check (and the goal presets) lower render scale below
-- the usual 85% when a goal can't be reached otherwise, and lets Mac-ever change display
-- mode, notch mode and VSync (see Registry.RESOLUTION). Josh, 2026-10-08: with it on,
-- "mac-ever should make changes to things such as resolution, overriding the standard rule".
UI.RESOLUTION_SWITCH_LABEL = L("Let Mac-ever lower resolution to reach your goal")

function UI.CreateResolutionSwitch(parent, font)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check.Text:SetFontObject(font or "GameFontHighlightSmall")
	check.Text:SetText(UI.RESOLUTION_SWITCH_LABEL)
	check:SetScript("OnShow", function(self)
		self:SetChecked(ns.db.ui.allowResolution == true)
	end)
	check:SetScript("OnClick", ns.Safe(function(self)
		ns.db.ui.allowResolution = self:GetChecked() or nil
		UI.Refresh()
	end))
	check:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, UI.RESOLUTION_SWITCH_LABEL, {
			{ text = L("Off (recommended): render scale never goes below 85%, so the picture stays sharp, and Mac-ever never changes display mode, notch mode or VSync.") },
			{ text = L("On: when your goal can't be reached any other way, the System Check lowers render scale below 85% (down to 50%), with every other setting at its lowest. The 3D world gets softer; text and the interface stay sharp. Run the check again after turning it on."), color = UI.COLORS.orange },
			{ text = L("On also lets Mac-ever change display mode, notch mode and VSync. Changing those refreshes the game window, which can reset your resolution."), color = UI.COLORS.grey },
		})
	end)
	check:SetScript("OnLeave", GameTooltip_Hide)
	return check
end

-- The Uncapped switch, in setup and on the System Check tab (Josh, 2026-10-11: every goal
-- caps at its own frame rate; uncapped is the player's toggle). Off by default. get()
-- returns the choice and set(on) stores it.
function UI.CreateUncappedSwitch(parent, get, set)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check.Text:SetFontObject("GameFontHighlightSmall")
	check.Text:SetText("Uncapped")
	function check:Update()
		self:SetChecked(get() == true)
	end
	check:SetScript("OnShow", check.Update)
	check:SetScript("OnClick", ns.Safe(function(self)
		set(self:GetChecked() == true)
	end))
	UI.SetTooltip(check, "Uncapped", {
		{ text = L("Off (recommended): the frame rate is capped at your goal, so your Mac does no more work than it needs to and stays cooler.") },
		{ text = L("On: your goal becomes a minimum and nothing caps the frame rate, so your Mac runs as fast as it can. It works harder and gets warmer."), color = UI.COLORS.orange },
	})
	return check
end
