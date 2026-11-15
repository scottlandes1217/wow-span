#!/bin/zsh
# Run by the LaunchAgent (see install.sh): keeps `wow-span --retina` running exactly while WoW is running
# with Offhand on. With Offhand off (/offhand toggle, saved when WoW quits) WoW runs on a normal screen.
dir=${0:A:h}
wow() { pgrep -qx 'World of Warcraft' }
# Offhand's account-wide on/off switch, as WoW last saved it
offhand_on() { ! grep -qs '^\["enabled"\] = false' "$wtf"/Account/*/SavedVariables/Offhand.lua }
# WoW saves its window size on quit and it drifts (resizes, macOS clamping), but Offhand only
# recognizes a canvas of the exact pixel size it was set up on. Pin it back to the biggest window
# that fits the span under the title bar, in pixels (--retina = 2x): 2528x1080 -> 4924x2104.
titlebar=28                # calibration knob: WoW's title bar height in points
normal_window=3406x1790    # WoW's window size with Offhand off (your setting before wow-span)
set_window() { sed -i '' "s/^SET GxWindowedResolution .*/SET GxWindowedResolution \"$1\"/" "$wtf/Config.wtf" }
pin_window() {
  if ! offhand_on; then set_window $normal_window; return; fi
  local size=$(grep -o '[0-9]*x[0-9]* is live' "$dir/run.log" | tail -1 | cut -d' ' -f1)
  [[ -n $size ]] || return
  local W=${size%x*} H=${size#*x}
  local h=$(( (H - titlebar) * 2 ))
  set_window "$(( h * W / H ))x$h"
}
while true; do
  if wow; then
    wtf=$(ps -o command= -p $(pgrep -x 'World of Warcraft' | head -1) | sed -E 's|^(.*)/World of Warcraft\.app/.*|\1|')/WTF
    if offhand_on; then
      "$dir/wow-span" --retina >> "$dir/run.log" 2>&1 &
      hp=$!
      while kill -0 $hp 2>/dev/null && wow; do sleep 0.5; done
      kill $hp 2>/dev/null; wait $hp 2>/dev/null
    else
      while wow; do sleep 0.5; done
    fi
    [[ -f $wtf/Config.wtf ]] && ! wow && pin_window
    # Helper died while WoW still runs (e.g. permission not granted yet): don't thrash the displays.
    wow && sleep 30
  fi
  sleep 0.5
done
