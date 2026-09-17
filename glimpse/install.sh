#!/usr/bin/env bash
#
# install.sh — installiert das Glimpse-Plugin (bullaku.glimpse) für die
# Omarchy-Shell. Einfach aus dem entpackten Archiv heraus ausführen:
#
#   ./install.sh
#
# Autostart ist nicht nötig: Die Omarchy-Shell lädt alles unter
# ~/.config/omarchy/plugins/ automatisch, und das Plugin ist mit
# "keepLoaded": true markiert — Ordner an Ort und Stelle heißt: läuft immer.
#
# Das Skript ist idempotent: erneutes Ausführen aktualisiert das Plugin,
# hängt die Bindings aber nicht doppelt an und überschreibt eine vorhandene
# Hotkey-Konfiguration nicht.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ID="bullaku.glimpse"
PLUGIN_DIR="$HOME/.config/omarchy/plugins"
BINDINGS="$HOME/.config/hypr/bindings.lua"
MARKER="Glimpse-Plugin (bullaku.glimpse)"

log() { printf '[INFO]  %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ -d "$SRC_DIR/$PLUGIN_ID" ]]            || die "Ordner '$PLUGIN_ID' nicht gefunden — Skript aus dem entpackten Archiv heraus starten."
[[ -f "$SRC_DIR/glimpse.json" ]]          || die "glimpse.json fehlt im Archiv."
[[ -f "$SRC_DIR/bindings-glimpse.lua" ]]  || die "bindings-glimpse.lua fehlt im Archiv."
[[ -f "$BINDINGS" ]]                      || die "$BINDINGS nicht gefunden — läuft hier wirklich Omarchy?"

# 1. Plugin-Ordner kopieren (vorhandene Version wird ersetzt = Update)
log "Kopiere Plugin nach $PLUGIN_DIR/$PLUGIN_ID ..."
mkdir -p "$PLUGIN_DIR"
rm -rf "$PLUGIN_DIR/$PLUGIN_ID"
cp -r "$SRC_DIR/$PLUGIN_ID" "$PLUGIN_DIR/"

# 2. Hotkey-Konfiguration kopieren (eigene Anpassungen bleiben erhalten)
if [[ -f "$HOME/.config/omarchy/glimpse.json" ]]; then
  log "~/.config/omarchy/glimpse.json existiert schon — bleibt unverändert."
else
  log "Kopiere Hotkey-Konfiguration nach ~/.config/omarchy/glimpse.json ..."
  cp "$SRC_DIR/glimpse.json" "$HOME/.config/omarchy/"
fi

# 3. Bindings anhängen — nur, wenn der Block noch nicht drin ist
if grep -qF "$MARKER" "$BINDINGS"; then
  log "Bindings-Block ist bereits in $BINDINGS — überspringe."
else
  log "Sichere $BINDINGS und hänge den Glimpse-Bindings-Block an ..."
  cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
  { echo; cat "$SRC_DIR/bindings-glimpse.lua"; } >> "$BINDINGS"
fi

# 4. Shell neu starten (QML-Cache!) und Hyprland-Config neu laden
log "Starte Omarchy-Shell neu (nötig wegen QML-Cache) ..."
omarchy restart shell
log "Lade Hyprland-Konfiguration neu ..."
hyprctl reload

echo
log "Fertig! Hotkeys: CTRL+GRAVE = Workspace-Übersicht, F7 = Fenstersuche."
log "Hotkeys ändern: ~/.config/omarchy/glimpse.json anpassen, dann 'hyprctl reload'."
