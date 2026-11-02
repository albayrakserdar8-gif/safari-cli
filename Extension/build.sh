#!/bin/bash
# Builds the Safari CLI Bridge app signed with the team chosen in Xcode (Signing & Capabilities)
# and installs it in ~/Applications. `--schedule` also installs a weekly job that rebuilds and
# re-signs it, since signatures from a free Apple ID expire.
set -euo pipefail
cd "$(dirname "$0")"
here="$PWD"
proj="Safari MCP Bridge/Safari MCP Bridge.xcodeproj"
team=$(grep -m1 -oE 'DEVELOPMENT_TEAM = [A-Z0-9]+' "$proj/project.pbxproj" | awk '{print $3}' || true)
if [ -z "$team" ]; then
  echo "No development team set. Open $proj in Xcode, pick your team under Signing & Capabilities for both targets, save, and rerun." >&2
  exit 1
fi

./gen.sh
dd="${TMPDIR:-/tmp}/safari-mcp-extension-build"
xcodebuild -project "$proj" -scheme "Safari MCP Bridge" -configuration Release -derivedDataPath "$dd" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic -quiet build

app="$dd/Build/Products/Release/Safari MCP Bridge.app"
dest="$HOME/Applications/Safari CLI Bridge.app"
mkdir -p "$HOME/Applications"
rm -rf "$dest.new" && ditto "$app" "$dest.new" && rm -rf "$dest" && mv "$dest.new" "$dest"
# The same app under its earlier name would register the extension twice.
old="$HOME/Applications/Safari MCP Bridge.app"
if [ -d "$old" ]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$old" || true
  mv "$old" "$HOME/.Trash/Safari MCP Bridge $(date +%s).app"
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$dest"
pluginkit -a "$dest/Contents/PlugIns/Safari MCP Bridge Extension.appex"
echo "installed $dest (team $team)"

if [ "${1:-}" = "--schedule" ]; then
  plist="$HOME/Library/LaunchAgents/com.sadopc.safari-mcp.resign.plist"
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.sadopc.safari-mcp.resign</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$here/build.sh</string></array>
  <key>StartCalendarInterval</key><dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>11</integer><key>Minute</key><integer>0</integer></dict>
  <key>RunAtLoad</key><false/>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/safari-mcp-resign.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/safari-mcp-resign.log</string>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)/com.sadopc.safari-mcp.resign" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  echo "weekly re-signing scheduled (Mondays 11:00); log: ~/Library/Logs/safari-mcp-resign.log"
fi
