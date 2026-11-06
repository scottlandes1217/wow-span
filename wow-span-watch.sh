#!/bin/zsh
# Run by the LaunchAgent (see install.sh): keeps `wow-span --retina` running exactly while WoW is running.
dir=${0:A:h}
wow() { pgrep -qf 'World of Warcraft.app/Contents/MacOS/World of Warcraft' }
while true; do
  if wow; then
    "$dir/wow-span" --retina >> "$dir/run.log" 2>&1 &
    hp=$!
    while kill -0 $hp 2>/dev/null && wow; do sleep 0.5; done
    kill $hp 2>/dev/null; wait $hp 2>/dev/null
    # Helper died while WoW still runs (e.g. permission not granted yet): don't thrash the displays.
    wow && sleep 30
  fi
  sleep 0.5
done
