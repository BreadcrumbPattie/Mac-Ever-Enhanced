local _, ns = ...

local CVars = ns.CVars
local Registry = ns.Registry
local Print = ns.Print
local REASONS = ns.REASONS

-- Prints what happened to a batch. Returns how many settings changed.
function ns.ReportResults(results, effects, emptyMessage)
	if not results then
		Print(REASONS[effects])
		return 0
	end

	local changed = 0
	for _, result in ipairs(results) do
		if result.status == "changed" or result.status == "staged" then
			changed = changed + 1
		elseif result.status == "adjusted" then
			changed = changed + 1
			Print(("%s was set to %s, the closest value the game allows"):format(result.name, result.detail))
		elseif result.status == "failed" then
			Print(("%s wasn't changed: %s"):format(result.name, REASONS[result.detail]))
		end
	end

	if changed == 0 then
		Print(emptyMessage or "Nothing needed changing.")
	else
		Print(("Changed %d setting%s."):format(changed, changed == 1 and "" or ns.L("s")))
	end
	-- Renderer settings too: Mac-ever never restarts the renderer (see CVars.Apply).
	if effects.gx or effects.client then
		local labels = {}
		for _, result in ipairs(results) do
			local entry = Registry.Get(result.name)
			if entry and (entry.restart == "client" or entry.restart == "gx") and CVars.DidChange(result) then
				labels[#labels + 1] = ns.Text(entry.label)
			end
		end
		local list = #labels == 1 and labels[1]
			or ("%s and %s"):format(table.concat(labels, ", ", 1, #labels - 1), labels[#labels])
		Print(("%s %s effect after you restart the game."):format(list, #labels == 1 and "takes" or "take"))
	end
	return changed
end

local function ShowHelp()
	Print("Commands:")
	print("  /macever - open or close the Mac-ever window")
	print("  /macever setup - tell Mac-ever which Mac you have and the frame rate you want, then run the System Check")
	print("  /macever status - your Mac's graphics chip, window size and frame rate")
	print("  /macever set <setting> <value> - change one graphics setting")
	print("  /macever changed - settings Mac-ever has changed, and their original values")
	print("  /macever restore - undo Mac-ever's changes (settings changed since elsewhere are left as they are)")
	print("  /macever defaults - reset all graphics settings to the game's defaults")
	print("  /macever report - a report of your setup and settings to send with a problem")
end

-- Read once: the window's status line shows it twice a second, and it can't change.
local chipNames

function ns.ChipNames()
	if not chipNames then
		local chips = {}
		for _, adapter in ipairs(C_VideoOptions.GetGxAdapterInfo()) do
			chips[#chips + 1] = adapter.name
		end
		chipNames = #chips > 0 and table.concat(chips, ", ") or "Graphics chip not reported"
	end
	return chipNames
end

-- Apple Silicon reports its graphics as "Apple M1 Pro" and so on. The Forever client
-- also runs on Intel Macs (Intel or AMD graphics), and on Windows: Mac-ever's tuning
-- was researched on Apple Silicon only, so the player is told. A client that
-- reports no chip is given the benefit of the doubt.
function ns.IsAppleSilicon()
	local adapters = C_VideoOptions.GetGxAdapterInfo()
	if #adapters == 0 then
		return true
	end
	for _, adapter in ipairs(adapters) do
		if (adapter.name or ""):match("^Apple ") then
			return true
		end
	end
	return false
end

ns.NOT_APPLE_SILICON = "Mac-ever is made for Apple Silicon Macs. Its tuning comes from Apple Silicon reports and testing, so on this computer it's untested and results may differ."

local function ShowStatus()
	local size = C_VideoOptions.GetCurrentGameWindowSize()
	Print(("Mac-ever %s"):format(ns.version or ""))
	print(("  Graphics chip: %s"):format(ns.ChipNames()))
	if not ns.IsAppleSilicon() then
		print("  Not Apple Silicon. " .. ns.NOT_APPLE_SILICON)
	end
	print(("  Game window: %d x %d at render scale %s"):format(size.x, size.y, C_CVar.GetCVar("RenderScale") or "?"))
	print(("  Frame rate: %.0f fps"):format(GetFramerate()))
	print(("  Settings changed by Mac-ever: %d"):format(#CVars.ListChanged()))
end

local function SetOne(args)
	local name, value = args:match("^(%S+)%s+(%S+)$")
	if not name then
		Print("Usage: /macever set <setting> <value>")
		return
	end
	if not Registry.Get(name) then
		Print(("%s isn't one of the standard graphics settings. Changing it can cause problems; /macever restore undoes it."):format(name))
	end
	ns.ReportResults(CVars.Apply({ { name = name, value = value } }))
end

local function ShowChanged()
	local list = CVars.ListChanged()
	if #list == 0 then
		Print("Mac-ever hasn't changed any settings.")
		return
	end
	Print("Settings Mac-ever has changed (original -> now):")
	for _, item in ipairs(list) do
		print(("  %s: %s -> %s"):format(item.name, item.original, item.current or "?"))
	end
end

local function Restore()
	local results, effects = CVars.RestoreOriginals()
	ns.ReportResults(results, effects, "Everything is already as it was before Mac-ever.")
end

local function ResetDefaults(args)
	if args ~= "confirm" then
		Print("This resets every graphics setting to the game's defaults. Type /macever defaults confirm to go ahead. /macever restore undoes it.")
		return
	end
	ns.ReportResults(CVars.ResetToDefaults())
end

local function Toggle()
	if ns.UI then
		ns.UI.Toggle()
	else
		ShowHelp()
	end
end

local function Setup()
	if ns.UI then
		ns.UI.Show()
		ns.UI.ShowSetup()
	else
		ShowHelp()
	end
end

local function Report()
	if ns.UI then
		ns.UI.ShowReport()
	else
		print(ns.ProblemReport.Build())
	end
end

-- /macever lang sr|en (fork addition): the interface language; reloads the interface.
local function SetLanguage(args)
	local id = args:lower()
	for _, item in ipairs(ns.Locale.LANGUAGES) do
		if item.id == id then
			if ns.Locale.lang ~= id then
				ns.Locale.Set(id)
				ReloadUI()
			end
			return
		end
	end
	Print("Usage: /macever lang en  or  /macever lang sr")
end

local handlers = {
	lang = SetLanguage,
	[""] = Toggle,
	setup = Setup,
	report = Report,
	help = ShowHelp,
	status = ShowStatus,
	set = SetOne,
	changed = ShowChanged,
	restore = Restore,
	defaults = ResetDefaults,
}

SLASH_MACEVER1 = "/macever"
SlashCmdList.MACEVER = ns.Safe(function(input)
	local command, args = input:match("^%s*(%S*)%s*(.-)%s*$")
	local handler = handlers[command:lower()] or ShowHelp
	handler(args)
end)
