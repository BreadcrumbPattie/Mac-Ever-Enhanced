# Mac-ever

## 0.7.0 (fork: cool and quiet)

### Added
- **Headroom.** The frame rate stays capped at your goal (60), but the System Check only raises graphics until the Mac could still reach goal x headroom without the cap (60 x 1.6 = about 96 fps). The GPU never runs flat out, so the fans stay quiet. Set it on the System Check tab; "Off" restores the original behaviour.

### Added (starting profiles)
- **The 60 fps preset works before any System Check.** It starts from a profile for your Mac's class (chip, Air or not, memory): lower render scale, SSAO, Compute Effects, view distance, environment and clutter on smaller chips, Shadows Good from M3 on. It stays capped at 60 and is replaced by the measured result once you run the System Check. Without permission to lower resolution it uses 85% render scale and says so.
- MacBook Air gets headroom x1.75 by default (it has no fan).

### Added (language)
- **Serbian (Latin) translation.** Choose it under Options > AddOns > Mac-ever > Language, or type /macever lang sr (and /macever lang en to go back). The interface reloads when you change it. Setting names from the game itself keep the game's language, and the Hidden Settings tooltips are still English.

### Changed
- **Shadow Quality never goes above Good.** The check only measures Low and Good.
- **Render Scale is kept between 50% and 70%** (FidelityFX upscaling), in 5% steps; the old 85-99% range and the "lower resolution" extra step are gone. Reports are now version 14.
- **The check now understands which settings are cheap.** View Distance, Environment Detail, Ground Clutter and Texture Filtering are measured like the rest, but when one costs less than 6% of a frame it stays at maximum instead of being given up for a few fps. The starting profiles no longer touch them. Texture Resolution is not tuned for frame rate at all: it follows your memory from setup (Fair on 8 GB, High on 16 GB or more). Reports are now version 15: run the check again.
- System Check reports are version 12: run the System Check again after updating.

## 0.6.0

### Changed
- **The System Check tests shadows on every Mac with an M3 or later chip,** not only the fastest Macs, and sets them by the same frame-rate rules as everything else. Macs with an M1 or M2 chip, the MacBook Neo and computers without Apple Silicon keep shadows Low. Run the System Check again after updating: presets and Apply Recommended need a new one.
- **Keep my Hidden Settings asks first.** Ticking it shows a warning: Mac-ever can't promise that your own Hidden Settings help the picture or frame rate. Without it, the System Check and its results still set Hidden Settings back to the game's defaults, apart from Mac-ever's sharpening and glow.

## 0.5.0

### Changed
- **Every frame rate is open on every Mac.** Nothing is greyed out in setup, on the System Check tab, on the Presets tab or in Instance Settings. If you pick a frame rate above what Mac-ever recommends for your Mac, a warning asks you to accept it first, and it's your call from there. The second time it appears, you can tick "Don't show this again". Frame rates Mac-ever recommends for your Mac never show the warning, and "Best fit for your Mac" hasn't changed.

## 0.4.0

### Changed
- **The Mac Fixes tab is gone.** Blizzard's launch build (70755 and later) includes its fixes for the Mac graphics problems Mac-ever worked around, including the green tint. The fixes, Reduce Green Tint, the Windowed (Fullscreen) warning and the Mac Fixes preset have gone with the tab, and no setting is marked as a Mac issue any more. Checked against build 70790.
- **Report a Problem is at the bottom of the window,** next to Game Defaults, on every tab. If the game crashes, it points to the crash files in World of Warcraft/_forever_/Errors.
- **Changing Compute Effects no longer asks for a UI reload.**
- **The window is a little wider at its smallest,** so the buttons along the bottom fit.
- **Mac-ever's Standard picture uses Gamma 1.0** (was 0.9), so night scenes aren't as dark. It still has Contrast 65%, Brightness 50% and Bloom 0.4, and every System Check result and goal preset brings it.

### Fixed
- **The System Check could crash the game.** It no longer switches Depth Effects while it measures: it keeps yours, and Sun Shafts, Refraction and Soft Edges stay as your Depth Effects sets them.
- **Standard Settings matches the game's Graphics menu again.** Compute Effects and Particle Density use the game's names and numbers, Secondary Lighting has Ultra, and the Anti-Aliasing mode is back, greying the rows it doesn't use. Low Latency Mode, Variable Rate Shading and Ray Traced Shadows no longer show on a Mac, and the multisampling rows only show where your Mac supports it.
- **The System Check uses the game's Particle Density range,** Low to Ultra, on Macs with Secondary Lighting.
- **Hidden Settings:** GI quality and the GPU debug switches are never listed or changed. Shadow Resolution offers the game's own 512 and 768. Shadow Mode, Water Surface Detail and Volumetric Fog Quality start at Low instead of Off.

