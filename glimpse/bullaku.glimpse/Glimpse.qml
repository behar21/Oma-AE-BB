import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  // Modi: "peek" | "search" | "setup" | "setup-done"
  property string mode: "peek"
  property string filterText: ""
  property string setupInput: ""
  property string configuredHotkey: ""
  property string configuredSearchHotkey: ""
  property string savedHotkeyLabel: ""
  property int selectedIndex: 0
  property bool cursorActive: true
  property double lastPress: 0

  // Daten aus hyprctl
  property var wsGroups: []      // [{ wsId, wsName, aspect, windows: [...] }]
  property var flatWins: []      // alle Fenster flach, mit flatIndex
  property var searchResults: []
  property int focusedWsId: (Hyprland.focusedWorkspace !== null) ? Hyprland.focusedWorkspace.id : -1

  // Suchbegriff-Aliase (deutsch + englisch) -> Fensterklassen-Muster
  readonly property var aliases: ({
    "browser": ["chromium", "chrome", "firefox", "brave", "zen", "librewolf", "vivaldi", "edge", "opera"],
    "terminal": ["foot", "alacritty", "kitty", "ghostty", "wezterm"],
    "files": ["nautilus", "thunar", "dolphin", "nemo", "pcmanfm"],
    "dateien": ["nautilus", "thunar", "dolphin", "nemo", "pcmanfm"],
    "editor": ["code", "codium", "cursor", "zed", "sublime"],
    "mail": ["thunderbird", "evolution", "geary", "outlook"],
    "chat": ["teams", "slack", "discord", "signal", "telegram", "element"],
    "musik": ["spotify", "rhythmbox", "elisa"],
    "music": ["spotify", "rhythmbox", "elisa"]
  })

  // ---- Theming: nutzt die [menu]-Farbflaechen wie die Emoji-Suche
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color borderColor: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(780), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(540), panel.height - Style.gapsOut * 2)
  property int rowHeight: Style.space(44)

  // Task-View-Raster
  readonly property int peekGap: Style.space(12)
  readonly property int peekCols: wsGroups.length <= 1 ? 1 : (wsGroups.length <= 4 ? 2 : 3)
  readonly property int peekCardW: peekFlick.width > 0
    ? Math.floor((peekFlick.width - (peekCols - 1) * peekGap) / peekCols)
    : Style.space(220)

  // ---------------------------------------------------------------- Plugin-API
  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    var now = Date.now()

    if (payload.setup === true) {
      root.enterSetup()
      return
    }

    if (payload.search === true) {
      if (!root.opened) {
        root.refresh()
        root.opened = true
      }
      root.lastPress = now
      root.enterSearch()
      return
    }

    if (!root.opened) {
      if (root.configuredHotkey === "") {
        root.enterSetup()
        return
      }
      root.mode = "peek"
      root.filterText = ""
      root.selectedIndex = 0
      root.cursorActive = true
      root.refresh()
      root.opened = true
      root.lastPress = now
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      return
    }

    // Overlay ist bereits offen: schneller Doppeldruck -> Suchmodus
    if (root.mode === "peek" && (now - root.lastPress) < 500) {
      root.enterSearch()
    } else {
      root.dismiss()
    }
    root.lastPress = now
  }

  function close() {
    root.opened = false
    // Delegates (und damit alle Live-Captures) abbauen; refresh() beim
    // naechsten Oeffnen baut sie frisch wieder auf.
    root.wsGroups = []
    root.flatWins = []
    root.searchResults = []
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "bullaku.glimpse")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ---------------------------------------------------------------- Modi
  function enterSetup() {
    root.mode = "setup"
    root.setupInput = ""
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function enterSearch() {
    root.mode = "search"
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildSearch()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // ---------------------------------------------------------------- Daten
  function refresh() {
    stateProc.running = true
  }

  function applyState(raw) {
    var parts = raw.split("@@SEP@@")
    var monitors = []
    var clients = []
    try { monitors = JSON.parse(parts[0]) } catch (e) { monitors = [] }
    try { clients = JSON.parse(parts.length > 1 ? parts[1] : "[]") } catch (e2) { clients = [] }

    // Monitor-Layoutboxen (Layout-Koordinaten, Skalierung/Rotation beruecksichtigt)
    var monById = {}
    for (var m = 0; m < monitors.length; m++) {
      var mon = monitors[m]
      var scale = (mon.scale && mon.scale > 0) ? mon.scale : 1
      var lw = mon.width / scale
      var lh = mon.height / scale
      if (mon.transform === 1 || mon.transform === 3 || mon.transform === 5 || mon.transform === 7) {
        var tmp = lw; lw = lh; lh = tmp
      }
      monById[mon.id] = { x: mon.x, y: mon.y, w: Math.max(1, lw), h: Math.max(1, lh) }
    }

    var byWs = {}
    var order = []
    for (var i = 0; i < clients.length; i++) {
      var c = clients[i]
      if (!c.mapped || c.hidden) continue
      if (!c.workspace || c.workspace.id === undefined || c.workspace.id < 1) continue

      var cls = c.class || c.initialClass || ""
      var entry = null
      try { entry = DesktopEntries.heuristicLookup(cls) } catch (e3) {}
      if (!entry && c.initialClass && c.initialClass !== cls) {
        try { entry = DesktopEntries.heuristicLookup(c.initialClass) } catch (e4) {}
      }

      var box = monById[c.monitor] || { x: 0, y: 0, w: 1920, h: 1080 }
      var relX = (c.at[0] - box.x) / box.w
      var relY = (c.at[1] - box.y) / box.h
      var relW = c.size[0] / box.w
      var relH = c.size[1] / box.h
      relW = Math.min(1, Math.max(0.04, relW))
      relH = Math.min(1, Math.max(0.04, relH))
      relX = Math.min(1 - relW, Math.max(0, relX))
      relY = Math.min(1 - relH, Math.max(0, relY))

      var win = {
        address: c.address,
        cls: cls,
        initialClass: c.initialClass || "",
        title: c.title || "",
        initialTitle: c.initialTitle || "",
        appName: (entry && entry.name) ? entry.name : cls,
        iconSource: (entry && entry.icon) ? Quickshell.iconPath(entry.icon) : "",
        wsId: c.workspace.id,
        wsName: c.workspace.name || String(c.workspace.id),
        relX: relX, relY: relY, relW: relW, relH: relH,
        flatIndex: -1
      }

      if (byWs[win.wsId] === undefined) {
        byWs[win.wsId] = {
          wsId: win.wsId,
          wsName: win.wsName,
          aspect: box.h / box.w,
          windows: []
        }
        order.push(win.wsId)
      }
      byWs[win.wsId].windows.push(win)
    }

    order.sort(function(a, b) { return a - b })
    var nextGroups = []
    var nextFlat = []
    for (var g = 0; g < order.length; g++) {
      var group = byWs[order[g]]
      for (var w = 0; w < group.windows.length; w++) {
        group.windows[w].flatIndex = nextFlat.length
        nextFlat.push(group.windows[w])
      }
      nextGroups.push(group)
    }

    root.wsGroups = nextGroups
    root.flatWins = nextFlat
    if (root.selectedIndex >= nextFlat.length) root.selectedIndex = Math.max(0, nextFlat.length - 1)
    if (root.mode === "search") root.rebuildSearch()
  }

  // ---------------------------------------------------------------- Suche
  function aliasWords(win) {
    var hay = (win.cls + " " + win.initialClass).toLowerCase()
    var words = []
    for (var key in root.aliases) {
      var patterns = root.aliases[key]
      for (var p = 0; p < patterns.length; p++) {
        if (hay.indexOf(patterns[p]) !== -1) { words.push(key); break }
      }
    }
    return words.join(" ")
  }

  function rebuildSearch() {
    var q = root.filterText.trim().toLowerCase()
    var out = []
    for (var i = 0; i < root.flatWins.length; i++) {
      var win = root.flatWins[i]
      if (q === "") { out.push(win); continue }
      var hay = (win.cls + " " + win.initialClass + " " + win.title + " "
                 + win.initialTitle + " " + win.appName + " "
                 + "workspace " + win.wsId + " " + root.aliasWords(win)).toLowerCase()
      var tokens = q.split(/\s+/)
      var ok = true
      for (var t = 0; t < tokens.length; t++) {
        if (hay.indexOf(tokens[t]) === -1) { ok = false; break }
      }
      if (ok) out.push(win)
    }
    root.searchResults = out
    if (root.selectedIndex >= out.length) root.selectedIndex = Math.max(0, out.length - 1)
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildSearch()
  }

  // ---------------------------------------------------------------- Aktionen
  function activateWindow(win) {
    if (!win) return
    root.dismiss()
    // Omarchys Hyprland wertet dispatch-Strings als Lua aus - klassische
    // Dispatcher-Syntax ("focuswindow address:...") ist dort ein Syntaxfehler.
    Quickshell.execDetached(["hyprctl", "dispatch",
      'hl.dsp.focus({ window = "address:' + win.address + '" })'])
  }

  function gotoWorkspace(wsId) {
    root.dismiss()
    Quickshell.execDetached(["hyprctl", "dispatch",
      'hl.dsp.focus({ workspace = "' + wsId + '" })'])
  }

  function currentList() {
    return root.mode === "search" ? root.searchResults : root.flatWins
  }

  function moveSelection(delta) {
    var list = root.currentList()
    if (list.length === 0) return
    root.cursorActive = true
    root.selectedIndex = (root.selectedIndex + delta + list.length) % list.length
    if (root.mode === "search")
      Qt.callLater(function() { resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain) })
  }

  // Hoch/Runter im Peek: zum vorherigen/naechsten Workspace springen
  function moveWorkspace(delta) {
    if (root.flatWins.length === 0 || root.wsGroups.length === 0) return
    root.cursorActive = true
    var cur = root.flatWins[Math.min(root.selectedIndex, root.flatWins.length - 1)]
    var gi = 0
    for (var i = 0; i < root.wsGroups.length; i++) {
      if (root.wsGroups[i].wsId === cur.wsId) { gi = i; break }
    }
    gi = (gi + delta + root.wsGroups.length) % root.wsGroups.length
    root.selectedIndex = root.wsGroups[gi].windows[0].flatIndex
  }

  function selectedWin() {
    var list = root.currentList()
    if (root.selectedIndex >= 0 && root.selectedIndex < list.length) return list[root.selectedIndex]
    return null
  }

  function activateSelection() {
    root.activateWindow(root.selectedWin())
  }

  // Wayland-Toplevel-Handle zu einer Hyprland-Fensteradresse finden
  function toplevelFor(address) {
    if (!address) return null
    var needle = String(address).toLowerCase()
    if (needle.indexOf("0x") === 0) needle = needle.substring(2)
    var values = Hyprland.toplevels.values
    for (var i = 0; i < values.length; i++) {
      var a = String(values[i].address).toLowerCase()
      if (a.indexOf("0x") === 0) a = a.substring(2)
      if (a === needle) return values[i]
    }
    return null
  }

  // Karte der aktuellen Auswahl in den Sichtbereich scrollen
  function ensurePeekVisible(item) {
    if (!item || !peekFlick.visible || peekFlick.contentHeight <= peekFlick.height) return
    var pos = item.mapToItem(peekFlick.contentItem, 0, 0)
    var margin = Style.space(8)
    var top = pos.y - margin
    var bottom = pos.y + item.height + margin
    if (top < peekFlick.contentY) {
      peekFlick.contentY = Math.max(0, top)
    } else if (bottom > peekFlick.contentY + peekFlick.height) {
      peekFlick.contentY = Math.min(Math.max(0, peekFlick.contentHeight - peekFlick.height), bottom - peekFlick.height)
    }
  }

  // ---------------------------------------------------------------- Hotkey-Setup
  function normalizeHotkey(text) {
    var parts = text.split("+")
    var out = []
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].trim()
      if (p === "") continue
      if (p.toLowerCase().indexOf("code:") === 0) out.push("code:" + p.substring(5))
      else if (p.length <= 6 && /^[a-zA-Z0-9]+$/.test(p)) out.push(p.toUpperCase())
      else out.push(p)
    }
    return out.join(" + ")
  }

  function saveHotkey(typed) {
    var hk = typed.trim() === "" ? "code:472" : root.normalizeHotkey(typed)
    var label = typed.trim() === "" ? "Fn (code:472)" : hk
    var cfgObj = { hotkey: hk }
    if (root.configuredSearchHotkey !== "") cfgObj.searchHotkey = root.configuredSearchHotkey
    var json = JSON.stringify(cfgObj, null, 2)
    Quickshell.execDetached(["bash", "-c",
      "mkdir -p \"$HOME/.config/omarchy\" && printf '%s\n' " + Util.shellQuote(json)
      + " > \"$HOME/.config/omarchy/glimpse.json\" && hyprctl reload"])
    root.configuredHotkey = hk
    root.savedHotkeyLabel = label
    root.mode = "setup-done"
  }

  // ---------------------------------------------------------------- Prozesse
  Process {
    id: stateProc
    command: ["bash", "-c", "hyprctl -j monitors && echo @@SEP@@ && hyprctl -j clients"]
    stdout: StdioCollector {
      onStreamFinished: root.applyState(text)
    }
  }

  Process {
    id: configProc
    command: ["bash", "-c", "cat \"$HOME/.config/omarchy/glimpse.json\" 2>/dev/null || true"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var cfg = JSON.parse(text)
          if (cfg && typeof cfg.hotkey === "string") root.configuredHotkey = cfg.hotkey
          if (cfg && typeof cfg.searchHotkey === "string") root.configuredSearchHotkey = cfg.searchHotkey
        } catch (e) {}
      }
    }
  }

  // ---------------------------------------------------------------- UI
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "glimpse"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          // ---- Setup-Modus
          if (root.mode === "setup") {
            if (event.key === Qt.Key_Escape) {
              root.dismiss()
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.saveHotkey(root.setupInput)
            } else if (event.key === Qt.Key_Backspace) {
              root.setupInput = root.setupInput.slice(0, -1)
            } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
              root.setupInput += event.text
            }
            event.accepted = true
            return
          }
          if (root.mode === "setup-done") {
            root.dismiss()
            event.accepted = true
            return
          }

          // ---- Peek/Suche
          if (event.key === Qt.Key_Escape) {
            if (root.mode === "search") {
              if (root.filterText) root.setFilter("")
              else { root.mode = "peek"; root.selectedIndex = 0 }
            } else {
              root.dismiss()
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.moveSelection(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.moveSelection(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            if (root.mode === "peek") root.moveWorkspace(-1)
            else root.moveSelection(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            if (root.mode === "peek") root.moveWorkspace(1)
            else root.moveSelection(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.moveSelection(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateSelection()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace && root.mode === "search") {
            root.setFilter(root.filterText.slice(0, -1))
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            // Tippen im Peek-Modus wechselt direkt in die Suche
            if (root.mode === "peek") root.enterSearch()
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // ------------------------------------------------ Kopfzeile
        Text {
          width: parent.width
          visible: root.mode === "search"
          text: root.filterText || "Fenster suchen … (z. B. \"Browser\" oder \"Teams\")"
          color: root.foreground
          opacity: root.filterText ? 1 : 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          elide: Text.ElideRight
        }

        // ------------------------------------------------ Setup
        Column {
          width: parent.width
          visible: root.mode === "setup"
          spacing: Style.space(10)

          Text {
            width: parent.width
            text: "Ersteinrichtung: Hotkey festlegen"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            wrapMode: Text.WordWrap
          }
          Text {
            width: parent.width
            text: "Tippe die Tastenkombination (z. B. SUPER + Y) und bestätige mit Enter.\nEnter ohne Eingabe: Fn-Taste (code:472).\nHinweis: Auf vielen Laptops verarbeitet die Firmware Fn intern – falls die Fn-Taste nicht reagiert, richte mit »omarchy-shell shell summon bullaku.glimpse '{\"setup\":true}'« eine andere Kombination ein."
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
          Rectangle {
            width: parent.width
            height: root.rowHeight
            radius: root.cornerRadius
            color: root.selectedBackground
            Text {
              anchors.fill: parent
              anchors.margins: Style.space(10)
              verticalAlignment: Text.AlignVCenter
              text: root.setupInput || "Fn"
              opacity: root.setupInput ? 1 : 0.5
              color: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              elide: Text.ElideRight
            }
          }
        }

        Column {
          width: parent.width
          visible: root.mode === "setup-done"
          spacing: Style.space(10)

          Text {
            width: parent.width
            text: "Hotkey gespeichert: " + root.savedHotkeyLabel
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            wrapMode: Text.WordWrap
          }
          Text {
            width: parent.width
            text: "1× drücken: Peek der belegten Workspaces.\n2× schnell drücken: Fenstersuche.\nBeliebige Taste schließt dieses Fenster."
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }

        // ------------------------------------------------ Peek: Task-View-Raster
        Flickable {
          id: peekFlick
          width: parent.width
          height: parent.height - y - footer.height - root.contentSpacing
          visible: root.mode === "peek"
          contentHeight: peekFlow.height
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Flow {
            id: peekFlow
            width: peekFlick.width
            spacing: root.peekGap

            Repeater {
              model: root.wsGroups

              Rectangle {
                id: cardRoot
                required property var modelData
                readonly property var grp: modelData
                readonly property bool isFocusedWs: grp.wsId === root.focusedWsId
                readonly property int miniH: Math.round(Math.min(Style.space(180), Math.max(Style.space(70), (root.peekCardW - Style.space(16)) * grp.aspect)))

                width: root.peekCardW
                height: headerText.height + miniH + Style.space(24)
                radius: root.cornerRadius
                color: "transparent"
                border.width: isFocusedWs ? 2 : 1
                border.color: isFocusedWs ? root.selectedBackground : Qt.alpha(root.foreground, 0.18)

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.gotoWorkspace(cardRoot.grp.wsId)
                }

                Text {
                  id: headerText
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.margins: Style.space(8)
                  text: "Workspace " + cardRoot.grp.wsName + (cardRoot.isFocusedWs ? "  ●" : "")
                  color: root.foreground
                  opacity: 0.85
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                // Miniatur des Workspaces
                Rectangle {
                  id: miniArea
                  anchors.top: headerText.bottom
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.margins: Style.space(8)
                  anchors.topMargin: Style.space(4)
                  height: cardRoot.miniH
                  radius: Math.max(2, root.cornerRadius - 2)
                  color: Qt.alpha(root.foreground, 0.06)
                  clip: true

                  Repeater {
                    model: cardRoot.grp.windows

                    Rectangle {
                      id: winRect
                      required property var modelData
                      readonly property var win: modelData
                      readonly property bool hasCursor: root.cursorActive && win.flatIndex === root.selectedIndex

                      x: Math.round(win.relX * miniArea.width)
                      y: Math.round(win.relY * miniArea.height)
                      width: Math.max(Style.space(18), Math.round(win.relW * miniArea.width))
                      height: Math.max(Style.space(16), Math.round(win.relH * miniArea.height))
                      radius: Math.max(2, root.cornerRadius - 4)
                      color: hasCursor ? root.selectedBackground : Qt.alpha(root.foreground, 0.13)
                      border.width: hasCursor ? 2 : 1
                      border.color: hasCursor ? root.selectedBackground : Qt.alpha(root.foreground, 0.35)

                      readonly property bool hasPreview: thumb.hasContent
                      clip: true

                      onHasCursorChanged: if (hasCursor) root.ensurePeekVisible(cardRoot)

                      // Live-Vorschau des Fensterinhalts.
                      // captureSource wird erst NACH der QML-Instanziierung gesetzt
                      // (Qt.callLater) statt als Binding: ein dynamic_cast auf das
                      // Toplevel-Handle während QQmlObjectCreator::finalize hat die
                      // Shell mit SIGSEGV gecrasht (2026-09-02).
                      ScreencopyView {
                        id: thumb
                        anchors.fill: parent
                        anchors.margins: winRect.hasCursor ? 2 : 1
                        live: true
                        visible: hasContent

                        Component.onCompleted: Qt.callLater(function() {
                          if (!thumb || !winRect) return
                          var t = root.toplevelFor(winRect.win.address)
                          if (t && t.wayland) thumb.captureSource = t.wayland
                        })
                        Component.onDestruction: thumb.captureSource = null
                      }

                      // Kleines App-Icon als Badge über der Vorschau
                      Image {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Style.space(3)
                        visible: winRect.hasPreview && winRect.win.iconSource !== ""
                        width: Math.max(Style.space(10), Math.min(Style.space(18), Math.min(winRect.width, winRect.height) * 0.35))
                        height: width
                        source: winRect.win.iconSource
                        sourceSize.width: Style.space(18)
                        sourceSize.height: Style.space(18)
                        fillMode: Image.PreserveAspectFit
                      }

                      // Fallback ohne Vorschau: zentriertes App-Icon bzw. Anfangsbuchstabe
                      Image {
                        anchors.centerIn: parent
                        visible: !winRect.hasPreview && winRect.win.iconSource !== ""
                        width: Math.max(Style.space(12), Math.min(Style.space(30), Math.min(winRect.width, winRect.height) * 0.6))
                        height: width
                        source: winRect.win.iconSource
                        sourceSize.width: Style.space(30)
                        sourceSize.height: Style.space(30)
                        fillMode: Image.PreserveAspectFit
                      }
                      Text {
                        anchors.centerIn: parent
                        visible: !winRect.hasPreview && winRect.win.iconSource === ""
                        text: (winRect.win.appName || "?").charAt(0).toUpperCase()
                        color: winRect.hasCursor ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: if (containsMouse) {
                          root.cursorActive = true
                          root.selectedIndex = winRect.win.flatIndex
                        }
                        onClicked: root.activateWindow(winRect.win)
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // ------------------------------------------------ Such-Ansicht
        Item {
          width: parent.width
          height: parent.height - y - footer.height - root.contentSpacing
          visible: root.mode === "search"

          ListView {
            id: resultList
            anchors.fill: parent
            model: root.searchResults
            clip: true
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: searchRow
              required property var modelData
              required property int index
              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

              width: resultList.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Item {
                id: searchIcon
                width: Style.space(26)
                height: Style.space(26)
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter

                Image {
                  anchors.fill: parent
                  visible: searchRow.modelData.iconSource !== ""
                  source: searchRow.modelData.iconSource
                  sourceSize.width: width
                  sourceSize.height: height
                  fillMode: Image.PreserveAspectFit
                }
                Rectangle {
                  anchors.fill: parent
                  visible: searchRow.modelData.iconSource === ""
                  radius: width / 2
                  color: root.selectedBackground
                  Text {
                    anchors.centerIn: parent
                    text: (searchRow.modelData.appName || "?").charAt(0).toUpperCase()
                    color: root.selectedText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                }
              }

              Text {
                id: wsTag
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: "WS " + searchRow.modelData.wsName
                color: searchRow.hasCursor ? root.selectedText : root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Column {
                anchors.left: searchIcon.right
                anchors.leftMargin: Style.space(10)
                anchors.right: wsTag.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  width: parent.width
                  text: searchRow.modelData.appName
                  color: searchRow.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: searchRow.modelData.title
                  color: searchRow.hasCursor ? root.selectedText : root.foreground
                  opacity: 0.65
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                z: -1
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.selectedIndex = searchRow.index
                }
                onClicked: root.activateWindow(searchRow.modelData)
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.searchResults.length === 0
            text: "Keine Treffer für „" + root.filterText + "“"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        // ------------------------------------------------ Fusszeile
        Column {
          id: footer
          width: parent.width
          visible: root.mode === "peek" || root.mode === "search"
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: {
              var w = root.selectedWin()
              return w ? (w.appName + (w.title ? "  —  " + w.title : "")) : " "
            }
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: root.mode === "peek"
              ? "←/→: Fenster · ↑/↓: Workspace · Enter/Klick: Fenster · Klick auf Karte: Workspace · Tippen: Suche · Esc: Schließen"
              : "↑/↓: Auswahl · Enter/Klick: Fenster · Esc: Zurück"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
