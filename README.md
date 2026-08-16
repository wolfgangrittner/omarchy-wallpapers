# Unsplash Wallpapers

Unsplash in the Omarchy bar. Draw a random photo from the topics and
collections you pick, set it as your wallpaper. An
[Omarchy](https://omarchy.org/) shell plugin, modelled on Unsplash's macOS
menu bar app.

Drawing and applying are separate — click the photo as often as you like;
nothing reaches your desktop until you press **Set as wallpaper**.

Requires Omarchy 4 (Quickshell-based shell).

## Install

```bash
omarchy plugin add git@gitlab.com:wolfgangrittner/omarchy-unsplash-wallpapers.git --enable --yes
```

Then open the panel (icon, top right) and paste an Unsplash **Access Key** into
settings (⚙). Get one free at <https://unsplash.com/oauth/applications>; a demo
app allows 50 requests/hour, which is ample — browsing is free, collection lists
cache for 30 minutes, and each new photo is one request.

Uninstall: `omarchy plugin remove wr.unsplash-wallpapers`

## Panes

| Pane | |
|---|---|
| **Home** | The photo on show. Click it (or the ⟳ over it) to draw another. **Set as wallpaper** applies it and closes the panel. |
| **Collections** | **Curated by Unsplash** lists the official editorial topics (Wallpapers, Nature, Textures, Architecture, Travel, Film…); below that, browse or search any public collection. Tick any mix. **Wallpapers** is selected out of the box; untick everything for all of Unsplash. |
| **History** | Every photo shown, applied or not. Click one to set it. |

## Mouse

| | |
|---|---|
| Left-click icon | Open/close |
| Right-click icon | Open and draw a photo |
| Click photo | Draw another |
| Click topic/collection | Select/deselect as a source |
| Click history thumb | Set it, close |
| Right-click history thumb | Open on unsplash.com |

## Keys

| | |
|---|---|
| `1` `2` `3` | Home / Collections / History |
| `n` | Draw a photo |
| `Enter` | Apply and close (Collections: toggle) |
| `←↓↑→` `hjkl` | Move cursor |
| `/` | Search collections |
| `r` | Reload collections |
| `o` | Open on unsplash.com |
| `Esc` | Close |

## Config

`bin/uw-config set <key> <value>` · `unset <key>...` · `get`

| Key | Default | |
|---|---|---|
| `orientation` | `landscape` | `landscape`, `portrait`, `squarish` (also a button in ⚙) |
| `keep` | `10` | Downloaded wallpapers to keep |
| `historyMax` | `200` | History entries to keep |

Config lives in `~/.local/state/omarchy/settings/unsplash.json` (mode 0600) —
outside `~/.config` so the access key stays out of dotfiles repos.

## Files

Wallpapers download at your screen's native width to
`~/.config/omarchy/backgrounds/<theme>/unsplash-<id>.jpg`, so `omarchy theme bg
next` cycles them too. Only photos you apply are downloaded. The `keep` newest
are kept; older `unsplash-*.jpg` in that directory are deleted, nothing else.

State, all in `~/.local/state/omarchy/settings/`:

```
unsplash.json          key, orientation, topics, collections, limits
unsplash-current.json  photo currently applied
unsplash-history.json  every photo shown
```

Source:

```
Panel.qml              bar button + three-pane popup
SourceRow.qml          one selectable topic/collection row
Model.js               endpoints, parsing, config, grid math
bin/uw-config          read/write config
bin/uw-history         record photos shown
bin/uw-set-wallpaper   download, apply, prune
```

## IPC

```bash
omarchy-shell unsplash toggle|open|close
omarchy-shell unsplash next          # draw a photo
omarchy-shell unsplash set           # apply the one on show
omarchy-shell unsplash showPane home|collections|history
```

Bind in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER CTRL", "U", "omarchy-shell unsplash toggle")
```

`next` then `set` on a systemd timer gives you rotation.

## Attribution

Credits every photographer, links back with Unsplash's required referral
parameters, and pings the API's download endpoint on apply — per the
[Unsplash API Terms](https://unsplash.com/api-terms).

## License

MIT