## 0.3.0

### New
- **Best fit for your Mac.** One preset is tagged Best fit for your Mac, so you can see where to start.
- **MacBook Neo** is a choice in setup.
- **Keep my Hidden Settings.** After your first System Check, tick it on the System Check tab and later checks, presets and Instance Settings leave your Hidden Settings as you set them.

### Changed
- **Goals your Mac can't hold are greyed out.** In setup, on the System Check tab, on the Presets tab and in Instance Settings, based on your Mac. MacBook Airs, MacBook Neos and 8 GB Macs, for example, go up to 60 fps. You can still set anything yourself in Standard Settings or the game's menu.
- **Presets and setup are by frame rate.** Pick a frame rate from 30 to 165 fps (the ones beyond your Mac are greyed out), and each keeps graphics as high as that frame rate allows. Battery Saver, Quiet & Cool, Smooth and ProMotion are now 30, 45, 60 and 120 fps, and 30 and 45 fps keep more graphics than Battery Saver and Quiet & Cool did.
- **Apply Recommended shows when it's applied.** Like a preset's Apply button, it turns into a green Applied button you can't click once you keep the System Check's recommendation. Change any of those settings, apply a preset or run a new check, and the red Apply Recommended button comes back.
- Checked against beta build 70450: the green tint is still reported, so Reduce Green Tint stays available.
- **Ultra Uncapped is gone.** For everything at maximum, move the game's Graphics Quality slider to 10.
- **The System Check only tunes Standard Settings.** It measures with Hidden Settings at the game's defaults and puts yours back when it finishes or stops. Applying its result or a goal preset sets Hidden Settings to the game's defaults too, apart from the fixed values below, so what you get is what was measured. Object detail (200%) and grass (density 128, 200 yd) are always set, Sharpen at Full Resolution is turned on and Dynamic Render Scale is turned off.
- **Shadows are turned down, except on the fastest Macs.** On every Mac but the fastest (such as an M4 Max or M5 Pro), the System Check no longer tunes shadows: every check result and goal preset sets Shadow Quality to Low with low shadow settings underneath. Raising them is up to you. On the fastest Macs the check tunes shadows as before.
- **Full-Screen Glow is turned off** with every System Check result and goal preset.
- **Sharpening is at its strongest** (Sharpness 0) with every System Check result and goal preset.
- **Every System Check result and goal preset brings Mac-ever's Standard picture:** Contrast 65%, Brightness 50%, Gamma 0.9 and Bloom 0.4. The Standard picture look is now this too. Adjust them as you see fit, or pick another picture look: the preset or result stays applied. Instance Settings leaves your picture as it is.
- **Run the System Check again after updating:** results from earlier versions can't be used.

### Fixed
- **Restore Originals keeps Hidden Settings where they belong.** Putting a Standard setting back makes the game re-derive the Hidden Settings under it. They now go back to what they were before Mac-ever too, and any you changed yourself stay as you set them.
- **The System Check could max out Hidden effects measured where they cost nothing** (water and reflections with no water in view, 10,000 yd draw distance in a forest), then pay for them with Shadows, SSAO and render scale.

## 0.2.4

### Fixed
- **The System Check could say "goal met" when it wasn't.** If its recommendation measured below your goal on every try, it still reported the goal as met, and Apply Recommended gave you that slower setup even when a faster one had been measured. It now judges by what it measured, and in that case recommends the faster setup it measured.

- **The System Check gave up things that barely cost anything.** Settings like view distance and textures could read as costing 2-3 fps from measurement noise alone, and near the limit of a spot the check lowered them for about 1 fps. Now:
  - it measures the lowest settings twice in a row and treats any cost smaller than that run's own wobble as free;
  - it allows for the frame rate drifting during the check;
  - textures, view distance and environment detail each get their own measurement;
  - when settings that cost little add up and the goal is missed, it gives them back least visible first (particles, depth effects, liquid and the like before filtering, environment detail, view distance and textures), measuring each step, and stops as soon as the goal is met. A step only counts when it's at least 3% faster, more than a scene's own wobble, so a spot right at the limit keeps its water, reflections and clutter and says the goal was missed by a little.

