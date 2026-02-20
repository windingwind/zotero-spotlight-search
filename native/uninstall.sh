#!/bin/bash
# uninstall.sh — Uninstall ZotLight
set -e

APP_INSTALL="/Applications"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
AGENT_LABEL="com.zotlight.app"
AGENT_PLIST="$LAUNCH_AGENTS/$AGENT_LABEL.plist"

echo "=== ZotLight Uninstaller ==="
echo ""

# 1. Unload and remove LaunchAgent
echo "[1/2] Removing LaunchAgent..."
launchctl unload "$AGENT_PLIST" 2>/dev/null || true
rm -f "$AGENT_PLIST"
echo "  ✓ LaunchAgent removed"

# 2. Remove app
echo "[2/2] Removing ZotLight.app..."
if [ -w "$APP_INSTALL" ]; then
    rm -rf "$APP_INSTALL/ZotLight.app"
else
    sudo rm -rf "$APP_INSTALL/ZotLight.app"
fi
echo "  ✓ ZotLight.app removed"

echo ""
echo "=== Uninstall Complete ==="
