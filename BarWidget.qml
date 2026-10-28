import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.gabrielforster.big-cursor"

  readonly property var cursorService: bar?.shell?.serviceFor(root.moduleName)
  readonly property int maxSize: cursorService
    ? cursorService.maxSize : Number(setting("maxSize", 96))
  readonly property real sensitivity: cursorService
    ? cursorService.sensitivity : Number(setting("sensitivity", 2.5))
  property bool popupOpen: false

  // Write one setting to this widget's shell.json entry. The service picks it
  // up from the file, but is updated first so the change is live on release.
  function persist(key, value) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    entry[key] = value

    if (cursorService) cursorService[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function preview() {
    if (cursorService) cursorService.preview()
  }

  function close() {
    root.popupOpen = false
  }

  function schedulePopupClose() {
    if (root.popupOpen) popupCloseTimer.restart()
  }

  Timer {
    id: popupCloseTimer
    interval: 200
    repeat: false
    onTriggered: {
      if (root.popupOpen && !button.tooltipHovered && !popup.containsMouse && !maxSlider.dragging
          && !sensitivitySlider.dragging)
        root.popupOpen = false
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onPopupOpenChanged: if (!root.popupOpen) popupCloseTimer.stop()

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: Style.bar.iconSlot
    fixedHeight: Style.bar.iconSlot
    useActiveColor: false
    tooltipText: "Big cursor · up to " + root.maxSize + " px"

    onPressed: function(buttonId) {
      if (buttonId === Qt.RightButton) root.preview()
      else if (buttonId === Qt.LeftButton) root.popupOpen = !root.popupOpen
    }

    onTooltipHoveredChanged: {
      if (tooltipHovered) popupCloseTimer.stop()
      else root.schedulePopupClose()
    }

    CursorArrow {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: Style.space(1)
      size: Style.space(20)
      fillColor: button.foreground
      strokeColor: "transparent"
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(260))
    contentHeight: popup.fittedContentHeight(panelColumn.implicitHeight)

    // Keep the popup open while moving between the bar button and the card.
    onContainsMouseChanged: {
      if (containsMouse) popupCloseTimer.stop()
      else root.schedulePopupClose()
    }

    Column {
      id: panelColumn
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        text: "BIG CURSOR"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        width: parent.width
        text: "Shake the mouse to find the cursor."
        color: root.bar.foreground
        opacity: 0.7
        wrapMode: Text.WordWrap
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { foreground: root.bar.foreground }

      SettingRow {
        label: "MAX SIZE"
        valueText: root.maxSize + " px"

        PanelSlider {
          id: maxSlider
          width: parent.width
          bar: root.bar
          minimum: 32
          maximum: 256
          step: 8
          integer: true
          value: root.maxSize
          onMoved: if (root.cursorService) root.cursorService.maxSize = Math.round(value)
          onReleased: {
            root.persist("maxSize", Math.round(value))
            root.preview()
          }
        }
      }

      SettingRow {
        label: "SHAKE NEEDED"
        valueText: root.sensitivity <= 2 ? "Light" : root.sensitivity <= 3.5 ? "Medium" : "Hard"

        PanelSlider {
          id: sensitivitySlider
          width: parent.width
          bar: root.bar
          minimum: 1.5
          maximum: 6
          step: 0.5
          value: root.sensitivity
          onMoved: if (root.cursorService) root.cursorService.sensitivity = value
          onReleased: root.persist("sensitivity", value)
        }
      }

      Button {
        width: parent.width
        text: "Preview"
        foreground: root.bar.foreground
        bordered: true
        onClicked: root.preview()
      }
    }
  }

  component SettingRow: Column {
    id: row
    property string label: ""
    property string valueText: ""
    default property alias content: slot.data

    width: parent.width
    spacing: Style.space(4)

    Item {
      width: parent.width
      height: labelText.implicitHeight

      Text {
        id: labelText
        text: row.label
        color: root.bar.foreground
        opacity: 0.7
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        anchors.right: parent.right
        text: row.valueText
        color: root.bar.foreground
        opacity: 0.75
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Item {
      id: slot
      width: parent.width
      height: childrenRect.height
    }
  }
}
