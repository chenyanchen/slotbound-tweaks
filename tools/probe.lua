-- Probe: a file-based REPL inside the running game, for finding game
-- internals while developing a feature. Loaded by loader.lua only when
-- SB_PROBE=1 (see docs/investigating.md):
--
--   SB_PROBE=1 ./launch.sh
--
-- Write Lua to logs/probe-in.lua; about once a second, when the file has
-- changed, it runs in the game's Lua state and what it prints with out()
-- lands in logs/probe-out.txt (errors as "ERROR: ..."). Globals resolve to
-- the game's _G. Helpers available to the snippet:
--
--   out(...)                   append a line to the output
--   dump(v, depth)             a table as text (default depth 2)
--   keys(t)                    "key:type" of a table's own keys, sorted (rawget, so
--                              tables with a throwing __index are safe)
--   modules(pattern)           names in package.loaded matching a Lua pattern
--   ups(f)                     a function's upvalues: "index:type"
--   consts(f)                  the identifiers/strings in a function's bytecode
--                              (field names, string literals): what it touches
--   findFns(needle)            paths of game functions whose bytecode contains
--                              `needle`, searched from src.* modules and _G,
--                              through upvalues ("path^3" = upvalue 3 of path)
--   lang(pattern, code)        language keys whose text (default: English)
--                              matches `pattern`: "key = text"
--   shot(name)                 save a screenshot to logs/probe-<name>.png
--   T                          the tweaks table
--
-- Read-only by default: nothing here changes the game unless the snippet
-- does. See docs/investigating.md for how to change state safely.
return function(T)
  local IN = T.root .. "/logs/probe-in.lua"
  local OUT = T.root .. "/logs/probe-out.txt"
  local P, last, timer, pendingShot = {}, nil, 0, nil

  local function dump(v, depth, seen, ind)
    depth = depth or 2; seen = seen or {}; ind = ind or ""
    if type(v) ~= "table" then return tostring(v) end
    if seen[v] then return "<cycle>" end
    if depth <= 0 then return "{...}" end
    seen[v] = true
    local out, n = {}, 0
    for k, x in next, v do
      n = n + 1
      if n > 80 then out[#out + 1] = ind .. "  ..."; break end
      out[#out + 1] = ind .. "  " .. tostring(k) .. " = " .. dump(x, depth - 1, seen, ind .. "  ")
    end
    return "{\n" .. table.concat(out, "\n") .. "\n" .. ind .. "}"
  end

  local function keys(t)
    local list = {}
    for k, v in next, t do
      list[#list + 1] = tostring(k) .. ":" .. type(v) .. (type(v) == "table" and ("#" .. #v) or "")
    end
    table.sort(list)
    return list
  end

  local function modules(pattern)
    local list = {}
    for name in pairs(package.loaded) do
      if type(name) == "string" and (not pattern or name:find(pattern)) then list[#list + 1] = name end
    end
    table.sort(list)
    return list
  end

  local function ups(f)
    local list = {}
    for i = 1, 255 do
      local n, v = debug.getupvalue(f, i)
      if n == nil then break end
      list[#list + 1] = i .. ":" .. type(v)
    end
    return list
  end

  local function consts(f)
    local ok, bc = pcall(string.dump, f)
    if not ok then return {} end
    local list, seen = {}, {}
    for s in bc:gmatch("[%a_][%w_%.]+") do
      if #s >= 3 and not seen[s] then seen[s] = true; list[#list + 1] = s end
    end
    return list
  end

  local function findFns(needle)
    local seenF, seenT, hits = {}, {}, {}
    local function fn(f, path, depth)
      if seenF[f] or depth > 6 then return end
      seenF[f] = true
      local ok, bc = pcall(string.dump, f)
      if ok and bc:find(needle, 1, true) then hits[#hits + 1] = path end
      for i = 1, 255 do
        local n, v = debug.getupvalue(f, i)
        if n == nil then break end
        if type(v) == "function" then fn(v, path .. "^" .. i, depth + 1) end
      end
    end
    local function tbl(t, path, depth)
      if seenT[t] or depth > 2 then return end
      seenT[t] = true
      for k, v in next, t do
        if type(v) == "function" then fn(v, path .. "." .. tostring(k), 0)
        elseif type(v) == "table" then tbl(v, path .. "." .. tostring(k), depth + 1) end
      end
    end
    for _, name in ipairs(modules("^src")) do
      local m = package.loaded[name]
      if type(m) == "table" then tbl(m, name, 0) elseif type(m) == "function" then fn(m, name, 0) end
    end
    for k, v in next, _G do
      if type(v) == "function" then fn(v, "_G." .. tostring(k), 0)
      elseif type(v) == "table" and k ~= "package" and k ~= "_G" then tbl(v, "_G." .. tostring(k), 1) end
    end
    table.sort(hits)
    return hits
  end

  local function lang(pattern, code)
    local L = package.loaded["src.data.language"]
    local t = type(L) == "table" and L[code or "en"]
    local list = {}
    for k, v in next, type(t) == "table" and t or {} do
      if type(v) == "string" and v:find(pattern) then list[#list + 1] = tostring(k) .. " = " .. v:gsub("\n", " ") end
    end
    table.sort(list)
    return list
  end

  function P.update(dt)
    if pendingShot then
      local name = pendingShot
      pendingShot = nil
      love.graphics.captureScreenshot(function(img)
        local f = io.open(T.root .. "/logs/probe-" .. name .. ".png", "wb")
        if f then f:write(img:encode("png"):getString()); f:close() end
      end)
    end
    timer = timer - dt
    if timer > 0 then return end
    timer = 1
    local f = io.open(IN, "r")
    if not f then return end
    local src = f:read("*a"); f:close()
    if src == last then return end
    last = src
    local buf = {}
    local env = setmetatable({
      T = T, dump = dump, keys = keys, modules = modules, ups = ups, consts = consts,
      findFns = findFns, lang = lang,
      shot = function(name) pendingShot = tostring(name or "shot") end,
      out = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
          local v = select(i, ...)
          parts[i] = type(v) == "table" and v[1] ~= nil and type(v[1]) == "string" and table.concat(v, "\n") or tostring(v)
        end
        buf[#buf + 1] = table.concat(parts, "\t")
      end,
    }, { __index = _G })
    local chunk, err = loadstring(src, "=probe-in")
    local ok, res
    if chunk then setfenv(chunk, env); ok, res = pcall(chunk) else ok, res = false, err end
    if not ok then buf[#buf + 1] = "ERROR: " .. tostring(res) end
    local o = io.open(OUT, "w")
    if o then o:write(table.concat(buf, "\n"), "\n"); o:close() end
  end

  T.log("probe: watching logs/probe-in.lua")
  return P
end
