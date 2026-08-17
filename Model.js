// Pure helpers for the Unsplash Wallpapers plugin: endpoint construction,
// response normalization, and config parsing. No QML types are touched here
// so every function stays trivially testable with plain JS.

// Attribution parameters Unsplash's API guidelines require on every link
// back to a photo or photographer profile.
var UTM = "utm_source=omarchy_wallpapers&utm_medium=referral"

// --------------------------------------------------------- trusted origins
//
// Ids and URLs below this line arrive inside a response body, so they are only
// as trustworthy as the API, DNS, and any proxy in between. An id ends up in a
// filename, a URL ends up in a download or in front of xdg-open, so each is
// checked here — where responses are normalized — and again in bin/ow-lib.sh,
// since the scripts can be run on their own.

var IMAGE_HOSTS = ["images.unsplash.com", "plus.unsplash.com"]
var LINK_HOSTS = ["unsplash.com", "www.unsplash.com"]
var API_HOST = "api.unsplash.com"

// The host of an https URL, or "" if it is anything this plugin should not be
// handling. Userinfo and ports are rejected rather than parsed off, because
// "https://images.unsplash.com@evil.example/x" is exactly the shape a host
// check is expected to miss.
function hostOf(url) {
  var u = String(url || "")
  if (u === "" || /[\s"'\\<>]/.test(u)) return ""
  var m = /^https:\/\/([^/?#]+)/.exec(u)
  if (!m) return ""
  var host = m[1]
  if (host.indexOf("@") >= 0 || host.indexOf(":") >= 0) return ""
  return host.toLowerCase()
}

function hostAllowed(url, hosts) {
  var host = hostOf(url)
  return host !== "" && hosts.indexOf(host) >= 0
}

// Each returns the value only when it is usable, so a rejected URL degrades to
// a missing thumbnail or a dead link rather than a bad request.
function imageUrl(url) { return hostAllowed(url, IMAGE_HOSTS) ? String(url) : "" }
function linkUrl(url) { return hostAllowed(url, LINK_HOSTS) ? String(url) : "" }
function apiUrl(url) { return hostAllowed(url, [API_HOST]) ? String(url) : "" }

// Photo ids become "unsplash-<id>.jpg" on disk; collection ids are pasted into
// a query string. Both are restricted to the alphabet Unsplash actually uses.
function photoId(id) {
  return /^[A-Za-z0-9_-]{1,128}$/.test(String(id || "")) ? String(id) : ""
}

// ------------------------------------------------------------------ endpoints
//
// These build a path, not a full URL: bin/ow-api owns the host, so the request
// that carries the access key cannot be pointed anywhere else from up here.

// One random photo, drawn from the selected collections when there are any.
// This is the whole engine behind "New photo": a single request per photo,
// matching how Unsplash's own desktop app works.
function randomEndpoint(collectionIds, orientation) {
  var url = "/photos/random?count=1"
  if (orientation) url += "&orientation=" + encodeURIComponent(orientation)

  var ids = collectionIdList(collectionIds)
  if (ids !== "") url += "&collections=" + encodeURIComponent(ids)

  // Random responses must never be served from a cache.
  return url + "&_=" + Date.now()
}

// The curated grid. These are search terms, not ids: the matching collections
// are looked up at runtime by bin/uw-curated (biggest wins) and cached in the
// config, so nothing here goes stale when Unsplash reshuffles its collections.
// `label` is what the grid shows — short and predictable, where the underlying
// collection titles are neither ("Black and White Images").
function curatedTerms() {
  return [
    { term: "wallpapers", label: "Wallpapers" },
    { term: "nature", label: "Nature" },
    { term: "architecture", label: "Architecture" },
    { term: "space", label: "Space" },
    { term: "beach", label: "Beach" },
    { term: "black & white", label: "Black & White" }
  ]
}

function curatedTermArgs() {
  var terms = curatedTerms()
  var out = []
  for (var i = 0; i < terms.length; i++) out.push(terms[i].term)
  return out
}

function labelForTerm(term) {
  var terms = curatedTerms()
  for (var i = 0; i < terms.length; i++) {
    if (terms[i].term === String(term || "")) return terms[i].label
  }
  return String(term || "")
}

// Attach display labels to what uw-curated discovered, keeping the order of
// curatedTerms() rather than the order the lookups happened to finish in.
function labelCurated(entries) {
  if (!(entries instanceof Array)) return []
  var byTerm = {}
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (e && e.term) byTerm[String(e.term)] = e
  }

  var out = []
  var terms = curatedTerms()
  for (var t = 0; t < terms.length; t++) {
    var found = byTerm[terms[t].term]
    if (!found || !found.id) continue
    // Runs over both a fresh ow-curated result and the copy cached in the
    // config, so a hand-edited config gets the same treatment as a response.
    var cid = photoId(found.id)
    if (cid === "") continue
    out.push({
      id: cid,
      term: terms[t].term,
      label: terms[t].label,
      title: String(found.title || terms[t].label),
      totalPhotos: parseInt(found.totalPhotos, 10) || 0,
      coverUrl: imageUrl(found.coverUrl),
      coverColor: String(found.coverColor || "#1b1b1b"),
      curator: String(found.curator || "")
    })
  }
  return out
}

function parseCurated(raw) {
  try {
    return labelCurated(JSON.parse(String(raw || "")))
  } catch (e) {
    return []
  }
}

// `/collections` is the public collection list; `/collections/featured` was
// removed from the API (it 404s), so browsing and searching are the two modes.
function collectionsEndpoint(query, perPage) {
  var per = Math.max(1, parseInt(perPage, 10) || 20)
  var q = String(query || "").replace(/^\s+|\s+$/g, "")
  if (q !== "") {
    return "/search/collections?query=" + encodeURIComponent(q) + "&per_page=" + per
  }
  return "/collections?per_page=" + per
}

function collectionIdList(collections) {
  var ids = []
  var list = collections instanceof Array ? collections : []
  for (var i = 0; i < list.length; i++) {
    var id = typeof list[i] === "string" ? list[i] : (list[i] ? list[i].id : "")
    id = photoId(String(id || "").replace(/^\s+|\s+$/g, ""))
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
    // A photo whose id would not survive becoming a filename is dropped here
    // rather than half-working its way down to ow-set-wallpaper.
    var pid = photoId(p.id)
    if (pid === "") continue
    out.push({
      id: pid,
      previewUrl: imageUrl(p.urls.regular || p.urls.small),
      thumbUrl: imageUrl(p.urls.small || p.urls.thumb),
      rawUrl: imageUrl(p.urls.raw || p.urls.full),
      htmlLink: p.links ? linkUrl(p.links.html) : "",
      downloadLocation: p.links ? apiUrl(p.links.download_location) : "",
      authorName: p.user ? String(p.user.name || "") : "",
      authorUsername: p.user ? String(p.user.username || "") : "",
      description: String(p.alt_description || p.description || ""),
      color: String(p.color || "#1b1b1b")
    })
  }
  return out
}

// `minPhotos` drops collections with too few photos a free key can fetch.
// Unsplash+ collections fall out of this naturally: their usable count is 0,
// and /photos/random answers 404 for them, so they are never worth offering.
function normalizeCollections(body, minPhotos) {
  var floor = Math.max(0, parseInt(minPhotos, 10) || 0)
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
    var cid = photoId(c.id)
    if (cid === "") continue
    // Only photos a free key can fetch: an Unsplash+ collection reports a
    // big total_photos but /photos/random returns 404 for it.
    var free = Math.max(0, (parseInt(c.total_photos, 10) || 0) - (parseInt(c.total_plus, 10) || 0))
    if (free < floor) continue

    out.push({
      // Collection ids are not always numeric ("WV3nU0MXUMw"), so they stay
      // strings everywhere — including in the saved config.
      id: cid,
      title: String(c.title || "Untitled"),
      description: String(c.description || ""),
      totalPhotos: free,
      coverUrl: (c.cover_photo && c.cover_photo.urls) ? imageUrl(c.cover_photo.urls.small) : "",
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
      ? "No free photos in those collections for this orientation — Unsplash+ collections are not available to the API."
      : "Unsplash returned no photo. Try again."
  }
  return errorFor(status, body)
}

// -------------------------------------------------------------------- links

// Returns "" for anything that is not an unsplash.com link. Callers hand the
// result to xdg-open, which will launch whatever handler a scheme is
// registered to, so a link out of a response body does not get to choose one.
function withUtm(url) {
  var u = linkUrl(url)
  if (u === "") return ""
  return u + (u.indexOf("?") >= 0 ? "&" : "?") + UTM
}

// Unsplash's raw URLs already carry an ixid query, so imgix parameters are
// always appended. fit=max keeps the full composition and only bounds the
// long edge — the background renderer does the cropping.
function wallpaperUrl(rawUrl, width) {
  var u = imageUrl(rawUrl)
  if (u === "") return ""
  var w = Math.max(640, parseInt(width, 10) || 2560)
  return u + (u.indexOf("?") >= 0 ? "&" : "?") + "w=" + w + "&q=85&fm=jpg&fit=max"
}

// The guidelines require crediting the photographer *and* Unsplash, with the
// photographer's profile linked. These build the two targets; both go through
// withUtm() before use.
function profileUrl(username) {
  var name = String(username || "").replace(/^\s+|\s+$/g, "")
  return name === "" ? "https://unsplash.com/" : "https://unsplash.com/@" + encodeURIComponent(name)
}

function unsplashUrl() {
  return "https://unsplash.com/"
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
  // Only a plain absolute path becomes a file:// source; anything else falls
  // back to the preview URL, which has already been origin-checked.
  var path = String(photo.path || "")
  if (/^\/[^\0"'\s]/.test(path)) return "file://" + path
  return imageUrl(photo.previewUrl)
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
    // Collections offering fewer than this many fetchable photos are not
    // worth showing: too thin to rotate through, and Unsplash+ ones cannot
    // be fetched at all.
    minPhotos: 10,
    // Resolved curated grid, discovered on first run by bin/uw-curated.
    curated: [],
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
  var minPhotos = parseInt(data.minPhotos, 10)
  if (isFinite(minPhotos) && minPhotos >= 0) config.minPhotos = minPhotos

  config.collections = parseSelectionList(data.collections, config.collections)
  config.curated = labelCurated(data.curated)
  return config
}

// Both selection lists are [{ id, title }]; a bare id array from a hand-edited
// config is tolerated.
function parseSelectionList(raw, fallback) {
  if (!(raw instanceof Array)) return fallback
  var selected = []
  for (var i = 0; i < raw.length; i++) {
    var entry = raw[i]
    if (typeof entry === "string") selected.push({ id: entry, title: entry })
    else if (entry && entry.id) selected.push({ id: String(entry.id), title: String(entry.title || entry.id) })
  }
  return selected
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
    // History rows get re-applied and re-opened, so a row is re-checked on the
    // way out of the file, not trusted for having been written locally.
    var hid = photoId(entry.id)
    if (hid === "") continue
    out.push({
      id: hid,
      authorName: String(entry.author || ""),
      authorUsername: String(entry.username || ""),
      htmlLink: linkUrl(entry.link),
      path: String(entry.path || ""),
      previewUrl: imageUrl(entry.preview),
      rawUrl: imageUrl(entry.raw),
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

// The Collections pane is a 3-wide curated grid stacked on a 1-wide list of
// search results. Cursor indices run through the grid first, then the list, so
// Down off the last grid row steps into the list and Up off the top of the
// list steps back into the grid.
function movePickerCursor(index, dx, dy, curatedCount, listCount, columns) {
  var cols = Math.max(1, parseInt(columns, 10) || 3)
  var total = curatedCount + listCount
  if (total <= 0) return 0
  var i = Math.max(0, Math.min(parseInt(index, 10) || 0, total - 1))

  if (i < curatedCount) {
    if (dx !== 0) {
      var column = i % cols
      var target = column + dx
      if (target < 0 || target >= cols) return i
      var sideways = i + dx
      return sideways >= 0 && sideways < curatedCount ? sideways : i
    }
    if (dy > 0) {
      var down = i + cols
      if (down < curatedCount) return down
      return listCount > 0 ? curatedCount : i
    }
    if (dy < 0) {
      var up = i - cols
      return up >= 0 ? up : i
    }
    return i
  }

  if (dy > 0) return i + 1 < total ? i + 1 : i
  if (dy < 0) {
    if (i > curatedCount) return i - 1
    return curatedCount > 0 ? curatedCount - 1 : i
  }
  return i
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
