local _, ns = ...
local L = ns.L

local UI = ns.UI

-- What Mac-ever is for, and that results vary and can crash the game (Josh, 2026-10-08):
-- a pop-up when the window opens (until the player ticks "Don't show this again"), and
-- a banner at the top of Hidden Settings. Banner text is kept to about two lines so the
-- page keeps its room. The System Check's risk is on its Run tooltip (Josh, 2026-10-16:
-- too many warnings on that page).

local ALERT_ICON = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"

-- Banner colours, checked for contrast against the stone: gold title 7.1:1, white text
-- 10.4:1 over the orange wash (WCAG AAA).
local WASH = { 1, 0.6, 0.2, 0.10 }
local ACCENT = { 1, 0.6, 0.2, 0.9 }
local PAD = 10
local ICON_SIZE = 22

-- A warning strip for one of UI.WARNINGS (or any { title, text, details?, action? }, where
-- action = { label, tooltip, onClick } adds a button). The caller anchors its TOPLEFT and TOPRIGHT; it
-- sets its own height to fit the text at whatever width it gets, so it never cuts text
-- off. The risk stays on the page; the background is on hover.
function UI.CreateWarningBanner(parent, warning)
	local banner = CreateFrame("Frame", nil, parent)

	banner.Wash = banner:CreateTexture(nil, "BACKGROUND")
	banner.Wash:SetAllPoints()
	banner.Wash:SetColorTexture(unpack(WASH))
	banner.Accent = banner:CreateTexture(nil, "BORDER")
	banner.Accent:SetPoint("TOPLEFT")
	banner.Accent:SetPoint("BOTTOMLEFT")
	banner.Accent:SetWidth(3)
	banner.Accent:SetColorTexture(unpack(ACCENT))

	banner.Icon = banner:CreateTexture(nil, "ARTWORK")
	banner.Icon:SetTexture(ALERT_ICON)
	banner.Icon:SetSize(ICON_SIZE, ICON_SIZE)
	banner.Icon:SetPoint("TOPLEFT", PAD, -PAD + 2)

	banner.Title = banner:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	banner.Title:SetPoint("TOPLEFT", banner.Icon, "TOPRIGHT", 8, -2)
	banner.Title:SetJustifyH("LEFT")
	banner.Title:SetText(warning.title)

	banner.Text = banner:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	banner.Text:SetPoint("TOPLEFT", banner.Title, "BOTTOMLEFT", 0, -4)
	banner.Text:SetJustifyH("LEFT")
	banner.Text:SetText(warning.text)
	if warning.details then
		banner:EnableMouse(true)
		UI.SetTooltip(banner, warning.title, { { text = warning.details } })
	end
	-- An optional button on the right, for the one thing the warning asks the player to do.
	local actionWidth = 0
	if warning.action then
		banner.Action = CreateFrame("Button", nil, banner, "UIPanelButtonTemplate")
		banner.Action:SetText(warning.action.label)
		actionWidth = math.max(120, (banner.Action:GetFontString():GetStringWidth() or 0) + 32)
		banner.Action:SetSize(actionWidth, 24)
		banner.Action:SetPoint("RIGHT", -PAD, 0)
		banner.Action:SetScript("OnClick", warning.action.onClick)
		UI.SetTooltip(banner.Action, warning.action.label, warning.action.tooltip)
		actionWidth = actionWidth + PAD
	end

	function banner:Fit(width)
		if not width or width <= 0 then
			return
		end
		local textWidth = width - PAD - ICON_SIZE - 8 - PAD - actionWidth
		self.Title:SetWidth(textWidth)
		self.Text:SetWidth(textWidth)
		self:SetHeight(PAD + (self.Title:GetStringHeight() or 14) + 4 + (self.Text:GetStringHeight() or 24) + PAD)
	end
	banner:SetScript("OnSizeChanged", function(self, width)
		self:Fit(width)
	end)
	banner:SetHeight(60) -- until the first size change gives it a width
	return banner
end

