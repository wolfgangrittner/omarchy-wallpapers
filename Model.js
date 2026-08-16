// Pure helpers for the Unsplash Wallpapers plugin: endpoint construction,
// response normalization, and config parsing. No QML types are touched here
// so every function stays trivially testable with plain JS.

var BASE = "https://api.unsplash.com"

// Attribution parameters Unsplash's API guidelines require on every link
// back to a photo or photographer profile.
var UTM = "utm_source=omarchy_unsplash_wallpapers&utm_medium=referral"

// Curated topic slugs, mirroring the category browser in Unsplash's own
// desktop app. `random` is not a topic — it hits the random endpoint.
function sources() {
  return [
    { id: "topic:wallpapers", label: "Wallpapers" },
    { id: "topic:nature", label: "Nature" },
    { id: "topic:textures-patterns", label: "Textures" },
    { id: "topic:architecture-interior", label: "Architecture" },
    { id: "topic:travel", label: "Travel" },
    { id: "random", label: "Shuffle" }
  ]
}

function labelForSource(id, query) {
  if (id === "search") return query ? '"' + query + '"' : "Search"
  var list = sources()
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i].label
  return "Featured"
}

function endpointFor(source, query, page, perPage, orientation) {
  var per = Math.max(1, parseInt(perPage, 10) || 12)
  var p = Math.max(1, parseInt(page, 10) || 1)
  var orient = orientation ? "&orientation=" + encodeURIComponent(orientation) : ""

  if (source === "search") {
    return BASE + "/search/photos?query=" + encodeURIComponent(query || "")
      + "&page=" + p + "&per_page=" + per + orient
  }
  if (source === "random") {
    // Random is uncacheable by design; the cache-buster keeps any
    // intermediary from replaying the previous set.
    return BASE + "/photos/random?count=" + per + orient + "&_=" + Date.now()
  }
  if (String(source).indexOf("topic:") === 0) {
    return BASE + "/topics/" + encodeURIComponent(String(source).substring(6))
      + "/photos?page=" + p + "&per_page=" + per + orient
  }
  return BASE + "/photos?page=" + p + "&per_page=" + per
}

// curl is invoked with `-w "\n__HTTP__%{http_code}"` so the status code
// survives without needing a second request or header parsing.
function parseHttp(text) {
  var raw = String(text || "")
  var marker = raw.lastIndexOf("\n__HTTP__")
  if (marker < 0) return { status: 0, body: raw }
  return {
    status: parseInt(raw.substring(marker + 9), 10) || 0,
    body: raw.substring(0, marker)
  }
}

// Every Unsplash list endpoint returns a slightly different envelope:
// /photos and /topics/*/photos return a bare array, /search/photos wraps it
// in `results`, and /photos/random returns an object when count is omitted.
function normalizePhotos(body) {
  var data
  try {
    data = JSON.parse(String(body || ""))
  } catch (e) {
    return []
  }

  var list = []
  if (data instanceof Array) list = data
  else if (data && data.results instanceof Array) list = data.results
  else if (data && data.id) list = [data]

  var out = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p || !p.urls) continue
    out.push({
      id: String(p.id || ""),
      thumbUrl: String(p.urls.small || p.urls.thumb || ""),
      rawUrl: String(p.urls.raw || p.urls.full || ""),
      htmlLink: p.links ? String(p.links.html || "") : "",
      downloadLocation: p.links ? String(p.links.download_location || "") : "",
      authorName: p.user ? String(p.user.name || "") : "",
      authorUsername: p.user ? String(p.user.username || "") : "",
      authorLink: (p.user && p.user.links) ? String(p.user.links.html || "") : "",
      description: String(p.alt_description || p.description || ""),
      color: String(p.color || "#1b1b1b"),
      width: parseInt(p.width, 10) || 0,
      height: parseInt(p.height, 10) || 0
    })
  }
  return out
}

// Unsplash signals a spent rate limit with 403, not 429.
function errorFor(status, body) {
  if (status === 401) return "Access key rejected — check it in settings (press ⚙)."
  if (status === 403) return "Hourly rate limit reached. Demo apps get 50 requests/hour."
  if (status === 404) return "Nothing found for that search."
  if (status === 0) return "Could not reach Unsplash. Check your connection."
  if (status >= 500) return "Unsplash is having trouble (" + status + "). Try again shortly."
  if (status >= 400) {
    var detail = ""
    try {
      var parsed = JSON.parse(String(body || ""))
      if (parsed && parsed.errors instanceof Array && parsed.errors.length > 0) detail = " — " + parsed.errors[0]
    } catch (e) {
      // Non-JSON error body; the status code alone has to carry the message.
    }
    return "Request failed (" + status + ")" + detail
  }
  return ""
}

