import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "nate.omatracker"
  ipcTarget: "nate.omatracker"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var tracker: null
  readonly property var barIdentity: hostWidget || root
  readonly property var snap: tracker && tracker.snapshot ? tracker.snapshot : ({})

  property bool followToday: true
  property string viewKey: ""
  property string selectedId: ""
  property bool openedFromHotkey: false
  property int tick: 0

  readonly property string shownKey: followToday ? String(snap.todayKey || "") : viewKey
  readonly property var shownDay: (snap.days && snap.days[shownKey]) ? snap.days[shownKey] : ({ total: 0, rows: [] })
  readonly property var rows: shownDay.rows || []
  readonly property var week: snap.week || []
  readonly property color fg: Color.popups.text
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.62)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.14)
  readonly property string ff: bar ? bar.fontFamily : Style.font.family
  readonly property int rowH: Style.space(46)
  readonly property int limitMinutes: {
    var limits = snap.limits || ({})
    var n = Number(limits[selectedId] || 0)
    return isFinite(n) ? n : 0
  }
  readonly property string selectedName: {
    var apps = snap.apps || ({})
    var app = apps[selectedId]
    if (app && app.name) return app.name
    for (var i = 0; i < rows.length; i++) if (rows[i].id === selectedId) return rows[i].name
    return selectedId ? Model.prettify(selectedId) : ""
  }

  function shownSeconds(row) {
    var _ = root.tick
    if (root.shownKey === String(root.snap.todayKey || "") && row.id === root.snap.focusedId)
      return Model.liveSeconds(root.snap, Date.now())
    return row.seconds
  }

  function shownTotal() {
    var _ = root.tick
    var total = root.shownDay.total || 0
    if (root.shownKey === String(root.snap.todayKey || "") && root.snap.since > 0)
      total += Math.max(0, Math.round((Date.now() - root.snap.since) / 1000))
    return total
  }

  function rowStatus(row, seconds) {
    return Model.statusFor(seconds, (row.limitMinutes || 0) * 60, root.snap.warnRatio || 0.8)
  }

  function tone(status) {
    if (status === "over") return Color.urgent
    if (status === "warn") return Color.accent
    return root.fg
  }

  function fill(row, seconds, status) {
    if (row.limitMinutes > 0) return root.tone(status)
    return Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
  }

  function share(row, seconds) {
    if (row.limitMinutes > 0) return Math.min(1, seconds / (row.limitMinutes * 60))
    var total = root.shownTotal()
    if (total <= 0) return 0
    return Math.min(1, seconds / total)
  }

  function weekMax() {
    var max = 1
    for (var i = 0; i < week.length; i++) if (week[i].seconds > max) max = week[i].seconds
    return max
  }

  function iconSource(name) {
    var value = String(name || "")
    if (!value) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  function selectDay(key) {
    root.followToday = key === String(root.snap.todayKey || "")
    root.viewKey = key
  }

  function moveSelection(dy) {
    if (!dy || !root.rows.length) return
    var idx = 0
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].id === root.selectedId) idx = i
    idx = Math.max(0, Math.min(root.rows.length - 1, idx + (dy > 0 ? 1 : -1)))
    root.selectedId = root.rows[idx].id
    var y = idx * (root.rowH + Style.space(2))
    if (y < list.contentY) list.contentY = y
    else if (y + root.rowH > list.contentY + list.height) list.contentY = y + root.rowH - list.height
  }

  function shiftDay(dx) {
    if (!dx || !root.week.length) return
    var idx = root.week.length - 1
    for (var i = 0; i < root.week.length; i++) if (root.week[i].key === root.shownKey) idx = i
    idx = Math.max(0, Math.min(root.week.length - 1, idx + dx))
    root.selectDay(root.week[idx].key)
  }

  function commitLimit(minutes) {
    if (!root.tracker || !root.selectedId) return
    root.tracker.setLimit(root.selectedId, minutes)
  }

  function bump(delta) {
    root.commitLimit(Math.max(0, (root.limitMinutes || 0) + delta))
  }

  function applyCustom() {
    var n = Math.round(Number(limitField.text))
    if (!isFinite(n) || n < 0) return
    root.commitLimit(n)
  }

  function syncLimitField() {
    if (limitField.activeFocus) return
    limitField.text = root.limitMinutes > 0 ? String(root.limitMinutes) : ""
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && root.bar.setCenterHoverRevealSuppressed)
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    if (!root.selectedId && root.snap.focusedId) root.selectedId = root.snap.focusedId
    root.controller.show()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    if (!root.selectedId && root.snap.focusedId) root.selectedId = root.snap.focusedId
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  onSelectedIdChanged: syncLimitField()
  onLimitMinutesChanged: syncLimitField()
  onOpenedChanged: if (opened) root.tick++

  Timer {
    interval: 1000
    repeat: true
    running: root.opened
    onTriggered: root.tick++
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: limitField.activeFocus
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) {
        if (dy) root.moveSelection(dy)
        if (dx) root.shiftDay(dx)
      }
      onTextKey: function(t) {
        if (t === "p") {
          if (root.tracker && root.snap) root.tracker.setPaused(!root.snap.paused)
        } else if (t === "t") {
          root.followToday = true
        }
      }

      Column {
        id: body
        width: parent.width
        spacing: Style.spacing.lg

        Item {
          width: parent.width
          height: Math.max(titleText.implicitHeight, totalText.implicitHeight)

          Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.shownKey && root.shownKey === String(root.snap.todayKey || "")
              ? "Today"
              : Model.dayLabel(root.shownKey)
            color: root.fg
            font.family: root.ff
            font.pixelSize: Style.font.title
          }

          Text {
            anchors.left: titleText.right
            anchors.right: totalText.left
            anchors.leftMargin: Style.spacing.lg
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.snap.focusedName && root.shownKey === String(root.snap.todayKey || "")
              ? root.snap.focusedName
              : ""
            color: root.dim
            font.family: root.ff
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            id: totalText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: {
              var _ = root.tick
              return Model.formatDuration(root.shownTotal())
            }
            color: root.fg
            font.family: root.ff
            font.pixelSize: Style.font.title
          }
        }

        Text {
          visible: text !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: {
            var snap = root.snap
            if (!snap || snap.paused !== true && root.shownKey !== String(snap.todayKey || "")) return ""
            if (snap.paused === true) return "Paused — time is not counting"
            return snap.focusedTitle ? String(snap.focusedTitle) : ""
          }
          color: root.dim
          font.family: root.ff
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Row {
          width: parent.width
          spacing: Style.space(4)
          visible: root.week.length > 0

          Repeater {
            model: root.week

            Item {
              required property var modelData
              width: (parent.width - Style.space(4) * 6) / 7
              height: Style.space(40)

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: dayNum.top
                anchors.bottomMargin: Style.space(3)
                height: Style.space(18)
                radius: Style.cornerRadius > 0 ? Style.space(2) : 0
                color: root.faint

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: Math.max(modelData.seconds > 0 ? Style.space(2) : 0, parent.height * (modelData.seconds / root.weekMax()))
                  radius: parent.radius
                  color: modelData.over
                    ? Color.urgent
                    : (modelData.isToday ? Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.5))
                }
              }

              Text {
                id: dayNum
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: String(modelData.label || "").split(" ").pop()
                color: root.shownKey === modelData.key ? Color.accent : root.dim
                font.family: root.ff
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectDay(modelData.key)
              }
            }
          }
        }

        Flickable {
          id: list
          width: parent.width
          height: root.rows.length === 0
            ? emptyText.implicitHeight
            : Math.min(Style.space(276), Math.max(root.rowH, column.implicitHeight))
          contentWidth: width
          contentHeight: root.rows.length === 0 ? emptyText.implicitHeight : column.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Text {
            id: emptyText
            visible: root.rows.length === 0
            width: list.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.tracker
              ? "Nothing tracked yet. Use a program and it will show up here."
              : "Omatracker is starting."
            color: root.dim
            font.family: root.ff
            font.pixelSize: Style.font.body
          }

          Column {
            id: column
            width: list.width
            spacing: Style.space(2)
            visible: root.rows.length > 0

            Repeater {
              model: root.rows

              Item {
                id: row
                required property var modelData
                width: column.width
                height: root.rowH

                readonly property int seconds: {
                  var _ = root.tick
                  return root.shownSeconds(modelData)
                }
                readonly property string status: root.rowStatus(modelData, seconds)
                readonly property bool selected: root.selectedId === modelData.id
                readonly property string iconPath: root.iconSource(modelData.icon)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius > 0 ? Style.space(6) : 0
                  color: row.selected
                    ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, Style.selectedFillAlpha)
                    : (rowMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, Style.hoverFillAlpha) : "transparent")
                }

                Image {
                  id: appIcon
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(16)
                  height: Style.space(16)
                  visible: iconPath !== "" && appIcon.status === Image.Ready
                  source: iconPath
                  fillMode: Image.PreserveAspectFit
                  sourceSize.width: width * Screen.devicePixelRatio
                  sourceSize.height: height * Screen.devicePixelRatio
                  asynchronous: true
                }

                Rectangle {
                  visible: !appIcon.visible
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(16)
                  height: width
                  radius: Style.cornerRadius > 0 ? width / 2 : Style.space(2)
                  color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: modelData.name ? modelData.name.charAt(0).toUpperCase() : "?"
                    color: root.fg
                    font.family: root.ff
                    font.pixelSize: Style.font.caption
                  }
                }

                Column {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(16) + Style.spacing.md * 2
                  anchors.right: timeText.left
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: modelData.name
                    color: root.tone(row.status)
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Rectangle {
                    width: parent.width
                    height: Style.space(4)
                    radius: Style.cornerRadius > 0 ? height / 2 : 0
                    color: root.faint

                    Rectangle {
                      width: parent.width * root.share(modelData, row.seconds)
                      height: parent.height
                      radius: parent.radius
                      color: root.fill(modelData, row.seconds, row.status)
                    }
                  }
                }

                Text {
                  id: timeText
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  horizontalAlignment: Text.AlignRight
                  text: Model.formatDuration(row.seconds) + (modelData.limitMinutes > 0 ? "\n/ " + Model.formatLimit(modelData.limitMinutes) : "")
                  color: root.tone(row.status)
                  font.family: root.ff
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectedId = modelData.id
                }
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.spacing.sm
          visible: root.selectedId !== ""

          Text {
            textFormat: Text.PlainText
            text: "LIMIT  " + root.selectedName.toUpperCase()
            color: root.dim
            font.family: root.ff
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            elide: Text.ElideRight
            width: parent.width
          }

          Flow {
            width: parent.width
            spacing: Style.spacing.sm

            Repeater {
              model: Model.PRESETS

              Button {
                required property var modelData
                text: modelData.label
                selected: root.limitMinutes === modelData.minutes
                foreground: root.fg
                accent: Color.accent
                fontFamily: root.ff
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.spacing.md
                verticalPadding: Style.spacing.xs
                onClicked: root.commitLimit(modelData.minutes)
              }
            }
          }

          Row {
            spacing: Style.spacing.sm

            Button {
              text: "−15"
              foreground: root.fg
              fontFamily: root.ff
              fontSize: Style.font.bodySmall
              onClicked: root.bump(-15)
            }

            TextField {
              id: limitField
              width: Style.space(72)
              placeholderText: "min"
              foreground: root.fg
              font.family: root.ff
              font.pixelSize: Style.font.body
              inputMethodHints: Qt.ImhDigitsOnly
              horizontalAlignment: Text.AlignHCenter
              verticalPadding: Style.spacing.xs
              onAccepted: root.applyCustom()
            }

            Button {
              text: "+15"
              foreground: root.fg
              fontFamily: root.ff
              fontSize: Style.font.bodySmall
              onClicked: root.bump(15)
            }

            Button {
              text: "Set"
              foreground: root.fg
              accent: Color.accent
              fontFamily: root.ff
              fontSize: Style.font.bodySmall
              onClicked: root.applyCustom()
            }
          }
        }

        Toggle {
          width: parent.width
          label: "Pause tracking"
          description: "Stops counting until you resume. Right-click the bar does the same."
          checked: root.snap.paused === true
          foreground: root.fg
          accent: Color.accent
          fontFamily: root.ff
          onClicked: if (root.tracker) root.tracker.setPaused(!root.snap.paused)
        }
      }
    }
  }
}
