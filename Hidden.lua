local _, ns = ...

local Registry = ns.Registry
local Choice = Registry.Choice

-- Console-only graphics settings: everything here is missing from the stock Graphics
-- menu. Names, defaults and help text come from the Forever 1.60.1 console variable
-- list (Ketho/BlizzardInterfaceResources, branch "forever", build 70205; every entry
-- re-checked against build 70532's list and the 70790 client on 2026-11-05).
--
-- Ranges are Mac-ever's choice of useful bounds. The game clamps anything it won't
-- accept, and Mac-ever then reports the value it settled on.
--
-- raid: the matching RAID* variable the game uses in raids and battlegrounds when
--       "Raid & Battleground Settings" is on. A raid copy of the entry is generated.

local function Slider(min, max, step, format)
	return { min = min, max = max, step = step, format = format }
end

local function Distance(value)
	return ("%d yd"):format(value)
end

local function Percent(value)
	return ("%d%%"):format(value)
end

local function Multiplier(value)
	return ("%.2fx"):format(value)
end

local QUALITY_0_3 = { Choice(0, "Off"), Choice(1, "Low"), Choice(2, "Good"), Choice(3, "High") }
-- For levels whose 0 still draws (2026-11-05): Low shadows use Shadow Mode 0, water is
-- drawn at Water Surface Detail 0 (its default), and Volumetric Fog has its own on/off.
local LEVELS_0_3 = { Choice(0, "Low"), Choice(1, "Fair"), Choice(2, "Good"), Choice(3, "High") }

local DERIVED_NOTE = "The quality sliders set these too, so changing quality afterwards resets them."
-- Josh, 2026-10-19: where the check doesn't tune shadows (M1, M2, the Neo, not Apple
-- Silicon; Josh 2026-11-07) every result and goal preset sets the shadows to fixed
-- low values (Solver.FixedChanges), "make sure we add a disclaimer saying that shadows are
-- turned down and are at the users discretion to increase". Approved wording, verbatim.
-- Macs whose shadows the check tunes (M3 and later) get the usual note only, and so
-- does a player keeping their Hidden Settings (Josh, 2026-10-19): Mac-ever doesn't turn
-- them down then.
local SHADOWS_DOWN_NOTE = "Mac-ever turns shadows down to save frame rate. Raising them is up to you."
Registry.SHADOWS_DOWN_NOTE = SHADOWS_DOWN_NOTE -- the System Check result says it too
local function ShadowsNote()
	if ns.Solver.TunesShadows() or ns.Solver.KeepsHidden() then
		return DERIVED_NOTE
	end
	return SHADOWS_DOWN_NOTE .. " " .. DERIVED_NOTE
end


