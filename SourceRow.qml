import QtQuick
import qs.Commons
import qs.Ui

// One selectable photo source in the Collections pane — an official topic or
// a browsable collection. Both render identically, so the row lives here
// rather than twice in Panel.qml.
//
// Taps are handled by TapHandler, not MouseArea: this list scrolls, and a
// MouseArea inside an interactive Flickable loses its click the moment the
// pointer drifts during the press.
Rectangle {
  id: root

  // { title, totalPhotos, coverUrl, coverColor, curator }
  property var entry: null
  property bool picked: false
  property bool hasCursor: false

  property color foreground: Color.foreground
  property color faint: Qt.darker(foreground, 2.0)
  property string fontFamily: Style.font.family

  signal toggled()
  signal hoveredIn()

  readonly property bool hot: hover.hovered || hasCursor

  height: Style.space(46)
  color: hot ? Style.hoverFillFor(foreground, Color.accent)
    : (picked ? Style.selectedFillFor(foreground, Color.accent) : "transparent")

  HoverHandler {
    id: hover
    cursorShape: Qt.PointingHandCursor
    onHoveredChanged: if (hovered) root.hoveredIn()
  }

  TapHandler {
    onTapped: root.toggled()
  }

  Row {
    id: inner
    // Sized from the row rather than its own children, so the text column
    // can claim the remaining space without a binding loop.
    width: parent.width - Style.spacing.rowPaddingX
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.md

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(54)
      height: Style.space(36)
      color: root.entry ? root.entry.coverColor : "#1b1b1b"
      clip: true

      Image {
        anchors.fill: parent
        source: root.entry ? root.entry.coverUrl : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: Style.space(54) * 2
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: inner.width - Style.space(54) - Style.space(20) - Style.spacing.md * 2
      spacing: Style.spacing.xxs

      Text {
        width: parent.width
        text: root.entry ? root.entry.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: {
          if (!root.entry) return ""
          var line = root.entry.totalPhotos + " photos"
          if (root.entry.curator && root.entry.curator !== "") line += " · " + root.entry.curator
          return line
        }
        color: root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.picked ? "󰄬" : "󰝦"
      color: root.picked ? root.foreground : root.faint
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
