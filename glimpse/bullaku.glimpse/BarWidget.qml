import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar-Icon (rechte Sektion): öffnet die Glimpse-Workspace-Übersicht.
BarWidget {
  id: root
  moduleName: "bullaku.glimpse"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    bar: root.bar
    text: "󰕰"
    horizontalMargin: 6
    verticalPadding: 6
    fixedWidth: root.vertical ? root.barSize : Style.space(24)
    fixedHeight: root.barSize
    onPressed: function() {
      Quickshell.execDetached(["omarchy-shell", "-q", "shell", "summon", "bullaku.glimpse", "{\"press\":true}"])
    }
  }
}
