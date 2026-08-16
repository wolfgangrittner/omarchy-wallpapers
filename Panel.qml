import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Unsplash Wallpapers — a bar widget that puts Unsplash in the top-right
// corner, modelled on Unsplash's own menu bar app.
//
// Three panes:
//   Home         a photo on show — click it to draw another, Set to apply it
//   Collections  browse/search collections and choose which ones feed Home
//   History      every photo shown so far; click one to bring it back
//
// Drawing and applying are deliberately separate: the hero holds a candidate
// that only becomes the wallpaper when Set is pressed, so cycling through
// photos never touches the desktop.
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
  readonly property var selectedCollections: config.collections instanceof Array ? config.collections : []

  readonly property int columns: Math.max(2, parseInt(setting("columns", 3), 10) || 3)
  readonly property int perPage: Math.max(6, parseInt(setting("perPage", 20), 10) || 20)

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")

  // ------------------------------------------------------------------ panes
  property string pane: "home"
  property bool setupOpen: false

  // -------------------------------------------------------------- pane data
  //
  // `previewPhoto` is the candidate on show in Home. It is null until the
  // user draws one, so opening the panel starts on the wallpaper in use.
  property var previewPhoto: null
  property var appliedPhoto: null
  readonly property var heroPhoto: previewPhoto || appliedPhoto
  readonly property bool heroIsApplied: !!heroPhoto && appliedId !== ""
    && String(heroPhoto.id) === appliedId
  readonly property bool canSet: !!heroPhoto && !heroIsApplied && !applying && !drawing

  property var history: []
  property var collections: []
  property string collectionQuery: ""
  property double collectionsFetchedAt: 0
  readonly property int collectionsTtlMs: 30 * 60 * 1000

  // ------------------------------------------------------------- status
  // Drawing a photo and applying one are separate actions now, so they get
  // separate flags: the hero spins while drawing, and dims while applying.
  property bool drawing: false
  property bool applying: false
  property bool loadingCollections: false
  property string errorText: ""

  // ------------------------------------------------------------- cursors
  property bool cursorActive: false
  property int historyIndex: 0
  property int collectionIndex: 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 2.0)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string appliedId: appliedPhoto ? String(appliedPhoto.id || "") : ""

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
    errorText = ""
    setupOpen = !configured
    if (panelFlick) panelFlick.contentY = 0
    if (pane === "collections") fetchCollections(false)
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  onPaneChanged: {
    cursorActive = false
    errorText = ""
    if (panelFlick) panelFlick.contentY = 0
    if (pane === "collections") fetchCollections(false)
  }

  function pluginBin(name) {
    return pluginDir + "bin/" + name
  }

  function saveConfig(key, value) {
    configProc.command = [pluginBin("uw-config"), "set", key, String(value)]
    configProc.running = true
  }

  function saveConfigJson(key, value) {
    configProc.command = [pluginBin("uw-config"), "setjson", key, JSON.stringify(value)]
    configProc.running = true
  }

  function openUrl(url) {
    if (!url) return
    Util.execDetached("xdg-open " + Util.shellQuote(Model.withUtm(url)))
  }

  // ------------------------------------------------------------- new photo
  //
  // One request per draw: ask the random endpoint for a single photo from the
  // selected collections. The result only goes on show — applying it is a
  // separate, explicit step.
  function newPhoto() {
    if (!configured || drawing) return
    drawing = true
    errorText = ""
    randomProc.command = ["curl", "-sS", "--max-time", "15",
      "-H", "Authorization: Client-ID " + accessKey,
      "-w", "\n__HTTP__%{http_code}",
      Model.randomEndpoint(selectedCollections, orientation)]
    randomProc.running = true
  }

  // Every photo shown is logged, applied or not, so History is a record of
  // everything seen rather than only what made it to the desktop.
  function recordShown(photo) {
    if (!photo) return
    historyProc.command = [pluginBin("uw-history"), "add",
      "--id", String(photo.id),
      "--author", String(photo.authorName || ""),
      "--username", String(photo.authorUsername || ""),
      "--link", String(photo.htmlLink || ""),
      "--preview", String(photo.previewUrl || ""),
      "--raw", String(photo.rawUrl || ""),
      "--max", String(parseInt(config.historyMax, 10) || 200)]
    historyProc.running = true
  }

  // Put the photo on show in Home without touching the wallpaper.
  function showPhoto(photo) {
    if (!photo) return
    previewPhoto = photo
    pane = "home"
  }

  // History is a one-click path back to a photo: apply it and get out of the
  // way. The hero follows along so reopening the panel shows what was set.
  function applyFromHistory(photo) {
    if (!photo) return
    previewPhoto = photo
    applyPhoto(photo)
    close()
  }

  function applyPhoto(photo) {
    if (!photo || !photo.rawUrl) return
    applying = true
    setProc.command = [pluginBin("uw-set-wallpaper"),
      "--id", String(photo.id),
      "--url", Model.wallpaperUrl(photo.rawUrl, targetWidth),
      "--raw-url", String(photo.rawUrl),
      "--preview", String(photo.previewUrl || ""),
      "--width", String(targetWidth),
      "--author", String(photo.authorName || ""),
      "--author-username", String(photo.authorUsername || ""),
      "--link", String(photo.htmlLink || ""),
      "--download-location", String(photo.downloadLocation || ""),
      "--key", accessKey,
      "--keep", String(parseInt(config.keep, 10) || 10)]
    setProc.running = true
  }

  // ----------------------------------------------------------- collections
  function fetchCollections(force) {
    if (!configured || loadingCollections) return
    var fresh = collections.length > 0 && (Date.now() - collectionsFetchedAt) < collectionsTtlMs
    if (!force && fresh) return

    loadingCollections = true
    errorText = ""
    collectionsProc.command = ["curl", "-sS", "--max-time", "15",
      "-H", "Authorization: Client-ID " + accessKey,
      "-w", "\n__HTTP__%{http_code}",
      Model.collectionsEndpoint(collectionQuery, perPage)]
    collectionsProc.running = true
  }

  function searchCollections() {
    collectionQuery = collectionField.text.replace(/^\s+|\s+$/g, "")
    collections = []
    collectionIndex = 0
    fetchCollections(true)
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function toggleCollection(collection) {
    if (!collection) return
    var next = Model.toggleCollection(selectedCollections, collection)
    config = Object.assign({}, config, { collections: next })
    saveConfigJson("collections", next)
  }

  function clearCollections() {
    config = Object.assign({}, config, { collections: [] })
    saveConfigJson("collections", [])
  }

  // -------------------------------------------------------------- settings
  function cycleOrientation() {
    var order = ["landscape", "portrait", "squarish"]
    var next = order[(order.indexOf(orientation) + 1) % order.length]
    config = Object.assign({}, config, { orientation: next })
    saveConfig("orientation", next)
  }

  function saveAccessKey() {
    var value = keyField.text.replace(/^\s+|\s+$/g, "")
    if (value === "") return
    config = Object.assign({}, config, { accessKey: value })
    saveConfig("accessKey", value)
    setupOpen = false
    errorText = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // ------------------------------------------------------------ cursor nav
  function moveCursor(dx, dy) {
    if (pane === "history") {
      if (history.length === 0) return
      historyIndex = Model.moveCursor(historyIndex, dx, dy, history.length, columns)
    } else if (pane === "collections") {
      if (collections.length === 0) return
      // A single-column list: vertical movement only.
      collectionIndex = Model.moveCursor(collectionIndex, 0, dy !== 0 ? dy : dx, collections.length, 1)
    }
  }

  function activateCursor() {
    if (pane === "history" && history.length > 0) {
      applyFromHistory(history[Math.max(0, Math.min(historyIndex, history.length - 1))])
    } else if (pane === "collections" && collections.length > 0) {
      toggleCollection(collections[Math.max(0, Math.min(collectionIndex, collections.length - 1))])
    } else if (pane === "home") {
      // Enter applies what is on show; `n` draws another.
      if (heroPhoto && !heroIsApplied) applyPhoto(heroPhoto)
    }
  }

  // ------------------------------------------------------------ file state
  FileView {
    id: configFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/unsplash.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.config = Model.parseConfig(text())
    onLoadFailed: root.config = Model.defaultConfig()
  }

  FileView {
    id: appliedFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/unsplash-current.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.appliedPhoto = Model.parseCurrent(text())
    onLoadFailed: root.appliedPhoto = null
  }

  FileView {
    id: historyFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/unsplash-history.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.history = Model.parseHistory(text())
    onLoadFailed: root.history = []
  }

  // -------------------------------------------------------------- processes
  Process {
    id: randomProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var response = Model.parseHttp(text)
        root.drawing = false

        if (response.status !== 200) {
          root.errorText = Model.randomErrorFor(response.status, response.body,
            root.selectedCollections.length > 0)
          return
        }
        var photos = Model.normalizePhotos(response.body)
        if (photos.length === 0) {
          root.errorText = "Unsplash returned no photo. Try again."
          return
        }

        root.previewPhoto = photos[0]
        root.recordShown(photos[0])
      }
    }
    onExited: function(exitCode) {
      root.drawing = false
      // curl itself failed, so the collector never saw a status line.
      if (exitCode !== 0 && root.errorText === "") root.errorText = Model.errorFor(0, "")
    }
  }

  Process {
    id: collectionsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var response = Model.parseHttp(text)
        root.loadingCollections = false
        if (response.status !== 200) {
          root.errorText = Model.errorFor(response.status, response.body)
          return
        }
        root.collections = Model.normalizeCollections(response.body)
        root.collectionIndex = 0
        root.collectionsFetchedAt = Date.now()
        if (root.collections.length === 0) root.errorText = "No collections matched that search."
      }
    }
    onExited: function(exitCode) {
      root.loadingCollections = false
      if (exitCode !== 0 && root.errorText === "") root.errorText = Model.errorFor(0, "")
    }
  }

  Process {
    id: setProc
    onExited: function(exitCode) {
      root.applying = false
      if (exitCode !== 0) root.errorText = "Could not apply that wallpaper."
    }
  }

  Process { id: configProc }
  Process { id: historyProc }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function next(): string { root.newPhoto(); return "ok" }
    function shuffle(): string { root.newPhoto(); return "ok" }
    function set(): string {
      if (!root.heroPhoto) return "nothing on show"
      root.applyPhoto(root.heroPhoto)
      return "ok"
    }

    // Open the panel straight onto one pane, so a keybinding can jump to
    // History or Collections without clicking through Home.
    function showPane(name: string): string {
      var target = String(name || "").toLowerCase()
      if (target !== "home" && target !== "collections" && target !== "history") return "unknown pane"
      root.pane = target
      root.setupOpen = false
      root.open()
      return "ok"
    }
  }

  // ----------------------------------------------------------- bar button
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰸉"
    tooltipText: root.opened ? "" : "Unsplash wallpapers"

    onPressed: function(buttonCode) {
      // Right-click draws a photo and opens the panel to show it. It must
      // not apply anything: the wallpaper only ever changes via Set.
      if (buttonCode === Qt.RightButton) {
        root.pane = "home"
        root.open()
        root.newPhoto()
      } else {
        root.toggle()
      }
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
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(660))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: keyField.activeFocus || collectionField.activeFocus

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "n" || t === "N") root.newPhoto()
        else if (t === "1") root.pane = "home"
        else if (t === "2") root.pane = "collections"
        else if (t === "3") root.pane = "history"
        else if (t === "o" || t === "O") root.openUrl(root.appliedPhoto ? root.appliedPhoto.htmlLink : "")
        else if (t === "/" && root.pane === "collections") collectionField.forceActiveFocus()
        else if (t === "r" || t === "R") {
          if (root.pane === "collections") root.fetchCollections(true)
        }
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

          // ================================================ header
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
                text: Model.selectionSummary(root.selectedCollections)
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: Math.min(implicitWidth, Style.space(190))
              }
            }

            Row {
              id: headerActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.drawing || root.applying || root.loadingCollections
                text: "󰦖"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall

                RotationAnimator on rotation {
                  running: root.drawing || root.applying || root.loadingCollections
                  from: 0
                  to: 360
                  duration: 900
                  loops: Animation.Infinite
                }
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

          // ================================================ tabs
          Row {
            width: parent.width
            visible: root.configured && !root.setupOpen
            spacing: Style.spacing.sm

            Repeater {
              model: [
                { id: "home", label: "Home" },
                { id: "collections", label: "Collections" },
                { id: "history", label: "History" }
              ]

              Button {
                required property var modelData
                text: modelData.label
                selected: root.pane === modelData.id
                bordered: root.pane === modelData.id
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.spacing.sm
                onClicked: root.pane = modelData.id
              }
            }
          }

          // ================================================ settings card
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
                tooltipText: "Opens unsplash.com/oauth/applications"
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

          // ================================================ error
          Text {
            width: parent.width
            visible: root.errorText !== "" && !root.setupOpen
            text: root.errorText
            color: bar ? bar.urgent : Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ================================================ HOME pane
          Column {
            width: parent.width
            visible: root.configured && !root.setupOpen && root.pane === "home"
            spacing: Style.spacing.lg

            // The photo on show — the wallpaper in use until a new one is
            // drawn. Clicking anywhere on it draws another.
            Rectangle {
              id: hero
              width: parent.width
              height: Math.round(width * 0.625)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
              clip: true

              property bool fellBack: false

              Image {
                id: heroImage
                anchors.fill: parent
                source: Model.heroSource(root.heroPhoto)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: hero.width * 2
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity {
                  NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                // The local copy is preferred, but pruning eventually removes
                // it; fall back to the CDN preview rather than showing a hole.
                onStatusChanged: {
                  if (status !== Image.Error || hero.fellBack) return
                  var preview = root.heroPhoto ? String(root.heroPhoto.previewUrl || "") : ""
                  if (preview === "") return
                  hero.fellBack = true
                  source = preview
                }
              }

              Connections {
                target: root
                function onHeroPhotoChanged() { hero.fellBack = false }
              }

              Text {
                anchors.centerIn: parent
                width: parent.width - Style.space(40)
                visible: !root.heroPhoto && !root.drawing
                text: "Nothing on show yet.\nClick here to pull a photo from Unsplash."
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
              }

              // Marks the photo already on the desktop, so it is obvious
              // whether the hero is the wallpaper or a candidate for it.
              Rectangle {
                visible: root.heroIsApplied && !!root.heroPhoto
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.spacing.sm
                width: currentLabel.implicitWidth + Style.spacing.lg
                height: currentLabel.implicitHeight + Style.spacing.sm
                color: Qt.rgba(0, 0, 0, 0.55)

                Text {
                  id: currentLabel
                  anchors.centerIn: parent
                  text: "CURRENT"
                  color: "white"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
              }

              // Dim the photo while it is being downloaded and applied.
              Rectangle {
                anchors.fill: parent
                visible: root.applying
                color: Qt.rgba(0, 0, 0, 0.5)
              }

              // The draw-another affordance: a circular arrow over the middle
              // of the image. The whole image is the click target; this just
              // makes that discoverable.
              Rectangle {
                id: refreshBadge
                anchors.centerIn: parent
                width: Style.space(58)
                height: width
                radius: width / 2
                color: Qt.rgba(0, 0, 0, heroMouse.containsMouse ? 0.62 : 0.42)
                opacity: root.applying ? 0 : 1

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on opacity { NumberAnimation { duration: 120 } }

                scale: heroMouse.containsMouse ? 1.06 : 1.0
                Behavior on scale {
                  NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }

                Text {
                  id: refreshGlyph
                  anchors.centerIn: parent
                  text: "󰑐"
                  color: "white"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display

                  RotationAnimator on rotation {
                    running: root.drawing
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                  }
                }
              }

              MouseArea {
                id: heroMouse
                anchors.fill: parent
                enabled: !root.drawing && !root.applying
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.newPhoto()
              }
            }

            // Attribution, as Unsplash's API guidelines require.
            Row {
              width: parent.width
              spacing: Style.spacing.sm
              visible: !!root.heroPhoto

              TapHandler {
                onTapped: root.openUrl(root.heroPhoto ? root.heroPhoto.htmlLink : "")
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
                width: parent.width - Style.space(24)
                text: Model.attributionText(root.heroPhoto)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            Row {
              width: parent.width
              spacing: Style.spacing.sm

              Button {
                text: "Set as wallpaper"
                tooltipText: root.heroIsApplied
                  ? "Already your wallpaper"
                  : "Put this photo on the desktop  (Enter)"
                bordered: true
                enabled: root.canSet
                // Button has no disabled paint of its own, so dim the label
                // to keep "already your wallpaper" from looking clickable.
                foreground: root.canSet ? root.foreground : root.faint
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.spacing.md
                onClicked: root.applyPhoto(root.heroPhoto)
              }

              Button {
                visible: !!root.heroPhoto
                text: "Open ↗"
                tooltipText: "Open this photo on unsplash.com  (o)"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.spacing.md
                onClicked: root.openUrl(root.heroPhoto ? root.heroPhoto.htmlLink : "")
              }
            }
          }

          // ================================================ COLLECTIONS pane
          Column {
            width: parent.width
            visible: root.configured && !root.setupOpen && root.pane === "collections"
            spacing: Style.spacing.lg

            Text {
              width: parent.width
              text: "Photos are drawn from the collections you select here."
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md

              TextField {
                id: collectionField
                width: parent.width - clearButton.implicitWidth - Style.spacing.md
                placeholderText: "Search collections…"
                foreground: root.foreground
                font.family: root.fontFamily

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.searchCollections()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Escape) {
                    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                    event.accepted = true
                  }
                }
              }

              Button {
                id: clearButton
                anchors.verticalCenter: parent.verticalCenter
                text: "Clear"
                tooltipText: "Deselect every collection and use all of Unsplash"
                bordered: true
                enabled: root.selectedCollections.length > 0
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.spacing.sm
                onClicked: root.clearCollections()
              }
            }

            // Selected collections are pinned here so a choice made from an
            // earlier search stays visible and removable after the list moves on.
            Column {
              width: parent.width
              visible: root.selectedCollections.length > 0
              spacing: Style.spacing.sm

              PanelSectionHeader {
                text: "SELECTED"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: root.selectedCollections

                Rectangle {
                  required property var modelData
                  width: parent.width
                  height: selectedRow.implicitHeight + Style.spacing.lg
                  color: Style.selectedFillFor(root.foreground, Color.accent)

                  Row {
                    id: selectedRow
                    x: Style.spacing.rowPaddingX
                    // Width is set from the row rectangle, never from this
                    // Row's own children — a Row sizes itself from them, so
                    // a child binding back to parent.width would loop.
                    width: parent.width - Style.spacing.rowPaddingX * 2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.md

                    Text {
                      id: selectedCheck
                      anchors.verticalCenter: parent.verticalCenter
                      text: "󰄬"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: selectedRow.width - selectedCheck.width - Style.spacing.md
                      text: modelData.title
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleCollection(modelData)
                  }
                }
              }
            }

            PanelSectionHeader {
              text: root.collectionQuery === "" ? "BROWSE" : "RESULTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.spacing.sm

              Repeater {
                model: root.collections

                Rectangle {
                  id: collectionRow
                  required property var modelData
                  required property int index

                  width: parent.width
                  height: Style.space(46)

                  readonly property bool picked: Model.isSelected(root.selectedCollections, modelData.id)
                  readonly property bool hot: rowMouse.containsMouse
                    || (root.cursorActive && root.pane === "collections" && root.collectionIndex === index)

                  color: hot ? Style.hoverFillFor(root.foreground, Color.accent)
                    : (picked ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent")

                  Row {
                    id: collectionInner
                    // Sized from the row rectangle rather than its own
                    // children, so the text column below can claim the
                    // remaining space without a binding loop.
                    width: parent.width - Style.spacing.rowPaddingX
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.md

                    Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(54)
                      height: Style.space(36)
                      color: modelData.coverColor
                      clip: true

                      Image {
                        anchors.fill: parent
                        source: modelData.coverUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize.width: Style.space(54) * 2
                      }
                    }

                    Column {
                      anchors.verticalCenter: parent.verticalCenter
                      width: collectionInner.width - Style.space(54) - Style.space(20)
                        - Style.spacing.md * 2
                      spacing: Style.spacing.xxs

                      Text {
                        width: parent.width
                        text: modelData.title
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        text: modelData.totalPhotos + " photos"
                          + (modelData.curator !== "" ? " · " + modelData.curator : "")
                        color: root.faint
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: collectionRow.picked ? "󰄬" : "󰝦"
                      color: collectionRow.picked ? root.foreground : root.faint
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }

                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) {
                      root.cursorActive = true
                      root.collectionIndex = collectionRow.index
                    }
                    onClicked: root.toggleCollection(collectionRow.modelData)
                  }
                }
              }
            }

            Text {
              width: parent.width
              visible: root.collections.length === 0 && !root.loadingCollections
              text: "No collections loaded."
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
            }
          }

          // ================================================ HISTORY pane
          Column {
            width: parent.width
            visible: root.configured && !root.setupOpen && root.pane === "history"
            spacing: Style.spacing.lg

            Text {
              width: parent.width
              text: "Every photo shown so far. Click one to set it as your wallpaper."
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Grid {
              id: historyGrid
              width: parent.width
              visible: root.history.length > 0
              columns: root.columns
              spacing: Style.spacing.sm

              readonly property int cellW: Model.cellWidth(width, root.columns, spacing)
              readonly property int cellH: Model.cellHeight(cellW)

              Repeater {
                model: root.history

                Rectangle {
                  id: historyCell
                  required property var modelData
                  required property int index

                  width: historyGrid.cellW
                  height: historyGrid.cellH
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                  clip: true

                  property bool fellBack: false

                  readonly property bool hot: historyMouse.containsMouse
                    || (root.cursorActive && root.pane === "history" && root.historyIndex === index)
                  readonly property bool isApplied: root.appliedId !== "" && String(modelData.id) === root.appliedId

                  Image {
                    anchors.fill: parent
                    source: Model.heroSource(historyCell.modelData)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: historyGrid.cellW * 2
                    opacity: status === Image.Ready ? 1 : 0

                    Behavior on opacity {
                      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }

                    // Older entries lose their local file to pruning; the CDN
                    // preview keeps the thumbnail alive.
                    onStatusChanged: {
                      if (status !== Image.Error || historyCell.fellBack) return
                      var preview = String(historyCell.modelData.previewUrl || "")
                      if (preview === "") return
                      historyCell.fellBack = true
                      source = preview
                    }
                  }

                  Rectangle {
                    anchors.fill: parent
                    visible: historyCell.hot
                    color: Qt.rgba(0, 0, 0, 0.45)

                    Text {
                      anchors.centerIn: parent
                      text: historyCell.isApplied ? "Current" : "Set"
                      color: "white"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Rectangle {
                    visible: historyCell.isApplied && !historyCell.hot
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
                    border.width: historyCell.hot ? Math.max(1, Style.space(2)) : 0
                    border.color: Style.hoverStateColor(root.foreground, Color.accent)
                  }

                  MouseArea {
                    id: historyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onContainsMouseChanged: if (containsMouse) {
                      root.cursorActive = true
                      root.historyIndex = historyCell.index
                    }
                    onClicked: function(mouse) {
                      if (mouse.button === Qt.RightButton) root.openUrl(historyCell.modelData.htmlLink)
                      else root.applyFromHistory(historyCell.modelData)
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              visible: root.history.length === 0
              text: "No wallpapers applied yet."
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
            }
          }
        }
      }
    }
  }
}
