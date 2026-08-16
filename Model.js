// Pure helpers for the Unsplash Wallpapers plugin: endpoint construction,
// response normalization, and config parsing. No QML types are touched here
// so every function stays trivially testable with plain JS.

var BASE = "https://api.unsplash.com"

// Attribution parameters Unsplash's API guidelines require on every link
// back to a photo or photographer profile.
var UTM = "utm_source=omarchy_unsplash_wallpapers&utm_medium=referral"

// ------------------------------------------------------------------ endpoints

// One random photo, drawn from the selected collections when there are any.
// This is the whole engine behind "New photo" and the rotation timer: a single
// request per change, matching how Unsplash's own desktop app works.
function randomEndpoint(collectionIds, orientation) {
  var url = BASE + "/photos/random?count=1"
  if (orientation) url += "&orientation=" + encodeURIComponent(orientation)
  var ids = collectionIdList(collectionIds)
  if (ids !== "") url += "&collections=" + encodeURIComponent(ids)
  // Random responses must never be served from a cache.
  return url + "&_=" + Date.now()
}

// `/collections` is the public collection list; `/collections/featured` was
// removed from the API (it 404s), so browsing and searching are the two modes.
function collectionsEndpoint(query, perPage) {
  var per = Math.max(1, parseInt(perPage, 10) || 20)
  var q = String(query || "").replace(/^\s+|\s+$/g, "")
  if (q !== "") {
    return BASE + "/search/collections?query=" + encodeURIComponent(q) + "&per_page=" + per
  }
  return BASE + "/collections?per_page=" + per
}

function collectionIdList(collections) {
  var ids = []
  var list = collections instanceof Array ? collections : []
  for (var i = 0; i < list.length; i++) {
    var id = typeof list[i] === "string" ? list[i] : (list[i] ? list[i].id : "")
    id = String(id || "").replace(/^\s+|\s+$/g, "")
    if (id !== "") ids.push(id)
  }
  return ids.join(",")
}

// ---------------------------------------------------------------- responses

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

// /photos/random returns a bare array when `count` is set and a single object
// when it is not; both shapes are accepted here.
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
      previewUrl: String(p.urls.regular || p.urls.small || ""),
      thumbUrl: String(p.urls.small || p.urls.thumb || ""),
      rawUrl: String(p.urls.raw || p.urls.full || ""),
      htmlLink: p.links ? String(p.links.html || "") : "",
      downloadLocation: p.links ? String(p.links.download_location || "") : "",
      authorName: p.user ? String(p.user.name || "") : "",
      authorUsername: p.user ? String(p.user.username || "") : "",
      description: String(p.alt_description || p.description || ""),
      color: String(p.color || "#1b1b1b")
    })
  }
  return out
}

function normalizeCollections(body) {
  var data
  try {
    data = JSON.parse(String(body || ""))
  } catch (e) {
    return []
  }

  var list = []
  if (data instanceof Array) list = data
  else if (data && data.results instanceof Array) list = data.results

  var out = []
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    if (!c || !c.id) continue
    out.push({
      // Collection ids are not always numeric ("WV3nU0MXUMw"), so they stay
      // strings everywhere — including in the saved config.
      id: String(c.id),
      title: String(c.title || "Untitled"),
      description: String(c.description || ""),
      totalPhotos: parseInt(c.total_photos, 10) || 0,
      coverUrl: (c.cover_photo && c.cover_photo.urls) ? String(c.cover_photo.urls.small || "") : "",
      coverColor: (c.cover_photo && c.cover_photo.color) ? String(c.cover_photo.color) : "#1b1b1b",
      curator: (c.user && c.user.name) ? String(c.user.name) : ""
    })
  }
  return out
}

