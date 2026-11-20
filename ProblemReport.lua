local _, ns = ...
local L = ns.L

local Registry = ns.Registry
local CVars = ns.CVars
local Benchmark = ns.Benchmark
local Devices = ns.Devices

-- Report a Problem (Josh, 2026-10-13): everything needed to look into a player's problem,
-- as plain text. Addons can't send anything or write the clipboard, so the player copies
-- it from a selected box and posts it on Mac-ever's CurseForge page. No character or
-- realm names.
--
-- Saved data is only written on logout or /reload, so after a crash this can't show the
-- check that crashed. The game's own crash file (in the Errors folder) lists every
-- setting at the moment of the crash, so the report asks for that too.

local ProblemReport = {}
ns.ProblemReport = ProblemReport

-- Project 1733200 (the TOC's X-Curse-Project-ID); CurseForge redirects it to the page.
ProblemReport.URL = "https://wow.curseforge.com/projects/1733200"
ProblemReport.ERRORS_FOLDER = "World of Warcraft/_forever_/Errors"

-- Settings beyond the ones the System Check tunes: quality masters, display, frame rate,
-- the renderer, the raid copies of Shadow Quality, Secondary Lighting and Compute Effects, and the Hidden settings that
-- cost the most frame rate or picture (the check tuned them before it went Standard-only,
-- Josh 2026-10-18; they still show what a player's Mac is drawing), plus sharpening, and
-- the fixed shadow, glow, sharpness and picture values (Josh, 2026-10-19).
local EXTRA_SETTINGS = {
	"graphicsQuality", "raidGraphicsQuality", "graphicsLightMode", "GxMaximize", "vsync", "NotchedDisplayMode",
	"useMaxFPS", "maxFPS", "useTargetFPS", "targetFPS", "DynamicRenderScale", "ResampleQuality",
	"gxMaxFrameLatency", "GxCompatOptionalGpuFeatures", "GxCompatWorkSubmitOptimizations",
	"GxCompatAsyncShaderCompilation", "GxCompatCommandListMultiThreading", "HDROutput",
	"raidGraphicsShadowQuality", "raidGraphicsLightMode", "raidGraphicsComputeEffects",
	"farclip", "horizonClip", "horizonStart", "sunShafts", "reflectionMode", "waterDetail", "weatherDensity",
	"maxLightDist", "shadowTextureSize", "animFrameSkipLOD", "ResampleAlwaysSharpen", "DynamicRenderScaleMin",
	"shadowMode", "shadowNumCascades", "shadowSoft", "shadowBlendCascades", "entityShadowFadeScale", "ffxGlow",
	"ResampleSharpness", "Contrast", "Brightness", "Gamma", "bloomUserMult",
}

local MAX_ERROR_LINES = 12

local function When(seconds)
	return seconds and date("%Y-%m-%d %H:%M", seconds) or "unknown time"
end

local function SetupLine()
	local profile = ns.db.profile
	local mac = type(profile) == "table" and Devices.Find(Devices.MACS, profile.mac)
	local memory = type(profile) == "table" and Devices.Find(Devices.MEMORY, profile.memory)
	if not mac or not memory or not profile.label or not profile.goal then
		return L("Setup: not set up")
	end
	local goal = profile.uncapped and ("at least %d fps"):format(profile.goal) or ("%d fps"):format(profile.goal)
	if profile.label == ("%d fps"):format(profile.goal) then -- saved by frame-rate setup: the label is the goal
		return (L("Setup: %s, %s: %s")):format(mac.label, memory.label, goal)
	end
	return (L("Setup: %s, %s: %s (%s)")):format(mac.label, memory.label, profile.label, goal)
end

-- name=value for every setting worth knowing, each once, in a fixed order.
local function SettingsLine()
	local names = {}
	for _, dimension in ipairs(Benchmark.DIMENSIONS) do
		names[#names + 1] = dimension.name
		for _, extra in ipairs(dimension.extras or {}) do
			names[#names + 1] = extra.name
		end
	end
	for _, name in ipairs(EXTRA_SETTINGS) do
		names[#names + 1] = name
	end
	local parts, seen = {}, {}
	for _, name in ipairs(names) do
		local key = Registry.Key(name)
		local value = not seen[key] and CVars.Read(name)
		seen[key] = true
		if value ~= nil and value ~= false then
			parts[#parts + 1] = ("%s=%s"):format(name, tostring(value))
		end
	end
	return L("Settings: ") .. table.concat(parts, " ")
end

local function CheckLine()
	local last = ns.db.lastCheckEnd
	if type(last) ~= "table" then
		return L("Last System Check: none")
	end
	local goal = last.uncapped and ("goal at least %s fps"):format(tostring(last.goal))
		or ("goal %s fps"):format(tostring(last.goal))
	local outcome
	if last.reason then
		outcome = ("stopped (%s) at %d%%: %s"):format(tostring(last.reason), math.floor((last.progress or 0) * 100 + 0.5),
			tostring(last.step or "?"))
	elseif last.fps then
		outcome = ("finished at %.0f fps"):format(last.fps)
	else
		outcome = "finished"
	end
	return (L("Last System Check: %s in %s, %s, %s")):format(When(last.time), tostring(last.zone or "?"), goal, outcome)
end

-- What the saved check recommends, in the Settings line's name=value form, so a report shows
-- the check's answer beside what the player ended up with (Josh, 2026-10-18). Only a report
-- this build understands; an older one's values mean something else.
local function RecommendedLine()
	local report = ns.db.lastCheck
	if type(report) ~= "table" or report.version ~= ns.Solver.REPORT_VERSION or type(report.settings) ~= "table" then
		return nil
	end
	local parts = {}
	for _, setting in ipairs(report.settings) do
		parts[#parts + 1] = ("%s=%s"):format(tostring(setting.name), tostring(setting.recommended))
		-- While Hidden Settings are kept (Josh, 2026-10-19), applying leaves out the fixed
		-- extras, which are all Hidden ones. The tick box as it is now decides, as for applying.
		for _, extra in ipairs(not ns.Solver.KeepsHidden() and setting.extras or {}) do
			parts[#parts + 1] = ("%s=%s"):format(tostring(extra.name), tostring(extra.value))
		end
	end
	return L("Check recommended: ") .. table.concat(parts, " ")
end

local function ErrorLines()
	local last = ns.db.lastError
	if type(last) ~= "table" or not last.message then
		return { L("Last error: none") }
	end
	local lines = { (L("Last error (%s):")):format(When(last.time)) }
	for line in tostring(last.message):gmatch("[^\n]+") do
		if #lines > MAX_ERROR_LINES then
			break
		end
		lines[#lines + 1] = "  " .. line
	end
	return lines
end

-- Other addons can change graphics settings too, so the loaded ones are listed.
local function AddonsLine()
	if not (C_AddOns.GetNumAddOns and C_AddOns.GetAddOnInfo and C_AddOns.IsAddOnLoaded) then
		return nil
	end
	local names = {}
	for index = 1, C_AddOns.GetNumAddOns() do
		local name = C_AddOns.GetAddOnInfo(index)
		if name and name ~= ns.name and C_AddOns.IsAddOnLoaded(index) then
			names[#names + 1] = name
		end
	end
	return L("Other addons: ") .. (#names > 0 and table.concat(names, ", ") or "none")
end

function ProblemReport.Build()
	local size = C_VideoOptions.GetCurrentGameWindowSize()
	local lines = {
		L("Mac-ever problem report"),
		(L("Mac-ever %s, game build %s")):format(tostring(ns.version or "?"), tostring(select(2, GetBuildInfo()) or "?")),
		(L("Graphics chip: %s, window %d x %d, %.0f fps now")):format(ns.ChipNames(), size.x, size.y, GetFramerate()),
		SetupLine(),
	}
	-- Only while it's in effect (Josh, 2026-10-19): then the Hidden values in the Settings
	-- line are the player's own, not the game's defaults or Mac-ever's fixed ones.
	if ns.Solver.KeepsHidden() then
		lines[#lines + 1] = L("Keep my Hidden Settings: on")
	end
	lines[#lines + 1] = SettingsLine()
	lines[#lines + 1] = CheckLine()
	lines[#lines + 1] = RecommendedLine() -- nil without a current check: nothing added
	for _, line in ipairs(ErrorLines()) do
		lines[#lines + 1] = line
	end
	lines[#lines + 1] = AddonsLine()
	lines[#lines + 1] = (L("If the game crashed: also send the newest .txt file in %s")):format(ProblemReport.ERRORS_FOLDER)
	return table.concat(lines, "\n")
end
