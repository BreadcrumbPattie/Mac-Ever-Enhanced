local _, ns = ...
local L = ns.L

local UI = ns.UI
local CVars = ns.CVars

local WIDTH, HEIGHT = 800, 680
-- 800 wide keeps the footer's three buttons (left) clear of a settings page's Apply,
-- Discard and change count (right).
local MIN_WIDTH, MIN_HEIGHT = 800, 600
local MAX_WIDTH, MAX_HEIGHT = 1400, 1100
local TAB_TEXT_PADDING = 48 -- the game's tab template leaves only 10px, so long names touch the edges
local STATUS_INTERVAL = 0.5

-- Tabs register themselves at load time; the window is only built on first open.
local tabs = {}

-- build(panel, frame) fills the panel once; panel.OnShown runs each time the tab opens.
function UI.RegisterTab(name, build)
	tabs[#tabs + 1] = { name = name, build = build }
end

local frame

local function UpdateFooter()
	frame.RestoreButton:SetEnabled(#CVars.ListChanged() > 0)
end

local function UpdateStatus()
	local size = C_VideoOptions.GetCurrentGameWindowSize()
	frame.Status:SetText(("%s   |cffb3b3b3·|r   %d × %d window   |cffb3b3b3·|r   %.0f fps"):format(
		ns.ChipNames(), size.x, size.y, GetFramerate()))
end

local function SelectTab(tabID)
	for id, tab in ipairs(tabs) do
		tab.panel:SetShown(id == tabID)
	end
	local panel = tabs[tabID].panel
	if panel.OnShown then
		panel:OnShown()
	end
	frame.selectedTab = tabID
end

local function Create()
	frame = CreateFrame("Frame", "MaceverFrame", UIParent, "PortraitFrameTemplate")
	local size = ns.db.ui.size
	frame:SetSize(math.max(MIN_WIDTH, size and size.width or WIDTH), math.max(MIN_HEIGHT, size and size.height or HEIGHT))
	frame:SetScale(ns.db.ui.scale or 1)
	frame:SetPoint("CENTER")
	-- Resizable with the game's own corner grip; every tab lays itself out to the size.
	frame:SetResizable(true)
	frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	frame.ResizeButton = CreateFrame("Button", nil, frame, "PanelResizeButtonTemplate")
	frame.ResizeButton:SetPoint("BOTTOMRIGHT", -4, 4)
	frame.ResizeButton:Init(frame, MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	frame:HookScript("OnSizeChanged", function(_, width, height)
		ns.db.ui.size = { width = width, height = height }
	end)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetTitle("Mac-ever")
	frame:SetPortraitToAsset(UI.ICON)
	table.insert(UISpecialFrames, "MaceverFrame") -- Escape closes it

	frame.Status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.Status:SetPoint("TOPLEFT", 64, -36)
	frame.Status:SetPoint("RIGHT", -16, 0)
	frame.Status:SetJustifyH("LEFT")
	frame.Status:SetWordWrap(false) -- one line; never spills under the title

	frame.Inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
	frame.Inset:SetPoint("TOPLEFT", 10, -60)
	frame.Inset:SetPoint("BOTTOMRIGHT", -8, 38)
	-- The inset's own background is near-black marble (average RGB 13, 13, 13), far too
	-- dark for this much text (Josh, 2026-10-07). The window's own stone is used instead;
	-- the inset's border still frames the content.
	UI.UsePanelTexture(frame.Inset.Bg)

	frame.RestoreButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.RestoreButton:SetSize(150, 24)
	frame.RestoreButton:SetPoint("BOTTOMLEFT", 12, 8)
	frame.RestoreButton:SetText(L("Restore Originals"))
	frame.RestoreButton:SetScript("OnClick", ns.Safe(function()
		local results, effects = CVars.RestoreOriginals()
		ns.ReportResults(results, effects, L("Everything is already as it was before Mac-ever."))
		UI.Refresh()
	end))
	UI.SetTooltip(frame.RestoreButton, L("Restore Originals"), {
		{ text = L("Undoes Mac-ever's changes: every setting Mac-ever has changed goes back to how it was before.") },
		{ text = L("A setting changed since, in the game's menu or by another addon, is left as it is."), color = UI.COLORS.grey },
	})

	frame.DefaultsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.DefaultsButton:SetSize(150, 24)
	frame.DefaultsButton:SetPoint("LEFT", frame.RestoreButton, "RIGHT", 8, 0)
	frame.DefaultsButton:SetText(L("Game Defaults"))
	frame.DefaultsButton:SetScript("OnClick", ns.Safe(function()
		UI.Apply(CVars.DefaultChanges())
	end))
	UI.SetTooltip(frame.DefaultsButton, L("Game Defaults"), {
		{ text = L("Resets the settings on the game's own Graphics menu to their defaults, like the menu's Defaults button. Hidden settings aren't touched.") },
		{ text = (L("You get %d seconds to keep or switch back, and Restore Originals undoes it later.")):format(UI.KEEP_SECONDS), color = UI.COLORS.green },
	})

	-- Report a Problem lives in the footer since the Mac Fixes tab went (Josh, 2026-11-04).
	frame.ReportButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.ReportButton:SetSize(150, 24)
	frame.ReportButton:SetPoint("LEFT", frame.DefaultsButton, "RIGHT", 8, 0)
	frame.ReportButton:SetText(L("Report a Problem"))
	frame.ReportButton:SetScript("OnClick", ns.Safe(function()
		UI.ShowReport()
	end))
	UI.SetTooltip(frame.ReportButton, L("Report a Problem"), {
		{ text = L("Shows a report of your Mac, setup and settings to copy and post on Mac-ever's CurseForge page. You can also type /macever report.") },
		{ text = L("It has no character or realm names. If the game crashed, the window says which crash file to add."), color = UI.COLORS.grey },
	})
	-- The footer's buttons are as wide as their labels, so all three fit on the left.
	for _, button in ipairs({ frame.RestoreButton, frame.DefaultsButton, frame.ReportButton }) do
		button:SetWidth(math.max(110, (button:GetTextWidth() or 0) + 32))
	end

	for _, tab in ipairs(tabs) do
		local panel = CreateFrame("Frame", nil, frame.Inset)
		panel:SetPoint("TOPLEFT", 4, -4)
		panel:SetPoint("BOTTOMRIGHT", -4, 4)
		panel:Hide()
		tab.panel = panel
		tab.build(panel, frame)
	end

	frame.TabSystem = CreateFrame("Frame", nil, frame, "TabSystemTemplate")
	frame.TabSystem:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 22, 2)
	for id, tab in ipairs(tabs) do
		frame.TabSystem:AddTab(tab.name)
		-- Size each tab to its text with proper padding.
		local button = frame.TabSystem:GetTabButton(id)
		local textWidth = button.Text:GetStringWidth()
		button.Text:SetWidth(textWidth + 4)
		button:SetTabWidth(textWidth + TAB_TEXT_PADDING)
	end
	frame.TabSystem:MarkDirty()
	frame.TabSystem:SetTabSelectedCallback(function(tabID)
		SelectTab(tabID)
		return false
	end)

	local elapsed = STATUS_INTERVAL
	frame:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed >= STATUS_INTERVAL then
			elapsed = 0
			UpdateStatus()
		end
	end)
	frame:SetScript("OnShow", function()
		UpdateStatus()
		UpdateFooter()
	end)

	frame.TabSystem:SetTab(1)
end

-- Re-reads everything after settings change outside the current tab. panel.Reload
-- (if present) also drops unapplied edits, since the values under them just changed.
local refreshers = {}

-- fn runs on every UI.Refresh, for pop-ups that show settings too.
function UI.OnRefresh(fn)
	refreshers[#refreshers + 1] = fn
end

function UI.Refresh()
	for _, fn in ipairs(refreshers) do
		fn()
	end
	if not frame or not frame:IsShown() then
		return
	end
	UpdateFooter()
	local panel = tabs[frame.selectedTab].panel
	local reload = panel.Reload or panel.OnShown
	if reload then
		reload(panel)
	end
end

-- Opens the window on a tab by name.
-- Shows the window on tabID (or the tab it was on). Each tab's OnShown runs once: a new
-- window has just selected its first tab, and switching tabs runs the new one's.
local function Open(tabID)
	if UI.NeedsSetup() then
		-- First time ever: the start-up message, then setup, without the window behind.
		UI.MaybeShowStartWarning()
		UI.MaybeShowSetup()
		return
	end
	local fresh = not frame
	if fresh then
		Create()
	end
	frame:Show()
	if tabID and tabID ~= frame.selectedTab then
		frame.TabSystem:SetTab(tabID)
	elseif not fresh then
		SelectTab(frame.selectedTab)
	end
	UI.MaybeShowStartWarning()
end

function UI.SelectTab(name)
	for id, tab in ipairs(tabs) do
		if tab.name == name then
			return Open(id)
		end
	end
	Open()
end

-- Window size for legibility (the game's own UI scale may be small, e.g. 0.65).
UI.SCALES = { 1, 1.15, 1.3, 1.5 }

function UI.SetScale(scale)
	ns.db.ui.scale = scale
	if frame then
		frame:SetScale(scale)
	end
	for _, dialog in ipairs(UI.DIALOGS) do
		dialog:SetScale(scale)
	end
end

function UI.Show()
	Open()
end

function UI.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		UI.Show()
	end
end
