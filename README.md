# Slotbound Tweaks

An unofficial, single-player tweak toolkit for [Slotbound](https://store.steampowered.com/app/4459590/Slotbound/) on macOS and Windows.
It adds an in-game panel (`F8`) for adjusting how the game plays, without modifying any game file.

![The Symbol Weights tab with Duelist set to 100%: every reel lands on Duelist](docs/cover.png)

> **Disclaimer.** This project is not affiliated with, endorsed by, or supported by Optima Arch, the developer of Slotbound.
> It is intended for personal, single-player use on a copy of the game you own.
> It does not contain, redistribute, or decrypt any game code or assets.
> Using it may break with game updates and is entirely at your own risk.
> Please don't report issues to the developer while it's active.
> If you are the developer and would like this project changed or taken down, please open an issue.

## Features

All features with settings live in one panel: press `F8` to open it, `Tab` to switch tabs.

| Feature | Where | Description |
|---|---|---|
| **Symbol Weights** | `F8` → Symbol Weights | Edit the slot machine's symbol weights. Saved between sessions. |
| **Unit Grades** | `F8` → Unit Grades | Edit the odds of each unit grade. Saved between sessions. |
| **Items** | `F8` → Items | Add, swap, level or delete the run's items, or choose what the shop sells. |
| **Cores** | `F8` → Cores | Add, swap or remove the run's cores, or choose what the core selection offers. |
| **Imprints** | `F8` → Imprints | Add, swap, level or remove the imprints of the units on the board. |
| **Spin Log** | none | Optional per-spin diagnostics written to `logs/tweaks.log`. Off by default. |

Symbols, unit grades, items, cores and imprints, with their names, effects and icons, are all read from the game itself, so new content from a game update shows up without changing the tweaks.

More features are planned; see [Adding a feature](#adding-a-feature).

### Fair play: leaderboards

Slotbound has online leaderboards. Once any tweak changes gameplay during a session (for example, non-default symbol weights or unit grade odds, or an edited item, core or imprint), leaderboard submissions are **blocked until the game is restarted**.
To submit scores again, reset the tweaks to defaults (or turn them off) and restart the game.
Steam achievements are not affected.

Please keep it that way if you fork this project.

## Requirements

- Slotbound 1.0.3 from Steam
- **macOS:** Apple Silicon, and the Xcode Command Line Tools (for `lldb`): `xcode-select --install`
- **Windows:** 64-bit Windows 10 or later. Nothing to install: the launcher uses the built-in Windows PowerShell 5.1.
  Tested with Slotbound 1.0.4 (Steam) on Windows Server 2022, launched both from a terminal and through the Steam launch option.

## Install & launch

```sh
git clone https://github.com/chenyanchen/slotbound-tweaks.git
```

Steam must be running. Then pick one of these:

- **Terminal:** `./launch.sh`
- **Steam:** Library → Slotbound → Properties → Launch Options:
  ```
  "/absolute/path/to/slotbound-tweaks/launch.sh" %command%
  ```
  Then press Play as usual. To go back to the unmodified game, clear the launch option.

On first launch, macOS may ask to allow debugging (Developer Tools).
The launcher needs this permission to attach to the game.

### Windows

Same steps, with `launch.bat` instead of `launch.sh`:

- **Terminal:** `launch.bat` (finds the game through Steam's library folders), or `launch.bat "D:\path\to\Slotbound.exe"`
- **Steam:** Launch Options:
  ```
  "C:\absolute\path\to\slotbound-tweaks\launch.bat" %command%
  ```

  With a launch option set, Steam itself writes `steam_appid.txt` into the game folder. It is harmless and does not come from this project.

## The panel

| Key | Action |
|---|---|
| `F8` | Open / close the panel (`fn`+`F8` on Mac keyboards) |
| `Tab` / `Shift`+`Tab` | Next / previous tab (also clickable) |
| `Esc` | Close |

While the panel is open it takes all keyboard input; clicks outside it still reach the game.
The panel remembers the last tab you used.

### Language

The panel follows the language chosen in the game's settings, and switches as soon as you change it there.

- Everything that comes from the game is shown in the game's language, using the game's own text: names and effects of units, items, cores and imprints, grade names, item types, and words like Items, Cores, Units and Shop.
- The panel's own text (help lines, messages) is translated into English, Simplified Chinese, Japanese and Korean (`lang/<code>.lua`). Other languages show it in English.
- For Chinese, Japanese and Korean the panel uses the game's own pixel font. Characters a font lacks are taken from another font, falling back to a system font (Arial) for scripts the game's TrueType fonts don't cover, such as Cyrillic.

To add a language, copy `lang/en.lua` to `lang/<code>.lua` (the game's language code, e.g. `de`, `ru`, `zh-Hant`) and translate the values; missing keys fall back to English.

### Symbol Weights and Unit Grades tabs

One bar per symbol or grade, adjusted with `-` / `+`.
Percentages are weight ÷ total weight; the white tick marks the game's own value.

| Key | Action |
|---|---|
| `O` | Only the selected entry (100%) |
| `0` | Set the selected entry to 0 |
| `R` | Reset to the game's values |
| `E` | Turn the tab on/off (off = the game's values) |

While Unit Grades differs from the game's odds, the game's grade pity is switched off, so the percentages shown are what is rolled.

### Items, Cores and Imprints tabs

The left side lists slots: the run's items and the shop, the run's cores and the core selection, or the units on the board and the selected unit's imprints.
The right side is the catalog of everything the game has, with filters. Hover anything to see its effect.

Click a slot (for Imprints, first a unit), then an entry in the catalog to put it there.
Change the level with `-` / `+` and remove with `x` or `Delete`. A gold corner in the catalog marks what you have, a green dot what is offered.

- Each entry can be held once (per unit, for imprints). Slot counts are the game's own; the imprint list always shows as many rows as the largest unit can have, with the rest marked locked.
- Editing is refused on the main menu, during a battle, while the slot machine is spinning (Cores, Imprints) and while the game's own imprint choice is open (Imprints).
- Edited entries stay in the run's save, so continuing such a run after a restart blocks leaderboard submissions for that session too.

## Configuration

Each feature keeps its settings in `config/<feature>.lua`, which is created on first run. You can edit these files in-game or by hand.

```lua
-- config/spin_log.lua
return {
  enabled = true,
}
```

## How it works

Slotbound is a LÖVE 11.5 / LuaJIT game. Its code ships encrypted, and the launcher verifies its files, so this project never touches them.

1. `launch.sh` starts the game under `lldb` and sets a breakpoint on `luaL_loadbuffer`.
2. When the game's own bootstrap loads `@main.lua`, `inject.py` runs `loader.lua` in the game's Lua state.
   It then detaches, so the game runs without a debugger.
3. `loader.lua` sets up the hooks below and loads each module from `features/`:

   | Hook | Used for |
   |---|---|
   | `love.graphics.present` | Per-frame update and panel drawing |
   | `love.handlers` | Input |
   | `require` | Patching game modules as they load |

4. **Symbol Weights** rewrites `src.data.constants`' `slot.symbolWeights`, which the game reads on every roll.
   It also updates the base weights that cores restore after their one-spin effects.
5. **Items** edits the run's item slots (`ui._itemPurchased`) and the shop (`ui._itemOffers`).
   New inventory entries are built with the game's own `restorePurchasedItems`, the function that loads a saved run.
6. **Unit Grades** rewrites `src.data.constants`' `unitGrades.probabilities`, which the game reads on every unit spawn, and bypasses `src.game.luck`'s grade pity while active.
7. **Cores** adds and removes cores through the game's own `src.game.cores` `select` / `remove`, and edits the selection screen's offers (`ui._coreSelect.offers`).
8. **Imprints** edits each board unit's `imprints` list (`battlefield.rosterUnits`), building entries from `src.data.constants`' `imprint.definitions` with the game's own level helper, the one absorbing uses.

When launched from Steam, `launch.sh` takes two extra steps:

- It removes `DYLD_*` variables, because Steam's overlay injection crashes `lldb`. As a result, the Steam overlay is unavailable while using tweaks.
- It re-executes itself natively, because the Steam client runs under Rosetta. The game itself always runs natively (arm64).

On Windows, `launch.bat` starts `launch.ps1` in 64-bit PowerShell (Steam is a 32-bit process). `launch.ps1` compiles `inject.cs` on the fly; it plays the role of `lldb` + `inject.py`.
It starts the game as a debuggee, sets a breakpoint on `luaL_loadbuffer` in `lua51.dll`, and when `@main.lua` is loaded, runs a few generated instructions on the game's thread that call `luaL_loadfile` + `lua_pcall` on `loader.lua`. It then restores the thread and detaches.

## Adding a feature

1. Create `features/<name>.lua`:

   ```lua
   return function(T)
     local cfg = T.config.load("<name>", { enabled = true }) -- config/<name>.lua
     local F = {}
     function F.update(dt) end
     function F.draw() end                          -- after the game has drawn (and the panel)
     function F.keypressed(key) return false end    -- return true to swallow
     function F.mousepressed(x, y, button) return false end
     function F.mousereleased(x, y, button) return false end
     function F.onRequire(name, module) end         -- a game module was loaded
     return F
   end
   ```

2. Add `"<name>"` to `FEATURES` at the top of `loader.lua`.
3. If the feature changes gameplay, call `T.taint("<reason>")` while it's active.
4. For settings UI, add a tab to the `F8` panel instead of handling a hotkey yourself:

   ```lua
   T.panel.addTab({
     id = "<name>", title = "My Feature",
     draw = function(x, y, w, h, s) end,       -- content rect in pixels, s = UI scale
     keypressed = function(key) end,           -- only while this tab is showing
     mousepressed = function(x, y, button) end -- only for clicks inside the content rect
   })
   ```

   `T.panel.isShowing("<name>")` tells whether your tab is visible; `T.panel.button(rect, label, font, active, enabled)` draws a button and `T.panel.stepper(opts)` draws a unified `-` / `+` pair with hold-to-repeat.
   For a bar editor like Symbol Weights or Unit Grades, use `T.weights.tab(spec)` (see `weights.lua`); for a "slots + catalog" tab like Items, Cores or Imprints, use `T.picker.tab(spec)` (see `picker.lua`).

Other helpers:

- `T.log(fmt, ...)` writes to the log.
- `T.tr(key, ...)` returns the panel's own text in the game's language (add the key to `lang/en.lua` and the other `lang/*.lua`); `T.gameText(key)` returns a string from the game's own language tables. Never hardcode visible text.
- `T.font(px)` returns a cached font that can draw the current language.
- `T.config.save(name, tbl)` saves a config file.
- `T.loadLua(relpath)` loads a Lua file. Use it instead of `loadfile`, which the game's bootstrap restricts to its own package.

If a feature throws an error, it is disabled and the error is logged. The game keeps running.

## Troubleshooting

Logs are in `logs/`:

| File | Contents |
|---|---|
| `launch.log` | Launcher |
| `inject.log` | Injection |
| `tweaks.log` | Features |
| `game.log` | Game stdout |

- If injection fails, the game still starts, just without tweaks. Check `inject.log`.
- `SB_DRYRUN=1 ./launch.sh` checks `lldb` and `python3` without starting the game.
  On Windows, `set SB_DRYRUN=1` then `launch.bat` checks PowerShell, compiles `inject.cs`, and logs where it found the game.
- `SB_SELFTEST=1 ./launch.sh` (Windows: `set SB_SELFTEST=1` then `launch.bat`) runs a self-test:
  - samples the game's real symbol picker 200,000 times and logs the distribution;
  - opens the panel through a synthetic `F8` key event;
  - saves a screenshot of each tab as `logs/selftest-<tab>.png`.
- Game updates can change internals. The code was written against Slotbound 1.0.3.

## License

[MIT](LICENSE) © Yanchen Chen. Covers this project's own code only. Slotbound is © Optima Arch.
