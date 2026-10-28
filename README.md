# Big Cursor

An [Omarchy](https://omarchy.org/) shell plugin that brings macOS "shake to
locate" to Hyprland. Wiggle the mouse and the cursor grows. The longer you
shake, the bigger it gets, up to the size you configure. Stop shaking and it
shrinks back.

It resizes the real compositor cursor (`hyprctl setcursor`), so the cursor
keeps its normal shape and works over every app.

## Install

```bash
omarchy plugin add https://github.com/gabrielforster/omarchy-big-cursor.git --enable
```

Or from a local checkout:

```bash
ln -s ~/Work/personal/omarchy-big-cursor ~/.config/omarchy/plugins/io.github.gabrielforster.big-cursor
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.gabrielforster.big-cursor
```

Requires `python3`, which Omarchy already ships as a dependency of `uwsm`.

## Configure

Settings go on the plugin's entry in the `plugins` array of
`~/.config/omarchy/shell.json`. Changes apply as soon as you save, with no
restart needed.

```json
"plugins": [
  {
    "id": "io.github.gabrielforster.big-cursor",
    "maxSize": 128
  }
]
```

| Key           | Default                        | Meaning                                                           |
|---------------|--------------------------------|-------------------------------------------------------------------|
| `maxSize`     | `96`                           | Largest cursor size in px (up to 256)                             |
| `sensitivity` | `2.5`                          | How shaky a movement must be. Higher values need a harder shake    |
| `growMs`      | `300`                          | Shaking time needed to reach `maxSize`                            |
| `holdMs`      | `500`                          | How long the cursor stays big after you stop                      |
| `shrinkMs`    | `350`                          | Time to shrink back from `maxSize`                                |
| `baseSize`    | `$HYPRCURSOR_SIZE` or `24`     | Normal cursor size to return to                                   |
| `theme`       | `$HYPRCURSOR_THEME` or `default` | Cursor theme passed to `setcursor`                              |

Cursor themes look best at sizes they ship natively. Adwaita includes 24, 32,
48, 64 and 96, and Hyprland scales sizes in between.

## How it works

- `cursor-bridge.py` is one long-lived process. It polls `cursorpos` on
  Hyprland's request socket (60 Hz while the pointer moves, 20 Hz when it is
  still) and prints positions. It also forwards `setcursor` commands from the
  service.
- `Service.qml` keeps the last 500 ms of movement. It counts that movement as a
  shake when the pointer covers at least `sensitivity` times the size of the
  area it stays inside and changes direction at least twice. A straight sweep
  or a single there-and-back flick doesn't count.
- While the shake lasts, a 0–1 level rises over `growMs`. After `holdMs`
  without shaking, it falls over `shrinkMs`. The cursor size follows that level
  with an ease-out curve.

If the plugin is disabled or reloaded while the cursor is enlarged, it is
restored to `baseSize`.
