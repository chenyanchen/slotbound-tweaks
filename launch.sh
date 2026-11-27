#!/bin/bash
# Launch Slotbound with Slotbound Tweaks.
#   Terminal:            ./launch.sh
#   Steam launch option: "/path/to/slotbound-tweaks/launch.sh" %command%
# Env:
#   SB_DRYRUN=1   check the environment (lldb, python3) without starting the game
#   SB_SELFTEST=1 run tools/selftest.lua after startup
#   SB_PROBE=1    run tools/probe.lua: a file-based REPL in the game (docs/investigating.md)
set -uo pipefail

# Steam injects its overlay via DYLD_INSERT_LIBRARIES (arm64/x86_64 only);
# that makes the arm64e lldb crash at load. Drop every DYLD_* variable.
for v in $(compgen -e | grep '^DYLD_'); do unset "$v"; done

# Steam's client runs under Rosetta, so this script inherits x86_64. The
# Command Line Tools' lldb/xcrun are arm64-only: re-exec natively.
if [[ "$(uname -m)" == "x86_64" && "$(sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]]; then
  exec /usr/bin/arch -arm64 /bin/bash "$0" "$@"
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/logs" "$DIR/config"
exec >>"$DIR/logs/launch.log" 2>&1
echo "=== launch.sh $(date '+%F %T') arch=$(uname -m) args: $*"

if [[ "${SB_DRYRUN:-}" == "1" ]]; then
  echo "dyld vars: $(compgen -e | grep '^DYLD_' | tr '\n' ' ')"
  /usr/bin/lldb --version | head -1 && echo "lldb OK"
  /usr/bin/python3 -c 'print("python3 OK")'
  exit 0
fi

GAME="$HOME/Library/Application Support/Steam/steamapps/common/Slotbound/Slotbound.app/Contents/MacOS/Slotbound"
if [[ $# -gt 0 ]]; then
  case "$1" in
    *.app) GAME="$1/Contents/MacOS/Slotbound"; shift ;;
    */Slotbound) GAME="$1"; shift ;;
  esac
fi
[[ -x "$GAME" ]] || { echo "Slotbound not found: $GAME"; exit 1; }

export SteamAppId="${SteamAppId:-4459590}"
export SteamGameId="${SteamGameId:-4459590}"
export SB_GAME="$GAME"
export SB_LOADER="$DIR/loader.lua"
export SB_OUT="$DIR/logs/game.log"
export SB_PID="$DIR/logs/.game.pid"
export SB_ARGS="$(/usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")"

rm -f "$SB_PID"
/usr/bin/lldb -b -Q -o "command script import '$DIR/inject.py'" > "$DIR/logs/inject.log" 2>&1

# Keep this script alive while the game runs so Steam still sees it as running.
if [[ -s "$SB_PID" ]]; then
  PID="$(cat "$SB_PID")"
  while kill -0 "$PID" 2>/dev/null; do sleep 2; done
fi
