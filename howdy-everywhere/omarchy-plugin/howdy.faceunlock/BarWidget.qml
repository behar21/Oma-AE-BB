import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar-Icon (rechts neben dem Akku): zeigt, ob die Howdy-Gesichtsentsperrung
// scharf ist. Der Lock-Screen-Watcher ist die einzige laufende Komponente --
// laeuft er, greift Face-Unlock. Klick oeffnet eine Status-Benachrichtigung.
BarWidget {
  id: root
  moduleName: "howdy.faceunlock"

  // "armed" = Watcher laeuft; "off" = gestoppt; "unknown" = wird geprueft.
  property string state: "unknown"
  property string summaryText: "Status wird geprueft ..."

  // Glyph (Nerd Font, Material-Design "face-recognition" U+F09B1); via shell.json
  // ueberschreibbar:  "howdy.faceunlock": { "icon": "..." }
  readonly property string glyph: root.setting("icon", String.fromCodePoint(0xF09B1))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    bar: root.bar
    text: root.glyph
    horizontalMargin: 6
    verticalPadding: 6
    fixedWidth: root.vertical ? root.barSize : Style.space(24)
    fixedHeight: root.barSize

    // Normale Bar-Farbe wenn scharf; Warnfarbe (rot) wenn der Watcher aus ist.
    active: root.state === "off"
    activeColor: Color.urgent
    useActiveColor: true

    tooltipText: root.state === "armed"
        ? "Face Unlock: aktiv"
        : (root.state === "off" ? "Face Unlock: INAKTIV -- Watcher gestoppt"
                                : "Face Unlock: pruefe ...")

    onPressed: function(mouseButton) {
      Quickshell.execDetached([
        "/usr/bin/notify-send", "-a", "Face Unlock",
        root.state === "armed" ? "Face Unlock aktiv" : "Face Unlock inaktiv",
        root.summaryText
      ])
    }
  }

  // ---- Status-Poll (alle 5 s, ein kurzer sh-Aufruf) ----
  // "armed" = der Sperrbildschirm entsperrt per Kamera (Howdy-PAM vorhanden).
  readonly property string probeScript:
    "grep -q howdy-everywhere /etc/pam.d/omarchy-lock-fingerprint 2>/dev/null && l=yes || l=no; " +
    "grep -q howdy-everywhere /etc/pam.d/polkit-1 2>/dev/null && p=yes || p=no; " +
    "grep -q howdy-everywhere /etc/pam.d/su 2>/dev/null && s=yes || s=no; " +
    "grep -q howdy-pam-exec /etc/pam.d/sudo 2>/dev/null && u=yes || u=no; " +
    "printf 'lock=%s polkit=%s su=%s sudo=%s' \"$l\" \"$p\" \"$s\" \"$u\""

  function applyProbe(out) {
    var m = {}
    out.trim().split(/\s+/).forEach(function (kv) {
      var p = kv.split("=")
      if (p.length === 2) m[p[0]] = p[1]
    })
    var armed = (m.lock === "yes")
    root.state = armed ? "armed" : "off"
    function tick(v) { return v === "yes" ? "✓" : "—" }
    root.summaryText =
      "Sperrbildschirm " + tick(m.lock) + "\n" +
      "sudo " + tick(m.sudo) + "   polkit " + tick(m.polkit) + "   su " + tick(m.su)
  }

  Process {
    id: probe
    running: false
    command: ["/bin/sh", "-c", root.probeScript]
    stdout: StdioCollector {
      id: probeOut
      waitForEnd: true
      onStreamFinished: root.applyProbe(probeOut.text)
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!probe.running) probe.running = true
  }
}
