local _, ns = ...
local L = ns.L

-- Everything on the game's own Graphics page, in the same order and sections, with a
-- Base / Raid switch like the menu's.
ns.UI.RegisterTab(L("Standard Settings"), function(panel, frame)
	ns.UI.CreateSettingsList(panel, frame, { tab = "standard", compact = true, scoped = true, search = true })
end)
