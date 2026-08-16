import QtQuick
import qs.Commons
import qs.Ui

// One tile in the curated grid: a photo from the collection, its name, and a
// checkmark once it is feeding your wallpapers.
//
// Taps go through TapHandler rather than MouseArea because this grid lives in
// a scrolling Flickable, which steals a MouseArea's click on any pointer drift.
Rectangle {
  id: root

  // { id, label, title, totalPhotos, coverUrl, coverColor, curator }
  property var entry: null
  property bool picked: false
  property bool hasCursor: false

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal toggled()
  signal hoveredIn()

  readonly property bool hot: hover.hovered || hasCursor

  color: entry ? entry.coverColor : "#1b1b1b"
  clip: true

  HoverHandler {
    id: hover
    cursorShape: Qt.PointingHandCursor
    onHoveredChanged: if (hovered) root.hoveredIn()
  }

  TapHandler {
    onTapped: root.toggled()
  }

  Image {
    anchors.fill: parent
    source: root.entry ? root.entry.coverUrl : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    sourceSize.width: root.width * 2
    opacity: status === Image.Ready ? 1 : 0

    Behavior on opacity {
      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
  }

  // Unselected tiles are dimmed so the chosen ones read at a glance.
  Rectangle {
    anchors.fill: parent
    color: "black"
    opacity: root.picked ? 0 : (root.hot ? 0.15 : 0.35)

    Behavior on opacity {
      NumberAnimation { duration: 120 }
    }
  }

  // Keeps the label legible over a bright photo.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Math.round(parent.height * 0.5)

    gradient: Gradient {
      GradientStop { position: 0.0; color: "transparent" }
      GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.75) }
    }
  }

  Text {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.sm
    text: root.entry ? root.entry.label : ""
    color: "white"
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    elide: Text.ElideRight
  }

  // Selection badge.
  Rectangle {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.spacing.sm
    width: Style.space(18)
    height: width
    radius: width / 2
    visible: root.picked
    color: Qt.rgba(0, 0, 0, 0.6)

    Text {
      anchors.centerIn: parent
      text: "󰄬"
      color: "white"
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    border.width: (root.picked || root.hot) ? Math.max(1, Style.space(2)) : 0
    border.color: root.picked
      ? Style.selectedStateColor(root.foreground, Color.accent)
      : Style.hoverStateColor(root.foreground, Color.accent)
  }
}