UI.WARNINGS = {
	hidden = {
		title = L("Advanced settings: results vary and can crash the game"),
		text = L("Some can cause visual problems, stutter or crashes. Change one at a time; Restore Originals undoes Mac-ever's changes."),
		details = L("Settings the game's own menu doesn't show, for fine-tuning beyond the presets. What works on one Mac may not on another."),
	},
}

-- The start-up pop-up. Shown the first time the window opens each session, until the
-- player ticks "Don't show this again", which hides it for good (Options can bring it back).
local START_TITLE = L("Before you start")
local START_TEXT = table.concat({
	L("Mac-ever tunes World of Warcraft: Forever's graphics for Apple Silicon Macs, using measurements taken on your own Mac."),
	-- Josh's wording, verbatim (2026-11-04).
	L("Mac-ever will be updated throughout World of Warcraft: Forever as we understand how WoW: Forever performs on Apple Silicon Macs."),
	L("Results vary between Macs, places in the world and game updates. Some changes, especially from the System Check and Hidden Settings, can cause visual problems, stutter or crashes."),
	(L("Every change gives you %d seconds to keep it or switch back, and Restore Originals undoes everything Mac-ever has changed. If the game ever crashes, type /macever defaults after restarting to reset its graphics settings.")):format(UI.KEEP_SECONDS),
	L("Mac-ever is a fan-made addon, not made or supported by Blizzard."),
}, "\n\n")
local WIDTH = 480

local startWarning
local shownThisSession = false

local function CreateStartWarning()
	local dialog = UI.CreateDialog("MaceverStartWarning", WIDTH, nil, "FULLSCREEN_DIALOG")
	dialog:SetPoint("CENTER", 0, 60)

	dialog.Icon = dialog:CreateTexture(nil, "ARTWORK")
	dialog.Icon:SetTexture(ALERT_ICON)
	dialog.Icon:SetSize(36, 36)
	dialog.Icon:SetPoint("TOP", 0, -20)

	dialog.Title = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	dialog.Title:SetPoint("TOP", dialog.Icon, "BOTTOM", 0, -8)
	dialog.Title:SetText(START_TITLE)

	dialog.Text = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	dialog.Text:SetPoint("TOP", dialog.Title, "BOTTOM", 0, -14)
	dialog.Text:SetWidth(WIDTH - 56)
	dialog.Text:SetJustifyH("LEFT")
	-- On an Intel Mac or a PC, that comes first.
	if ns.IsAppleSilicon() then
		dialog.Text:SetText(START_TEXT)
	else
		dialog.Text:SetText((L("This computer's graphics chip (%s) isn't Apple Silicon. %s\n\n%s")):format(
			ns.ChipNames(), ns.NOT_APPLE_SILICON, START_TEXT))
	end

	dialog.DontShow = UI.Plain(CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate"))
	dialog.DontShow:SetPoint("TOPLEFT", dialog.Text, "BOTTOMLEFT", -4, -14)
	dialog.DontShow.Text:SetFontObject("GameFontHighlight")
	dialog.DontShow.Text:SetText(L("Don't show this again"))

	dialog.OK = UI.Plain(UI.MakeGreen(CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")))
	dialog.OK:SetSize(150, 24)
	dialog.OK:SetPoint("BOTTOM", 0, 18)
	dialog.OK:SetText(L("I Understand"))
	dialog.OK:SetScript("OnClick", ns.Safe(function()
		if dialog.DontShow:GetChecked() then
			ns.db.ui.hideStartWarning = true
		end
		dialog:Hide()
	end))

	-- Icon, title, text, the switch and the button, sized to the text.
	dialog:SetHeight(20 + 36 + 8 + (dialog.Title:GetStringHeight() or 18) + 14 + (dialog.Text:GetStringHeight() or 200)
		+ 14 + UI.CHECK_SIZE + 10 + 24 + 18)
	return dialog
end

function UI.ShowStartWarning()
	startWarning = startWarning or CreateStartWarning()
	startWarning.DontShow:SetChecked(ns.db.ui.hideStartWarning == true)
	startWarning:Show()
end

-- Called whenever the main window opens.
function UI.MaybeShowStartWarning()
	if shownThisSession or ns.db.ui.hideStartWarning then
		return
	end
	shownThisSession = true
	UI.ShowStartWarning()
end
