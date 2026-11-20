local _, ns = ...

-- Every graphics setting Mac-ever manages, mirroring the stock Graphics menu in
-- Blizzard_SettingsDefinitions_Shared/Graphics.lua and Mainline/GraphicsOverrides.lua
-- (Forever 1.60.1, checked against build 70790 on 2026-11-05: options, labels and when each
-- row shows). Labels use the same global strings as the stock menu.
-- Hardware selection (gxApi, gxAdapter, gxMonitor) and UI scale are deliberately excluded.
--
-- Fields:
--   group     section in the Custom tab
--   order     apply order; quality masters go first so they can't overwrite what follows
--   control   "choice" (choices = list or function), "slider" (min/max/step), "toggle"
--   restart   "gx" (the stock menu restarts the renderer; Mac-ever doesn't, so it takes
--             effect after a game restart), "window" (window refresh), "client" (game
--             restart), matching the stock menu's commit flags
--   risk      "caution" or "advanced"; omitted means low risk
--   quality   per-setting quality CVar that follows the quality master
--   shown     optional function; false hides the setting on this Mac/client

local function T(key, fallback)
	return { key, fallback }
end

local LOW = T("VIDEO_OPTIONS_LOW", "Low")
local FAIR = T("VIDEO_OPTIONS_FAIR", "Fair")
local GOOD = T("VIDEO_OPTIONS_MEDIUM", "Good")
local HIGH = T("VIDEO_OPTIONS_HIGH", "High")
local ULTRA = T("VIDEO_OPTIONS_ULTRA", "Ultra")
local ULTRA_HIGH = T("VIDEO_OPTIONS_ULTRA_HIGH", "Ultra High")
local DISABLED = T("VIDEO_OPTIONS_DISABLED", "Disabled")
local ENABLED = T("VIDEO_OPTIONS_ENABLED", "Enabled")
local NONE = T("VIDEO_OPTIONS_NONE", "None")

local function Choice(value, label, tooltip)
	return { value = value, label = label, tooltip = tooltip }
end

local function LevelSlider()
	-- Stored 0-9, shown 1-10 like the stock menu.
	return { min = 0, max = 9, step = 1, format = function(value) return tostring(value + 1) end }
end

local MASTER, RAID_TOGGLE, DETAIL, DISPLAY, COMPAT, HIDDEN, DISCOVERED = 1, 2, 3, 4, 5, 6, 7

-- The conditions the stock menu checks to decide which rows and options a Mac gets.
local function SecondaryLighting()
	return C_VideoOptions.IsSecondaryLightingSupported() and true or false
end
local function PBRWater()
	return C_VideoOptions.IsPBRWaterSupported() and true or false
end
local function OnMac()
	return IsMacClient ~= nil and IsMacClient() and true or false
end
local function MSAASupported()
	return MultiSampleAntiAliasingSupported ~= nil and MultiSampleAntiAliasingSupported() ~= nil
end

