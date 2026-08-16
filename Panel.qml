import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Unsplash Wallpapers — a bar widget that browses Unsplash and applies photos
// as the Omarchy background, modelled on Unsplash's own menu bar app.
//
// The widget itself is the popup owner (the tailscale/agents pattern): one
// QML file holds both the bar button and the KeyboardPanel it anchors, so the
// bar's popout coordinator tracks a single item.
Panel {
  id: root
  moduleName: "wr.unsplash-wallpapers"
  ipcTarget: "unsplash"
  manageIpc: false

  // ---------------------------------------------------------------- config
  //
  // Persisted config lives in ~/.local/state/omarchy/settings/unsplash.json,
  // written by bin/uw-config and watched here, so edits from either side
  // converge without a restart.
  property var config: Model.defaultConfig()
  readonly property string accessKey: String(config.accessKey || "")
  readonly property bool configured: accessKey.length > 0
  readonly property string orientation: String(config.orientation || "landscape")
  readonly property int rotateMinutes: parseInt(config.rotateMinutes, 10) || 0

  readonly property int columns: Math.max(2, parseInt(setting("columns", 3), 10) || 3)
  readonly property int perPage: Math.max(6, parseInt(setting("perPage", 12), 10) || 12)

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")

  // ----------------------------------------------------------- browse state
  property string source: "topic:wallpapers"
  property string query: ""
  property var photos: []
  property int cursorIndex: 0
  property bool cursorActive: false
  property bool loading: false
  property string errorText: ""

  // Feed cache: the demo API tier allows 50 requests/hour, so reopening the
  // panel reuses the last response for a source until it goes stale.
  property string cacheKey: ""
  property double fetchedAt: 0
  property bool refetchQueued: false
  readonly property int cacheTtlMs: 10 * 60 * 1000

  // Attribution for the photo currently on screen, restored from disk so it
  // survives a shell restart.
  property var appliedPhoto: null
  readonly property string appliedId: appliedPhoto ? String(appliedPhoto.id || "") : ""

  property bool setupOpen: false
  property bool searchOpen: false
  // Set the next successfully fetched photo as the wallpaper. Used when a
  // rotation fires with no feed loaded yet.
  property bool applyAfterFetch: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 2.0)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var cursorPhoto: photos.length > 0
    ? photos[Math.max(0, Math.min(cursorIndex, photos.length - 1))]
    : null
  // The footer describes whatever the eye is on: the grid cursor while
  // browsing, otherwise the photo actually in use.
  readonly property var footerPhoto: (cursorActive && cursorPhoto) ? cursorPhoto : (appliedPhoto || cursorPhoto)

  // Native pixel width of the screen showing the panel — what the wallpaper
  // is downloaded at, so a HiDPI display is not handed a logical-size image.
  readonly property int targetWidth: {
    var screen = panel.screen
    if (!screen) return 2560
    var dpr = screen.devicePixelRatio || 1
    return Math.max(1280, Math.round(screen.width * dpr))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ------------------------------------------------------------- lifecycle
  onOpenedChanged: {
    if (!opened) return
    cursorActive = false
    setupOpen = !configured
    if (panelFlick) panelFlick.contentY = 0
    fetch(false)
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function pluginBin(name) {
    return pluginDir + "bin/" + name
  }

  function saveConfig(key, value) {
    configProc.command = [pluginBin("uw-config"), "set", key, String(value)]
    configProc.running = true
  }

  // ----------------------------------------------------------------- fetch
  function fetch(force) {
    if (!configured) return

    var key = source + "|" + (source === "search" ? query : "")
    if (source === "search" && query.replace(/^\s+|\s+$/g, "") === "") {
      photos = []
      return
    }

    var fresh = cacheKey === key && photos.length > 0
      && (Date.now() - fetchedAt) < cacheTtlMs
    // Shuffle is never cached — asking for it again means wanting new photos.
    if (!force && fresh && source !== "random") return

    if (feedProc.running) {
      // A source switch mid-flight queues one refetch rather than racing two
      // curls whose responses could arrive out of order.
      refetchQueued = true
      return
    }

    loading = true
    errorText = ""
    feedProc.command = ["curl", "-sS", "--max-time", "15",
      "-H", "Authorization: Client-ID " + accessKey,
      "-w", "\n__HTTP__%{http_code}",
      Model.endpointFor(source, query, 1, perPage, orientation)]
    feedProc.running = true
  }

  function selectSource(id) {
    if (id !== "search") searchOpen = false
    source = id
    cursorIndex = 0
    cursorActive = false
    saveConfig("source", id)
    fetch(false)
  }

  function commitSearch() {
    var text = searchField.text.replace(/^\s+|\s+$/g, "")
    query = text
    saveConfig("query", text)
    if (text === "") {
      selectSource("topic:wallpapers")
      return
    }
    source = "search"
    cursorIndex = 0
    saveConfig("source", "search")
    fetch(true)
  }

  function openSearch() {
    searchOpen = true
    Qt.callLater(function() {
      searchField.text = root.query
      searchField.selectAll()
      searchField.forceActiveFocus()
    })
  }

  function closeSearch() {
    searchOpen = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // --------------------------------------------------------------- apply
  function setWallpaper(photo) {
    if (!photo || !photo.rawUrl) return

    appliedPhoto = photo
    setProc.command = [pluginBin("uw-set-wallpaper"),
      "--id", String(photo.id),
      "--url", Model.wallpaperUrl(photo.rawUrl, targetWidth),
      "--width", String(targetWidth),
      "--author", String(photo.authorName || ""),
      "--author-username", String(photo.authorUsername || ""),
      "--link", String(photo.htmlLink || ""),
      "--download-location", String(photo.downloadLocation || ""),
      "--key", accessKey,
      "--keep", String(parseInt(config.keep, 10) || 10)]
    setProc.running = true
  }

  // Pick a photo from the loaded feed rather than spending an API request —
  // the browsing feed is already a fresh, source-filtered pool.
  function shuffle() {
    if (!configured) return
    if (photos.length === 0) {
      applyAfterFetch = true
      fetch(true)
      return
    }
    // Refresh a stale pool in the background so a long-running rotation does
    // not keep recycling the same page all day.
    if ((Date.now() - fetchedAt) > 6 * 60 * 60 * 1000) fetch(true)

    var candidates = []
    for (var i = 0; i < photos.length; i++) {
      if (String(photos[i].id) !== appliedId) candidates.push(photos[i])
    }
    if (candidates.length === 0) candidates = photos
    setWallpaper(candidates[Math.floor(Math.random() * candidates.length)])
  }

  function cycleRotation() {
    var next = Model.nextRotateMinutes(rotateMinutes)
    config = Object.assign({}, config, { rotateMinutes: next })
    saveConfig("rotateMinutes", next)
  }

  function cycleOrientation() {
    var order = ["landscape", "portrait", "squarish"]
    var next = order[(order.indexOf(orientation) + 1) % order.length]
    config = Object.assign({}, config, { orientation: next })
    saveConfig("orientation", next)
    fetch(true)
  }

  function saveAccessKey() {
    var value = keyField.text.replace(/^\s+|\s+$/g, "")
    if (value === "") return
    config = Object.assign({}, config, { accessKey: value })
    saveConfig("accessKey", value)
    setupOpen = false
    errorText = ""
    Qt.callLater(function() {
      if (keyCatcher) keyCatcher.forceActiveFocus()
      root.fetch(true)
    })
  }

  function openUrl(url) {
    if (!url || !bar) return
    bar.run("xdg-open " + bar.shellQuote(Model.withUtm(url)))
  }

  // ------------------------------------------------------------ processes
  FileView {
    id: configFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/unsplash.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.config = Model.parseConfig(text())
      if (root.source === "topic:wallpapers" && root.config.source) root.source = String(root.config.source)
      if (root.query === "") root.query = String(root.config.query || "")
    }
    onLoadFailed: root.config = Model.defaultConfig()
  }

  FileView {
    id: appliedFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/unsplash-current.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text())
        if (data && data.id) {
          root.appliedPhoto = {
            id: String(data.id),
            authorName: String(data.author || ""),
            authorUsername: String(data.username || ""),
            htmlLink: String(data.link || ""),
            rawUrl: "",
            thumbUrl: ""
          }
        }
      } catch (e) {
        // No applied photo yet, or a partially written file — the footer
        // simply falls back to the grid cursor.
      }
    }
  }

  Process {
    id: feedProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var response = Model.parseHttp(text)
        root.loading = false

        if (response.status !== 200) {
          root.errorText = Model.errorFor(response.status, response.body)
          return
        }

        var list = Model.normalizePhotos(response.body)
        if (list.length === 0) {
          root.errorText = "No photos came back for this source."
          return
        }

        root.photos = list
        root.cursorIndex = 0
        root.errorText = ""
        root.cacheKey = root.source + "|" + (root.source === "search" ? root.query : "")
        root.fetchedAt = Date.now()

        if (root.applyAfterFetch) {
          root.applyAfterFetch = false
          root.setWallpaper(list[Math.floor(Math.random() * list.length)])
        }
      }
    }
    onExited: function(exitCode) {
      root.loading = false
      // curl could not run or the transfer failed outright; the collector
      // above never saw a status line to report.
      if (exitCode !== 0 && root.errorText === "") root.errorText = Model.errorFor(0, "")
      if (root.refetchQueued) {
        root.refetchQueued = false
        Qt.callLater(function() { root.fetch(true) })
      }
    }
  }

  Process { id: setProc }
  Process { id: configProc }

  Timer {
    id: rotateTimer
    interval: Math.max(1, root.rotateMinutes) * 60 * 1000
    running: root.rotateMinutes > 0
    repeat: true
    onTriggered: root.shuffle()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function shuffle(): string { root.shuffle(); return "ok" }
    function refresh(): string { root.fetch(true); return "ok" }
  }

  // ----------------------------------------------------------- bar button
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰸉"
    tooltipText: root.opened ? "" : "Unsplash wallpapers"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.shuffle()
      else if (buttonCode === Qt.MiddleButton) root.fetch(true)
      else root.toggle()
    }
  }

  // ----------------------------------------------------------------- panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || keyField.activeFocus

      onMoveRequested: function(dx, dy) {
        if (root.photos.length === 0) return
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        root.cursorIndex = Model.moveCursor(root.cursorIndex, dx, dy, root.photos.length, root.columns)
      }
      onActivateRequested: if (root.cursorActive && root.cursorPhoto) root.setWallpaper(root.cursorPhoto)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "/") root.openSearch()
        else if (t === "r" || t === "R") root.fetch(true)
        else if (t === "s" || t === "S") root.shuffle()
        else if (t === "o" || t === "O") root.openUrl(root.footerPhoto ? root.footerPhoto.htmlLink : "")
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: panelFlick.width
          spacing: Style.spacing.xl

          // ---- header ------------------------------------------------
          Item {
            width: parent.width
            height: Math.max(titleRow.implicitHeight, headerActions.implicitHeight)

            Row {
              id: titleRow
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.md

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "UNSPLASH"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                font.letterSpacing: 1.5
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.configured && !root.setupOpen
                text: Model.labelForSource(root.source, root.query)
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              id: headerActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.loading
                text: "󰦖"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall

                RotationAnimator on rotation {
                  running: root.loading
                  from: 0
                  to: 360
                  duration: 900
                  loops: Animation.Infinite
                }
              }

              PanelActionButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.configured
                iconText: ""
                tooltipText: "Search photos  (/)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.searchOpen ? root.closeSearch() : root.openSearch()
              }

              PanelActionButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.configured
                iconText: "󰑐"
                tooltipText: "Reload this source  (r)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.fetch(true)
              }

              PanelActionButton {
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰒓"
                tooltipText: "Settings"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: {
                  root.setupOpen = !root.setupOpen
                  if (root.setupOpen) Qt.callLater(function() {
                    keyField.text = root.accessKey
                    keyField.forceActiveFocus()
                  })
                }
              }
            }
          }

          // ---- setup / settings card ---------------------------------
          Column {
            width: parent.width
            visible: root.setupOpen
            spacing: Style.spacing.lg

            PanelSeparator { foreground: root.foreground }

            Text {
              width: parent.width
              text: root.configured
                ? "Your Unsplash access key. Replace it if you rotate the key on unsplash.com."
                : "Unsplash needs a free access key. Create an app on unsplash.com — a demo app allows 50 requests an hour — then paste its Access Key here."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md

              TextField {
                id: keyField
                width: parent.width - saveKeyButton.implicitWidth - Style.spacing.md
                placeholderText: "Access Key"
                foreground: root.foreground
                font.family: root.fontFamily

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.saveAccessKey()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Escape) {
                    root.setupOpen = false
                    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                    event.accepted = true
                  }
                }
              }

              Button {
                id: saveKeyButton
                anchors.verticalCenter: parent.verticalCenter
                text: "Save"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.saveAccessKey()
              }
            }

            Row {
              spacing: Style.spacing.md

              Button {
                text: "Get a key"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.openUrl("https://unsplash.com/oauth/applications")
              }

              Button {
                text: "Orientation: " + root.orientation
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.cycleOrientation()
              }
            }
          }

          // ---- source chips -------------------------------------------
          Flow {
            width: parent.width
            visible: root.configured && !root.setupOpen
            spacing: Style.spacing.sm

            Repeater {
              model: Model.sources()

              Button {
                required property var modelData
                text: modelData.label
                selected: root.source === modelData.id
                bordered: root.source === modelData.id
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.spacing.sm
                onClicked: {
                  if (modelData.id === "random") {
                    root.source = "random"
                    root.saveConfig("source", "random")
                    root.fetch(true)
                  } else {
                    root.selectSource(modelData.id)
                  }
                }
              }
            }
          }

          // ---- search field -------------------------------------------
          TextField {
            id: searchField
            width: parent.width
            visible: root.configured && !root.setupOpen && root.searchOpen
            placeholderText: "Search Unsplash…"
            foreground: root.foreground
            font.family: root.fontFamily

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.commitSearch()
                root.closeSearch()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                root.closeSearch()
                event.accepted = true
              }
            }
          }

          // ---- error --------------------------------------------------
          Text {
            width: parent.width
            visible: root.errorText !== "" && !root.setupOpen
            text: root.errorText
            color: bar ? bar.urgent : Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ---- photo grid ---------------------------------------------
          Grid {
            id: photoGrid
            width: parent.width
            visible: root.configured && !root.setupOpen && root.photos.length > 0
            columns: root.columns
            spacing: Style.spacing.sm

            readonly property int cellW: Model.cellWidth(width, root.columns, spacing)
            readonly property int cellH: Model.cellHeight(cellW)

            Repeater {
              model: root.photos

              Rectangle {
                id: cell
                required property var modelData
                required property int index

                width: photoGrid.cellW
                height: photoGrid.cellH
                // Unsplash ships each photo's dominant color; using it as the
                // cell background means the grid reads as photos immediately
                // instead of flashing empty boxes.
                color: modelData.color
                clip: true

                readonly property bool hot: cellMouse.containsMouse
                  || (root.cursorActive && root.cursorIndex === cell.index)
                readonly property bool isApplied: root.appliedId !== "" && String(modelData.id) === root.appliedId

                Image {
                  anchors.fill: parent
                  source: modelData.thumbUrl
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                  sourceSize.width: photoGrid.cellW * 2
                  opacity: status === Image.Ready ? 1 : 0

                  Behavior on opacity {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                  }
                }

                // Hover scrim + hint, so a cell reads as clickable.
                Rectangle {
                  anchors.fill: parent
                  visible: cell.hot
                  color: Qt.rgba(0, 0, 0, 0.45)

                  Text {
                    anchors.centerIn: parent
                    text: cell.isApplied ? "Current" : "Set"
                    color: "white"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                // Badge on the photo currently in use.
                Rectangle {
                  visible: cell.isApplied && !cell.hot
                  anchors.top: parent.top
                  anchors.right: parent.right
                  width: Style.space(16)
                  height: Style.space(16)
                  color: Qt.rgba(0, 0, 0, 0.55)

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
                  border.width: cell.hot ? Math.max(1, Style.space(2)) : 0
                  border.color: Style.hoverStateColor(root.foreground, Color.accent)
                }

                MouseArea {
                  id: cellMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton

                  onContainsMouseChanged: if (containsMouse) {
                    root.cursorActive = true
                    root.cursorIndex = cell.index
                  }
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) root.openUrl(cell.modelData.htmlLink)
                    else root.setWallpaper(cell.modelData)
                  }
                }
              }
            }
          }

          // ---- empty state --------------------------------------------
          Text {
            width: parent.width
            visible: root.configured && !root.setupOpen && root.photos.length === 0
              && !root.loading && root.errorText === ""
            text: "Nothing loaded yet."
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
          }

          // ---- footer --------------------------------------------------
          Column {
            width: parent.width
            visible: root.configured && !root.setupOpen
            spacing: Style.spacing.lg

            PanelSeparator { foreground: root.foreground }

            Item {
              width: parent.width
              height: Math.max(credit.implicitHeight, footerActions.implicitHeight)

              // Attribution, as Unsplash's API guidelines require. Clicking
              // opens the photo page with the referral parameters attached.
              Row {
                id: credit
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - footerActions.width - Style.spacing.md
                spacing: Style.spacing.sm
                visible: !!root.footerPhoto

                TapHandler {
                  onTapped: root.openUrl(root.footerPhoto ? root.footerPhoto.htmlLink : "")
                }
                HoverHandler {
                  cursorShape: Qt.PointingHandCursor
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰋩"
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: credit.width - Style.space(24)
                  text: Model.attributionText(root.footerPhoto)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Row {
                id: footerActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.sm

                Button {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Auto: " + Model.rotateLabel(root.rotateMinutes)
                  tooltipText: "How often to switch to another photo from this source"
                  bordered: true
                  selected: root.rotateMinutes > 0
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  verticalPadding: Style.spacing.sm
                  onClicked: root.cycleRotation()
                }

                Button {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Shuffle"
                  tooltipText: "Set a random photo from this source  (s)"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  verticalPadding: Style.spacing.sm
                  onClicked: root.shuffle()
                }
              }
            }
          }
        }
      }
    }
  }
}
