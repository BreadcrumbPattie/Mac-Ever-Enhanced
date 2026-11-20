local _, ns = ...
local L = ns.L

local UI = ns.UI

-- Report a Problem (Josh, 2026-10-13): the text from ProblemReport in a selected,
-- read-only box. Addons can't write the clipboard, so the player presses Cmd+C and posts
-- it on Mac-ever's CurseForge page.
local WIDTH = 600
local SIDE = 24
local BOX_HEIGHT = 240

local INTRO = L("Press Cmd+C to copy the report below (it's already selected), then paste it in a comment on Mac-ever's CurseForge page:")
local CRASH_NOTE = L("If the game crashed, also attach the newest .txt file from %s. It lists your settings at the moment of the crash.")

local dialog

-- A box whose text can be selected and copied but not changed.
local function ReadOnly(box, text)
	box.fixedText = text
	box:SetText(text)
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(self.fixedText)
			self:HighlightText()
		end
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box:SetScript("OnEscapePressed", function()
		dialog:Hide()
	end)
end

local function Create()
	dialog = UI.CreateDialog("MaceverReportDialog", WIDTH, L("Report a Problem"))
	dialog:SetPoint("CENTER", 0, 40)
	local inner = WIDTH - SIDE * 2

	dialog.Text = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	dialog.Text:SetPoint("TOP", dialog.Title, "BOTTOM", 0, -12)
	dialog.Text:SetWidth(inner)
	dialog.Text:SetJustifyH("LEFT")
	dialog.Text:SetText(INTRO)
	local y = 22 + (dialog.Title:GetStringHeight() or 18) + 12 + (dialog.Text:GetStringHeight() or 30) + 8

	dialog.Link = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
	dialog.Link:SetSize(inner - 8, 22)
	dialog.Link:SetPoint("TOPLEFT", SIDE + 6, -y)
	dialog.Link:SetAutoFocus(false)
	ReadOnly(dialog.Link, ns.ProblemReport.URL)
	y = y + 22 + 8

	dialog.Crash = UI.Muted(dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	dialog.Crash:SetPoint("TOPLEFT", SIDE, -y)
	dialog.Crash:SetWidth(inner)
	dialog.Crash:SetJustifyH("LEFT")
	dialog.Crash:SetText(CRASH_NOTE:format(ns.ProblemReport.ERRORS_FOLDER))
	y = y + (dialog.Crash:GetStringHeight() or 24) + 10

	-- The report scrolls inside an inset, so a long error stack never grows the window.
	local inset = CreateFrame("Frame", nil, dialog, "InsetFrameTemplate")
	inset:SetPoint("TOPLEFT", SIDE, -y)
	inset:SetSize(inner, BOX_HEIGHT)
	UI.UsePanelTexture(inset.Bg)
	local scroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	dialog.Scroll = scroll
	dialog.Box = CreateFrame("EditBox", nil, scroll)
	dialog.Box:SetMultiLine(true)
	dialog.Box:SetAutoFocus(false)
	dialog.Box:SetFontObject("GameFontHighlightSmall")
	dialog.Box:SetWidth(inner - 36)
	scroll:SetScrollChild(dialog.Box)
	y = y + BOX_HEIGHT + 14

	dialog.SelectAll = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	dialog.SelectAll:SetSize(150, 24)
	dialog.SelectAll:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -6, 18)
	dialog.SelectAll:SetText(L("Select All"))
	dialog.SelectAll:SetScript("OnClick", ns.Safe(function()
		dialog.Box:SetFocus()
		dialog.Box:HighlightText()
	end))
	UI.SetTooltip(dialog.SelectAll, L("Select All"), {
		{ text = L("Selects the whole report again, so Cmd+C copies all of it.") },
	})

	dialog.Close = UI.Plain(CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate"))
	dialog.Close:SetSize(150, 24)
	dialog.Close:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 6, 18)
	dialog.Close:SetText(CLOSE or "Close")
	dialog.Close:SetScript("OnClick", function()
		dialog:Hide()
	end)

	dialog:SetHeight(y + 24 + 18)
end

function UI.ShowReport()
	if not dialog then
		Create()
	end
	-- Built fresh each time, so it shows the settings as they are now.
	ReadOnly(dialog.Box, ns.ProblemReport.Build())
	dialog:Show()
	dialog.Scroll:SetVerticalScroll(0)
	dialog.Box:SetFocus()
	dialog.Box:HighlightText()
end
