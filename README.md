# Mac-Ever Enhanced

**This is Mac-Ever.** Mac-Ever is an addon for World of Warcraft: Forever on Apple Silicon Macs, created by **Doakus**. All rights to Mac-Ever belong to its original author. This repository is an unofficial, fan-made modified copy shared for the community, and it is not affiliated with or endorsed by the original author or by Blizzard. If the author wants it changed or removed, please open an issue and it will be taken down.

**Original Mac-Ever (please support the author):**
- CurseForge: https://www.curseforge.com/projects/1733200
- Wago.io: https://addons.wago.io/addons/QKyqxBK7 (also reachable as https://wago.io/QKyqxBK7)

## What is different in this version

My version is an enhanced build of Mac-Ever with **headroom**, which makes frame rate stable while gaming and keeps the fans quiet.

- **Headroom.** The frame rate stays locked at your goal (for example 60 fps), but graphics are only raised until your Mac could still reach goal x headroom without the cap (60 x 1.6 = about 96 fps). The GPU never runs flat out, so the Mac stays cooler, the fans stay quiet and the frame rate stays stable. Set it on the System Check tab; "Off" restores the original behaviour.
- **Keep boxes.** Every setting in the System Check table shows its fps cost and can be kept as it is; the rest is worked out around it.
- **Starting profiles per Mac.** The 60 fps preset works before any System Check, from a profile for your class of Mac (chip, Air or not, memory). A System Check replaces it with a measured result.
- **Render Scale stays between 50% and 70%**, **Shadow Quality tops out at Good**, **cheap settings (View Distance, Environment Detail, Ground Clutter) stay at maximum when they cost little fps**, **textures follow your memory**, it is suggested from your memory (Fair on 8 GB, High on 16 GB or more).
- **MacBook Air** gets more headroom by default, because it has no fan.
- **Serbian translation** (Latin script): Options > AddOns > Mac-ever > Language, or `/macever lang sr`.

See [CHANGELOG.md](CHANGELOG.md) for details. System Check reports are version 12: run the System Check again after updating.

## Install

Copy this folder into `World of Warcraft/_forever_/Interface/AddOns/` and name it `Mac-ever` (replace the original if you have it). Then `/reload` and type `/macever`.

## Status

Experimental. The starting profile values are estimates, not measurements. If something breaks, please open an issue with the output of `/macever report`.
