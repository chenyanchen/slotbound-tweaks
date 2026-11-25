-- Slotbound Tweaks loader.
-- inject.py runs this file inside the game's Lua state right before the game's
-- main.lua executes. It installs a few hooks and loads every feature listed in
-- FEATURES from features/<name>.lua.
--
-- Feature contract: features/<name>.lua returns `function(T) return feature end`
-- where `feature` may define any of:
--   update(dt)                       every frame, before present
--   draw()                           every frame, after the game has drawn
--   keypressed(key, scancode, rep)   return true to swallow the event
--   mousepressed(x, y, button)       return true to swallow the event
--   mousereleased(x, y, button)      return true to swallow the event
--   onRequire(name, module)          a game module was required
-- A feature that throws is disabled (logged), the game keeps running.
-- Features with UI add a tab to the shared F8 panel (panel.lua, T.panel);
-- picker.lua (T.picker) builds the slot + catalog tabs (Items, Cores).

local FEATURES = { "symbol_weights", "items", "cores", "spin_log" }

local SRC = debug.getinfo(1, "S").source:gsub("^@", "")
local ROOT = SRC:match("^(.*)/[^/]*$") or "."

local T = {
  root = ROOT,
  features = {},   -- name -> feature table
  order = {},      -- feature names in load order
  tainted = false, -- gameplay was modified this session: leaderboard submits blocked
  taintReasons = {},
}
_G.__SLOTBOUND_TWEAKS = T

----------------------------------------------------------------------------
-- logging
----------------------------------------------------------------------------
local LOG_PATH = ROOT .. "/logs/tweaks.log"
function T.log(fmt, ...)
  local f = io.open(LOG_PATH, "a")
  if not f then return end
  f:write(os.date("[%H:%M:%S] "), string.format(fmt, ...), "\n")
  f:close()
end
local log = T.log

----------------------------------------------------------------------------
-- file loading (the game's bootstrap replaces the global loadfile with a
-- loader that only accepts files from its encrypted package)
----------------------------------------------------------------------------
function T.loadLua(rel)
  local path = ROOT .. "/" .. rel
  local f = assert(io.open(path, "r"))
  local src = f:read("*a"); f:close()
  return assert(loadstring(src, "@" .. path))()
end

