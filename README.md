# Slotbound Tweaks

An unofficial, single-player tweak toolkit for [Slotbound](https://store.steampowered.com/app/4459590/Slotbound/) on macOS.
It adds in-game panels for adjusting how the game plays, without modifying any game file.

> **Disclaimer.** This project is not affiliated with, endorsed by, or supported by Optima Arch, the developer of Slotbound.
> It is intended for personal, single-player use on a copy of the game you own.
> It does not contain, redistribute, or decrypt any game code or assets.
> Using it may break with game updates and is entirely at your own risk.
> Please don't report issues to the developer while it's active.
> If you are the developer and would like this project changed or taken down, please open an issue.

## Features

| Feature | Hotkey | Description |
|---|---|---|
| **Symbol Odds** | `F8` | Edit the slot machine's symbol weights (Warrior, Archer, Spear, Mage, Horse, Duelist). Takes effect immediately and is saved between sessions. |
| **Spin Log** | none | Optional per-spin diagnostics written to `logs/tweaks.log`. Off by default. |

More features are planned; see [Adding a feature](#adding-a-feature).

### Fair play: leaderboards

Slotbound has online leaderboards. Once any tweak changes gameplay during a session (for example, non-default symbol odds), leaderboard submissions are **blocked until the game is restarted**.
To submit scores again, reset the tweaks to defaults (or turn them off) and restart the game.
Steam achievements are not affected.

Please keep it that way if you fork this project.

## Requirements

- macOS on Apple Silicon
- Slotbound 1.0.3 from Steam
- Xcode Command Line Tools (for `lldb`): `xcode-select --install`

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

## Symbol Odds panel

| Key | Action |
|---|---|
| `F8` | Open / close the panel (`fn`+`F8` on Mac keyboards) |
| `↑` / `↓` | Select a symbol (hold to repeat) |
| `←` / `→` | Weight −/+ 0.01, or 0.05 with `Shift`. Hold to repeat; holding for more than 1.5 s speeds up. The `-`/`+` buttons behave the same. |
| `O` | Only the selected symbol (100%) |
| `0` | Set the selected weight to 0 |
| `R` | Reset to the game's defaults |
| `E` | Toggle the feature on/off (off = game defaults) |
| `Esc` | Close |

Percentages are weight ÷ total weight. The white tick on each bar marks the game's default probability.
The game's default weights are W 0.20, A 0.20, S 0.20, M 0.15, H 0.15, D 0.10.

Some cores (Mirage Goblet, Old Crown, Spore Shroom, Ban Stamp) temporarily bias the weights for a spin, and those effects still stack on top of your settings.
The Joker is not adjustable: its chance comes from cores and the game caps it at 5%.

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
   | `love.graphics.present` | Per-frame update and overlay drawing |
   | `love.handlers` | Input |
   | `require` | Patching game modules as they load |

4. **Symbol Odds** rewrites `src.data.constants`' `slot.symbolWeights`, which the game reads on every roll.
   It also updates the base weights that cores restore after their one-spin effects.

When launched from Steam, `launch.sh` takes two extra steps:

- It removes `DYLD_*` variables, because Steam's overlay injection crashes `lldb`. As a result, the Steam overlay is unavailable while using tweaks.
- It re-executes itself natively, because the Steam client runs under Rosetta. The game itself always runs natively (arm64).

## Adding a feature

1. Create `features/<name>.lua`:

   ```lua
   return function(T)
     local cfg = T.config.load("<name>", { enabled = true }) -- config/<name>.lua
     local F = {}
     function F.update(dt) end
     function F.draw() end                          -- after the game has drawn
     function F.keypressed(key) return false end    -- return true to swallow
     function F.mousepressed(x, y, button) return false end
     function F.mousereleased(x, y, button) return false end
     function F.onRequire(name, module) end         -- a game module was loaded
     return F
   end
   ```

2. Add `"<name>"` to `FEATURES` at the top of `loader.lua`.
3. If the feature changes gameplay, call `T.taint("<reason>")` while it's active.

Other helpers:

- `T.log(fmt, ...)` writes to the log.
- `T.font(px)` returns a cached font.
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
- `SB_SELFTEST=1 ./launch.sh` runs a self-test:
  - samples the game's real symbol picker 200,000 times and logs the distribution;
  - opens the panel through a synthetic `F8` key event;
  - saves `logs/selftest.png`.
- Game updates can change internals. The code was written against Slotbound 1.0.3.

## License

[MIT](LICENSE) © Yanchen Chen. Covers this project's own code only. Slotbound is © Optima Arch.