local hidden = {
	-- Draw distance & fog
	{ name = "farclip", raid = "RAIDfarclip", group = "h_distance", control = "slider", slider = Slider(300, 10000, 100, Distance),
		label = "Draw Distance", tooltip = "How far away the world is drawn at all. Higher shows more scenery and costs more GPU time." },
	{ name = "horizonStart", raid = "RAIDhorizonStart", group = "h_distance", control = "slider", slider = Slider(100, 10000, 100, Distance),
		label = "Fog Start Distance", tooltip = "Where distance fog starts to fade the world out." },
	{ name = "horizonClip", raid = "RAIDhorizonClip", group = "h_distance", control = "slider", slider = Slider(300, 10000, 100, Distance),
		label = "Horizon Distance", tooltip = "How far the low-detail horizon (distant terrain silhouettes) is drawn." },
	{ name = "disableHorizonStart", group = "h_distance", control = "toggle",
		label = "Disable Full Fog", tooltip = "Turns off the fully fogged band at the edge of the draw distance." },

	-- Level of detail
	{ name = "terrainLodDist", raid = "RAIDterrainLodDist", group = "h_detail", control = "slider", slider = Slider(100, 1500, 25, Distance),
		label = "Terrain Detail Distance", tooltip = "How far full-detail terrain is drawn before it switches to simpler versions." },
	{ name = "TerrainLodDiv", raid = "RAIDTerrainLodDiv", group = "h_detail", control = "slider", slider = Slider(128, 1024, 32),
		label = "Terrain Detail Divisor", tooltip = "How quickly terrain detail drops off with distance." },
	{ name = "wmoLodDist", raid = "RAIDwmoLodDist", group = "h_detail", control = "slider", slider = Slider(100, 1500, 25, Distance),
		label = "Building Detail Distance", tooltip = "How far buildings and large structures keep full detail." },
	{ name = "wmoDoodadDist", group = "h_detail", control = "slider", slider = Slider(500, 5000, 100, Distance),
		label = "Building Prop Distance", tooltip = "How far props inside and around buildings are loaded." },
	{ name = "doodadLodScale", raid = "RAIDdoodadLodScale", group = "h_detail", control = "slider", slider = Slider(25, 300, 5, Percent),
		label = "Object Detail Scale", tooltip = "Scales how long trees, rocks and props keep their detailed models." },
	{ name = "entityLodDist", raid = "RAIDentityLodDist", group = "h_detail", control = "slider", slider = Slider(0, 50, 1),
		label = "Character Detail Distance", tooltip = "Level-of-detail distance for players and creatures." },
	{ name = "lodObjectCullSize", raid = "RAIDlodObjectCullSize", group = "h_detail", control = "slider", slider = Slider(0, 50, 1),
		label = "Small Object Culling Size", tooltip = "Objects smaller than this stop being drawn at distance. Lower keeps more small objects." },
	{ name = "lodObjectCullDist", raid = "RAIDlodObjectCullDist", group = "h_detail", control = "slider", slider = Slider(0, 200, 5, Distance),
		label = "Small Object Culling Distance", tooltip = "Minimum distance before small objects can be culled." },
	{ name = "lodObjectMinSize", raid = "RAIDlodObjectMinSize", group = "h_detail", control = "slider", slider = Slider(0, 100, 1),
		label = "Object Minimum Size", tooltip = "Smallest on-screen size an object can be before it's hidden." },
	{ name = "lodObjectFadeScale", raid = "RAIDlodObjectFadeScale", group = "h_detail", control = "slider", slider = Slider(25, 300, 5, Percent),
		label = "Object Fade Distance", tooltip = "Scales the distance at which objects fade in and out." },
	{ name = "dynamicLod", group = "h_detail", control = "toggle",
		label = "Dynamic Level of Detail", tooltip = "Lets the game lower detail on the fly when it's struggling to keep up." },
	{ name = "animFrameSkipLOD", group = "h_detail", control = "toggle",
		label = "Skip Animation Frames at Distance", tooltip = "Distant characters animate at a lower rate. Saves CPU time in busy areas." },

	-- Grass & ground clutter
	{ name = "groundEffectDensity", raid = "RAIDgroundEffectDensity", group = "h_ground", control = "slider", slider = Slider(16, 256, 8),
		label = "Grass Density", tooltip = "How thickly grass and small plants are drawn." },
	{ name = "groundEffectDist", raid = "RAIDgroundEffectDist", group = "h_ground", control = "slider", slider = Slider(0, 500, 10, Distance),
		label = "Grass Distance", tooltip = "How far away grass and small plants are drawn." },
	{ name = "groundEffectFade", raid = "RAIDgroundEffectFade", group = "h_ground", control = "slider", slider = Slider(0, 500, 10, Distance),
		label = "Grass Fade Distance", tooltip = "Where grass starts fading out." },

	-- Shadows
	{ name = "shadowMode", raid = "RAIDshadowMode", group = "h_shadows", control = "choice", choices = LEVELS_0_3,
		label = "Shadow Mode", tooltip = "Underlying shadow quality level (0-3)." },
	{ name = "shadowTextureSize", raid = "RAIDshadowTextureSize", group = "h_shadows", control = "choice",
		-- 512 and 768 are what the game itself sets for its lower shadow levels.
		choices = { Choice(512, "512"), Choice(768, "768"), Choice(1024, "1024 (Standard)"), Choice(2048, "2048 (Sharp)") },
		label = "Shadow Resolution", tooltip = "Resolution of the shadow map. Higher gives crisper shadow edges and uses more GPU memory." },
	{ name = "shadowNumCascades", raid = "RAIDshadowNumCascades", group = "h_shadows", control = "slider", slider = Slider(1, 4, 1),
		label = "Shadow Cascades", tooltip = "How many shadow detail bands are used. More keeps distant shadows sharper." },
	{ name = "shadowSoft", raid = "RAIDshadowSoft", group = "h_shadows", control = "toggle",
		label = "Soft Shadows", tooltip = "Softens shadow edges." },
	{ name = "shadowBlendCascades", raid = "RAIDshadowBlendCascades", group = "h_shadows", control = "toggle",
		label = "Blend Shadow Cascades", tooltip = "Smooths the visible line where one shadow band meets the next." },
	{ name = "entityShadowFadeScale", raid = "RAIDentityShadowFadeScale", group = "h_shadows", control = "slider", slider = Slider(5, 100, 5),
		label = "Character Shadow Distance", tooltip = "How far away characters and creatures cast shadows." },

	-- Lighting, water & effects
	{ name = "sunShafts", raid = "RAIDsunShafts", group = "h_effects", control = "choice",
		choices = { Choice(0, "Off"), Choice(1, "Low"), Choice(2, "High") },
		label = "Sun Shafts", tooltip = "God rays from the sun through trees and buildings." },
	{ name = "volumeFog", raid = "RAIDVolumeFog", group = "h_effects", control = "toggle",
		label = "Volumetric Fog", tooltip = "Fog with depth and light scattering." },
	{ name = "volumeFogLevel", raid = "RAIDVolumeFogLevel", group = "h_effects", control = "choice", choices = LEVELS_0_3,
		label = "Volumetric Fog Quality", tooltip = "Quality of volumetric fog (0-3)." },
	{ name = "volumeFogInterior", group = "h_effects", control = "toggle",
		label = "Indoor Volumetric Fog", tooltip = "Volumetric fog inside buildings and caves." },
	{ name = "reflectionMode", raid = "RAIDreflectionMode", group = "h_effects", control = "choice", choices = QUALITY_0_3,
		label = "Reflections", tooltip = "Quality of reflections on water and shiny surfaces." },
	{ name = "reflectionDownscale", group = "h_effects", control = "toggle",
		label = "Half-Resolution Reflections", tooltip = "Draws reflections at lower resolution to save GPU time." },
	{ name = "refraction", raid = "RAIDrefraction", group = "h_effects", control = "choice",
		choices = { Choice(0, "Off"), Choice(1, "Low"), Choice(2, "High") },
		label = "Refraction", tooltip = "Distortion through water, glass and heat haze." },
	{ name = "waterDetail", raid = "RAIDWaterDetail", group = "h_effects", control = "choice", choices = LEVELS_0_3,
		label = "Water Surface Detail", tooltip = "Detail of water surfaces." },
	{ name = "rippleDetail", raid = "RAIDrippleDetail", group = "h_effects", control = "choice",
		choices = { Choice(0, "Low"), Choice(1, "Good"), Choice(2, "High") },
		label = "Water Ripples", tooltip = "Detail of ripples on water." },
	{ name = "weatherDensity", raid = "RAIDweatherDensity", group = "h_effects", control = "choice", choices = QUALITY_0_3,
		label = "Weather Density", tooltip = "How much rain, snow and dust weather draws." },
	{ name = "particleDensity", raid = "RAIDparticleDensity", group = "h_effects", control = "slider", slider = Slider(10, 100, 5, Percent),
		label = "Particle Amount", tooltip = "Percentage of spell and environment particles drawn." },
	{ name = "particleMTDensity", raid = "RAIDparticleMTDensity", group = "h_effects", control = "slider", slider = Slider(10, 100, 5, Percent),
		label = "Layered Particle Amount", tooltip = "Percentage of multi-texture particles drawn." },
	{ name = "particulatesEnabled", raid = "RAIDParticulatesEnabled", group = "h_effects", control = "toggle",
		label = "Ambient Particles", tooltip = "Floating dust, pollen and embers in the air." },
	{ name = "DepthBasedOpacity", raid = "RAIDDepthBasedOpacity", group = "h_effects", control = "toggle",
		label = "Soft Particle Edges", tooltip = "Fades particles where they meet surfaces instead of showing hard edges." },
	{ name = "clusteredShading", raid = "RAIDclusteredShading", group = "h_effects", control = "toggle",
		label = "Lit Transparent Effects", tooltip = "Lets lights affect transparent effects like glass and particles." },
	{ name = "specular", group = "h_effects", control = "slider", slider = Slider(0, 1, 0.05, Multiplier),
		label = "Specular Highlights", tooltip = "Strength of shiny highlights on surfaces." },
	-- The game refused 4096 on an M1 Pro (2026-10-07); its default, 2048, is the top.
	{ name = "maxLightDist", group = "h_effects", control = "slider", slider = Slider(256, 2048, 128, Distance),
		label = "Light Distance", tooltip = "How far away dynamic lights are drawn." },
	{ name = "ffxGlow", group = "h_effects", control = "toggle",
		label = "Full-Screen Glow", tooltip = "A soft glow over the whole picture. Many players turn it off for a crisper, less hazy image." },
	{ name = "ffxNether", group = "h_effects", control = "toggle",
		label = "Nether Distortion", tooltip = "The wavy, blurred screen effect in nether and magical areas." },
	{ name = "ffxDeath", group = "h_effects", control = "toggle",
		label = "Death Desaturation", tooltip = "Drains colour from the screen when you die." },
	{ name = "showfootprintparticles", group = "h_effects", control = "toggle",
		label = "Footprint Particles", tooltip = "Dust and splashes from footsteps." },

	-- Ambient occlusion tuning (ASSAO)
	{ name = "assaoRadius", group = "h_ao", control = "slider", slider = Slider(0.5, 5, 0.05),
		label = "Shadow Radius", tooltip = "Size of the area that casts ambient occlusion." },
	{ name = "assaoShadowMult", group = "h_ao", control = "slider", slider = Slider(0, 5, 0.1, Multiplier),
		label = "Strength", tooltip = "How dark the ambient occlusion is." },
	{ name = "assaoShadowPower", group = "h_ao", control = "slider", slider = Slider(0.5, 5, 0.05),
		label = "Contrast", tooltip = "How sharply ambient occlusion darkens corners." },
	{ name = "assaoBlurPassCount", group = "h_ao", control = "slider", slider = Slider(0, 6, 1),
		label = "Smoothing Passes", tooltip = "Number of smoothing passes. More looks softer and costs a little GPU time." },
	{ name = "assaoFadeOutTo", group = "h_ao", control = "slider", slider = Slider(50, 1000, 10, Distance),
		label = "Fade-Out Distance", tooltip = "Distance at which ambient occlusion fully fades away." },

	-- Resolution & sharpness
	{ name = "ResampleAlwaysSharpen", group = "h_sharpness", control = "toggle",
		label = "Sharpen at Full Resolution", tooltip = "Runs the sharpening pass even at 100% render scale, which normally skips it. Known as \"glasses for WoW\": a much crisper picture for almost no cost." },
	{ name = "DynamicRenderScale", group = "h_sharpness", control = "toggle", risk = "caution",
		label = "Dynamic Render Scale", tooltip = "Lowers render scale automatically when the GPU can't hit your Target FPS (set Target FPS in Standard Settings). It can cause hitching." },
	{ name = "DynamicRenderScaleMin", group = "h_sharpness", control = "slider",
		slider = Slider(0.33, 1, 0.01, function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end),
		label = "Dynamic Render Scale Minimum", tooltip = "Lowest render scale Dynamic Render Scale may drop to." },

	-- HDR: only ever changed by the player (no preset, System Check or Game Defaults).
	{ name = "HDROutput", group = "h_hdr", control = "toggle", risk = "caution",
		label = "HDR Output", tooltip = "Brighter highlights and richer colour on HDR screens. Changes the picture's output format while the game runs: on some setups that can make colours look wrong until it's switched off or the UI is reloaded." },
	{ name = "HDRFactor", group = "h_hdr", control = "slider", slider = Slider(1, 4, 0.1, Multiplier),
		label = "HDR Strength", tooltip = "How far above normal brightness HDR highlights may go. Capped at what your screen can show." },
	{ name = "useHDRPeakBrightness", group = "h_hdr", control = "toggle",
		label = "Override Peak Brightness", tooltip = "Use the peak brightness below instead of what your screen reports." },
	{ name = "HDRPeakBrightness", group = "h_hdr", control = "slider",
		slider = Slider(400, 1600, 50, function(value) return ("%d nits"):format(value) end),
		label = "Peak Brightness", tooltip = "Brightest highlight your screen can show. MacBook Pro XDR displays reach 1600 nits for HDR highlights." },
	{ name = "useHDRBrightness", group = "h_hdr", control = "toggle",
		label = "Override Paper White", tooltip = "Use the brightness below for normal (non-highlight) content." },
	{ name = "HDRBrightness", group = "h_hdr", control = "slider",
		slider = Slider(80, 500, 1, function(value) return ("%d nits"):format(value) end),
		label = "Paper White Brightness", tooltip = "Brightness of normal content in HDR. Raise it if HDR looks dim." },

	-- Performance
	{ name = "maxFPSLoading", group = "h_performance", control = "slider", slider = Slider(10, 200, 5, function(value) return ("%d fps"):format(value) end),
		label = "Loading Screen FPS Cap", tooltip = "Frame cap during loading screens. Lower leaves more power for loading." },
	{ name = "sceneOcclusionEnable", group = "h_performance", control = "toggle",
		label = "Occlusion Culling", tooltip = "Skips drawing things hidden behind other objects. Leave on unless troubleshooting." },
	{ name = "componentTextureLevel", raid = "RAIDcomponentTextureLevel", group = "h_performance", control = "choice",
		choices = { Choice(0, "Full"), Choice(1, "Half"), Choice(2, "Quarter") },
		label = "Character Texture Detail", tooltip = "Texture detail for character armour and skin. Lower saves video memory." },

	-- Camera
	{ name = "cameraDistanceMaxZoomFactor", group = "h_camera", control = "slider", slider = Slider(1, 4, 0.1, Multiplier),
		label = "Max Camera Distance", tooltip = "How far you can zoom the camera out." },

	-- Screenshots
	{ name = "screenshotFormat", group = "h_screenshots", control = "choice",
		choices = { Choice("jpeg", "JPEG"), Choice("png", "PNG (lossless)"), Choice("tga", "TGA") },
		label = "Screenshot Format", tooltip = "File format for screenshots." },
	{ name = "screenshotQuality", group = "h_screenshots", control = "slider", slider = Slider(1, 10, 1),
		label = "Screenshot Quality", tooltip = "JPEG quality for screenshots (1-10)." },

	-- Hidden compatibility switches
	{ name = "GxCompatAsyncComputeQueue", group = "h_compat", control = "toggle", restart = "gx", risk = "advanced",
		label = "Async Compute Queue", tooltip = "Lets some compute work run on a separate GPU queue." },
	{ name = "GxCompatCopyQueue", group = "h_compat", control = "toggle", restart = "gx", risk = "advanced",
		label = "Copy Queue", tooltip = "Lets GPU upload work run on a separate queue." },
	{ name = "GxCompatLowLatencyCallbacks", group = "h_compat", control = "toggle", restart = "gx", risk = "advanced",
		label = "Low-Latency GPU Callbacks", tooltip = "Checks for finished GPU work more often instead of waiting the maximum time." },
}