----------------------------------------------------------------------------
-- per-feature config: config/<name>.lua, a plain `return { ... }` table
----------------------------------------------------------------------------
local function serialize(v, ind)
  ind = ind or ""
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "boolean" then return tostring(v) end
  if t == "number" then
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.6g", v)
  end
  if t ~= "table" then return "nil" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return type(a) == "number"
  end)
  local out = { "{" }
  for _, k in ipairs(keys) do
    local ks = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. serialize(k) .. "]")
    out[#out + 1] = ind .. "  " .. ks .. " = " .. serialize(v[k], ind .. "  ") .. ","
  end
  out[#out + 1] = ind .. "}"
  return table.concat(out, "\n")
end

local function merge(defaults, loaded)
  local out = {}
  for k, v in pairs(defaults) do
    local lv = loaded and loaded[k]
    if type(v) == "table" and type(lv) == "table" then out[k] = merge(v, lv)
    elseif lv ~= nil and (v == nil or type(lv) == type(v)) then out[k] = lv
    else out[k] = v end
  end
  if loaded then
    for k, lv in pairs(loaded) do if out[k] == nil then out[k] = lv end end
  end
  return out
end

T.config = {}
function T.config.path(name) return ROOT .. "/config/" .. name .. ".lua" end

function T.config.save(name, tbl)
  local f = io.open(T.config.path(name), "w")
  if not f then log("cannot write config %s", name); return end
  f:write("-- Slotbound Tweaks: ", name, " (edited in-game; safe to edit by hand)\nreturn ",
    serialize(tbl), "\n")
  f:close()
end

-- Returns defaults merged with config/<name>.lua; writes the file if missing.
function T.config.load(name, defaults)
  defaults = defaults or {}
  local f = io.open(T.config.path(name), "r")
  if not f then
    T.config.save(name, defaults)
    return merge(defaults, nil)
  end
  local src = f:read("*a"); f:close()
  local chunk, err = loadstring(src, "=" .. name .. ".lua")
  if not chunk then log("config %s: %s (using defaults)", name, tostring(err)); return merge(defaults, nil) end
  setfenv(chunk, {})
  local ok, t = pcall(chunk)
  if not ok or type(t) ~= "table" then log("config %s invalid (using defaults)", name); return merge(defaults, nil) end
  return merge(defaults, t)
end

----------------------------------------------------------------------------
-- shared helpers
----------------------------------------------------------------------------
local fonts = {}
function T.font(px)
  px = math.max(10, math.floor(px + 0.5))
  local f = fonts[px]
  if not f then f = love.graphics.newFont(px); fonts[px] = f end
  return f
end

-- Mark this session as modified. Leaderboard submissions stay blocked until
-- the game is restarted.
function T.taint(reason)
  if not T.taintReasons[reason] then
    T.taintReasons[reason] = true
    log("session tainted (%s): leaderboard submissions disabled until restart", reason)
  end
  T.tainted = true
end

----------------------------------------------------------------------------
-- leaderboard guard
----------------------------------------------------------------------------
local lbPatched = false
local function patchLeaderboard(lb)
  if lbPatched then return end
  lb = lb or package.loaded["src.leaderboard"]
  if type(lb) ~= "table" or type(lb.submit) ~= "function" then return end
  local orig = lb.submit
  lb.submit = function(...)
    if T.tainted then
      log("blocked leaderboard submit (session modified)")
      return nil
    end
    return orig(...)
  end
  lbPatched = true
  log("leaderboard submit guarded")
end

----------------------------------------------------------------------------
-- feature dispatch
----------------------------------------------------------------------------
local function call(name, method, ...)
  local feat = T.features[name]
  local fn = feat and feat[method]
  if not fn or feat._broken then return nil end
  local ok, res = pcall(fn, ...)
  if not ok then
    feat._broken = true
    log("feature %s failed in %s, disabled: %s", name, method, tostring(res))
    return nil
  end
  return res
end

local function broadcast(method, ...)
  for _, name in ipairs(T.order) do call(name, method, ...) end
end

local function firstSwallows(method, ...)
  for _, name in ipairs(T.order) do
    if call(name, method, ...) then return true end
  end
  return false
end

----------------------------------------------------------------------------
-- hooks
-- love.update/love.draw are re-wrapped by the game itself (runtime
-- diagnostics, presentation pacer); wrapping them again recursed into a stack
-- overflow. These hook points are stable instead:
--   love.graphics.present : once per frame, after the game has drawn
--   love.handlers.<event> : the event dispatch table used by love.run
--   require               : to patch game modules the moment they load
----------------------------------------------------------------------------
local lastTime
local origPresent = love.graphics.present
love.graphics.present = function(...)
  local now = love.timer.getTime()
  local dt = lastTime and (now - lastTime) or 0
  lastTime = now
  if not lbPatched then pcall(patchLeaderboard) end
  broadcast("update", dt)
  broadcast("draw")
  return origPresent(...)
end

for _, ev in ipairs({ "keypressed", "mousepressed", "mousereleased" }) do
  local orig = love.handlers[ev]
  love.handlers[ev] = function(...)
    if firstSwallows(ev, ...) then return end
    if orig then return orig(...) end
  end
end

local origRequire = require
_G.require = function(name, ...)
  local mod = origRequire(name, ...)
  if name == "src.leaderboard" then pcall(patchLeaderboard, mod) end
  broadcast("onRequire", name, mod)
  return mod
end

----------------------------------------------------------------------------
-- load the shared panel (first in dispatch order), then the features
----------------------------------------------------------------------------
do
  local ok, res = pcall(function() return T.loadLua("panel.lua")(T) end)
  if ok and type(res) == "table" then
    T.features.panel = res
    T.order[#T.order + 1] = "panel"
  else
    log("panel failed to load: %s", tostring(res))
    -- keep T.panel usable so features can still register tabs
    T.panel = { addTab = function() end, isShowing = function() return false end }
  end
  local okP, errP = pcall(function() return T.loadLua("picker.lua")(T) end)
  if not okP then log("picker failed to load: %s", tostring(errP)) end
end

for _, name in ipairs(FEATURES) do
  local ok, res = pcall(function() return T.loadLua("features/" .. name .. ".lua")(T) end)
  if ok and type(res) == "table" then
    T.features[name] = res
    T.order[#T.order + 1] = name
  else
    log("feature %s failed to load: %s", name, tostring(res))
  end
end

if os.getenv("SB_SELFTEST") == "1" then
  local ok, res = pcall(function() return T.loadLua("tools/selftest.lua")(T) end)
  if ok and type(res) == "table" then
    T.features.selftest = res
    T.order[#T.order + 1] = "selftest"
  else
    log("selftest failed to load: %s", tostring(res))
  end
end

log("loader ready: %s", table.concat(T.order, ", "))