function withUtm(url) {
  var u = String(url || "")
  if (u === "") return ""
  return u + (u.indexOf("?") >= 0 ? "&" : "?") + UTM
}

// Unsplash's raw URLs already carry an ixid query, so imgix parameters are
// always appended. fit=max keeps the full composition and only bounds the
// long edge — the background renderer does the cropping.
function wallpaperUrl(rawUrl, width) {
  var u = String(rawUrl || "")
  if (u === "") return ""
  var w = Math.max(640, parseInt(width, 10) || 2560)
  return u + (u.indexOf("?") >= 0 ? "&" : "?") + "w=" + w + "&q=85&fm=jpg&fit=max"
}

function attributionText(photo) {
  if (!photo) return ""
  var name = String(photo.authorName || "").replace(/^\s+|\s+$/g, "")
  return name === "" ? "Photo from Unsplash" : "Photo by " + name + " on Unsplash"
}

// Rotation cadences offered by the footer button, in minutes. 0 is off.
function rotateOptions() {
  return [
    { minutes: 0, label: "Off" },
    { minutes: 15, label: "15m" },
    { minutes: 60, label: "1h" },
    { minutes: 360, label: "6h" },
    { minutes: 1440, label: "Daily" }
  ]
}

function rotateLabel(minutes) {
  var options = rotateOptions()
  var m = parseInt(minutes, 10) || 0
  for (var i = 0; i < options.length; i++) if (options[i].minutes === m) return options[i].label
  return m + "m"
}

function nextRotateMinutes(minutes) {
  var options = rotateOptions()
  var m = parseInt(minutes, 10) || 0
  for (var i = 0; i < options.length; i++) {
    if (options[i].minutes === m) return options[(i + 1) % options.length].minutes
  }
  return 0
}

function defaultConfig() {
  return {
    accessKey: "",
    source: "topic:wallpapers",
    query: "",
    orientation: "landscape",
    rotateMinutes: 0,
    keep: 10
  }
}

function parseConfig(raw) {
  var config = defaultConfig()
  var data
  try {
    data = JSON.parse(String(raw || ""))
  } catch (e) {
    return config
  }
  if (!data || typeof data !== "object") return config

  if (typeof data.accessKey === "string") config.accessKey = data.accessKey.replace(/^\s+|\s+$/g, "")
  if (typeof data.source === "string" && data.source !== "") config.source = data.source
  if (typeof data.query === "string") config.query = data.query
  if (typeof data.orientation === "string") config.orientation = data.orientation
  var rotate = parseInt(data.rotateMinutes, 10)
  if (isFinite(rotate) && rotate >= 0) config.rotateMinutes = rotate
  var keep = parseInt(data.keep, 10)
  if (isFinite(keep) && keep >= 0) config.keep = keep
  return config
}

// Grid geometry. Cells keep a 3:2 frame, the most common Unsplash landscape
// ratio, so thumbnails crop symmetrically instead of jittering row to row.
function cellWidth(available, columns, gap) {
  var cols = Math.max(1, parseInt(columns, 10) || 3)
  var total = Math.max(0, Number(available) || 0) - gap * (cols - 1)
  return Math.max(40, Math.floor(total / cols))
}

function cellHeight(width) {
  return Math.round((Number(width) || 0) * 2 / 3)
}

// Grid cursor movement, clamped so Left/Right never wrap onto another row
// and Up/Down never fall off the ends of the model.
function moveCursor(index, dx, dy, count, columns) {
  if (count <= 0) return 0
  var cols = Math.max(1, parseInt(columns, 10) || 3)
  var i = Math.max(0, Math.min(parseInt(index, 10) || 0, count - 1))

  if (dx !== 0) {
    var column = i % cols
    var target = column + dx
    if (target < 0 || target >= cols) return i
    var moved = i + dx
    return moved >= 0 && moved < count ? moved : i
  }
  if (dy !== 0) {
    var next = i + dy * cols
    return next >= 0 && next < count ? next : i
  }
  return i
}
