local _, ns = ...
local L = ns.L

local UI = ns.UI

-- Mac-ever's entry under Options > AddOns: a short description, a way into the main
-- window and the minimap button toggle.
local function Create()
	local panel = CreateFrame("Frame")

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Mac-ever")

	local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	description:SetPoint("RIGHT", -16, 0)
	description:SetJustifyH("LEFT")
	description:SetText(L("Graphics tuning for Apple Silicon Macs: a System Check that measures your Mac, presets, and every graphics setting the game allows."))

	local open = UI.Plain(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
	open:SetSize(180, 24)
	open:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -20)
	open:SetText(L("Open Mac-ever"))
	open:SetScript("OnClick", ns.Safe(function()
		HideUIPanel(SettingsPanel)
		UI.Show()
	end))

	local minimap = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	minimap:SetPoint("TOPLEFT", open, "BOTTOMLEFT", -4, -16)
	minimap.Text:SetFontObject("GameFontHighlight")
	minimap.Text:SetText(L("Show minimap button"))
	minimap:SetScript("OnClick", ns.Safe(function(self)
		UI.SetMinimapButtonShown(self:GetChecked())
	end))
	UI.Plain(minimap)

	local startWarning = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	startWarning:SetPoint("TOPLEFT", minimap, "BOTTOMLEFT", 0, -8)
	startWarning.Text:SetFontObject("GameFontHighlight")
	startWarning.Text:SetText(L("Show the warning when opening Mac-ever"))
	startWarning:SetScript("OnClick", ns.Safe(function(self)
		ns.db.ui.hideStartWarning = not self:GetChecked()
	end))
	UI.SetTooltip(startWarning, L("Show the warning when opening Mac-ever"), {
		{ text = L("The \"Before you start\" message: what Mac-ever does, that results vary, and how to undo everything.") },
	})

	panel:SetScript("OnShow", function()
		minimap:SetChecked(not ns.db.ui.minimap.hide)
		startWarning:SetChecked(not ns.db.ui.hideStartWarning)
	end)

	local resolution = UI.CreateResolutionSwitch(panel, "GameFontHighlight")
	resolution:SetPoint("TOPLEFT", startWarning, "BOTTOMLEFT", 0, -8)

	-- Window size, for legibility.
	local sizeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	sizeLabel:SetPoint("TOPLEFT", resolution, "BOTTOMLEFT", 4, -16)
	sizeLabel:SetText(L("Mac-ever window size:"))
	local size = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
	size:SetWidth(140)
	size:SetPoint("LEFT", sizeLabel, "RIGHT", 10, 0)
	size:SetupMenu(function(_, root)
		for _, scale in ipairs(UI.SCALES) do
			root:CreateRadio(("%d%%"):format(math.floor(scale * 100 + 0.5)), function()
				return (ns.db.ui.scale or 1) == scale
			end, function()
				UI.SetScale(scale)
			end)
		end
	end)
	UI.SetTooltip(size, L("Mac-ever window size"), {
		{ text = L("Makes Mac-ever's window and pop-ups larger, for easier reading. You can also resize the window by dragging its bottom-right corner.") },
	})

	-- Language (fork addition). Kept in a CVar so it's known while the files load
	-- (Locale.lua); changing it reloads the interface.
	local languageLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	languageLabel:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -22)
	languageLabel:SetText("Language / Jezik:")
	local language = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
	language:SetWidth(180)
	language:SetPoint("LEFT", languageLabel, "RIGHT", 10, 0)
	language:SetupMenu(function(_, root)
		for _, item in ipairs(ns.Locale.LANGUAGES) do
			root:CreateRadio(item.label, function()
				return ns.Locale.lang == item.id
			end, function()
				if ns.Locale.lang ~= item.id then
					ns.Locale.Set(item.id)
					ReloadUI()
				end
			end)
		end
	end)
	UI.SetTooltip(language, "Language / Jezik", {
		{ text = "Changing the language reloads the interface. / Promena jezika ponovo učitava interfejs." },
	})

	local hint = UI.Muted(panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	hint:SetPoint("TOPLEFT", languageLabel, "BOTTOMLEFT", 0, -16)
	hint:SetPoint("RIGHT", -16, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText(L("You can also type /macever in chat."))

	local category = Settings.RegisterCanvasLayoutCategory(panel, "Mac-ever")
	Settings.RegisterAddOnCategory(category)
end

ns.On("PLAYER_LOGIN", Create)
