# Investigating the game

How to find what a new feature needs inside Slotbound: where the data lives, which game function does the job, and what the text is called. The game's code ships encrypted and this project never decrypts it, so everything here happens at runtime, in the game's own Lua state.

## What survives, and what doesn't

The game's bytecode is stripped: local variable names, parameter names and line numbers are gone (`debug.getinfo(f).linedefined` is 0, `debug.getlocal` returns nil). Everything the program needs to run is still there:

- **Module and field names.** Lua tables are looked up by string keys at runtime (`unit.imprints` is a hash lookup of `"imprints"`), so they can't be stripped. `package.loaded["src.game.cores"]` is an ordinary table of named functions.
- **Bytecode constants.** `string.dump(f)` returns a function's bytecode, whose constant table holds every field name and string literal the function uses. That tells you what a function touches, without decompiling it.
- **Closures.** A module's private functions and state are upvalues of its public functions, reachable with `debug.getupvalue`.

Control flow is not readable (there is no decompiler in this workflow), so conclusions about *when* the game does something are inferences. Say so when you rely on one, and check it in the game.

## The probe

`tools/probe.lua` is a file-based REPL in the running game. Start the game with it:

```sh
SB_PROBE=1 ./launch.sh          # Windows: set SB_PROBE=1, then launch.bat
```

Write Lua to `logs/probe-in.lua`. About once a second, when the file has changed, it runs in the game and whatever it passes to `out()` is written to `logs/probe-out.txt` (errors as `ERROR: ...`). Globals are the game's `_G`; `T` is the tweaks table. The helpers are listed at the top of `tools/probe.lua`.

```lua
-- logs/probe-in.lua
out(modules("^src%.game"))                      -- which game modules exist
out(keys(package.loaded["src.game.cores"]))     -- what one of them exports
out(dump(package.loaded["src.data.constants"].imprint.slots))
```

Most data only exists during a run: start or continue one (and spin a few times) before probing it.

## Finding things

| Looking for | How | Example from this repo |
|---|---|---|
| A system's module | `modules("pattern")`, then `keys(...)` | `src.ui.imprint`, `src.data.constants` → `imprint.definitions` |
| Static data | `dump(table, depth)` | imprint definitions with `levels[n].desc` / `.stats` |
| Live state | the globals `ui`, `battlefield`, `phase`, `uiLocked`; `keys(battlefield)` | `battlefield.rosterUnits[i].imprints`, `ui._itemPurchased` |
| Who reads or writes a field | `findFns("fieldName")`, then `consts(f)` on the hits | `findFns("imprints")` led to `battlefield.dropRoster` (the absorb path) |
| A private function | walk the upvalues of a public one: `ups(f)`, `debug.getupvalue(f, i)` | the imprint level helper is an upvalue of `dropRoster` |
| The game's own word for something | `lang("pattern", code)` | `lang("Imprint")` → `imprint_gained_label`, `collection_imprint_slots` |
| Text keys for content | `lang` on a known name, then follow the key pattern | `imprint.name.<id>`, `imprint.desc.<id>_<level>`, `grade.label.<grade>`, `unit.name.<key>` |
| Icons and fonts | the paths in the data (`def.icon`), `love.filesystem.getDirectoryItems` | `love.graphics.newImage(def.icon)`; fonts under the directory of `ui.fontPath` |

Use the game's text only where it fits the context, and check it in every language: the game's Korean `imprint_gained_label` means "acquired imprint", and its Chinese "Off" (`关闭`) reads as "Close" on a button.

## Locating a private function robustly

Upvalue indexes and closure layouts change between game versions. Don't store "upvalue 16 of dropRoster"; find the function by what it is:

1. Walk the candidates (upvalues of a public function, `findFns` hits).
2. Filter by shape: `debug.getinfo(f, "u").nparams`, the bytecode constants it must contain (`"levels"`, `"definitions"`) and must not (`"imprints"`).
3. **Verify on a scratch copy** before using it: call it on a copy of real data and check the result (`helper(copy, 2)` sets `copy.level == 2` and the level's `desc`).
4. Keep a fallback that does the same thing by hand, log which one is in use, and fail soft when neither works.

The same applies to data found by shape (see `T.isSymbolList`).

## Changing state safely

- **Prefer the game's own code path**: the function a run-save load or the game's own UI uses (`restorePurchasedItems`, `cores.select` / `cores.remove`, the absorb level helper). Building game objects by hand misses fields the game sets.
- **Try changes on copies first**, and snapshot what you change so you can put it back (`cores.exportState()` / `importState(s)`, a copy of a unit's `imprints`).
- **Don't call functions you don't understand** just to see what they return: `assets.load()` reloads the game's assets. Read their constants first.
- **Tables can throw on unknown keys**: `love.handlers` raises "Unknown event" from `__index`. Iterate with `next` and read with `rawget` (the probe's helpers do).
- **Probing a real run changes it.** Anything a test edits counts as modified (see the leaderboard guard); restore what you changed.

## From findings to a feature

- Read every list from the game (no hardcoded content; see CLAUDE.md).
- Use the game's own code path, located robustly, failing soft.
- Refuse editing when the game is mid-action: main menu, battle, `uiLocked` (spinning), the game's own modals.
- Call `T.taint("<reason>")` while the change is active, and make sure a modified run still taints after a restart (a marker field that the run save keeps, or ids remembered in `config/<name>.lua`).
- Text: `T.gameText` for anything the game names, `T.tr` with keys in every `lang/*.lua` for the tweaks' own text; fonts from `T.font`.
- UI: a panel tab built on `T.weights.tab` or `T.picker.tab`; `T.panel.stepper` for `-` / `+`.
- Document what you found in CLAUDE.md (a "<Feature> specifics" section: where the data is, which game function is used, when editing is refused) and the feature in the README table.
- Verify in the game: `SB_SELFTEST=1 ./launch.sh` for screenshots of every tab, the probe for live checks.

## Practical notes

- Steam must be running. Check for a running game first (`pgrep -lf Slotbound`): launching again starts a second instance.
- The probe and the self-test are development tools, loaded only with their environment variables. Don't commit temporary edits to `loader.lua`.
- In zsh, a glob with no match aborts the whole command (`rm logs/selftest-*.png`); use `find logs -name 'selftest-*.png' -delete`.
