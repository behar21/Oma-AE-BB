# Glimpse

Omarchy-Shell-Plugin (`bullaku.glimpse`): **Task-View aller belegten Workspaces**
mit **Live-Vorschauen der Fensterinhalte** — ähnlich SUPER+Tab unter Windows —
plus **Fenstersuche** zum direkten Hinspringen.

## Features

- Jeder belegte Workspace ist eine Karte im Raster; leere Workspaces werden ausgeblendet.
- Fenster erscheinen als maßstäbliche Miniaturen an ihrer echten Bildschirmposition
  und zeigen ihren **echten Inhalt live** (Wayland-Screencopy über Quickshells
  `ScreencopyView`), mit App-Icon-Badge. Ist kein Capture möglich, wird ersatzweise
  das App-Icon gezeigt.
- Der aktive Workspace ist farblich umrandet und mit ● markiert; die Fußzeile
  zeigt App-Name und Titel der Auswahl.
- Fenstersuche über Fensterklasse, Titel, App-Name sowie Aliase wie „browser",
  „terminal", „dateien", „chat", „mail", „musik" (deutsch und englisch).
- Optionales 󰕰-Icon in der Menüleiste, das die Übersicht per Klick öffnet.

## Voraussetzungen

Omarchy mit Omarchy-Shell (Quickshell) unter Hyprland.

## Installation

Schnellste Variante — das Skript erledigt alles, sichert vorher `bindings.lua`,
hängt bei erneutem Ausführen nichts doppelt an und lässt eine vorhandene
`glimpse.json` unangetastet:

```bash
./install.sh
```

Manuell in 3 Schritten:

```bash
# 1. Plugin-Ordner kopieren (wird automatisch geladen)
mkdir -p ~/.config/omarchy/plugins
cp -r bullaku.glimpse ~/.config/omarchy/plugins/

# 2. Hotkey-Konfiguration kopieren
cp glimpse.json ~/.config/omarchy/

# 3. Hotkey-Bindings anhängen (liest glimpse.json bei jedem Hyprland-Reload)
cat bindings-glimpse.lua >> ~/.config/hypr/bindings.lua
```

Danach einmal die Shell neu starten (QML-Cache!) und Hyprland neu laden:

```bash
omarchy restart shell
hyprctl reload
```

Autostart ist nicht nötig: Die Omarchy-Shell lädt alle Plugins unter
`~/.config/omarchy/plugins/` automatisch, und das Manifest setzt
`keepLoaded: true` — Ordner an Ort und Stelle heißt: läuft immer.

## Bedienung

| Aktion | Wirkung |
|---|---|
| **CTRL + GRAVE** (Taste links neben der 1) oder Klick aufs Bar-Icon | Task-View öffnen |
| **F7** oder Hotkey 2× schnell | direkt in die Fenstersuche |
| Tippen in der Task-View | wechselt direkt in die Suche |
| ← / → (oder Tab) | vorheriges/nächstes Fenster |
| ↑ / ↓ | vorheriger/nächster Workspace |
| Enter oder Klick auf Vorschau | zum Fenster springen |
| Klick auf Karte | zum Workspace wechseln |
| Esc | Suche leeren → zurück zur Task-View → schließen |

## Hotkeys ändern

`~/.config/omarchy/glimpse.json` bearbeiten, danach `hyprctl reload`:

```json
{
  "hotkey": "CTRL + GRAVE",
  "searchHotkey": "F7"
}
```

## Optional: Icon in der Statusleiste

In `~/.config/omarchy/shell.json` im gewünschten Bar-Abschnitt (z. B. `right`)
ergänzen — die Datei wird beim Speichern automatisch neu geladen:

```json
{ "id": "bullaku.glimpse" }
```

## Dateien in diesem Ordner

| Datei/Ordner | Zielort |
|---|---|
| `bullaku.glimpse/` | `~/.config/omarchy/plugins/bullaku.glimpse/` |
| `glimpse.json` | `~/.config/omarchy/glimpse.json` |
| `bindings-glimpse.lua` | Inhalt ans Ende von `~/.config/hypr/bindings.lua` |
| `install.sh` | Installationsskript (idempotent) |

## Fehlersuche

- Nach Änderungen am Plugin-QML tut sich nichts? QML-Cache — einmal
  `omarchy restart shell` ausführen. Notfalls `omarchy-shell shell rescanPlugins`.
- Fensterdaten kommen bei jedem Öffnen frisch aus `hyprctl -j monitors/clients`;
  die Vorschauen laufen live über das Hyprland-Toplevel-Export-Protokoll.
