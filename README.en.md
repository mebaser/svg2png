# svg2png

[한국어](README.md) | **English**

A macOS tool that converts SVG files to PNG straight from the Finder right-click menu.

Rendering is done by WebKit — the same engine as Safari — so gradients, filters, masks,
embedded CSS, web fonts and external image references come out exactly as they look in a browser.
No external dependencies: no Homebrew, Python or Node.

## Install

```
./install.sh
```

Only Xcode Command Line Tools are required (`xcode-select --install` if you don't have them).

## Usage

Right-click one or more `.svg` files in Finder and open **Services**:

| Menu item | What it does |
|---|---|
| **PNG로 변환** (Convert to PNG) | Converts immediately using your settings |
| **PNG로 변환…** (Convert to PNG…) | Lets you pick the size and background first |

- The PNG is saved next to the original SVG with the same name.
- Defaults: **2× the original size, transparent background**.
- If a PNG with the same name already exists, you're asked whether to overwrite it or save as `name-1.png`.
- The menu only appears for SVG files.

If the menu doesn't show up, restart Finder with `killall Finder`.
You can enable/disable the items or assign shortcuts in
`System Settings → Keyboard → Keyboard Shortcuts → Services`.

## Settings

Edit `~/Library/Application Support/svg2png/config.sh` — changes apply immediately
and survive reinstalling.

```sh
SCALE=2                 # default scale for "Convert to PNG". 1 = original size
BACKGROUND=transparent  # transparent | white | black | #RRGGBB | #RRGGBBAA
OVERWRITE=ask           # ask · always (overwrite) · never (always use a new name)
NOTIFY=1                # 1 = show a notification when done · 0 = silent
REVEAL=0                # 1 = select the result in Finder after converting
```

## Command line

The installer links the tool to `/usr/local/bin/svg2png`. If it skipped that step for lack of permission:

```
sudo ln -sf "$HOME/Library/Application Support/svg2png/bin/svg2png" /usr/local/bin/svg2png
```

```
svg2png logo.svg                 # logo.png at 2×
svg2png -s 1 logo.svg            # original size
svg2png -w 1024 icon.svg         # 1024px wide (height keeps the aspect ratio)
svg2png -m 512 icon.svg          # fit the longest side to 512px
svg2png -b white -f *.svg        # white background, overwrite, batch
svg2png -o ~/Desktop/out *.svg   # write to another folder
```

Run `svg2png --help` for all options.

## How the size is determined

svg2png finds a sensible original size however the SVG declares it:

1. The `width`/`height` attributes — `pt`, `mm`, `cm` and `in` are converted, not just `px`
2. If they depend on the viewport (e.g. `100%`), they're ignored and the `viewBox` size is used
3. If neither exists, the bounding box of what is actually drawn
4. Failing all of that, 512×512

The scale or requested pixel size is then applied. The aspect ratio is always preserved,
and output is capped at 20000px per side. The PNG's DPI is recorded so its physical size
matches the original (2× → 144 dpi).

## Layout

```
src/svg2png.swift            the converter, rendering via WebKit
quickaction/quick-action.sh  script invoked by the right-click menu
install.sh / uninstall.sh    install and remove
```

Installed to:

```
~/Library/Application Support/svg2png/bin/svg2png
~/Library/Application Support/svg2png/quick-action.sh
~/Library/Application Support/svg2png/config.sh
~/Library/Services/SVG를 PNG로 변환.workflow
~/Library/Services/SVG를 PNG로 변환 (옵션).workflow
/usr/local/bin/svg2png                        (symlink)
```

## Troubleshooting

If a conversion fails, run it from Terminal to see why:

```
SVG2PNG_DEBUG=1 "$HOME/Library/Application Support/svg2png/bin/svg2png" file.svg
```

The first time you convert a file in Desktop, Documents or Downloads, macOS may ask for
folder access — allow it so the PNG can be written. The **Convert to PNG…** item may also
ask for Automation permission the first time; the dialogs work either way, but with it they
come to the front.

## Uninstall

```
./uninstall.sh
```

PNG files you've converted are left untouched.

## License

MIT
