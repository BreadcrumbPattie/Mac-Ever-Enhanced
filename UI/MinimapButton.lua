local _, ns = ...
local L = ns.L

local UI = ns.UI

-- The minimap button, through LibDBIcon (Josh, 2026-10-11): the standard button most
-- addons use, so minimap button collectors gather it and square or restyled minimaps
-- (ElvUI, Leatrix) place it properly. Forever doesn't load the Retail addon compartment.
-- The libraries come with Mac-ever's packaged releases (.pkgmeta externals); for a copy
-- straight from the repository, scripts/fetch-libs.sh puts them in Libs.
local NAME = "Mac-ever"
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local launcher = LDB and LDB:NewDataObject(NAME, {
	type = "launcher",
	label = NAME,
	icon = UI.ICON,
	OnClick = function()
		ns.SafeCall(UI.Toggle)
	end,
	OnTooltipShow = function(tooltip)
		tooltip:AddLine(NAME)
		tooltip:AddLine(L("Click to open. Drag to move this button."), 1, 1, 1, true)
	end,
})

function UI.SetMinimapButtonShown(shown)
	ns.db.ui.minimap.hide = not shown
	if not DBIcon then
		return
	end
	if shown then
		DBIcon:Show(NAME)
	else
		DBIcon:Hide(NAME)
	end
end

ns.On("PLAYER_LOGIN", function()
	if not (launcher and DBIcon) then
		ns.Print(L("The minimap button's libraries are missing. Type /macever to open Mac-ever."))
		return
	end
	-- LibDBIcon keeps its position (minimapPos) and hide in this table.
	DBIcon:Register(NAME, launcher, ns.db.ui.minimap)
end)
