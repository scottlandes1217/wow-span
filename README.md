# wow-span

Play World of Warcraft across **two monitors on a Mac** — so the
[Offhand](https://www.curseforge.com/wow/addons/offhand) addon can put your map, bags and chat on
the second screen while the game stays on the first.

The Mac WoW client refuses to make its window bigger than one display, and macOS has no "span
displays" mode. wow-span works around both without touching the game:

1. It creates a **virtual display** as wide as your monitors combined (e.g. 2528×1080).
2. WoW runs on that display, so WoW and Offhand see one wide monitor.
3. It **mirrors** each slice of that display onto your real monitors in real time, hiding WoW's
   title bar, keeping the mouse inside the game, and stepping aside for Cmd-Tab and Mission Control.

It starts automatically when WoW launches (including from Battle.net) and stops when WoW quits.

> Uses the private `CGVirtualDisplay` API (the same one DeskPad and BetterDisplay use), so a macOS
> update could break it. It never modifies or injects into the WoW client — it only captures the
> screen. Not affiliated with Blizzard or the Offhand author.

## Requirements

- macOS on Apple silicon (tested on macOS 27, M5 Pro) with two monitors
- Xcode or the Command Line Tools (`xcode-select --install`) for `swiftc`
- Offhand installed in WoW

## Install

```sh
git clone https://github.com/<you>/wow-span.git ~/wow-span
~/wow-span/install.sh
```

Then launch WoW. The first time, macOS asks to allow **wow-span** for **Screen Recording** and
**Accessibility** — allow both, then quit WoW and launch it again.

## Set up WoW and Offhand (once)

Your monitors are laid out left→right in the order of System Settings → Displays. The biggest
monitor is shown 1:1 and should be your game screen (Offhand's "Mainhand"); the others are scaled
to its height. The helper's virtual display is called **WoW Span**.

1. In WoW: **Options → Graphics → Monitor: WoW Span**, **Display Mode: Windowed**.
   (Offhand requires Windowed; wow-span hides the title bar for you.)
2. Quit and relaunch WoW so it picks up the new monitor size.
3. Run `/offhand wizard`, choose the manual setup, and set:
   - **Mainhand**: the side your game screen is on
   - **Seam**: game-screen width ÷ total width. Total width = sum over monitors of
     `width × gameScreenHeight ÷ height`. Example: 1920×1080 + portrait 900×1600 →
     1920 + 608 = 2528, seam = 1920 ÷ 2528 = **75.9%**.
4. Finish with **Create Mainhand HUD Layout** and reload.

**If you change your monitors** (rotate one, change resolution, rearrange), the virtual display
changes size: quit WoW, relaunch, and run the Offhand wizard again.

## Options

- The LaunchAgent runs `wow-span --retina`: a 2× (HiDPI) virtual display, sharp on 4K screens but
  heavier on the GPU. Edit `wow-span-watch.sh` and drop `--retina` for a lighter 1× display.
- `refreshRate` at the top of `main.swift` (default 60).
- Run it by hand instead of the LaunchAgent: `./wow-span --retina` (Ctrl-C to stop).

## Troubleshooting

- **Screens look wrong / stuck:** Cmd-Tab out of WoW, or quit WoW (wow-span stops with it).
- **Monitors left mirrored after a crash:** run `./unmirror`.
- **Permission prompts keep coming back:** in Privacy & Security, remove `wow-span` from Screen
  Recording and Accessibility, then launch WoW and allow again. Rebuilding with an ad-hoc signature
  (no Apple Development certificate) needs this every time.
- **WoW opened on one screen:** it launched before the virtual display was ready — relaunch it.
- Log: `run.log` in this folder.

## Uninstall

```sh
~/wow-span/uninstall.sh
```