for _, entry in ipairs(hidden) do
	entry.order = Registry.ORDER.HIDDEN
	Registry.Add(entry)
	if entry.raid then
		local copy = {}
		for key, value in pairs(entry) do
			copy[key] = value
		end
		copy.name = entry.raid
		copy.raid = true
		copy.worldName = entry.name
		entry.raid = nil
		entry.raidName = copy.name
		Registry.Add(copy)
	end
end

-- The Hidden Settings hierarchy (Josh, 2026-10-07): broad display settings at the top,
-- the most granular at the bottom, related groups next to each other, and settings within
-- a group from broad to fine. Everything Else stays last. Every curated setting must be
-- listed here exactly once (checked by the tests).
local AO_NOTE = "Fine-tunes the SSAO setting. Only has an effect while SSAO is on."
local HDR_NOTE = "Needs an HDR screen, such as the XDR display on 14\" and 16\" MacBook Pros. If anything looks wrong after changing HDR Output, switch it off or /reload. Mac-ever never changes it by itself."
Registry.HIDDEN_HIERARCHY = {
	{ id = "h_hdr", label = "HDR (XDR & HDR displays)", note = HDR_NOTE,
		names = { "HDROutput", "HDRFactor", "useHDRPeakBrightness", "HDRPeakBrightness", "useHDRBrightness", "HDRBrightness" } },
	{ id = "h_sharpness", label = "Image Clarity",
		names = { "ResampleAlwaysSharpen", "DynamicRenderScale", "DynamicRenderScaleMin" } },
	{ id = "h_distance", label = "Draw Distance & Fog", note = DERIVED_NOTE,
		names = { "farclip", "horizonClip", "horizonStart", "disableHorizonStart" } },
	{ id = "h_camera", label = "Camera",
		names = { "cameraDistanceMaxZoomFactor" } },
	{ id = "h_detail", label = "World Detail", note = DERIVED_NOTE,
		names = { "terrainLodDist", "wmoLodDist", "doodadLodScale", "wmoDoodadDist", "entityLodDist",
			"lodObjectFadeScale", "lodObjectCullDist", "lodObjectCullSize", "lodObjectMinSize", "TerrainLodDiv" } },
	{ id = "h_ground", label = "Grass & Ground Clutter", note = DERIVED_NOTE,
		names = { "groundEffectDensity", "groundEffectDist", "groundEffectFade" } },
	{ id = "h_lighting", label = "Lighting & Atmosphere", note = DERIVED_NOTE,
		names = { "sunShafts", "volumeFog", "volumeFogLevel", "volumeFogInterior", "maxLightDist", "specular", "clusteredShading" } },
	{ id = "h_shadows", label = "Shadows", note = ShadowsNote,
		names = { "shadowMode", "shadowTextureSize", "shadowNumCascades", "shadowSoft", "shadowBlendCascades", "entityShadowFadeScale" } },
	{ id = "h_ao", label = "Ambient Occlusion Tuning", note = AO_NOTE,
		names = { "assaoRadius", "assaoShadowMult", "assaoShadowPower", "assaoBlurPassCount", "assaoFadeOutTo" } },
	{ id = "h_water", label = "Water & Reflections", note = DERIVED_NOTE,
		names = { "waterDetail", "rippleDetail", "reflectionMode", "reflectionDownscale", "refraction" } },
	{ id = "h_particles", label = "Particles & Weather", note = DERIVED_NOTE,
		names = { "particleDensity", "particleMTDensity", "weatherDensity", "particulatesEnabled", "DepthBasedOpacity", "showfootprintparticles" } },
	{ id = "h_screen", label = "Screen Effects",
		names = { "ffxGlow", "ffxDeath", "ffxNether" } },
	{ id = "h_performance", label = "Performance",
		names = { "dynamicLod", "animFrameSkipLOD", "sceneOcclusionEnable", "componentTextureLevel", "maxFPSLoading" } },
	{ id = "h_screenshots", label = "Screenshots",
		names = { "screenshotFormat", "screenshotQuality" } },
	{ id = "h_compat", label = "Hidden Compatibility Settings", note = "Low-level renderer switches. Change one at a time.",
		names = { "GxCompatAsyncComputeQueue", "GxCompatCopyQueue", "GxCompatLowLatencyCallbacks" } },
}

