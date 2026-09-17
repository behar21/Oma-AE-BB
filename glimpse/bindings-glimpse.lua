-- Glimpse-Plugin (bullaku.glimpse): Workspace-Übersicht & Fenstersuche.
-- Hotkeys stehen in ~/.config/omarchy/glimpse.json ("hotkey" = Übersicht,
-- "searchHotkey" = direkte Fenstersuche). Dieser Block liest sie bei jedem
-- Hyprland-Reload neu ein; ohne Konfigurationsdatei wird nichts gebunden.
local glimpse_conf = (os.getenv("HOME") or "") .. "/.config/omarchy/glimpse.json"
local glimpse_file = io.open(glimpse_conf, "r")
if glimpse_file then
  local glimpse_json = glimpse_file:read("*a")
  glimpse_file:close()
  local glimpse_hotkey = glimpse_json:match('"hotkey"%s*:%s*"([^"]+)"')
  local glimpse_search = glimpse_json:match('"searchHotkey"%s*:%s*"([^"]+)"')
  if glimpse_hotkey and #glimpse_hotkey > 0 then
    o.bind(glimpse_hotkey, "Glimpse", "omarchy-shell -q shell summon bullaku.glimpse '{\"press\":true}'")
  end
  if glimpse_search and #glimpse_search > 0 then
    o.bind(glimpse_search, "Glimpse: Suche", "omarchy-shell -q shell summon bullaku.glimpse '{\"search\":true}'")
  end
end
