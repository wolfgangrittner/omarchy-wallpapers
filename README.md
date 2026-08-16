# Unsplash Wallpapers

An Omarchy shell plugin that puts Unsplash in the top-right corner of the bar —
the Linux equivalent of Unsplash's macOS menu bar app. Click the icon, browse
curated topics or search, click a photo, and it becomes your background.

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
Key** into the panel's settings (the ⚙ button). A demo app allows 50 requests
per hour, which is plenty — the plugin caches each source for 10 minutes and
rotation reuses the already-loaded feed instead of spending a request.

The key is stored in `~/.local/state/omarchy/settings/unsplash.json` with mode
0600, deliberately outside `~/.config` so it does not end up in a dotfiles repo.

## Using it

| Action | What happens |
|---|---|
| Left-click the bar icon | Open/close the panel |
| Right-click the bar icon | Shuffle — set a random photo from the current source |
| Middle-click the bar icon | Reload the current source |
| Click a photo | Set it as the background |
| Right-click a photo | Open it on unsplash.com |
| `Auto: …` button | Cycle rotation: Off → 15m → 1h → 6h → Daily |

Keyboard, while the panel is open:

| Key | Action |
|---|---|
| Arrows / `hjkl` | Move the grid cursor |
| `Enter` / `Space` | Set the highlighted photo |
| `/` | Search |
| `r` | Reload the source |
| `s` | Shuffle |
| `o` | Open the current photo on unsplash.com |
| `Esc` | Close |

## Where wallpapers go

Photos are downloaded at your screen's native width into the user background
directory for the active theme:

```
~/.config/omarchy/backgrounds/<theme>/unsplash-<photo-id>.jpg
```

That means `omarchy theme bg next` cycles through them alongside the theme's own
backgrounds. The plugin keeps the 10 most recent downloads and deletes older
`unsplash-*.jpg` files in that directory — nothing else is ever touched. Change
the count with:

```bash
~/.config/omarchy/plugins/wr.unsplash-wallpapers/bin/uw-config set keep 25
```

## Optional: a keybinding

The panel is reachable over the shell's IPC, so you can bind it in
`~/.config/hypr/bindings.lua` if you want it without the mouse:

```lua
o.bind("SUPER CTRL", "U", "omarchy-shell unsplash toggle")
o.bind("SUPER CTRL SHIFT", "U", "omarchy-shell unsplash shuffle")
```

## Attribution

The panel credits every photographer, links back to the photo with Unsplash's
required referral parameters, and pings the API's download endpoint when a photo
is applied — the conditions of the Unsplash API Terms.

## Files

```
manifest.json          plugin manifest (bar-widget, right section by default)
Panel.qml              bar button + popup panel
Model.js               endpoint building, response parsing, grid math
bin/uw-config          read/write the config file
bin/uw-set-wallpaper   download, apply, prune, and record attribution
```
