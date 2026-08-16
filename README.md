# Unsplash Wallpapers

An Omarchy shell plugin that puts Unsplash in the top-right corner of the bar —
the Linux equivalent of Unsplash's macOS menu bar app. It shows one photo drawn
at random from the collections you choose; you set it as your wallpaper when you
like what you see.

Drawing and applying are separate. Clicking the image draws another photo —
as often as you like — and nothing reaches your desktop until you press
**Set as wallpaper**.

Three panes:

| Pane | What it does |
|---|---|
| **Home** | The photo on show, large, with its credit. Click the image (or the circular arrow over it) to draw another; **Set as wallpaper** applies it |
| **Collections** | Browse or search Unsplash collections and tick the ones photos should come from |
| **History** | Every photo shown so far, applied or not; click one to set it and close |

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
| Right-click the bar icon | Open the panel and draw a new photo |
| Click the photo | Draw another one — the wallpaper is untouched |
| **Set as wallpaper** | Apply the photo on show and close the panel (greyed out when it is already your wallpaper) |
| **Open ↗** or the credit line | Open the photo on unsplash.com |
| Click a collection | Select/deselect it as a source |
| Click a history thumbnail | Set it as the wallpaper and close the panel |
| Right-click a history thumbnail | Open that photo on unsplash.com |

Keyboard, while the panel is open:

| Key | Action |
|---|---|
| `1` `2` `3` | Home / Collections / History |
| `n` | Draw a new photo |
| Arrows / `hjkl` | Move the cursor in the collection list or history grid |
| `Enter` / `Space` | Apply and close (Collections: toggle the selection) |
| `/` | Search collections |
| `r` | Reload the collection list |
| `o` | Open the photo on unsplash.com |
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

Only photos you actually apply are downloaded; ones you merely look at cost
nothing but the preview. That means `omarchy theme bg next` cycles through your
wallpapers alongside the theme's own backgrounds.

The plugin keeps the 10 most recent downloads and deletes older `unsplash-*.jpg`
files in that directory — nothing else is ever touched. History outlives the
files: 200 entries are kept, and any whose image is gone (or was never
downloaded) falls back to Unsplash's CDN preview for its thumbnail, so setting
one simply downloads it then. Both limits are configurable:

```bash
~/.config/omarchy/plugins/wr.unsplash-wallpapers/bin/uw-config set keep 25
~/.config/omarchy/plugins/wr.unsplash-wallpapers/bin/uw-config set historyMax 500
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
`next` (alias `shuffle`) to draw a photo, `set` to apply the one on show, and
`showPane <home|collections|history>`. Chaining `next` then `set` is the
scriptable equivalent of the old auto-rotation, if you ever want it back on a
systemd timer.

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
bin/uw-history         record every photo shown; point entries at local files
bin/uw-set-wallpaper   download, apply, prune old downloads
```

State it owns, all under `~/.local/state/omarchy/settings/`:

```
unsplash.json          access key, orientation, selected collections, limits
unsplash-current.json  the photo currently applied
unsplash-history.json  every photo shown (200 most recent)
```

## History

`git log` in this directory. Tag `v1-grid` is the first version, which browsed
topics in a thumbnail grid instead of featuring a single photo.
