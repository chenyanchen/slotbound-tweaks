# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An unofficial tweak toolkit for the Steam game Slotbound (LÖVE 11.5 / LuaJIT, written against game version 1.0.3). It runs extra Lua inside the live game process: via `lldb` on macOS Apple Silicon, and via a small built-in debugger (`inject.cs`) on Windows x64 (verified with Slotbound 1.0.4 on Windows Server 2022, from a terminal and via the Steam launch option). It never modifies, decrypts, or redistributes game files — keep it that way.

## Commands

There is no build step, linter, or unit-test suite. All verification happens against the running game (Steam must be running, game must be installed).

| Command | Purpose |
|---|---|
| `./launch.sh` | Launch the game with tweaks |
| `SB_DRYRUN=1 ./launch.sh` | Check `lldb` / `python3` only; does not start the game |
| `SB_SELFTEST=1 ./launch.sh` | Launch, then run `tools/selftest.lua`: samples the game's real symbol picker 200,000×, opens the panel with a synthetic `F8`, saves `logs/selftest-<tab>.png` for each tab |

Windows: `launch.bat` (same `SB_DRYRUN` / `SB_SELFTEST` env vars, set with `set VAR=1` first). It writes the same log files.

`launch.sh` redirects all of its own output to `logs/launch.log`, so the terminal stays silent — read the logs to see results:

- `logs/launch.log` — launcher
- `logs/inject.log` — lldb / `inject.py` (check here first if tweaks don't appear)
- `logs/tweaks.log` — `T.log` output from the loader and features (`SELFTEST` lines land here)
- `logs/game.log` — game stdout/stderr

`config/` and `logs/` are gitignored local state.

## Architecture

Three stages, each in a different runtime:

1. **`launch.sh` (bash)** — strips `DYLD_*` vars (Steam's overlay injection crashes `lldb`), re-execs itself as arm64 when inherited x86_64 from Steam's Rosetta client, passes parameters to the next stage through `SB_*` env vars, runs `lldb` in batch mode, then stays alive polling the game pid so Steam sees the game as running.
2. **`inject.py` (lldb's embedded Python)** — launches the game, breaks on `luaL_loadbuffer`, and waits for the call whose chunk name (register `x3`) is `@main.lua`. At that point `x0` is the `lua_State*`; it calls `luaL_loadfile` + `lua_pcall` on `loader.lua` through expression evaluation, then detaches. The register usage is arm64-specific. Any failure is logged and the game continues unmodified.

On Windows, stages 1-2 are replaced by:

- **`launch.bat` → `launch.ps1`** — the `.bat` forces 64-bit PowerShell via `Sysnative` (Steam is 32-bit, so its child cmd.exe is too; a 32-bit debugger cannot debug the 64-bit game). `launch.ps1` finds the game through Steam's `libraryfolders.vdf`, compiles `inject.cs` with `Add-Type`, then waits on the game pid.
- **`inject.cs`** — C# 5 (the compiler bundled with PowerShell 5.1: no `$""`, no `?.`, no `=>` members). Starts the game with `DEBUG_ONLY_THIS_PROCESS`, finds the Lua API by parsing PE exports of loaded modules (`lua51.dll` in stock LÖVE), puts an `int3` on `luaL_loadbuffer`, and checks `r9` (chunk name) / `rcx` (`lua_State*`) per the Win64 ABI. On `@main.lua` it redirects the thread to generated x64 code that calls `luaL_loadfile` + `lua_pcall` (+ `lua_tolstring`/`lua_settop` on error) and traps back with `int3`, restores the saved context, and detaches. The loader path is passed with forward slashes (loader.lua derives `ROOT` by splitting on `/`) and as an 8.3 short path if it contains non-ASCII characters.

3. **`loader.lua` (game's LuaJIT state, before the game's `main.lua` runs)** — builds the shared table `T` (also `_G.__SLOTBOUND_TWEAKS`), installs hooks, loads `i18n.lua` (`T.lang`, `T.tr`, `T.gameText`, `T.font`), then `panel.lua` (the shared `F8` window, `T.panel`, first in dispatch order) then the shared tab builders `weights.lua` (`T.weights`, the bar editor used by Symbol Weights and Unit Grades) and `picker.lua` (`T.picker`, the slots + catalog tab used by Items, Cores and Imprints), then each name in `FEATURES` from `features/<name>.lua`.

### Constraints inside the game's Lua state

- **Do not wrap `love.update` / `love.draw`.** The game re-wraps them itself and wrapping again caused a stack overflow. The loader hooks `love.graphics.present` (per-frame `update` then `draw`), `love.handlers.<event>` (input, with swallow support), and global `require` (`onRequire`) instead.
- **Use `T.loadLua(relpath)`, not `loadfile`/`require`**, for this repo's files: the game's bootstrap replaces `loadfile` with one that only accepts its encrypted package.
- It's Lua 5.1 / LuaJIT: `loadstring`, `setfenv`, `unpack`.
- The game's source is not available. Game internals are reached through `package.loaded["src...."]` and by scanning closures with `debug.getupvalue` / `debug.setupvalue` using structural fingerprints (e.g. the weighted picker is identified by its upvalues `(constants, {"W","A","S","M","H","D"})`; the cores module's private state is found as an upvalue of `cores.finishSpinModifiers`). These are the parts most likely to break on a game update; guard them and fail soft.
- **Don't hardcode game content.** Read lists from the game so updates that add content need no changes here: symbols via `T.gameSymbols()` (keys of `constants.slot.symbolWeights`; `T.isSymbolList(t)` for the picker fingerprint), grades via `constants.unitGrades.order`, items via `src.game.item.getAll()`, cores via `src.game.cores.getIds()`, names and labels via the game's language tables (`T.gameText`, in the game's current language; see Languages), filters via `T.picker.filtersFrom(catalog, ...)`. Hardcode only display fallbacks (e.g. the C/U/R/L rarity names, which the game has no labels for, as `rarity.<code>` in `lang/*.lua`) and make unknown values still work.

### Languages

The panel follows the game's language (`currentGameLang`), looked up on every draw so switching in the game's settings applies at once. Text the game has comes from the game: `T.gameText(key)` (current language, then English) for names, effects, grade labels, item types, symbol names (`merc_contract_unit_<sym>`). The tweaks' own text goes through `T.tr(key, ...)`: `lang/<code>.lua` (en, zh, ja, ko), falling back to `lang/en.lua`; a few keys (`items`, `cores`, `units`, `shop`) take the game's word when it has one (`GAME_WORDS` in `i18n.lua`; only where the game's word fits the context: its "Off" reads as "Close" in Chinese, so on/off are our own). Never hardcode visible text: add the key to `lang/en.lua` and the other `lang/*.lua` with the same `%s`/`%d` placeholders in the same order. Spec fields shown as text (`title`, `intro`, `note`, `help`, `unavailableText`, `noneText`) may be functions so they follow the language. `T.font(px)` picks, per language, the first of (LÖVE's default font, the game's TTF/OTF fonts found under the directory of `ui.fontPath`, system Arial) that can draw a sample of that language, rounds sizes to multiples of 10 px for the game's pixel fonts, and attaches the others as fallbacks. Fonts are TrueType only: the game's `.fnt` bitmap fonts can't be sized.

### Features

A feature file returns `function(T) return F end`; `F` may define `update(dt)`, `draw()`, `keypressed`, `mousepressed`, `mousereleased` (return `true` to swallow), and `onRequire(name, module)`. Every call is `pcall`ed; a feature that throws is marked `_broken`, logged, and skipped from then on. To add one: create the file, add its name to `FEATURES` in `loader.lua`, and document it in the README's feature table.

UI goes in a tab of the shared panel, not a separate hotkey: `T.panel.addTab({ id, title, draw(x, y, w, h, s), keypressed(key), mousepressed(x, y, button), onShow() })`. The panel owns `F8`/`Esc`/`Tab`, swallows all keys while open and clicks on itself, and draws the shared leaderboard-status footer. Hit rects are rebuilt each frame in `draw`.

Per-feature settings live in `config/<name>.lua` via `T.config.load(name, defaults)` (merges with defaults, type-checked, creates the file if missing) and `T.config.save`.

### Leaderboard guard (must be preserved)

The game has online leaderboards. Any feature that changes gameplay must call `T.taint("<reason>")` while it is active. The loader wraps `src.leaderboard`'s `submit` and blocks it for the rest of the session once tainted (taint is never cleared; only a restart resets it). Do not weaken or bypass this.

### Items specifics

Owned items are `ui._itemPurchased` (copies of item defs plus `level`; `nil` until the run's first purchase, so treat it as empty and create it on first add) with a parallel key list `ui._itemPurchasedKeys` (`"p<n>"`; `ui._itemPanelNextId` is the *last* id handed out, so the next key is `+1`). Shop offers are `ui._itemOffers` (references to the defs). New entries are built with the global `restorePurchasedItems({{id=, level=}})` (what a run-save load uses) and spliced in. Every created or changed entry carries the `__slotboundTweaks` marker, which survives the run save, so a modified run taints later sessions too; planted shop-offer ids are kept in `config/items.lua` until the shop rerolls them. Editing is refused on the main menu (`phase == "menu"`) and during battles (`phase == "battle"`).

### Cores specifics

`src.game.cores`: `getActive()` returns a *copy* of the active list (`{ key, def, stacks, startWave, ... }`), `select(def, wave)` activates a core (appended; it does not reject duplicates, the tab does), `remove(key)` deactivates one, `exportState()` / `importState(s)` snapshot and restore the active list (handy to undo tests). The open selection screen is `ui._coreSelect` (`.active`, `.offers` = core defs); `ui._coreSelectOffersCache.offers` keeps the wave's offers. The run save stores cores as bare ids, so instead of a marker the keys of added or offered cores are kept in `config/cores.lua` and taint the session while active or offered; they are pruned only while a run is going (not on the menu), so continuing a saved run still taints. Editing is refused on the menu, in battle, and while `uiLocked` (spinning).

### Imprints specifics

Board units are `battlefield.rosterUnits` (a sparse list; the global `battlefield`). Each has `imprints` (a list of instances: a copy of `constants.imprint.definitions[id]` without `levels`, plus `level`, `maxLevel`, `rarity` and that level's `desc`/`shortDesc`/`stats`) and `maxImprintSlots` (default per grade in `constants.imprint.slots`). An imprint's `rarity` is the grade whose units pass it on: `src.game.battlefield.signatureImprint(unit)` maps symbol × grade to an id, which the tab inverts. Levels are set with the game's own helper, a 2-parameter upvalue of `battlefield.dropRoster` (the absorb path) found by its bytecode constants and verified on a scratch copy, with a built-in fallback. The run save deep-copies `rosterUnits`, so the `__slotboundTweaks` marker on created or changed instances survives and taints later sessions. Editing is refused on the menu, in battle, while `uiLocked`, and while the game's imprint choice modal (`imprintModal.active`) is open. `src.ui.imprint` and `src.game.unit_abilities` are the game's imprint UI and unit skills; `src.data.randomoption` is a different system (random stat options on spawned units, `unit.randomOptions`).

### Unit Grades specifics

`battlefield.spawn` (the global `battlefield` object, not the `src.game.battlefield` module) reads `constants.unitGrades.probabilities` on every spawn, passes it through `require("src.game.luck").grade.boostedProbs` (the pity; returns a boosted copy, or `nil` for no boost), and rolls along `unitGrades.order` with a local function (upvalue 3 of `spawn`); the probabilities must sum to 1, the remainder falls back to normal. `unit_grades.lua` writes normalized values in place (keeping `special`), treats any rewrite it did not make as new game defaults (`applyUpgradeEffects` rewrites the table from meta upgrades), and while modified wraps `boostedProbs` to return `nil`.

### Symbol Weights specifics

The game reads `require("src.data.constants").slot.symbolWeights` on every roll. Some cores temporarily swap that table for one spin and restore it from `_baseSymbolWeights` in the cores module's private state. `symbol_weights.lua` therefore writes to **both**: the base copy always, and the live table only when no core effect is currently applied (`_weightsApplied`), so core effects still stack on top of the user's weights.