-- World quality settings. Raid copies are generated from these below.
local qualityEntries = {
	{ name = "graphicsQuality", master = true, control = "slider", slider = LevelSlider(),
		label = T("BASE_GRAPHICS_QUALITY", "Graphics Quality"), tooltip = T("OPTION_TOOLTIP_GRAPHICS_QUALITY") },
	{ name = "graphicsShadowQuality", control = "choice",
		label = T("SHADOW_QUALITY", "Shadow Quality"), tooltip = T("OPTION_TOOLTIP_SHADOW_QUALITY"),
		choices = {
			Choice(0, LOW, T("VIDEO_OPTIONS_SHADOW_QUALITY_LOW")),
			Choice(1, FAIR, T("VIDEO_OPTIONS_SHADOW_QUALITY_FAIR")),
			Choice(2, GOOD, T("VIDEO_OPTIONS_SHADOW_QUALITY_MEDIUM")),
			Choice(3, HIGH, T("VIDEO_OPTIONS_SHADOW_QUALITY_HIGH")),
			Choice(4, ULTRA, T("VIDEO_OPTIONS_SHADOW_QUALITY_ULTRA")),
			Choice(5, ULTRA_HIGH, T("VIDEO_OPTIONS_SHADOW_QUALITY_ULTRA_HIGH")),
		} },
	-- Called Legacy Liquid Detail where the newer water (Liquid Rendering) is available.
	{ name = "graphicsLiquidDetail", control = "choice",
		label = function()
			return PBRWater() and T("LEGACY_LIQUID_DETAIL", "Legacy Liquid Detail") or T("LIQUID_DETAIL", "Liquid Detail")
		end,
		tooltip = function()
			return PBRWater() and T("OPTION_TOOLTIP_LEGACY_LIQUID_DETAIL") or T("OPTION_TOOLTIP_LIQUID_DETAIL")
		end,
		choices = {
			Choice(0, LOW, T("VIDEO_OPTIONS_LIQUID_DETAIL_LOW")),
			Choice(1, FAIR, T("VIDEO_OPTIONS_LIQUID_DETAIL_FAIR")),
			Choice(2, GOOD, T("VIDEO_OPTIONS_LIQUID_DETAIL_MEDIUM")),
			Choice(3, HIGH, T("VIDEO_OPTIONS_LIQUID_DETAIL_ULTRA")),
		} },
	{ name = "graphicsPBRLiquidDetail", control = "choice",
		shown = function() return C_VideoOptions.IsPBRWaterSupported() end,
		label = T("PBR_LIQUID_DETAIL", "Liquid Rendering"), tooltip = T("OPTION_TOOLTIP_PBR_LIQUID_DETAIL"),
		choices = {
			Choice(0, LOW, T("VIDEO_OPTIONS_PBR_LIQUID_DETAIL_LOW")),
			Choice(1, HIGH, T("VIDEO_OPTIONS_PBR_LIQUID_DETAIL_HIGH")),
			Choice(2, ULTRA, T("VIDEO_OPTIONS_PBR_LIQUID_DETAIL_ULTRA")),
		} },
	-- Numbered by whether the Mac has Secondary Lighting (build 70532): with it, 0 is Low and
	-- 4 Ultra; without, 0 is Disabled and 5 Ultra.
	{ name = "graphicsParticleDensity", control = "choice", minQuality = 1,
		label = T("PARTICLE_DENSITY", "Particle Density"), tooltip = T("OPTION_TOOLTIP_PARTICLE_DENSITY"),
		choices = function()
			if SecondaryLighting() then
				return { Choice(0, LOW), Choice(1, FAIR), Choice(2, GOOD), Choice(3, HIGH), Choice(4, ULTRA) }
			end
			return {
				Choice(0, DISABLED, T("VIDEO_OPTIONS_COMBAT_CUES_DISABLED_WARNING", "Hides important combat effects.")),
				Choice(1, LOW), Choice(2, FAIR), Choice(3, GOOD), Choice(4, HIGH), Choice(5, ULTRA),
			}
		end },
	{ name = "graphicsSSAO", control = "choice",
		label = T("SSAO_LABEL", "SSAO"), tooltip = T("OPTION_TOOLTIP_SSAO"),
		choices = { Choice(0, DISABLED), Choice(1, LOW), Choice(2, GOOD), Choice(3, HIGH), Choice(4, ULTRA) } },
	{ name = "graphicsDepthEffects", control = "choice",
		label = T("DEPTH_EFFECTS", "Depth Effects"), tooltip = T("OPTION_TOOLTIP_DEPTH_EFFECTS"),
		choices = {
			Choice(0, DISABLED, T("VIDEO_OPTIONS_DEPTH_EFFECTS_DISABLED")),
			Choice(1, LOW, T("VIDEO_OPTIONS_DEPTH_EFFECTS_LOW")),
			Choice(2, GOOD, T("VIDEO_OPTIONS_DEPTH_EFFECTS_MEDIUM")),
			Choice(3, HIGH, T("VIDEO_OPTIONS_DEPTH_EFFECTS_HIGH")),
		} },
	{ name = "graphicsComputeEffects", control = "choice",
		label = T("COMPUTE_EFFECTS", "Compute Effects"), tooltip = T("OPTION_TOOLTIP_COMPUTE_EFFECTS"),
		-- The game calls 0 Low since build 70425; its description still says what 0 turns off.
		choices = {
			Choice(0, LOW, T("VIDEO_OPTIONS_COMPUTE_EFFECTS_DISABLED")),
			Choice(1, FAIR, T("VIDEO_OPTIONS_COMPUTE_EFFECTS_LOW")),
			Choice(2, GOOD, T("VIDEO_OPTIONS_COMPUTE_EFFECTS_MEDIUM")),
			Choice(3, HIGH, T("VIDEO_OPTIONS_COMPUTE_EFFECTS_HIGH")),
			Choice(4, ULTRA, T("VIDEO_OPTIONS_COMPUTE_EFFECTS_ULTRA")),
		} },
	{ name = "graphicsOutlineMode", control = "choice",
		shown = function() return C_VideoOptions.IsOutlineModeSupported() end,
		label = T("OUTLINE_MODE", "Outline Mode"), tooltip = T("OPTION_TOOLTIP_OUTLINE_MODE"),
		choices = { Choice(0, DISABLED), Choice(1, GOOD), Choice(2, HIGH) } },
	{ name = "graphicsTextureResolution", control = "choice",
		label = T("TEXTURE_DETAIL", "Texture Resolution"), tooltip = T("OPTION_TOOLTIP_TEXTURE_DETAIL"),
		choices = {
			Choice(0, LOW, T("VIDEO_OPTIONS_TEXTURE_DETAIL_LOW")),
			Choice(1, FAIR, T("VIDEO_OPTIONS_TEXTURE_DETAIL_FAIR")),
			Choice(2, HIGH, T("VIDEO_OPTIONS_TEXTURE_DETAIL_HIGH")),
		} },
	{ name = "graphicsSpellDensity", control = "choice",
		shown = function() return C_VideoOptions.IsSpellVisualDensitySystemSupported() end,
		label = T("SPELL_DENSITY", "Spell Density"), tooltip = T("OPTION_TOOLTIP_SPELL_DENSITY"),
		choices = {
			Choice(0, T("VIDEO_OPTIONS_SFX_DENSITY_MIN", "Essential"), T("VIDEO_OPTIONS_SFX_DENSITY_MIN_TOOLTIP")),
			Choice(1, T("VIDEO_OPTIONS_SFX_DENSITY_REDUCED", "Some"), T("VIDEO_OPTIONS_SFX_DENSITY_REDUCED_TOOLTIP")),
			Choice(2, T("VIDEO_OPTIONS_SFX_DENSITY_FULL", "Everything"), T("VIDEO_OPTIONS_SFX_DENSITY_FULL_TOOLTIP")),
		} },
	{ name = "graphicsProjectedTextures", control = "choice",
		label = T("PROJECTED_TEXTURES", "Projected Textures"), tooltip = T("OPTION_TOOLTIP_PROJECTED_TEXTURES"),
		choices = {
			Choice(0, DISABLED, T("VIDEO_OPTIONS_COMBAT_CUES_DISABLED_WARNING", "Hides important combat effects.")),
			Choice(1, ENABLED),
		} },
	{ name = "graphicsLightMode", control = "choice",
		shown = function() return C_VideoOptions.IsSecondaryLightingSupported() end,
		label = T("LIGHTING_MODE", "Secondary Lighting"), tooltip = T("OPTION_TOOLTIP_LIGHTING_MODE"),
		choices = {
			Choice(0, FAIR, T("VIDEO_OPTIONS_ADVANCEDLIGHT_LOW")),
			Choice(1, GOOD, T("VIDEO_OPTIONS_ADVANCEDLIGHT_MEDIUM")),
			Choice(2, HIGH, T("VIDEO_OPTIONS_ADVANCEDLIGHT_HIGH")),
			Choice(3, ULTRA, T("VIDEO_OPTIONS_ADVANCEDLIGHT_ULTRA")),
		} },
	{ name = "graphicsViewDistance", control = "slider", slider = LevelSlider(),
		label = T("FARCLIP", "View Distance"), tooltip = T("OPTION_TOOLTIP_FARCLIP") },
	{ name = "graphicsEnvironmentDetail", control = "slider", slider = LevelSlider(),
		label = T("ENVIRONMENT_DETAIL", "Environment Detail"), tooltip = T("OPTION_TOOLTIP_ENVIRONMENT_DETAIL") },
	{ name = "graphicsGroundClutter", control = "slider", slider = LevelSlider(),
		label = T("GROUND_CLUTTER", "Ground Clutter"), tooltip = T("OPTION_TOOLTIP_GROUND_CLUTTER") },
}

