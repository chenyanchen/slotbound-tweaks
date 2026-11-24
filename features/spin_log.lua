-- Spin Log: per-spin diagnostics written to logs/tweaks.log.
-- Off by default; set `enabled = true` in config/spin_log.lua.
--
--   picks : what the game's weighted picker returned while building the grid
--   grid  : the grid once it has settled (after cores/items/luck rewrote it)
-- If picks follow your weights but the grid does not, something after the
-- roll (an item, a core, or the hidden luck correction) changed the cells.

return function(T)
  local cfg = T.config.load("spin_log", { enabled = false })
  if not cfg.enabled then return {} end

  local ORDER = { "W", "A", "S", "M", "H", "D" }
  local STABLE = 0.6 -- seconds the grid must stay unchanged to count as settled
  local F = { instances = setmetatable({}, { __mode = "k" }), picks = {}, events = {}, spin = 0 }

  local function isSymbolList(t)
    return type(t) == "table" and t[1] == "W" and t[6] == "D" and #t == 6
  end

  -- The weighted picker is a local in slot.lua with upvalues
  -- (constants, {W,A,S,M,H,D}); slot instances' methods close over it.
  local function hookPicker(inst)
    if F.pickerHooked then return end
    local C = package.loaded["src.data.constants"]
    for _, f in pairs(inst) do
      if type(f) == "function" then
        for i = 1, 40 do
          local n, u = debug.getupvalue(f, i)
          if n == nil then break end
          if type(u) == "function" then
            local _, a = debug.getupvalue(u, 1)
            local _, b = debug.getupvalue(u, 2)
            if a == C and isSymbolList(b) then
              local orig = u
              debug.setupvalue(f, i, function(...)
                local s = orig(...)
                if s ~= nil then F.picks[s] = (F.picks[s] or 0) + 1 end
                return s
              end)
              F.pickerHooked = true
              T.log("spin_log: weighted picker hooked")
              return
            end
          end
        end
      end
    end
  end

  local function wrapLuck(luck)
    for _, name in ipairs({ "tryCorrection", "shouldForceSpin", "finalizePaidSpinOutcome" }) do
      local orig = luck[name]
      if type(orig) == "function" then
        luck[name] = function(...)
          local r = { orig(...) }
          if r[1] then F.events[#F.events + 1] = name end
          return unpack(r)
        end
      end
    end
  end

  function F.onRequire(name, mod)
    if type(mod) ~= "table" then return end
    if name == "src.game.slot" and type(mod.new) == "function" and not F.slotWrapped then
      F.slotWrapped = true
      local orig = mod.new
      mod.new = function(...)
        local inst = orig(...)
        if type(inst) == "table" then
          F.instances[inst] = true
          pcall(hookPicker, inst)
        end
        return inst
      end
    elseif name == "src.game.luck" and not F.luckWrapped then
      F.luckWrapped = true
      wrapLuck(mod)
    end
  end

  local function gridSig(g)
    if type(g) ~= "table" then return nil end
    local rows = {}
    for r = 1, #g do
      local row = g[r]
      if type(row) ~= "table" then return nil end
      local cells = {}
      for c = 1, #row do
        local v = row[c]
        if type(v) == "table" then v = v.symbol or v.sym or v.key end
        cells[#cells + 1] = tostring(v)
      end
      rows[#rows + 1] = table.concat(cells, " ")
    end
    return table.concat(rows, " / ")
  end

  local function fmtCounts(t)
    local parts, seen = {}, {}
    for _, k in ipairs(ORDER) do
      if t[k] then parts[#parts + 1] = k .. "=" .. t[k] end
      seen[k] = true
    end
    for k, v in pairs(t) do
      if not seen[k] then parts[#parts + 1] = tostring(k) .. "=" .. v end
    end
    return table.concat(parts, " ")
  end

  local function weightsStr()
    local C = package.loaded["src.data.constants"]
    local w = C and C.slot and C.slot.symbolWeights or {}
    local parts = {}
    for _, k in ipairs(ORDER) do parts[#parts + 1] = string.format("%s=%.3g", k, tonumber(w[k]) or 0) end
    return table.concat(parts, " ")
  end

  function F.update(dt)
    local inst = next(F.instances)
    if not inst then return end
    local sig = gridSig(inst.grid)
    if sig ~= F.lastSig then F.lastSig, F.stableFor = sig, 0 else F.stableFor = (F.stableFor or 0) + dt end
    if sig and sig ~= F.loggedSig and F.stableFor >= STABLE and next(F.picks) then
      F.loggedSig = sig
      F.spin = F.spin + 1
      local counts = {}
      for cell in sig:gmatch("[^ /]+") do counts[cell] = (counts[cell] or 0) + 1 end
      T.log("spin#%d weights{%s}\n    picks{%s}\n    grid {%s}  [%s]%s", F.spin, weightsStr(),
        fmtCounts(F.picks), fmtCounts(counts), sig,
        #F.events > 0 and ("  luck:" .. table.concat(F.events, ",")) or "")
      F.picks, F.events = {}, {}
    end
  end

  return F
end
