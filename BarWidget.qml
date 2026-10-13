import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "nate.omatracker"

  readonly property var tracker: bar && bar.shell ? bar.shell.serviceFor("nate.omatracker") : null
  readonly property var snap: tracker && tracker.snapshot ? tracker.snapshot : null
  readonly property bool showName: {
    var value = settings ? settings.showName : undefined
    return value === undefined || value === null ? true : !!value
  }
  property int tick: 0

  readonly property string label: {
    var _ = root.tick
    return root.snap ? Model.barLabel(root.snap, Date.now(), root.showName, root.vertical) : "Omatracker"
  }
  readonly property string toneName: {
    var _ = root.tick
    return root.snap ? Model.liveStatus(root.snap, Date.now()) : "open"
  }
  readonly property color tone: {
    if (root.toneName === "over") return root.bar ? root.bar.urgent : Color.urgent
    if (root.toneName === "warn") return Color.accent
    return root.bar ? root.bar.barForeground : Color.foreground
  }
  readonly property string tip: {
    var _ = root.tick
    return root.snap ? Model.tooltip(root.snap, Date.now()) : "Omatracker"
  }

  function pushSettings() {
    if (root.tracker && root.tracker.applySettings) root.tracker.applySettings(root.settings)
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("tracker" in target) target.tracker = root.tracker
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: root.vertical ? 0 : button.labelWidth

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
    else if (panelLoader.item) panelLoader.item.open()
  }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: { injectPanel(); pushSettings() }
  onSettingsChanged: { injectPanel(); pushSettings() }
  onTrackerChanged: { injectPanel(); pushSettings() }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.tick++
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    foreground: root.tone
    useActiveColor: false
    dimmed: root.snap ? (root.snap.paused || !root.snap.since) : false
    tooltipText: root.tip
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.tracker && root.snap) root.tracker.setPaused(!root.snap.paused)
        return
      }
      root.togglePanel()
    }
  }
}
