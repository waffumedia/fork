#!/bin/zsh
# Keep Fork always on: the API server (port 3300, behind Tailscale Funnel) and the Mac worker
# (downloads Grokbot picks, tags scenes) start at login and restart if they crash.
# Undo: launchctl bootout gui/$(id -u)/com.waffu.fork.server ; same for .worker ; rm ~/Library/LaunchAgents/com.waffu.fork.*
set -e
DIR=/Users/waffu/Claude/fork
NPM=$(command -v npm); NODEDIR=$(dirname $(command -v node))
mkdir -p "$DIR/logs" ~/Library/LaunchAgents
for name in server worker; do
  if [ $name = server ]; then ARGS="<string>$NPM</string><string>start</string>"; else ARGS="<string>/usr/bin/python3</string><string>pipeline/worker.py</string><string>--loop</string>"; fi
  P=~/Library/LaunchAgents/com.waffu.fork.$name.plist
  cat > $P <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.waffu.fork.$name</string>
  <key>ProgramArguments</key><array>$ARGS</array>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$NODEDIR:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$DIR/logs/$name.log</string>
  <key>StandardErrorPath</key><string>$DIR/logs/$name.log</string>
</dict></plist>
EOF
  launchctl bootout gui/$(id -u)/com.waffu.fork.$name 2>/dev/null || true
  launchctl bootstrap gui/$(id -u) $P
done
launchctl list | grep com.waffu.fork
