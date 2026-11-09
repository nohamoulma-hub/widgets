#!/bin/bash
# Retire les deux tâches de fond installées par install_agents.sh.
# Les fichiers du projet et les données ne sont pas touchés.
set -euo pipefail

DOMAIN="gui/$(id -u)"
for label in com.noham.deskwidgets.collector com.noham.deskwidgets.app; do
  launchctl bootout "$DOMAIN/$label" 2>/dev/null || true
  echo "Arrêté: $label"
done
echo "Les fichiers .plist restent dans ~/Library/LaunchAgents: tu peux les supprimer à la main."
