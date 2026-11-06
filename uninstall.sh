#!/bin/zsh
# Remove the LaunchAgent and stop wow-span. The repo folder is left alone.
launchctl bootout gui/$(id -u)/wow-span 2>/dev/null
rm -f ~/Library/LaunchAgents/wow-span.plist
pkill -x wow-span
echo "Uninstalled."