### Changed
- **Mac Fixes have their own tab.** Every Mac fix switch, Reduce Green Tint, the Windowed (Fullscreen) warning and Apply Mac Fixes are now together on the Mac Fixes tab, the last tab. Presets and System Check now only tune frame rate and picture quality. Presets still keep the fixes that are on, and System Check still offers Apply Mac Fixes when a fix that's on isn't applied yet.
- **Report a Problem is on the Mac Fixes tab.** At the bottom of the window it sat behind Discard and Apply on the settings tabs. /macever report still works.
- **System Check is simpler.** It's three steps from top to bottom: choose your goal, run the check, see the result. Labels and controls line up, the progress bar only shows while the check runs, and the whole page scrolls, so the result has more room. The warning banner is gone: what can go wrong while it runs is on the Run button's tooltip, and one short notice mentions the Windowed (Fullscreen) bug and where its fix is.
- **The applied preset stands out.** Its card turns green, with a tick and Applied beside its name, and its Apply button becomes a green Applied button you can't click. Change any of its settings, here, in the game's menu or with another addon, and the red Apply button comes back. A new System Check result re-tailors the presets, so none shows as applied until you apply one again.
- **Bloom Intensity.** Beta build 70425 replaced the game's Bloom choice with a Bloom Intensity slider at the end of Graphics > Advanced. Standard Settings now shows the same slider in the same place, 0 to 1 in steps of 0.2. As before, presets and the System Check leave it as you set it.
- **The System Check makes sure your settings came back.** A second after putting your settings back, it checks each one again and puts back any that didn't stay. If one still won't, it tells you which, and Restore Originals puts it back.
- **By Location is now Instance Settings**, on the Presets tab. It works as before.
- Checked against beta build 70425: the green tint is still reported, so Reduce Green Tint stays available.

## 0.2.3

### New
- **Report a Problem.** A button at the bottom of the Mac-ever window (or type /macever report) shows a report of your Mac, setup, settings, the last System Check and the last error Mac-ever caught, already selected. Press Cmd+C and paste it in a comment on Mac-ever's CurseForge page. It has no character or realm names. If the game crashed, also attach the newest file from World of Warcraft/_classic_beta_/Errors.

### Fixed
- **System Check crash.** On some Macs (reported on M5 Max), the game could crash at about 80% of the System Check. That step raised Secondary Lighting to High while the game ran, which is the suspected cause. The System Check no longer changes Secondary Lighting: it stays at your setting, and Ultra Uncapped still sets it to High.
- The System Check progress bar sat at 99% for most of the check on some Macs. It now moves steadily to the end.

### Changed
- **Reduce Green Tint is clear about what it can do.** The green tint is a known bug in the latest beta build, and Blizzard is working on a fix. Reduce Green Tint may make it fainter, but can't always stop it. A /reload clears the tint for a few minutes.

## 0.2.2

### New
- **Windowed warning under System Check results.** On some Macs, a known bug in the latest beta build makes Windowed (Fullscreen) run at a much lower frame rate than Windowed. If your result seems low, click Switch to Windowed (you get the usual seconds to keep it or switch back), then run the check again. Mac-ever never changes display mode unless you click it.

### Fixed
- Changing display mode, notch mode or VSync from Mac-ever, including putting them back with Restore Originals or by switching back, caused a Lua error and didn't refresh the game window.

## 0.2.1

### Changed
- **Mac Fixes turns Triple Buffering back on.** Version 0.1.0 turned it off for everyone, but it's on by default in the game, and testers ruled it out as a cause of the Mac problems. If it's still off, the Mac Fixes card says so; switch its Known Issues fix on to keep it off.
- **Mac-ever never restarts the renderer.** Triple Buffering and the Compatibility settings now take effect the next time you start the game, and chat says so. Version 0.1.0 restarted the renderer on every preset, which may have crashed the game on some Macs.
- **The System Check is the same on every Mac.** It no longer keeps running for up to 2 more minutes when your Mac is warming up. On a fanless MacBook Air, a long session can run a little slower than the check measured; running the check once your Mac has warmed up gives the closest result.

## 0.2.0

### New
- **Setup**: the first time you open Mac-ever, three short steps on their own: which Mac you have and how much memory, then what matters most, from choices that suit your Mac (a top-end Mac is offered up to 120 fps; an older or 8 GB Mac gets realistic targets). Setup measures nothing and changes no settings; at the end it runs the System Check, then the main window opens. MacBook owners are reminded to plug in, and MacBook Air owners to let their Mac warm up first. Change it any time from the System Check tab or with /macever setup.
- **Known Issues**: a switch for each Mac fix, on the Mac Fixes card. A fix starts on while its problem is open on your game build and off once Blizzard has fixed it, and you can turn any of them on or off yourself (the old Unlock choices carry over). Hover a fix for what it does.
- **Reduce Green Tint**: on the Mac Fixes card and under a System Check result. The green tint is a game bug Blizzard is fixing; until then, this holds Shadow Quality at Low and Secondary Lighting at Fair, which makes it show much less.
- **By Location**: on the Presets tab, choose different settings for the open world, dungeons, raids and battlegrounds (your own settings, the System Check result, or a preset). Mac-ever switches when the loading screen ends, waits for combat to end, and puts your own settings back when you leave. Off by default. It never changes settings that restart the screen or the game window, and with the game's Raid & Battleground Settings on, it changes those in raids and battlegrounds.
- **Uncapped switch**: every frame-rate goal caps at its own frame rate (30, 45, 60, 90, 120, 144 or 165 fps). Turn on Uncapped, in setup or on the System Check tab, to make your goal a minimum instead, so your Mac runs as fast as it can. Off by default.
- 144 and 165 fps goals for high-refresh displays. Like every goal, one your Mac can't reach is still chased as far as it can go.
- CMAA 2 anti-aliasing, on Macs that support it and can afford it. Each anti-aliasing level is measured on its own, so cheap FXAA is never priced like CMAA 2.

