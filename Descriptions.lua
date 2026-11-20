local _, ns = ...
local L = ns.L

local Registry = ns.Registry

-- One plain-English line per setting, shown under its name: what it changes on screen
-- and what it costs. Hidden settings already carry this in their tooltip text; raid
-- copies reuse their world setting's line. Discovered console variables show the
-- game's own help text instead.
local SUMMARIES = {
	-- Graphics quality
	graphicsQuality = L("Moves every quality setting below it to a preset level at once (1 = lowest, 10 = highest)."),
	graphicsShadowQuality = L("Detail and reach of shadows from characters, buildings and terrain. A big GPU cost."),
	graphicsLiquidDetail = L("Detail of water, lava and other liquids, including reflections on them."),
	graphicsPBRLiquidDetail = L("Newer, more realistic water rendering. Higher looks better and costs more GPU time."),
	graphicsParticleDensity = L("How many particles spells and the world show (smoke, sparks, magic). Busy fights cost the most."),
	graphicsSSAO = L("Soft contact shadows in corners and where objects meet the ground. Adds depth; costs GPU time."),
	graphicsDepthEffects = L("Depth-of-field blur and other distance-based effects."),
	graphicsComputeEffects = L("Volumetric fog and other compute-shader effects. A large GPU cost."),
	graphicsOutlineMode = L("Outlines drawn around targets and objects you mouse over."),
	graphicsTextureResolution = L("Sharpness of surface textures. Mainly uses video memory, little frame rate."),
	graphicsSpellDensity = L("How many spell effects from other players you see. Lower reduces clutter in big fights."),
	graphicsProjectedTextures = L("Spell effects drawn onto the ground, such as area-of-effect markers. Turning off hides combat cues."),
	graphicsLightMode = L("Bounced and indirect lighting (global illumination). A very large GPU cost on Macs."),
	graphicsViewDistance = L("How far away the world is drawn. Higher shows more scenery and costs GPU and CPU time."),
	graphicsEnvironmentDetail = L("How many trees, rocks and props are drawn, and how far away."),
	graphicsGroundClutter = L("Density and distance of grass and small plants."),
	bloomUserMult = L("Strength of the glow around bright lights."),
	RAIDsettingsEnabled = L("Use a separate, usually lower, set of quality settings in raids and battlegrounds."),

	-- Display
	RenderScale = L("Resolution the 3D world is drawn at. Tip: 99% with FidelityFX looks crisper than 100%, because sharpening only runs below 100%."),
	ResampleQuality = L("How the world is scaled when Render Scale isn't 100%. FidelityFX looks sharpest."),
	ResampleSharpness = L("Sharpening strength: 0 is the strongest, 2 the weakest. Stronger looks crisper; too strong looks gritty. 0.2 is the game's default."),
	textureFilteringMode = L("Keeps textures sharp at steep angles, such as the ground ahead of you. Small cost."),
	PROXY_ANTIALIASING = L("How edges are smoothed: image-based (FXAA, CMAA), multisampling, or both. Greys out the rows it doesn't use."),
	ffxAntiAliasingMode = L("Smooths jagged edges. FXAA is cheap; CMAA 2 cost about 56 fps on an M1 Pro in testing."),
	MSAAQuality = L("Smooths jagged edges by sampling each pixel several times. Costly at Retina resolutions."),
	MSAAAlphaTest = L("Also smooths the edges of leaves, fences and grass when multisampling is on."),
	vsync = L("Syncs frames to your screen to stop tearing. Limits frame rate to the screen's refresh rate."),
	GxMaxFrameLatency = L("Lets the CPU queue an extra frame. Smoother on some systems, adds input lag."),
	LowLatencyMode = L("Reduces the delay between your input and what you see."),
	NotchedDisplayMode = L("How the game handles the camera notch on MacBook screens."),
	GxMaximize = L("Fill the whole screen, or play in a window."),
	vrsValar = L("Draws less important parts of the image at lower detail to save GPU time."),
	shadowRt = L("Ray-traced shadows. Not supported on Macs."),
	physicsLevel = L("Whether grass, cloth and objects react to you and to creatures."),
	cameraFov = L("How wide the camera's view is."),

	-- Frame rate
	useMaxFPS = L("Turns the foreground frame-rate cap on or off."),
	maxFPS = L("Highest frame rate while the game is in front. Lower saves battery and keeps the Mac cooler."),
	useMaxFPSBk = L("Turns the background frame-rate cap on or off."),
	maxFPSBk = L("Highest frame rate while you're in another app. Low values save a lot of battery."),
	useTargetFPS = L("Lets the game lower detail on its own when it falls below Target FPS."),
	targetFPS = L("Frame rate the game tries to stay above when Target FPS is on."),

	-- Brightness & colour
	Brightness = L("Overall brightness."),
	Contrast = L("Difference between light and dark areas."),
	Gamma = L("Brightness of mid-tones. Raise it to see into dark areas."),

	-- Compatibility
	GxCompatOptionalGpuFeatures = L("Uses extra GPU features when available. Off makes the game act as if the GPU had only the basics."),
	GxCompatAsyncShaderCompilation = L("Prepares shaders in the background instead of pausing the game to do it."),
	GxCompatCommandListMultiThreading = L("Spreads rendering work across several CPU cores."),
	GxCompatWorkSubmitOptimizations = L("Sends work to the GPU from a separate thread."),
}

for _, entry in ipairs(Registry.entries) do
	entry.summary = SUMMARIES[entry.name] or (entry.worldName and SUMMARIES[entry.worldName]) or entry.summary
	if not entry.summary and entry.group:match("^h_") then
		entry.summary = entry.tooltip
	end
end

-- The language is only known once the saved data has loaded: translate again then.
ns.Locale.OnReady(function()
	for _, entry in ipairs(Registry.entries) do
		if entry.summary then
			entry.summary = ns.L(entry.summary)
		end
	end
end)

-- Exported for tests: every curated setting must have a line.
Registry.SUMMARIES = SUMMARIES
