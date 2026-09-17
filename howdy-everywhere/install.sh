#!/usr/bin/env bash
# howdy-everywhere — Installer (als NORMALER Benutzer starten, nicht mit sudo).
#
# Richtet Howdy-Gesichtsentsperrung dauerhaft ein:
#   * Sperrbildschirm (omarchy-shell lock): Klon des Lock-Plugins + Howdy-PAM
#     -> der Sperrbildschirm entsperrt automatisch per Kamera
#   * PAM: polkit/pkexec + su                 -> per pkexec (einmal Passwort)
#   * Omarchy-Bar-Icon rechts neben dem Akku  -> Status
#
# sudo (Terminal) war bereits eingerichtet und bleibt erhalten.
# Idempotent und via ./uninstall.sh umkehrbar. Passwort bleibt ueberall Fallback.

set -euo pipefail

MARK='howdy-everywhere'
DIR="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
PLUGIN_ID='howdy.faceunlock'
LOCK_PAM='/etc/pam.d/omarchy-lock-fingerprint'

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[31mFehler:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] && die "Bitte als normaler Benutzer starten (NICHT root/sudo)."
command -v omarchy >/dev/null 2>&1 || warn "omarchy-CLI nicht gefunden — Sperrbildschirm/Bar werden ggf. uebersprungen."

echo "howdy-everywhere — Installation ($STAMP)"

# --- 1) Sperrbildschirm: Lock-Plugin klonen + Fingerprint-Gate auf Howdy -----
# Der Omarchy-Sperrbildschirm hat einen biometrischen Auto-Auth-Pfad, der aber
# per Default nur fprintd/Fingerabdruck freischaltet. Wir klonen das Lock-Plugin
# und entfernen die fprintd-Bedingung, sodass der Pfad greift, sobald die
# Howdy-PAM-Datei existiert (siehe Schritt 3).
if command -v omarchy >/dev/null 2>&1; then
  clonedir="$(ls -d "$HOME"/.config/omarchy/plugins/*.lock 2>/dev/null | head -1 || true)"
  if [ -z "$clonedir" ]; then
    omarchy plugin clone omarchy.lock >/dev/null 2>&1 || warn "Klon von omarchy.lock fehlgeschlagen."
    clonedir="$(ls -d "$HOME"/.config/omarchy/plugins/*.lock 2>/dev/null | head -1 || true)"
  fi
  if [ -n "$clonedir" ] && [ -f "$clonedir/Service.qml" ]; then
    svc="$clonedir/Service.qml"
    if grep -q "fprintd-list" "$svc"; then
      cp -a "$svc" "$svc.bak.${MARK}.${STAMP}"
      sed -i -E 's#&& command -v fprintd-list[^;]*grep -qi finger##' "$svc"
      ok "Lock-Plugin geklont & gepatcht ($(basename "$clonedir")) — Kamera statt Fingerabdruck."
    else
      ok "Lock-Plugin bereits gepatcht ($(basename "$clonedir"))."
    fi
  else
    warn "Lock-Clone nicht gefunden — Sperrbildschirm uebersprungen."
  fi
fi

# --- 2) Omarchy-Bar-Icon (rechts neben dem Akku) ----------------------------
PLUGINS="$HOME/.config/omarchy/plugins"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
if [ -d "$PLUGINS" ] && [ -f "$SHELL_JSON" ]; then
  rm -rf "${PLUGINS:?}/${PLUGIN_ID}"
  cp -a "$DIR/omarchy-plugin/${PLUGIN_ID}" "$PLUGINS/${PLUGIN_ID}"
  cp -a "$SHELL_JSON" "${SHELL_JSON}.bak.${MARK}.${STAMP}"
  tmp="$(mktemp)"
  jq --arg id "$PLUGIN_ID" '.bar.layout.right |= (if any(.[]; .id==$id) then . else . + [{"id":$id}] end)' "$SHELL_JSON" > "$tmp" && mv "$tmp" "$SHELL_JSON"
  ok "Bar-Icon installiert & rechts neben dem Akku eingetragen."
else
  warn "Omarchy-Shell nicht gefunden — Bar-Icon uebersprungen."
fi

# --- 3) PAM (root, via pkexec) — Sperrbildschirm + polkit + su --------------
need_pam=0
grep -q "$MARK" "$LOCK_PAM" 2>/dev/null || need_pam=1
grep -q "$MARK" /etc/pam.d/polkit-1 2>/dev/null || need_pam=1
grep -q "$MARK" /etc/pam.d/su 2>/dev/null || need_pam=1
if [ "$need_pam" -eq 1 ]; then
  echo "  PAM wird eingerichtet — bitte im Dialog authentifizieren ..."
  pkexec "$DIR/pam-setup.sh" install
else
  ok "PAM bereits konfiguriert."
fi

# --- 4) Shell neu starten, damit Lock-Clone + Bar-Icon geladen werden -------
command -v omarchy >/dev/null 2>&1 && omarchy restart shell >/dev/null 2>&1 && ok "omarchy-shell neu gestartet." || warn "Bitte 'omarchy restart shell' ausfuehren."

echo
ok "Fertig."
echo "  Test:  Bildschirm mit Ctrl+Super+L sperren und in die Kamera schauen"
echo "         (klappt nicht? -> Passwort tippen, dann 'sudo howdy test' pruefen)"
echo "  Zurueck:  $DIR/uninstall.sh"
