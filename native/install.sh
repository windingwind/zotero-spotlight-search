#!/bin/bash
# install.sh — Build and install ZotLight
set -e

APP_INSTALL="/Applications"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
AGENT_LABEL="com.zotlight.app"
AGENT_PLIST="$LAUNCH_AGENTS/$AGENT_LABEL.plist"

echo "=== ZotLight Installer ==="
echo ""

# 1. Build app bundle
echo "[1/2] Building ZotLight.app..."
bash build.sh
echo "  ✓ App built"

# 2. Install app + LaunchAgent
echo "[2/2] Installing ZotLight.app and LaunchAgent..."

# Install app to /Applications
if [ -w "$APP_INSTALL" ]; then
    rm -rf "$APP_INSTALL/ZotLight.app"
    cp -R dist/ZotLight.app "$APP_INSTALL/"
else
    sudo rm -rf "$APP_INSTALL/ZotLight.app"
    sudo cp -R dist/ZotLight.app "$APP_INSTALL/"
fi
echo "  ✓ ZotLight.app installed to $APP_INSTALL"

# Install LaunchAgent
mkdir -p "$LAUNCH_AGENTS"
launchctl unload "$AGENT_PLIST" 2>/dev/null || true

cat > "$AGENT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_INSTALL/ZotLight.app/Contents/MacOS/ZotLight</string>
        <string>--sync</string>
    </array>
    <key>StartInterval</key>
    <integer>600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/ZotLight.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ZotLight.err</string>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF

launchctl load "$AGENT_PLIST"
echo "  ✓ LaunchAgent installed and loaded (runs every 10 min)"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Spotlight indexing started in background."
echo "Wait ~30s then try Cmd+Space and search for a paper title."
echo ""
echo "To open settings: click ZotLight.app in Finder/Applications"
echo ""
echo "To clear Spotlight index:"
echo "  /Applications/ZotLight.app/Contents/MacOS/ZotLight --clear"
echo ""
echo "To uninstall:"
echo "  launchctl unload $AGENT_PLIST"
echo "  rm $AGENT_PLIST"
echo "  sudo rm -rf $APP_INSTALL/ZotLight.app"
