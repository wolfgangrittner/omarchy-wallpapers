# Omarchy Wallpapers

A wallpaper browser in the Omarchy bar. Draw a random photo from the
collections you pick, set it as your wallpaper. An
[Omarchy](https://omarchy.org/) shell plugin, powered by
[Unsplash](https://unsplash.com/).

Not affiliated with or endorsed by Unsplash. The
[API guidelines](https://help.unsplash.com/en/articles/2511245-unsplash-api-guidelines)
forbid using their name in an application name or their logo as an app icon,
so this is "Omarchy Wallpapers"; every photo credits its photographer and
Unsplash, both linked.

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
| **Collections** | A 3×2 grid of six curated collections — Wallpapers, Nature, Architecture, Space, Beach, Black & White — plus search for any other public collection. Tick any mix. **Wallpapers** is selected out of the box; untick everything to draw from all of Unsplash. |
| **History** | Every photo shown, applied or not. Click one to set it. |

## Mouse

| | |
|---|---|
| Left-click icon | Open/close |
| Right-click icon | Open and draw a photo |
| Click photo | Draw another |
| Click a collection | Select/deselect as a source |
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
| `minPhotos` | `10` | Hide collections offering fewer usable photos than this |
| `curated` | discovered | The six grid collections. Resolved on first run, cached here. Rebuild from ⚙. |
| `collections` | Wallpapers | Which collections photos are drawn from |

### The curated grid

Collection ids are never hardcoded. On first run `bin/uw-curated` searches
Unsplash for each of the six names and keeps the **largest match**, counted in
photos a free API key can actually fetch — `total_photos` minus `total_plus`.

That last part matters: the biggest "wallpapers" collection is entirely
Unsplash+ premium, and `/photos/random` answers 404 for it, so ranking on the
raw count picks a collection that silently returns nothing. It prefers
collections with at least 50 usable photos, falling back to the largest usable
one so a thin search term still yields a tile. Results are cached in `curated`;
**Rebuild curated** in ⚙ re-runs the lookup.

The same count drives the browse list: collections with fewer than `minPhotos`
fetchable photos are hidden, which removes Unsplash+ collections (0 usable) and
near-empty ones in a single rule. The pane says how many it hid.

Config lives in `~/.local/state/omarchy/settings/unsplash.json` (mode 0600) —
outside `~/.config` so the access key stays out of dotfiles repos.

## Files

Wallpapers download at your screen's native width to
`~/.config/omarchy/backgrounds/<theme>/unsplash-<id>.jpg`, so `omarchy theme bg
next` cycles them too. Only photos you apply are downloaded. The `keep` newest
are kept; older `unsplash-*.jpg` in that directory are deleted, nothing else.

State, all in `~/.local/state/omarchy/settings/`:

```
unsplash.json          key, orientation, collections, curated, limits
unsplash-current.json  photo currently applied
unsplash-history.json  every photo shown
```

Source:

```
Panel.qml              bar button + three-pane popup
CuratedCell.qml        one tile in the curated grid
SourceRow.qml          one row in the search/browse list
Model.js               endpoints, parsing, config, grid math
bin/uw-config          read/write config
bin/uw-curated         resolve the six curated collections
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
o.bind("SUPER CTRL", "U", "omarchy-shell wallpapers toggle")
```

`next` then `set` on a systemd timer gives you rotation.

## Attribution

Every photo credits its photographer and Unsplash, both linked with the
required `utm_source`/`utm_medium` referral parameters; images are hotlinked
from the API's own URLs, and the download endpoint is pinged on apply — per the
[Unsplash API Guidelines](https://help.unsplash.com/en/articles/2511245-unsplash-api-guidelines).

## License

MIT