for _, group in ipairs(Registry.HIDDEN_HIERARCHY) do
	Registry.AddGroup({ id = group.id, tab = "hidden", label = group.label, note = group.note })
	for position, name in ipairs(group.names) do
		local entry = assert(Registry.Get(name), name)
		entry.group, entry.listOrder = group.id, position
		local raidCopy = entry.raidName and Registry.Get(entry.raidName)
		if raidCopy then
			raidCopy.group, raidCopy.listOrder = group.id, position
		end
	end
end

-- The reset set (Josh, 2026-10-18): Hidden settings that go back to the game's defaults
-- while the System Check measures and with every check result and goal preset, so the
-- player gets what was measured. The check tunes only Standard Settings, and the Standard
-- sliders re-derive many of these on every write, so the reset is written first (the
-- change flag first) and the sliders then set their own values on top.
-- Not reset:
--   * raid copies, here: the check never writes the raid sliders, so nothing would
--     re-derive them (RAIDfarclip would sit at its static default, 1000). In a raid,
--     Instance Settings maps the reset to the raid copies with the raid sliders instead.
--   * HDR, Camera, Screenshots, the compatibility switches and Everything Else: not about
--     frame rate or picture quality, the player's own choice, or needing a restart
--   * ResampleAlwaysSharpen and DynamicRenderScale: set instead, to 1 and 0
--     (Solver.ForApply), as the check measures
--   * doodadLodScale, groundEffectDensity and groundEffectDist: Josh's fixed extras, set
--     instead (Benchmark DIMENSIONS)
--   * Full-Screen Glow, and the shadow settings where the check doesn't tune them: Josh's fixed values
--     (2026-10-19), set instead (Solver.FixedChanges; Solver.WithReset leaves them out)
--   * componentTextureLevel: likely derived by Texture Resolution, which is never forced
--     (it reloads every texture), so nothing would set it back where the game puts it
--   * Sun Shafts, Refraction and Soft Edges: derived by Depth Effects, which the check
--     never switches or forces (it crashed an M5 Pro mid-check, 2026-11-05), so they stay
--     as the player's Depth Effects set them (Josh, 2026-11-05)
--   * anything that needs a restart, and Registry.NEVER_WRITE
-- The values are what a fresh install has. The screen corruption of 2026-10-07 came from
-- switching RenderFormat, which is in Registry.NEVER_WRITE and stays blocked.
Registry.RESET_GROUPS = { "h_distance", "h_detail", "h_ground", "h_lighting", "h_shadows", "h_ao", "h_water",
	"h_particles", "h_screen", "h_performance" }
