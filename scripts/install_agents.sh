#!/bin/bash
# Installe deux tâches de fond pour ton compte:
#  1. le collecteur, relancé toutes les 15 minutes
#  2. le widget, lancé à l'ouverture de session
# Retrait complet: scripts/uninstall_agents.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/DeskWidgets.app/Contents/MacOS/DeskWidgets"
AGENTS="$HOME/Library/LaunchAgents"
DOMAIN="gui/$(id -u)"

if [ ! -x "$APP" ]; then
  echo "Le widget n'est pas encore compilé. Lance d'abord: scripts/build_app.sh" >&2
  exit 1
fi
mkdir -p "$AGENTS"

# Écrit un fichier de tâche de fond (nom, programme et arguments, options)
write_agent() {
  local label="$1" extra="$2"
  shift 2
  local file="$AGENTS/$label.plist"
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0"><dict>'
    echo "<key>Label</key><string>$label</string>"
    echo '<key>ProgramArguments</key><array>'
    for arg in "$@"; do echo "<string>$arg</string>"; done
    echo '</array>'
    echo '<key>RunAtLoad</key><true/>'
    echo "$extra"
    echo '</dict></plist>'
  } > "$file"
  # On décharge l'ancienne version si elle existe (l'erreur "pas chargée" est normale)
  launchctl bootout "$DOMAIN/$label" 2>/dev/null || true
  launchctl bootstrap "$DOMAIN" "$file"
  echo "Installé: $label"
}

write_agent "com.noham.deskwidgets.collector" \
  '<key>StartInterval</key><integer>900</integer>' \
  /usr/bin/python3 "$ROOT/collector/collect_projects.py"

write_agent "com.noham.deskwidgets.app" \
  '<key>LimitLoadToSessionType</key><string>Aqua</string>' \
  "$APP"