### Changed
- **Mac Fixes follow the game build.** Each fix is tied to the build where Blizzard fixed the problem. Checked against build 70338: Blizzard has fixed the Mac problems with Secondary Lighting, Shadows, Compute Effects, Triple Buffering and the Compatibility settings. On current builds, Mac Fixes turns the four Compatibility settings back on (leaving them off costs frame rate), and the System Check measures Shadows, Secondary Lighting and Compute Effects. It skips Shadows on Fair, where buildings and terrain stop casting shadows.
- **Best Looking is now Ultra Uncapped**, which says what it is: every setting at maximum with no frame-rate cap, the most demanding setup rather than the best for every Mac. It leaves Bloom as you set it, and uses CMAA 2 only once a System Check has picked it.
- **The System Check runs cooler.** It no longer runs everything at maximum just to measure it: "Everything at maximum" is predicted from what each setting cost, and measured when that's what the check recommends. Run's tooltip says the check runs your graphics at full speed for about 2 minutes, so your Mac will get warm.
- The System Check notices when your Mac is still slowing down as it warms up (most likely on a fanless MacBook Air). It keeps the recommended settings running for up to 2 more minutes until the frame rate levels off, and tunes them again if they no longer hold your goal warm.
- **Restore Originals undoes only Mac-ever's own changes.** A setting you or another addon changed after Mac-ever is left as it is (chat says which), so Mac-ever no longer overrides other addons' graphics choices.
- **The minimap button is the standard kind** (LibDBIcon), so minimap button collectors can gather it and square or restyled minimaps place it properly. It keeps its position.
- **Cleaner pages**: each card and control keeps one short line on the page, and the details are in its tooltip. Hover the small i beside a card's name for the full description. Every button, switch and picker explains itself on hover. On the Hidden Settings page, each setting's description is one line, in full on hover.
- Pop-ups grow with the Window Size option, close with Escape (on the keep countdown, Escape switches back), and size themselves to their text. Confirmations put Cancel on the left, like Switch Back.
- Apply Recommended is green, so it's clear it's the one step that changes your settings after a System Check.
- Unapplied changes on the settings pages are labelled "Not applied", not just shown in gold.
- The Graphics Quality slider leaves Bloom as you set it. It's a matter of taste, and High can make sunsets glare.
- The Compatibility Settings note on the Standard Settings page follows your game build.
- Optional GPU Features says it takes effect after restarting the game.
- On an Intel Mac or a PC, the start-up message and /macever status say Mac-ever is made for Apple Silicon and is untested there.
- System Check results saved by v0.1.0 aren't used to tailor presets (their levels no longer match): run the check again.

### Fixed
- A reload or logout in the middle of a System Check left the check's test settings in place; they're now put back at the next login. Changes can't be made while a check runs (the check would undo them), and Reload First is off until it finishes.
- The window size menu showed 114% for 115%.
- A 30 or 45 fps System Check result was shown as Battery Saver or Quiet & Cool.
- A By Location choice for a preset that no longer exists broke every loading screen.
- One addon error could stop others from running at login.

## 0.1.0

First release, for the World of Warcraft: Forever beta on Apple Silicon Macs.

- **Mac Fixes**: applies the known fixes for Forever on Macs and keeps them in place. Each fix can be unlocked if you want to try it yourself.
- **System Check**: measures your Mac and finds the best-looking settings for the frame rate you choose (30 to 120 fps). It can also lower resolution to reach a goal, if you allow it.
- **Presets**: Best Looking, Battery Saver, Quiet & Cool, Smooth and ProMotion.
- **Picture looks**: Standard, Cinematic, Vivid, Daylight, Evening and Shadow Detail.
- **Standard and Hidden Settings**: every graphics setting the game allows, with a plain-English description of each.
- Every change gives you 15 seconds to keep it or switch back, and Restore Originals undoes everything Mac-ever has changed.
