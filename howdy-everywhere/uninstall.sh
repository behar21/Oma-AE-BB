#!/usr/bin/env bash
# howdy-everywhere — Deinstallation (als normaler Benutzer starten).
# Entfernt Bar-Icon, PAM-Zeilen und setzt das Lock-Plugin auf das Original
# zurueck. Passwort-Login bleibt ueberall unberuehrt.

set -euo pipefail

MARK='howdy-everywhere'
DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ID='howdy.faceunlock'

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] && { echo "Bitte als normaler Benutzer starten."; exit 1; }

echo "howdy-everywhere — Deinstallation"

# 1) Lock-Plugin-Klon entfernen, Original reaktivieren
if command -v omarchy >/dev/null 2>&1; then
  clonedir="$(ls -d "$HOME"/.config/omarchy/plugins/*.lock 2>/dev/null | head -1 || true)"
  if [ -n "$clonedir" ]; then
    cid="$(basename "$clonedir")"
    omarchy plugin enable omarchy.lock >/dev/null 2>&1 || true
    omarchy plugin remove "$cid" --yes >/dev/null 2>&1 || rm -rf "$clonedir"
    ok "Lock-Plugin-Klon entfernt, omarchy.lock reaktiviert."
  fi
fi

# 2) Bar-Icon entfernen
PLUGINS="$HOME/.config/omarchy/plugins"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
[ -d "${PLUGINS}/${PLUGIN_ID}" ] && rm -rf "${PLUGINS:?}/${PLUGIN_ID}" && ok "Bar-Plugin entfernt."
if [ -f "$SHELL_JSON" ] && jq -e --arg id "$PLUGIN_ID" 'any(.bar.layout.right[]?; .id==$id)' "$SHELL_JSON" >/dev/null 2>&1; then
  tmp="$(mktemp)"; jq --arg id "$PLUGIN_ID" '.bar.layout.right |= map(select(.id != $id))' "$SHELL_JSON" > "$tmp" && mv "$tmp" "$SHELL_JSON"
  ok "Bar-Layout bereinigt."
fi

# 3) PAM zuruecksetzen (root)
echo "  PAM wird zurueckgesetzt — bitte im Dialog authentifizieren ..."
pkexec "$DIR/pam-setup.sh" uninstall

command -v omarchy >/dev/null 2>&1 && omarchy restart shell >/dev/null 2>&1 || true
echo
ok "Fertig. sudo (falls vorher da) ist unberuehrt geblieben."