local RESET_ALSO = { "DynamicRenderScaleMin" } -- from Image Clarity
local NOT_RESET = {
	resamplealwayssharpen = true, dynamicrenderscale = true,
	doodadlodscale = true, groundeffectdensity = true, groundeffectdist = true,
	componenttexturelevel = true,
	sunshafts = true, refraction = true, depthbasedopacity = true,
}

-- The reset set's names.
function Registry.HiddenResetNames()
	local names = {}
	local function Consider(name)
		local key = Registry.Key(name)
		local entry = Registry.Get(name)
		if entry and not entry.raid and not entry.restart and not NOT_RESET[key]
			and not Registry.NEVER_WRITE[key] then
			names[#names + 1] = entry.name
		end
	end
	local resetGroups = {}
	for _, id in ipairs(Registry.RESET_GROUPS) do
		resetGroups[id] = true
	end
	for _, group in ipairs(Registry.HIDDEN_HIERARCHY) do
		if resetGroups[group.id] then
			for _, name in ipairs(group.names) do
				Consider(name)
			end
		end
	end
	for _, name in ipairs(RESET_ALSO) do
		Consider(name)
	end
	return names
end

-- The reset set as changes, flagged first: each setting this client has and can change,
-- even one already at its default. A setting already there isn't written (CVars.Apply
-- skips it), but in a raid Instance Settings maps the change to the raid copy, which may
-- not be at its default. skip: an optional set of Registry.Key names to leave out (ones
-- the caller already sets).
function Registry.HiddenResetChanges(skip)
	local changes = {}
	for _, name in ipairs(Registry.HiddenResetNames()) do
		if not (skip and skip[Registry.Key(name)]) then
			local value, default = ns.CVars.Inspect(name)
			if value ~= nil and default ~= nil then
				changes[#changes + 1] = { name = name, value = default, first = true }
			end
		end
	end
	return changes
end

-- Discovered: every other graphics console variable the running client reports.
-- Shown as plain text fields, all marked Advanced.
Registry.AddGroup({ id = "discovered", tab = "hidden", label = "Everything Else",
	note = "Every other graphics console variable this version of the game has, straight from the game's own list, with the game's own description. Mac-ever hasn't vetted these.",
	collapsible = true,
	confirm = {
		title = "These settings can crash the game",
		text = "Everything Else lists raw graphics console variables straight from the game. Mac-ever hasn't checked what they do on Macs, and some are developer switches that can crash the game, corrupt the picture or make it unplayable.\n\nOnly change one if you know exactly what it does. If something goes wrong, type /macever restore in chat, or relaunch the game and use Restore Originals.",
		accept = "Show Them",
	} })

-- Development switches and things that would break the client or its settings.
local NEVER_LIST = {
	allowsoftwarerenderer = true, allowsoftwarerendererdx12 = true, hwdetect = true,
	gxapi = true, gxadapter = true, gxmonitor = true, gxnewresolution = true, gxafrdevicescount = true,
	gxprismenabled = true, videooptionsversion = true, videooptionsversiondefault = true,
	textureerrorcolors = true, hotreloadmodels = true, forcelodcheck = true, driverversioncheck = true,
	framebuffercacheforcenoheaps = true, forceresolutiondefaulttomaxsize = true,
	reloaduionaspectchange = true, linear = true,
	-- Switch the frame buffer format while the game runs: this corrupted the whole
	-- screen on a Mac in testing (2026-10-07). See Registry.NEVER_WRITE.
	renderformat = true,
	-- GI quality and Blizzard's GPU debug switches (2026-11-05). See Registry.NEVER_WRITE.
	giquality = true, gxdebuglevel = true, gxdebugbreaklevel = true,
}

local GRAPHICS_CATEGORY = 1 -- Enum.ConsoleCategory.Graphics
local CVAR_TYPE = 0 -- Enum.ConsoleCommandType.Cvar

local discovered = false

-- Returns how many variables were added. Safe to call more than once.
function Registry.DiscoverConsoleVariables()
	if discovered or not ConsoleGetAllCommands then
		return 0
	end
	discovered = true

	local category = Enum and Enum.ConsoleCategory and Enum.ConsoleCategory.Graphics or GRAPHICS_CATEGORY
	local cvarType = Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar or CVAR_TYPE

	local found = {}
	for _, info in ipairs(ConsoleGetAllCommands()) do
		local name = info.command
		if info.category == category and info.commandType == cvarType and name
			and not Registry.Get(name) and not NEVER_LIST[name:lower()]
			and not name:match("^RAID") and not name:match("^raidGraphics") then
			local value, _, _, _, isLocked, isSecure, isReadOnly = C_CVar.GetCVarInfo(name)
			if value ~= nil and not isSecure and not isReadOnly and not isLocked then
				found[#found + 1] = { name = name, help = info.help }
			end
		end
	end
	table.sort(found, function(a, b) return a.name:lower() < b.name:lower() end)

	for _, item in ipairs(found) do
		Registry.Add({
			name = item.name,
			group = "discovered",
			control = "text",
			risk = "advanced",
			order = Registry.ORDER.DISCOVERED,
			label = item.name,
			tooltip = item.help ~= "" and item.help or nil,
		})
	end
	return #found
end

ns.On("PLAYER_LOGIN", Registry.DiscoverConsoleVariables)