// Unsplash signals a spent rate limit with 403, not 429.
function errorFor(status, body) {
  if (status === 401) return "Access key rejected — check it in settings (⚙)."
  if (status === 403) return "Hourly rate limit reached. Demo apps get 50 requests/hour."
  if (status === 404) return "Nothing found."
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

// A 404 from the random endpoint means the collection/orientation combination
// is empty, which is a filter problem rather than a missing resource.
function randomErrorFor(status, body, hasCollections) {
  if (status === 404) {
    return hasCollections
      ? "No photos in those collections for this orientation."
      : "Unsplash returned no photo. Try again."
  }
  return errorFor(status, body)
}

// -------------------------------------------------------------------- links

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

// Prefer the copy already on disk — it is the exact image on screen and needs
// no network — and fall back to the CDN preview once pruning removes it.
function heroSource(photo) {
  if (!photo) return ""
  var path = String(photo.path || "")
  if (path !== "") return "file://" + path
  return String(photo.previewUrl || "")
}

// -------------------------------------------------------------------- config

function defaultConfig() {
  return {
    accessKey: "",
    orientation: "landscape",
    keep: 10,
    // History records every photo shown, not just the ones applied, so it
    // needs a ceiling — the panel renders the whole list.
    historyMax: 200,
    // [{ id, title }] — the title is stored alongside the id so the selected
    // list stays readable without re-fetching every collection it names.
    collections: []
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
  if (typeof data.orientation === "string") config.orientation = data.orientation
  var keep = parseInt(data.keep, 10)
  if (isFinite(keep) && keep >= 0) config.keep = keep
  var historyMax = parseInt(data.historyMax, 10)
  if (isFinite(historyMax) && historyMax > 0) config.historyMax = historyMax

  if (data.collections instanceof Array) {
    var selected = []
    for (var i = 0; i < data.collections.length; i++) {
      var entry = data.collections[i]
      // Tolerate a bare id array from a hand-edited config.
      if (typeof entry === "string") selected.push({ id: entry, title: entry })
      else if (entry && entry.id) selected.push({ id: String(entry.id), title: String(entry.title || entry.id) })
    }
    config.collections = selected
  }
  return config
}

function isSelected(collections, id) {
  var list = collections instanceof Array ? collections : []
  for (var i = 0; i < list.length; i++) if (String(list[i].id) === String(id)) return true
  return false
}

function toggleCollection(collections, collection) {
  var list = []
  var found = false
  var current = collections instanceof Array ? collections : []
  for (var i = 0; i < current.length; i++) {
    if (String(current[i].id) === String(collection.id)) found = true
    else list.push(current[i])
  }
  if (!found) list.push({ id: String(collection.id), title: String(collection.title || collection.id) })
  return list
}

function selectionSummary(collections) {
  var count = collections instanceof Array ? collections.length : 0
  if (count === 0) return "All of Unsplash"
  if (count === 1) return collections[0].title
  return count + " collections"
}

// ------------------------------------------------------------------- history

// unsplash-current.json holds a single entry in the same shape as one history
// row, so it is parsed through the same normalizer.
function parseCurrent(raw) {
  var text = String(raw || "").replace(/^\s+|\s+$/g, "")
  if (text === "") return null
  var entries = parseHistory("[" + text + "]")
  return entries.length > 0 ? entries[0] : null
}

function parseHistory(raw) {
  var data
  try {
    data = JSON.parse(String(raw || ""))
  } catch (e) {
    return []
  }
  if (!(data instanceof Array)) return []

  var out = []
  for (var i = 0; i < data.length; i++) {
    var entry = data[i]
    if (!entry || !entry.id) continue
    out.push({
      id: String(entry.id),
      authorName: String(entry.author || ""),
      authorUsername: String(entry.username || ""),
      htmlLink: String(entry.link || ""),
      path: String(entry.path || ""),
      previewUrl: String(entry.preview || ""),
      rawUrl: String(entry.raw || ""),
      appliedAt: String(entry.appliedAt || ""),
      color: "#1b1b1b"
    })
  }
  return out
}

// ---------------------------------------------------------------- grid math

// Cells keep a 3:2 frame, the most common Unsplash landscape ratio, so
// thumbnails crop symmetrically instead of jittering row to row.
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
