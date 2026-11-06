#!/bin/zsh
# Build wow-span and install a LaunchAgent that runs it whenever World of Warcraft is running.
set -e
dir=${0:A:h}
"$dir/build.sh"
plist=~/Library/LaunchAgents/wow-span.plist
cat > $plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>wow-span</string>
  <key>ProgramArguments</key><array><string>/bin/zsh</string><string>$dir/wow-span-watch.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
PLIST
launchctl bootout gui/$(id -u)/wow-span 2>/dev/null || true
launchctl bootstrap gui/$(id -u) $plist
echo "Installed. wow-span will start with WoW. Allow Screen Recording + Accessibility for wow-span when asked."
