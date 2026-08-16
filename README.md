# Unsplash Wallpapers

An Omarchy shell plugin that puts Unsplash in the top-right corner of the bar —
the Linux equivalent of Unsplash's macOS menu bar app. It keeps one photo on
your desktop, drawn at random from the collections you choose, and can refresh
it on a schedule.

Three panes:

| Pane | What it does |
|---|---|
| **Home** | The wallpaper in use, large, with its photographer credit and a **New photo** button that draws a fresh random photo from your collections |
| **Collections** | Browse or search Unsplash collections and tick the ones photos should come from |
| **History** | Every wallpaper you have used; click one to put it back |

## Install

The plugin lives in `~/.config/omarchy/plugins/wr.unsplash-wallpapers/`.

```bash
omarchy plugin enable wr.unsplash-wallpapers --section right
```

Move it within the bar with `omarchy bar move wr.unsplash-wallpapers`, and turn
it off again with `omarchy plugin disable wr.unsplash-wallpapers`.

## Access key

Unsplash's API requires a key; there is no unauthenticated endpoint. Create a
free app at <https://unsplash.com/oauth/applications> and paste its **Access
Key** into the panel's settings (⚙). A demo app allows 50 requests per hour,
which is plenty: browsing costs nothing, collection lists are cached for 30
minutes, and each new wallpaper is exactly one request.

The key is stored in `~/.local/state/omarchy/settings/unsplash.json` with mode
0600, deliberately outside `~/.config` so it does not end up in a dotfiles repo.

## Using it

| Action | What happens |
|---|---|
| Left-click the bar icon | Open/close the panel |
| Right-click the bar icon | New photo, without opening the panel |
| **New photo** | Draw a random photo from the selected collections |
| **Auto: …** | Cycle rotation: Off → 15m → 1h → 6h → Daily |
| Click a collection | Select/deselect it as a source |
| Click a history thumbnail | Set that wallpaper again |
| Click the hero image or credit | Open the photo on unsplash.com |

Keyboard, while the panel is open:

| Key | Action |
|---|---|
| `1` `2` `3` | Home / Collections / History |
| `n` | New photo |
| Arrows / `hjkl` | Move the cursor in the collection list or history grid |
| `Enter` / `Space` | Select the collection / apply the wallpaper |
| `/` | Search collections |
| `r` | Reload the collection list |
| `o` | Open the current photo on unsplash.com |
| `Esc` | Close |

With no collections selected the source is all of Unsplash. Orientation
(landscape / portrait / squarish) is a button in settings — leave it on
landscape unless you have a portrait display, or you will get square photos
cropped to fit.

## Where wallpapers go

Photos are downloaded at your screen's native width into the user background
directory for the active theme:

```
~/.config/omarchy/backgrounds/<theme>/unsplash-<photo-id>.jpg
```

That means `omarchy theme bg next` cycles through them alongside the theme's own
backgrounds. The plugin keeps the 10 most recent downloads and deletes older
`unsplash-*.jpg` files in that directory — nothing else is ever touched. History
entries outlive the files (60 are kept) and fall back to Unsplash's CDN preview
for their thumbnail, so re-applying an old wallpaper simply downloads it again.
Change the count with:

```bash
~/.config/omarchy/plugins/wr.unsplash-wallpapers/bin/uw-config set keep 25
```

## Optional: a keybinding

The panel is reachable over the shell's IPC, so you can bind it in
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER CTRL", "U", "omarchy-shell unsplash toggle")
o.bind("SUPER CTRL SHIFT", "U", "omarchy-shell unsplash next")
o.bind("SUPER CTRL", "H", "omarchy-shell unsplash showPane history")
```

Available IPC calls on the `unsplash` target: `open`, `close`, `toggle`,
`next` (alias `shuffle`), and `showPane <home|collections|history>`.

## Attribution

The panel credits every photographer, links back to the photo with Unsplash's
required referral parameters, and pings the API's download endpoint when a photo
is applied — the conditions of the Unsplash API Terms.

## Files

```
manifest.json          plugin manifest (bar-widget, right section by default)
Panel.qml              bar button + the three-pane popup
Model.js               endpoint building, response parsing, config, grid math
bin/uw-config          read/write the config file
bin/uw-set-wallpaper   download, apply, record history, prune old downloads
```

State it owns, all under `~/.local/state/omarchy/settings/`:

```
unsplash.json          access key, orientation, rotation, selected collections
unsplash-current.json  the photo currently applied
unsplash-history.json  the last 60 photos applied
```

## History

`git log` in this directory. Tag `v1-grid` is the first version, which browsed
topics in a thumbnail grid instead of featuring a single photo.
