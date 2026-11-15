#!/bin/zsh
# Remove the LaunchAgent and stop wow-span. The repo folder is left alone.
launchctl bootout gui/$(id -u)/com.scottlandes.wow-span 2>/dev/null
rm -f ~/Library/LaunchAgents/com.scottlandes.wow-span.plist
pkill -x wow-span
echo "Uninstalled."
