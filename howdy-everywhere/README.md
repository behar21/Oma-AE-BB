# howdy-everywhere

Erweitert die **Howdy**-Gesichtserkennung (die Linux-Variante von „Windows
Hello") auf fast alle Stellen, an denen sonst ein Passwort nötig wäre — inklusive
**Sperrbildschirm mit automatischer Kamera-Entsperrung**. Kein Skript tippt
Passwörter; überall wird dieselbe Face-Auth wie bei `sudo` über PAM genutzt.

## Was abgedeckt ist

| Szenario | Mechanismus | Woher |
|----------|-------------|-------|
| `sudo` im Terminal | `/etc/pam.d/sudo` → `pam_exec` → `howdy-pam-exec` | war schon aktiv |
| **Sperrbildschirm** (omarchy-shell lock) | Lock-Plugin-Klon + `/etc/pam.d/omarchy-lock-fingerprint` | dieses Paket |
| **polkit / pkexec** (GUI-Dialoge) | `/etc/pam.d/polkit-1` | dieses Paket |
| **`su`** | `/etc/pam.d/su` | dieses Paket |
| Bar-Icon (Status) rechts neben dem Akku | Omarchy-Plugin `howdy.faceunlock` | dieses Paket |

Der Boot-/Login-Bildschirm (SDDM) bleibt bewusst beim Passwort.

## Wie der Sperrbildschirm funktioniert (wichtig)

Aktuelles Omarchy sperrt **nicht mehr mit hyprlock**, sondern mit dem eigenen
Quickshell-Lockscreen (`omarchy-shell lock`). Dieser hat einen biometrischen
Auto-Auth-Pfad (`PamContext config: "omarchy-lock-fingerprint"`), der per Default
aber **nur fprintd/Fingerabdruck** freischaltet.

Dieses Paket:
1. **klont** das Lock-Plugin (`omarchy plugin clone omarchy.lock` → `<user>.lock`)
   und entfernt im Klon die fprintd-Bedingung, sodass der biometrische Pfad
   greift, sobald die Howdy-PAM-Datei existiert;
2. legt `/etc/pam.d/omarchy-lock-fingerprint` mit `pam_exec → howdy-pam-exec` an.

Ergebnis: Der Sperrbildschirm pollt im Hintergrund die Kamera und entsperrt bei
Gesichtstreffer automatisch. Das Passwortfeld bleibt als Fallback erhalten.

> Ein früherer `howdy-lock-watcher` (für hyprlock, per SIGUSR1) wird von diesem
> Paket **entfernt** — er funktioniert mit dem neuen Lockscreen nicht.

## Sicherheitsprinzip

Jede PAM-Zeile ist `auth sufficient`. Schlägt die Erkennung fehl oder ist die
Kamera belegt, fällt PAM auf die normale Passwortabfrage zurück — **ein
Aussperren ist ausgeschlossen**.

## Bar-Icon

Nerd-Font-Glyph „face-recognition"; **normale Farbe** = Sperrbildschirm-Face
aktiv, **rot** = nicht aktiv. **Klick** = Benachrichtigung mit Abdeckung.
Glyph änderbar in `~/.config/omarchy/shell.json`:
`{ "id": "howdy.faceunlock", "icon": "󰈺" }`.

## Installation / Deinstallation

```bash
~/.local/share/howdy-everywhere/install.sh      # als normaler Benutzer!
~/.local/share/howdy-everywhere/uninstall.sh
```

Userspace-Teil (Lock-Klon, Bar-Icon) läuft direkt; der PAM-Teil wird per
`pkexec` eskaliert (einmal Passwort). Idempotent, Backups `*.bak.howdy-everywhere.*`.

## Paketinhalt

```
install.sh / uninstall.sh      Einstieg (User)
pam-setup.sh                   privilegierter PAM-Teil (root, via pkexec)
omarchy-plugin/howdy.faceunlock/   Bar-Icon (manifest.json + BarWidget.qml)
bin/howdy-pam-exec             PAM-Shim (portabel mitgeliefert)
```

## Voraussetzungen (auch beim Kollegen)

- Arch/Omarchy (Quickshell-Shell, `omarchy plugin` verfügbar)
- **Howdy eingerichtet und angelernt** (`sudo howdy add`, Test: `sudo howdy test`)
  — dieses Paket richtet die Kamera/Modelle NICHT selbst ein
- die NOPASSWD-sudoers-Regel für `compare.py` (legt Howdy an)
- `jq`, `notify-send`

## Test

`Ctrl+Super+L` drücken und in die Kamera schauen → sollte automatisch entsperren.
Wenn nicht: Passwort tippen (Fallback), dann `sudo howdy test` prüfen.
