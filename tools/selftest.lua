-- Self-test, loaded by loader.lua only when SB_SELFTEST=1:
--   SB_SELFTEST=1 ./launch.sh
-- 1) samples the game's own weighted symbol picker and logs the distribution
-- 2) opens the tweaks panel through a real (synthetic) F8 key event
-- 3) saves a screenshot of every tab to logs/selftest-<tab>.png
return function(T)
  local ORDER = { "W", "A", "S", "M", "H", "D" }
  local S = { t = 0 }

  -- The picker is a local in src/game/slot.lua whose upvalues are
  -- (constants, {W,A,S,M,H,D}). Search the slot module's closures for it.
  local function findPicker()
    local slot, C = package.loaded["src.game.slot"], package.loaded["src.data.constants"]
    if type(slot) ~= "table" or type(C) ~= "table" then return nil end
    local seen = {}
    local function scan(f, depth)
      if seen[f] or depth > 4 then return nil end
      seen[f] = true
      local ups = {}
      for i = 1, 60 do
        local n, v = debug.getupvalue(f, i)
        if n == nil then break end
        ups[i] = v
      end
      if ups[1] == C and type(ups[2]) == "table" and ups[2][1] == "W" and #ups[2] == 6 and ups[3] == nil then
        return f
      end
      for _, v in pairs(ups) do
        if type(v) == "function" then
          local r = scan(v, depth + 1)
          if r then return r end
        end
      end
    end
    for _, v in pairs(slot) do
      if type(v) == "function" then
        local r = scan(v, 0)
        if r then return r end
      end
    end
  end

  local function sample()
    local pick = findPicker()
    if not pick then T.log("SELFTEST picker not found"); return end
    local w = package.loaded["src.data.constants"].slot.symbolWeights
    local n, counts, tot = 200000, {}, 0
    for _ = 1, n do
      local s = pick(nil)
      counts[s] = (counts[s] or 0) + 1
    end
    for _, k in ipairs(ORDER) do tot = tot + (w[k] or 0) end
    local parts = {}
    for _, k in ipairs(ORDER) do
      parts[#parts + 1] = string.format("%s=%.2f%%(want %.2f%%)", k, 100 * (counts[k] or 0) / n,
        100 * (w[k] or 0) / tot)
    end
    T.log("SELFTEST picker x%d: %s", n, table.concat(parts, " "))
  end

  local function shoot(name)
    love.graphics.captureScreenshot(function(img)
      local f = io.open(T.root .. "/logs/selftest-" .. name .. ".png", "wb")
      if f then f:write(img:encode("png"):getString()); f:close() end
      T.log("SELFTEST screenshot saved to logs/selftest-%s.png", name)
    end)
  end

  function S.update(dt)
    S.t = S.t + dt
    local odds = T.features.symbol_weights
    if not S.sampled and odds and odds.defaults and S.t > 3 then
      S.sampled = true
      local ok, err = pcall(sample)
      if not ok then T.log("SELFTEST sample error: %s", tostring(err)) end
      love.event.push("keypressed", "f8", "f8", false)
    end
    if S.sampled and not S.checked and S.t > 4 then
      S.checked = true
      S.tab = 0
      T.log("SELFTEST panel open after synthetic F8: %s", tostring(T.panel and T.panel.open))
    end
    -- one screenshot per tab, one second apart, switching with a synthetic Tab
    local tabs = T.panel and T.panel.tabs or {}
    if S.checked and S.tab < #tabs and S.t > 5 + S.tab * 1.5 then
      S.tab = S.tab + 1
      local cur = T.panel.activeTab()
      shoot(cur and cur.id or tostring(S.tab))
      if S.tab < #tabs then love.event.push("keypressed", "tab", "tab", false) end
    end
  end

  return S
end
