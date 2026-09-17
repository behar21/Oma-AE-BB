#!/usr/bin/env bash
# howdy-everywhere — privileged PAM part (root).
# Usage: pam-setup.sh install | uninstall
# Self-elevates via pkexec when not run as root, so it also works standalone.

set -euo pipefail

MARK='howdy-everywhere'
PAM_EXEC='/usr/local/bin/howdy-pam-exec'
HOWDY_LINE="auth       sufficient   pam_exec.so quiet ${PAM_EXEC}  # ${MARK}"
STAMP="$(date +%Y%m%d-%H%M%S)"
SERVICES=(polkit-1 su)                          # "auth sufficient" davor einfuegen
LOCK_PAM='/etc/pam.d/omarchy-lock-fingerprint'  # eigene managed-Datei (Sperrbildschirm)
DIR="$(cd "$(dirname "$0")" && pwd)"
ACTION="${1:-install}"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[31mFehler:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] && exec pkexec "$0" "$ACTION"

backup() { [ -e "$1" ] && cp -a "$1" "${1}.bak.${MARK}.${STAMP}" && printf '  Backup: %s\n' "${1}.bak.${MARK}.${STAMP}" || true; }

insert_before_first_auth() {
  local f="$1" tmp; tmp="$(mktemp)"
  awk -v line="$HOWDY_LINE" '!ins && $1=="auth"{print line; ins=1} {print} END{if(!ins) print line}' "$f" > "$tmp"
  install -m 0644 -o root -g root "$tmp" "$f"; rm -f "$tmp"
}
strip_marker() {
  local f="$1" tmp; [ -e "$f" ] || return 0; tmp="$(mktemp)"
  grep -v "# ${MARK}\$" "$f" > "$tmp" || true
  install -m 0644 -o root -g root "$tmp" "$f"; rm -f "$tmp"
}

install_pam_exec() {
  if [ ! -x "$PAM_EXEC" ]; then
    if [ -f "$DIR/bin/howdy-pam-exec" ]; then install -m 0755 "$DIR/bin/howdy-pam-exec" "$PAM_EXEC"
    else
      cat > "$PAM_EXEC" <<'SHIM'
#!/bin/sh
[ -n "$PAM_USER" ] || exit 1
if [ "$(id -u)" -eq 0 ]; then
  exec /usr/bin/python3 /usr/lib/security/howdy/compare.py "$PAM_USER"
else
  exec /usr/bin/sudo -n /usr/bin/python3 /usr/lib/security/howdy/compare.py "$PAM_USER"
fi
SHIM
      chmod 0755 "$PAM_EXEC"
    fi
    ok "$PAM_EXEC angelegt."
  else ok "$PAM_EXEC vorhanden."; fi
}

setup_lock_fingerprint() {
  # Der Omarchy-Sperrbildschirm nutzt PamContext config "omarchy-lock-fingerprint"
  # als biometrischen Auto-Auth-Pfad. Wir belegen ihn mit Howdy (Gesicht).
  if [ -e "$LOCK_PAM" ] && grep -q "$MARK" "$LOCK_PAM"; then ok "omarchy-lock-fingerprint: bereits konfiguriert."; return; fi
  [ -e "$LOCK_PAM" ] && backup "$LOCK_PAM"
  cat > "$LOCK_PAM" <<EOF
#%PAM-1.0
# ${MARK}: managed file
${HOWDY_LINE}
auth       required     pam_deny.so
account    required     pam_permit.so
EOF
  chmod 0644 "$LOCK_PAM"
  ok "omarchy-lock-fingerprint: Howdy-PAM angelegt (Sperrbildschirm)."
}

do_install() {
  echo "PAM-Setup: install ($STAMP)"
  install_pam_exec
  for svc in "${SERVICES[@]}"; do
    local target="/etc/pam.d/${svc}"
    case "$svc" in
      polkit-1)
        if [ -e "$target" ] && grep -q "$MARK" "$target"; then ok "polkit-1: bereits konfiguriert."; continue; fi
        if [ ! -e "$target" ]; then
          local vendor=/usr/lib/pam.d/polkit-1 tmp; [ -e "$vendor" ] || die "$vendor fehlt."
          tmp="$(mktemp)"; { echo "#%PAM-1.0"; echo "# ${MARK}: managed file"; echo "$HOWDY_LINE"; sed '/^#%PAM-1.0/d' "$vendor"; } > "$tmp"
          install -m 0644 -o root -g root "$tmp" "$target"; rm -f "$tmp"; ok "polkit-1: /etc-Override angelegt."
        else backup "$target"; insert_before_first_auth "$target"; ok "polkit-1: Howdy-Zeile ergaenzt."; fi ;;
      *)
        [ -e "$target" ] || { warn "$svc: $target fehlt — uebersprungen."; continue; }
        if grep -q "$MARK" "$target"; then ok "$svc: bereits konfiguriert."; continue; fi
        backup "$target"; insert_before_first_auth "$target"; ok "$svc: Howdy-Zeile ergaenzt." ;;
    esac
  done
  setup_lock_fingerprint
  ok "PAM fertig (Sperrbildschirm + polkit/pkexec + su)."
}

do_uninstall() {
  echo "PAM-Setup: uninstall"
  for svc in "${SERVICES[@]}"; do
    local target="/etc/pam.d/${svc}"
    [ -e "$target" ] || { warn "$svc: nicht vorhanden."; continue; }
    grep -q "$MARK" "$target" || { warn "$svc: keine Spuren."; continue; }
    if grep -q "${MARK}: managed file" "$target"; then rm -f "$target"; ok "$svc: /etc-Override entfernt (Vendor-Default aktiv)."
    else strip_marker "$target"; ok "$svc: Howdy-Zeile entfernt."; fi
  done
  if [ -e "$LOCK_PAM" ] && grep -q "$MARK" "$LOCK_PAM"; then rm -f "$LOCK_PAM"; ok "omarchy-lock-fingerprint entfernt."; fi
  ok "PAM zurueckgesetzt. Backups (*.bak.${MARK}.*) bleiben in /etc/pam.d/."
}

case "$ACTION" in
  install)   do_install ;;
  uninstall) do_uninstall ;;
  *) die "unbekannte Aktion: $ACTION (install|uninstall)";;
esac
