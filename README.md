# Big Cursor

An [Omarchy](https://omarchy.org/) shell plugin that brings macOS "shake to
locate" to Hyprland. Wiggle the mouse and the cursor grows. The longer you
shake, the bigger it gets, up to the size you configure. Stop shaking and it
shrinks back.

![Big Cursor](preview.png)

## Install

```bash
omarchy plugin add https://github.com/gabrielforster/omarchy-big-cursor.git --enable
```

The cursor icon appears on the right side of the bar. Move it with
`omarchy bar move io.github.gabrielforster.big-cursor --section <left|center|right>`.

Or from a local checkout:

```bash
ln -s ~/path/to/omarchy-big-cursor ~/.config/omarchy/plugins/io.github.gabrielforster.big-cursor
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.gabrielforster.big-cursor
```

A symlinked checkout doesn't hot-reload. Run `omarchy restart shell` after
editing it.

## Remove

```bash
omarchy plugin remove io.github.gabrielforster.big-cursor
```

To keep it installed but turn it off, use
`omarchy plugin disable io.github.gabrielforster.big-cursor`. Either way the
real cursor is restored and the settings entry is dropped from
`~/.config/omarchy/shell.json`. The plugin writes nothing else to disk.

## Requirements

- Omarchy with the Quickshell-based `omarchy-shell` and Hyprland's Lua config,
  since it uses `hyprctl eval` to hide the real cursor while enlarged. Tested
  on Hyprland 0.56.
- `python3` with only the standard library. Omarchy already ships it as a
  dependency of `uwsm`.

## Configure

Click the cursor icon in the bar to set:

- **Max size:** how big the cursor can get, from 32 to 256 px. A preview plays
  when you release the slider.
- **Shake needed:** how hard you have to shake before it grows. Choose
  **Light** (2.0), **Medium** (2.5) or **Hard** (3.5), or turn on **Custom
  value** for a slider from 1.5 to 5.0. Above about 4, a shake has to be
  faster than most hands can manage.

Right-click the icon to preview the maximum size.

The same settings live on the plugin's entry in
`~/.config/omarchy/shell.json` and apply as soon as you save:

```json
{ "id": "io.github.gabrielforster.big-cursor", "maxSize": 128, "sensitivity": 2.5 }
```

| Key           | Default                    | Meaning                                                          |
|---------------|----------------------------|------------------------------------------------------------------|
| `maxSize`     | `96`                       | Largest cursor size in px (up to 256)                            |
| `sensitivity` | `2.5`                      | How shaky a movement must be. Higher values need a harder shake  |
| `growMs`      | `300`                      | Shaking time needed to reach `maxSize`                           |
| `holdMs`      | `500`                      | How long the cursor stays big after you stop                     |
| `shrinkMs`    | `350`                      | Time to shrink back from `maxSize`                               |
| `baseSize`    | `$HYPRCURSOR_SIZE` or `24` | Size the enlarged arrow starts from                              |

## How it works

- `cursor-bridge.py` is one long-lived process. It polls `cursorpos` on
  Hyprland's request socket (125 Hz while the pointer moves, 20 Hz when it is
  still) and prints positions. It also hides and shows the real cursor when the
  service asks.
- `Service.qml` keeps the last 500 ms of movement. It counts that movement as a
  shake when the pointer covers at least `sensitivity` times the size of the
  area it stays inside and changes direction at least twice. A straight sweep
  or a single there-and-back flick doesn't count.
- While enlarged, the real cursor is hidden and a vector arrow is drawn on an
  overlay that is mapped only for that moment. The overlay scales smoothly at
  any size. Hyprland's `setcursor` can't do this: it reloads the whole theme
  on every step and doesn't redraw the cursor that's already showing.
- While the shake lasts, a 0–1 level rises over `growMs`. After `holdMs`
  without shaking, it falls over `shrinkMs`. The arrow size follows that level
  with an ease-out curve.

The real cursor comes back if the plugin is disabled or reloaded, or if the
shell exits while the cursor is enlarged.
