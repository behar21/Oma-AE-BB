# Oma-AE-BB — Omarchy-Plugins

Selbstgebaute Plugins und Erweiterungen für [Omarchy](https://omarchy.org)
(Arch + Hyprland + Omarchy-Shell/Quickshell). Jedes Plugin liegt in einem
eigenen Ordner mit ausführlicher README und Installationsskript.

## Inhalt

| Ordner | Plugin | Beschreibung |
|---|---|---|
| [`glimpse/`](glimpse/) | `bullaku.glimpse` | Task-View aller belegten Workspaces mit **Live-Fenstervorschauen** (à la SUPER+Tab unter Windows) und Fenstersuche. Hotkeys: `CTRL+GRAVE` / `F7`, optionales Bar-Icon. |
| [`howdy-everywhere/`](howdy-everywhere/) | `howdy.faceunlock` + PAM-Setup | Erweitert die **Howdy**-Gesichtserkennung („Windows Hello" für Linux) auf Sperrbildschirm (automatische Kamera-Entsperrung), polkit/pkexec und `su` — plus Status-Icon in der Bar. |

## Installation

In den jeweiligen Plugin-Ordner wechseln und die dortige README lesen —
beide bringen ein idempotentes `install.sh` mit:

```bash
cd glimpse && ./install.sh
cd howdy-everywhere && ./install.sh   # Howdy muss vorher eingerichtet sein
```

## Voraussetzungen

- Omarchy mit Omarchy-Shell (Quickshell) unter Hyprland
- Für `howdy-everywhere`: eingerichtetes und angelerntes Howdy
  (`sudo howdy add`, Test mit `sudo howdy test`)

## Allgemeine Hinweise

- Die Omarchy-Shell lädt alle Plugins unter `~/.config/omarchy/plugins/`
  automatisch — kein separater Autostart nötig.
- Nach Änderungen am Plugin-QML greift der QML-Cache: einmal
  `omarchy restart shell` ausführen.