local function FormatFPS(value)
	return (_G.SETTINGS_FMT_FPS or "%d FPS"):format(value)
end

local function FormatPercent(value)
	return ("%d%%"):format(math.floor(value * 100 + 0.5))
end

-- The stock menu's Anti-Aliasing modes.
local AA_NONE, AA_IMAGE, AA_MULTISAMPLE, AA_ADVANCED = 0, 1, 2, 3

local function MSAAChoices()
	local choices = { Choice(0, NONE) }
	if MultiSampleAntiAliasingSupported then
		local function Add(...)
			for i = 1, select("#", ...), 3 do
				local quality, samples, coverage = select(i, ...)
				local value = tonumber((tostring(quality):match("^[^,]+")))
				local label = (_G.ADVANCED_ANTIALIASING_MSAA_FORMAT or "%dx (%dx coverage)"):format(samples, coverage)
				choices[#choices + 1] = Choice(value, label)
			end
		end
		Add(MultiSampleAntiAliasingSupported())
	end
	return choices
end

local function ImageAAChoices()
	local choices = {
		Choice(0, NONE),
		Choice(1, T("ANTIALIASING_FXAA_LOW", "FXAA Low"), T("OPTION_TOOLTIP_ANTIALIASING_FXAA_LOW")),
		Choice(2, T("ANTIALIASING_FXAA_HIGH", "FXAA High"), T("OPTION_TOOLTIP_ANTIALIASING_FXAA_HIGH")),
	}
	if AntiAliasingSupported then
		local _, cmaa, cmaa2 = AntiAliasingSupported()
		if cmaa then
			choices[#choices + 1] = Choice(3, T("ANTIALIASING_CMAA", "CMAA"), T("OPTION_TOOLTIP_ANTIALIASING_CMAA"))
		end
		if cmaa2 then
			choices[#choices + 1] = Choice(4, T("ANTIALIASING_CMAA2", "CMAA 2"), T("OPTION_TOOLTIP_ANTIALIASING_CMAA2"))
		end
	end
	return choices
end

local function RenderScaleSlider()
	local minValue = GetMinRenderScale and GetMinRenderScale() or 0.33
	local maxValue = GetMaxRenderScale and GetMaxRenderScale() or 1
	return { min = minValue, max = maxValue, step = 0.01, format = FormatPercent }
end

local function CameraFovSlider()
	local minValue, maxValue = 50, 90
	if GetCameraFOVDefaults then
		local _, low, high = GetCameraFOVDefaults()
		minValue, maxValue = low or minValue, high or maxValue
	end
	return { min = minValue, max = maxValue, step = 5 }
end

local otherEntries = {
	-- Display
	{ name = "RenderScale", group = "display", control = "slider", slider = RenderScaleSlider,
		label = T("RENDER_SCALE", "Render Scale"), tooltip = T("OPTION_TOOLTIP_RENDER_SCALE") },
	{ name = "ResampleQuality", group = "display", control = "choice",
		label = T("RESAMPLE_QUALITY", "Resample Quality"), tooltip = T("OPTION_TOOLTIP_RESAMPLE_QUALITY"),
		choices = {
			Choice(0, T("RESAMPLE_QUALITY_POINT", "Point"), T("VIDEO_OPTIONS_RESAMPLE_QUALITY_POINT")),
			Choice(1, T("RESAMPLE_QUALITY_BILINEAR", "Bilinear"), T("VIDEO_OPTIONS_RESAMPLE_QUALITY_BILINEAR")),
			Choice(2, T("RESAMPLE_QUALITY_BICUBIC", "Bicubic"), T("VIDEO_OPTIONS_RESAMPLE_QUALITY_BICUBIC")),
			Choice(3, T("RESAMPLE_QUALITY_FSR", "FidelityFX Super Resolution"), T("VIDEO_OPTIONS_RESAMPLE_QUALITY_FSR")),
		} },
	-- Shows the game's real value (0 = strongest, 2 = weakest). The stock menu displays it
	-- reversed (2 - value), which contradicted the description (Josh, 2026-10-07).
	{ name = "ResampleSharpness", group = "display", control = "slider",
		slider = { min = 0, max = 2, step = 0.1, format = function(value)
			if value <= 0.05 then
				return "0.0 (strongest)"
			elseif value >= 1.95 then
				return "2.0 (weakest)"
			end
			return ("%.1f"):format(value)
		end },
		label = T("RESAMPLE_SHARPNESS", "Sharpness"), tooltip = T("OPTION_TOOLTIP_SHARPNESS") },
	{ name = "textureFilteringMode", group = "display", control = "choice",
		label = T("ANISOTROPIC", "Texture Filtering"), tooltip = T("OPTION_TOOLTIP_ANISOTROPIC"),
		choices = {
			Choice(0, T("VIDEO_OPTIONS_BILINEAR", "Bilinear")),
			Choice(1, T("VIDEO_OPTIONS_TRILINEAR", "Trilinear")),
			Choice(2, T("VIDEO_OPTIONS_2XANISOTROPIC", "2x Anisotropic")),
			Choice(3, T("VIDEO_OPTIONS_4XANISOTROPIC", "4x Anisotropic")),
			Choice(4, T("VIDEO_OPTIONS_8XANISOTROPIC", "8x Anisotropic")),
			Choice(5, T("VIDEO_OPTIONS_16XANISOTROPIC", "16x Anisotropic")),
		} },
	-- The stock menu's Anti-Aliasing mode (PROXY_ANTIALIASING): no setting of its own, read
	-- from Image-Based and Multisample, and greying whichever of them the mode doesn't use.
	-- Picking None turns both off, Image-Based turns Multisample off, Multisample turns
	-- Image-Based off (Graphics.lua, Forever 70790). See ns.CustomModel for the proxy.
	{ name = "PROXY_ANTIALIASING", group = "display", control = "choice", proxy = "aamode",
		choices = function()
			local choices = { Choice(AA_NONE, NONE), Choice(AA_IMAGE, T("FXAA_CMAA_LABEL", "Image-Based Techniques")) }
			if MSAASupported() then
				choices[#choices + 1] = Choice(AA_MULTISAMPLE, T("MSAA_LABEL", "Multisample Techniques"))
				if AntiAliasingSupported then
					choices[#choices + 1] = Choice(AA_ADVANCED, T("ADVANCED_LABEL", "Advanced"))
				end
			end
			return choices
		end,
		label = T("ANTIALIASING", "Anti-Aliasing"), tooltip = T("OPTION_TOOLTIP_ANTIALIASING") },
	{ name = "ffxAntiAliasingMode", group = "display", control = "choice", choices = ImageAAChoices,
		parentModes = { [AA_IMAGE] = true, [AA_ADVANCED] = true },
		label = T("FXAA_CMAA_LABEL", "Image-Based Anti-Aliasing"), tooltip = T("OPTION_TOOLTIP_ANTIALIASING_IB") },
	-- MSAAQuality reads back as "samples,coverage"; only the sample count is compared. The
	-- stock menu only has these two rows on a Mac that supports multisampling (build 70707).
	{ name = "MSAAQuality", group = "display", control = "choice", choices = MSAAChoices, risk = "caution",
		shown = MSAASupported, parentModes = { [AA_MULTISAMPLE] = true, [AA_ADVANCED] = true },
		normalize = function(value) return value and (value:match("^[^,]+")) end,
		label = T("MSAA_LABEL", "Multisample Anti-Aliasing"), tooltip = T("OPTION_TOOLTIP_ADVANCED_MSAA") },
	{ name = "MSAAAlphaTest", group = "display", control = "toggle", risk = "caution",
		shown = MSAASupported, parentModes = { [AA_MULTISAMPLE] = true, [AA_ADVANCED] = true },
		label = T("MULTISAMPLE_ALPHA_TEST", "Multisample Alpha Test"), tooltip = T("OPTION_TOOLTIP_MULTISAMPLE_ALPHA_TEST") },
	{ name = "vsync", group = "display", control = "toggle", restart = "window", risk = "caution",
		label = T("VERTICAL_SYNC", "Vertical Sync"), tooltip = T("OPTION_TOOLTIP_VERTICAL_SYNC") },
	{ name = "GxMaxFrameLatency", group = "display", control = "choice", restart = "gx", risk = "caution",
		label = T("TRIPLE_BUFFER", "Triple Buffering"), tooltip = T("OPTION_TOOLTIP_TRIPLE_BUFFER"),
		choices = { Choice(2, DISABLED), Choice(3, ENABLED) } },
	-- The stock menu has no Low Latency Mode, Variable Rate Shading or Ray Traced Shadows on
	-- a Mac (build 70425).
	{ name = "LowLatencyMode", group = "display", control = "choice", risk = "caution",
		shown = function() return not OnMac() end,
		label = T("LOW_LATENCY_MODE", "Low Latency Mode"), tooltip = T("OPTION_TOOLTIP_LOW_LATENCY_MODE"),
		choices = {
			Choice(0, T("GX_ADAPTER_AUTO_DETECT", "Auto Detect")),
			Choice(1, DISABLED),
			Choice(2, T("VIDEO_OPTIONS_BUILTIN", "Built-in")),
		} },
	{ name = "NotchedDisplayMode", group = "display", control = "choice", restart = "window", risk = "caution",
		shown = function() return C_UI.DoesAnyDisplayHaveNotch() end,
		label = T("NOTCH_MODE", "Notch Mode"), tooltip = T("OPTION_TOOLTIP_NOTCH_MODE"),
		choices = {
			Choice(0, T("NOTCH_MODE_OVERLAP", "Overlap"), T("VIDEO_OPTIONS_NOTCH_MODE_OVERLAP")),
			Choice(1, T("NOTCH_MODE_SHIFT_UI", "Shift UI"), T("VIDEO_OPTIONS_NOTCH_MODE_SHIFT_UI")),
			Choice(2, T("NOTCH_MODE_WINDOW_BELOW", "Window Below Notch"), T("VIDEO_OPTIONS_NOTCH_MODE_WINDOW_BELOW")),
		} },
	{ name = "GxMaximize", group = "display", control = "choice", restart = "window", risk = "caution",
		label = T("DISPLAY_MODE", "Display Mode"), tooltip = T("OPTION_TOOLTIP_DISPLAY_MODE"),
		choices = {
			Choice(1, T("VIDEO_OPTIONS_WINDOWED_FULLSCREEN", "Windowed (Fullscreen)")),
			Choice(0, T("VIDEO_OPTIONS_WINDOWED", "Windowed")),
		} },
	{ name = "vrsValar", group = "display", control = "choice", risk = "caution",
		shown = function() return not OnMac() end,
		label = T("VRS_MODE", "Variable Rate Shading"), tooltip = T("OPTION_TOOLTIP_VRS_MODE"),
		choices = {
			Choice(0, DISABLED),
			Choice(1, T("VIDEO_OPTIONS_STANDARD", "Standard"), T("OPTION_TOOLTIP_VRS_STANDARD")),
			Choice(2, T("VIDEO_OPTIONS_AGGRESSIVE", "Aggressive"), T("OPTION_TOOLTIP_VRS_AGGRESSIVE")),
		} },
	{ name = "shadowRt", group = "display", control = "choice", risk = "caution",
		shown = function() return not SecondaryLighting() and not OnMac() end,
		label = T("RT_SHADOW_QUALITY", "Ray Traced Shadows"), tooltip = T("OPTION_TOOLTIP_RT_SHADOW_QUALITY"),
		choices = {
			Choice(0, DISABLED),
			Choice(1, FAIR, T("VIDEO_OPTIONS_RT_SHADOW_QUALITY_FAIR")),
			Choice(2, GOOD, T("VIDEO_OPTIONS_RT_SHADOW_QUALITY_MEDIUM")),
			Choice(3, HIGH, T("VIDEO_OPTIONS_RT_SHADOW_QUALITY_HIGH")),
		} },
	{ name = "physicsLevel", group = "display", control = "choice", restart = "client", risk = "caution",
		label = T("PHYSICS_INTERACTION", "Physics Interaction"), tooltip = T("OPTION_PHYSICS_OPTIONS"),
		choices = {
			Choice(0, T("NO_ENVIRONMENT_INTERACTION", "None")),
			Choice(1, T("PLAYER_ONLY_INTERACTION", "Player Only")),
			Choice(2, T("PLAYER_AND_NPC_INTERACTION", "Player and NPCs")),
		} },
	{ name = "cameraFov", group = "display", control = "slider", slider = CameraFovSlider,
		label = T("CAMERA_FOV", "Field of View"), tooltip = T("OPTION_TOOLTIP_CAMERA_FOV") },

	-- Frame rate
	{ name = "useMaxFPS", group = "advanced", control = "toggle",
		label = T("MAXFPS_CHECK", "Max Foreground FPS"), tooltip = T("OPTION_MAXFPS_CHECK") },
	{ name = "maxFPS", group = "advanced", control = "slider",
		slider = { min = 8, max = 200, step = 1, format = FormatFPS },
		label = T("MAXFPS", "Max Foreground FPS"), tooltip = T("OPTION_MAXFPS_CHECK") },
	{ name = "useMaxFPSBk", group = "advanced", control = "toggle",
		label = T("MAXFPSBK_CHECK", "Max Background FPS"), tooltip = T("OPTION_MAXFPSBK_CHECK") },
	{ name = "maxFPSBk", group = "advanced", control = "slider",
		slider = { min = 8, max = 200, step = 1, format = FormatFPS },
		label = T("MAXFPSBK", "Max Background FPS"), tooltip = T("OPTION_MAXFPSBK_CHECK") },
	{ name = "useTargetFPS", group = "advanced", control = "toggle",
		label = T("TARGETFPS", "Target FPS"), tooltip = T("OPTION_TARGETFPS_CHECK") },
	{ name = "targetFPS", group = "advanced", control = "slider",
		slider = { min = 8, max = 200, step = 1, format = FormatFPS },
		label = T("TARGETFPS", "Target FPS"), tooltip = T("OPTION_TARGETFPS_CHECK") },

	-- Image
	{ name = "Brightness", group = "advanced", control = "slider",
		slider = { min = 0, max = 100, step = 1, format = function(value) return ("%d%%"):format(value) end },
		label = T("OPTIONS_BRIGHTNESS", "Brightness"), tooltip = T("OPTION_TOOLTIP_BRIGHTNESS") },
	{ name = "Contrast", group = "advanced", control = "slider",
		slider = { min = 0, max = 100, step = 1, format = function(value) return ("%d%%"):format(value) end },
		label = T("OPTION_CONTRAST", "Contrast"), tooltip = T("OPTION_TOOLTIP_CONTRAST") },
	{ name = "Gamma", group = "advanced", control = "slider",
		slider = { min = 0.3, max = 2.8, step = 0.1, format = function(value) return ("%.1f"):format(value) end },
		label = T("GAMMA", "Gamma"), tooltip = T("OPTION_TOOLTIP_GAMMA") },
	-- Build 70425 replaced the quality section's Bloom choice (graphicsBloomUserMult, which
	-- no longer has a value) with this slider at the end of Advanced: 0 to 1 in steps of
	-- 0.2, shown as 0, 0.2 ... 1 (Josh's screenshot, 2026-10-16). A matter of taste, not
	-- detail: no quality level changes it (Josh, 2026-10-08: high Bloom made sunsets
	-- glare). Since 2026-10-19 (Josh) the Standard picture look sets it to 0.4, and with
	-- it every System Check result and goal preset.
	-- The stock menu shows it only when the game started in linear colour.
	{ name = "bloomUserMult", group = "advanced", control = "slider", taste = true,
		shown = function() return C_VideoOptions.IsLinearEnabledOnStart() end,
		slider = { min = 0, max = 1, step = 0.2, format = function(value)
			local rounded = math.floor(value * 10 + 0.5) / 10
			return rounded % 1 == 0 and ("%d"):format(rounded) or ("%.1f"):format(rounded)
		end },
		label = T("BLOOM_MULT", "Bloom Intensity"), tooltip = T("OPTION_TOOLTIP_BLOOM_MULT") },

	-- Compatibility: renderer settings.
	-- Optional GPU Features only changes after a game restart, in both directions; a
	-- renderer restart leaves it stale (Blizzard forums thread 2354050, 2026-10).
	{ name = "GxCompatOptionalGpuFeatures", group = "compat", control = "toggle", restart = "client", risk = "advanced",
		label = T("COMPAT_SETTING_OPTIONAL_GPU_FEATURES", "Optional GPU Features"),
		tooltip = T("OPTION_TOOLTIP_COMPAT_SETTING_OPTIONAL_GPU_FEATURES") },
	{ name = "GxCompatAsyncShaderCompilation", group = "compat", control = "toggle", restart = "gx", risk = "advanced",
		label = T("COMPAT_SETTING_DEVICE_MULTITHREADING", "Multithreaded Shader Compilation"),
		tooltip = T("OPTION_TOOLTIP_COMPAT_SETTING_DEVICE_MULTITHREADING") },
	{ name = "GxCompatCommandListMultiThreading", group = "compat", control = "toggle", restart = "gx", risk = "advanced",
		label = T("COMPAT_SETTING_CMDLIST_MULTITHREADING", "Multithreaded Rendering"),
		tooltip = T("OPTION_TOOLTIP_COMPAT_SETTING_CMDLIST_MULTITHREADING") },
	{ name = "GxCompatWorkSubmitOptimizations", group = "compat", control = "toggle", restart = "gx", risk = "advanced",
		label = T("COMPAT_SETTING_ADV_WORK_SUBMIT", "Advanced Work Submission"),
		tooltip = T("OPTION_TOOLTIP_COMPAT_SETTING_ADV_WORK_SUBMIT") },
}

local entries = {}

local function Add(entry)
	entries[#entries + 1] = entry
end

for _, entry in ipairs(qualityEntries) do
	entry.group = "quality"
	entry.quality = true
	entry.order = entry.master and MASTER or DETAIL
	Add(entry)
end

Add({ name = "RAIDsettingsEnabled", group = "quality", raid = true, control = "toggle", order = RAID_TOGGLE,
	label = T("RAID_SETTINGS_ENABLED", "Use Raid & Battleground Settings"), tooltip = T("RAID_SETTINGS_ENABLED_TOOLTIP") })

for _, world in ipairs(qualityEntries) do
	local raid = {}
	for key, value in pairs(world) do
		raid[key] = value
	end
	raid.name = "raidG" .. world.name:sub(2)
	raid.group = "quality"
	raid.raid = true
	raid.worldName = world.name
	world.raidName = raid.name
	raid.minQuality = nil -- the stock menu only sets a minimum for the world copy
	if world.master then
		raid.label = T("SETTINGS_RAID_GRAPHICS_QUALITY", "Raid Graphics Quality")
	end
	Add(raid)
end

for _, entry in ipairs(otherEntries) do
	entry.order = entry.group == "compat" and COMPAT or DISPLAY
	Add(entry)
end

-- Order and sections of the game's own Graphics page (Graphics.lua, Forever 1.60.1), so
-- Standard Settings reads like the menu players already know. A frame-rate cap shows
-- as one row: its on/off switch (toggle) next to its slider.
local NATIVE_LAYOUT = {
	display = { "GxMaximize", "RenderScale", "vsync", "NotchedDisplayMode", "LowLatencyMode",
		"PROXY_ANTIALIASING", "ffxAntiAliasingMode", "MSAAQuality", "MSAAAlphaTest", "cameraFov" },
	advanced = { "GxMaxFrameLatency", "textureFilteringMode", "shadowRt", "ResampleQuality", "vrsValar",
		"physicsLevel", "maxFPS", "maxFPSBk", "targetFPS", "ResampleSharpness", "Contrast", "Brightness", "Gamma",
		"bloomUserMult" },
}
local CAP_TOGGLES = { maxFPS = "useMaxFPS", maxFPSBk = "useMaxFPSBk", targetFPS = "useTargetFPS" }

for _, entry in ipairs(entries) do
	for group, names in pairs(NATIVE_LAYOUT) do
		for position, name in ipairs(names) do
			if entry.name == name then
				entry.group = group
				entry.listOrder = position
			end
		end
	end
	if CAP_TOGGLES[entry.name] then
		entry.toggle = CAP_TOGGLES[entry.name]
	end
end
for _, entry in ipairs(entries) do
	for _, toggleName in pairs(CAP_TOGGLES) do
		if entry.name == toggleName then
			entry.group = "advanced"
			entry.inList = false -- shown as the switch on its slider's row
		end
	end
end

local Registry = { entries = entries, T = T, Choice = Choice }
Registry.AA = { NONE = AA_NONE, IMAGE = AA_IMAGE, MULTISAMPLE = AA_MULTISAMPLE, ADVANCED = AA_ADVANCED }
ns.Registry = Registry

-- Apply-order bands for other files that add entries.
Registry.ORDER = { HIDDEN = HIDDEN, DISCOVERED = DISCOVERED }

-- tab: which tab lists the group. note: optional line under the group heading.
Registry.groups = {
	{ id = "display", tab = "standard", label = T("GRAPHICS_LABEL", "Graphics") },
	{ id = "quality", tab = "standard", label = T("GRAPHICS_QUALITY", "Graphics Quality") },
	{ id = "advanced", tab = "standard", label = T("ADVANCED_LABEL", "Advanced") },
	{ id = "compat", tab = "standard", label = T("COMPATIBILITY_SETTINGS", "Compatibility Settings") },
}

local byKey = {}

-- Adds an entry after load (hidden settings, discovered console variables).
function Registry.Add(entry)
	entries[#entries + 1] = entry
	entry.index = #entries
	byKey[entry.name:lower()] = entry
	return entry
end

for index, entry in ipairs(entries) do
	entry.index = index
	byKey[entry.name:lower()] = entry
end

function Registry.AddGroup(group)
	Registry.groups[#Registry.groups + 1] = group
end

function Registry.GetGroup(id)
	for _, group in ipairs(Registry.groups) do
		if group.id == id then
			return group
		end
	end
end

-- Settings Mac-ever must never write, even to restore an original: they switch the
-- frame buffer's pixel format while the game runs. A Game Defaults + Restore cycle that
-- switched RenderFormat corrupted the whole screen on an M1 Pro (2026-10-07). The stock
-- menu never changes these either. (HDR Output was blocked too, then brought back at
-- Josh's request: he'd used it without problems. Only the player changes it.)
-- GI quality neither: at a wrong value the world goes dark and flat (Stormwind,
-- 2026-10-16), and the game sets it from Secondary Lighting itself. Nor the GPU debug
-- switches, which are for Blizzard's own debugging (2026-11-05).
Registry.NEVER_WRITE = {
	renderformat = true, raidrenderformat = true,
	giquality = true, raidgiquality = true,
	gxdebuglevel = true, gxdebugbreaklevel = true,
}

-- Settings that change the screen resolution or window, or refresh the game window
-- (which can reset its size: on 2026-10-07 an M1 Pro's output dropped from 3024x1964 to
-- 1512x982 right after Mac-ever's window refresh). Mac-ever only changes these when the
-- player allows it (ns.db.ui.allowResolution); undoing Mac-ever's own earlier changes is
-- still allowed. Asked for by Josh: resolution "is something fundamental that the user
-- may pick for one reason or another". Render scale isn't resolution (Josh: "render
-- scale is not the same as resolution"): it's managed by the sharpness rules instead.
Registry.RESOLUTION = {
	gxmaximize = true, notcheddisplaymode = true, vsync = true,
}

function Registry.IsResolution(name)
	return Registry.RESOLUTION[name:lower()] == true
end

-- CVar names are case-insensitive in the client, so all lookups go through this.
function Registry.Key(name)
	return name:lower()
end

function Registry.Get(name)
	return byKey[Registry.Key(name)]
end

function Registry.RestartKind(name)
	local entry = Registry.Get(name)
	return entry and entry.restart
end

function Registry.Normalize(name, value)
	local entry = Registry.Get(name)
	if entry and entry.normalize and value ~= nil then
		return entry.normalize(value)
	end
	return value
end

function Registry.IsShown(entry)
	if entry.shown then
		local ok, shown = pcall(entry.shown)
		return ok and shown and true or false
	end
	return true
end

function Registry.GetChoices(entry)
	if type(entry.choices) == "function" then
		return entry.choices()
	end
	return entry.choices
end

function Registry.GetSlider(entry)
	if type(entry.slider) == "function" then
		return entry.slider()
	end
	return entry.slider
end

-- Why the client won't accept a value on this Mac, or nil if it will. Uses the same
-- checks as the stock menu (IsGraphicsSettingValueSupported / IsGraphicsCVarValueSupported).
local VALIDATION_MESSAGES = {
	"VRN_ILLEGAL", "VRN_UNSUPPORTED", "VRN_GRAPHICS", "VRN_DUALCORE", "VRN_QUADCORE",
	"VRN_CPUMEM_2GB", "VRN_CPUMEM_4GB", "VRN_CPUMEM_8GB", "VRN_NEEDS_5_0", "VRN_NEEDS_6_0",
	"VRN_NEEDS_RT", "VRN_NEEDS_DX12", "VRN_NEEDS_DX12_VRS2", "VRN_NEEDS_APPLE_GPU", "VRN_NEEDS_AMD_GPU",
	"VRN_NEEDS_INTEL_GPU", "VRN_NEEDS_NVIDIA_GPU", "VRN_NEEDS_QUALCOMM_GPU", "VRN_NEEDS_MACOS_10_13",
	"VRN_NEEDS_MACOS_10_14", "VRN_NEEDS_MACOS_10_15", "VRN_NEEDS_MACOS_11_0", "VRN_NEEDS_MACOS_12_0",
	"VRN_NEEDS_MACOS_13_0", "VRN_NEEDS_WINDOWS_10", "VRN_NEEDS_WINDOWS_11", "VRN_MACOS_UNSUPPORTED",
	"VRN_WINDOWS_UNSUPPORTED", "VRN_LEGACY_UNSUPPORTED", "VRN_DX11_UNSUPPORTED", "VRN_DX12_WIN7_UNSUPPORTED",
	"VRN_REMOTE_DESKTOP_UNSUPPORTED", "VRN_WINE_UNSUPPORTED", "VRN_NVAPI_WINE_UNSUPPORTED",
	"VRN_APPLE_UNSUPPORTED", "VRN_AMD_UNSUPPORTED", "VRN_INTEL_UNSUPPORTED", "VRN_NVIDIA_UNSUPPORTED",
	"VRN_QUALCOMM_UNSUPPORTED", "VRN_GPU_DRIVER", "VRN_COMPAT_MODE",
}

function Registry.UnsupportedReason(entry, value)
	-- Both checks are client internals; treat any error as "no objection".
	local ok, code
	if entry.quality and IsGraphicsSettingValueSupported then
		ok, code = pcall(IsGraphicsSettingValueSupported, entry.name, value, entry.raid == true)
	elseif not entry.quality and IsGraphicsCVarValueSupported then
		ok, code = pcall(IsGraphicsCVarValueSupported, entry.name, value)
	end
	if not ok or not code or code == 0 then
		return nil
	end
	local key = VALIDATION_MESSAGES[code]
	return key and _G[key] or "Not supported on this Mac"
end

-- Unregistered CVars (from /macever set) apply after everything known.
function Registry.SortKey(name)
	local entry = Registry.Get(name)
	if entry then
		return entry.order, entry.index
	end
	return DISCOVERED + 1, 0
end

-- Per-setting values the stock menu applies for a quality level (0-9), for world or raid.
-- Mirrors OnGCChanged in the stock Graphics settings. Returns an empty list if the client
-- doesn't provide GetGraphicsCVarValueForQualityLevel. Settings of taste (entry.taste)
-- keep the player's value, unlike the stock menu.
function Registry.QualityValues(level, raid)
	local values = {}
	if not GetGraphicsCVarValueForQualityLevel then
		return values
	end
	for _, entry in ipairs(entries) do
		if entry.quality and not entry.master and not entry.taste and (entry.raid == true) == raid and Registry.IsShown(entry) then
			local value = GetGraphicsCVarValueForQualityLevel(entry.name, level, raid)
			if value ~= nil then
				if entry.minQuality and value < entry.minQuality then
					value = entry.minQuality
				end
				values[#values + 1] = { name = entry.name, value = value }
			end
		end
	end
	return values
end
