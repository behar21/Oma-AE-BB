# Glimpse

Omarchy-Shell-Plugin: Task-View aller **belegten** Workspaces (leere werden
ausgeblendet) mit **Live-Vorschauen der Fensterinhalte** — ähnlich SUPER+Tab
unter Windows — plus Fenstersuche zum direkten Hinspringen.

## Ansicht

Jeder Workspace ist eine Karte im Raster. Die Fenster werden als maßstäbliche
Miniaturen an ihrer echten Bildschirmposition gezeichnet und zeigen ihren
**echten Inhalt live** (Wayland-Screencopy über Quickshells `ScreencopyView`),
mit kleinem App-Icon-Badge. Kann ein Fenster nicht gecaptured werden, wird
ersatzweise das App-Icon angezeigt. Der aktive Workspace ist farblich umrandet
und mit ● markiert; die Fußzeile zeigt App-Name und Titel der Auswahl.

In der Menüleiste (rechte Sektion) sitzt zusätzlich ein 󰕰 -Icon, das die
Übersicht per Klick öffnet.

## Bedienung

| Aktion | Wirkung |
|---|---|
| Hotkey (Standard: `CTRL + GRAVE`) oder Klick aufs Bar-Icon | Task-View |
| Such-Hotkey (Standard: `F7`) oder Hotkey 2× schnell | Fenstersuche (z. B. „Browser“, „Teams“) |
| Tippen in der Task-View | wechselt direkt in die Suche |
| ← / → (oder Tab) | vorheriges/nächstes Fenster |
| ↑ / ↓ | vorheriger/nächster Workspace (Auswahl scrollt automatisch in den Sichtbereich) |
| Enter oder Klick auf Vorschau | zum Fenster springen (mehrere Instanzen einer App werden alle gezeigt) |
| Klick auf Karte | zum Workspace wechseln |
| Esc | Suche leeren → zurück zur Task-View → schließen |

Die Suche berücksichtigt Fensterklasse, Titel, App-Name sowie Aliase wie
„browser“, „terminal“, „dateien“, „chat“, „mail“, „musik“ (deutsch und englisch).

## Hotkeys ändern

`~/.config/omarchy/glimpse.json` bearbeiten:

```json
{
  "hotkey": "CTRL + GRAVE",
  "searchHotkey": "F7"
}
```

Danach `hyprctl reload`. Alternativ den Einrichtungsdialog erneut aufrufen:

```bash
omarchy-shell shell summon bullaku.glimpse '{"setup":true}'
```

## Dateien

- `~/.config/omarchy/plugins/bullaku.glimpse/` — Plugin (Manifest, `Glimpse.qml`, `BarWidget.qml`)
- `~/.config/omarchy/glimpse.json` — Hotkeys
- `~/.config/hypr/bindings.lua` — liest die Hotkeys aus der JSON-Datei und
  bindet sie auf `omarchy-shell shell summon bullaku.glimpse …`

## Hinweise

- Fensterdaten kommen bei jedem Öffnen frisch aus `hyprctl -j monitors/clients`;
  die Vorschauen laufen live über das Hyprland-Toplevel-Export-Protokoll.
- Nach Änderungen am Plugin-QML die Shell mit `omarchy restart shell` neu
  starten — der Hot-Reload leert den QML-Komponenten-Cache nicht.
