local _, ns = ...
local L = ns.L

-- Console-only settings the stock Graphics menu doesn't show, plus every other graphics
-- console variable the game reports.
ns.UI.RegisterTab(L("Hidden Settings"), function(panel, frame)
	ns.UI.CreateSettingsList(panel, frame, { tab = "hidden", scoped = true, search = true, banner = ns.UI.WARNINGS.hidden,
		note = L("The System Check and goal presets set these back to the game's defaults, apart from Mac-ever's fixed values, unless Keep my Hidden Settings is on. Changing them can cost frame rate or picture quality.") })
end)
