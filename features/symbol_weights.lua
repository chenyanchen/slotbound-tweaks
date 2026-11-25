-- Symbol Weights: edit the slot machine's symbol weights in-game (F8 panel tab).
--
-- How the game rolls symbols (v1.0.3):
--   src/game/slot.lua picks the unit symbols (W/A/S/M/H/D) by weight from
--   require("src.data.constants").slot.symbolWeights, read fresh on every roll.
--   The symbols listed here are the keys of that table, so symbols the game
--   adds later show up on their own.
--   Some cores (MirageGoblet, OldCrown, SporeShroom, BanStamp) temporarily swap
--   that table for one spin, keeping a copy of the "base" weights in the cores
--   module's private state (_baseSymbolWeights) and restoring it afterwards.
--   This feature replaces the base weights, so core effects still stack on top.

return function(T)
  local F = {
    defaults = nil, -- the game's own weights, by symbol
    keys = nil,     -- the game's symbols, in display order (known once defaults are)
    checkTimer = 0,
  }

  -- This feature used to be called Symbol Odds (config/symbol_odds.lua).
  do
    local DEFAULTS = { enabled = true, weights = {} }
    local new = io.open(T.config.path("symbol_weights"), "r")
    local old = not new and io.open(T.config.path("symbol_odds"), "r")
    if new then new:close() end
    if old then
      old:close()
      F.cfg = T.config.load("symbol_odds", DEFAULTS)
      T.config.save("symbol_weights", F.cfg)
      os.remove(T.config.path("symbol_odds"))
      T.log("symbol_weights: migrated config/symbol_odds.lua")
    else
      F.cfg = T.config.load("symbol_weights", DEFAULTS)
    end
  end

  local function copy(src)
    local t = {}
    for k, v in pairs(src or {}) do t[k] = v end
    return t
  end

  local function same(a, b)
    for _, k in ipairs(F.keys or {}) do
      if math.abs((tonumber(a and a[k]) or 0) - (tonumber(b and b[k]) or 0)) > 1e-9 then return false end
    end
    return true
  end

  local function round2(x) return math.floor(x * 100 + 0.5) / 100 end

  local function save()
    local w = {}
    for k, v in pairs(F.cfg.weights) do
      if tonumber(v) then w[k] = round2(tonumber(v)) end
    end
    T.config.save("symbol_weights", { enabled = F.cfg.enabled, weights = w })
  end

  --------------------------------------------------------------------------
  -- game access
  --------------------------------------------------------------------------
  local function constants() return package.loaded["src.data.constants"] end

  -- Private state of src/game/cores.lua: an upvalue of cores.finishSpinModifiers.
  local function coresState()
    if F._coresState then return F._coresState end
    local cores, C = package.loaded["src.game.cores"], constants()
    local f = type(cores) == "table" and cores.finishSpinModifiers
    if type(f) ~= "function" then return nil end
    for i = 1, 16 do
      local name, v = debug.getupvalue(f, i)
      if name == nil then break end
      if type(v) == "table" and v ~= C and (v.active ~= nil or v.iconCache ~= nil
          or v._weightsApplied ~= nil or v._baseSymbolWeights ~= nil) then
        F._coresState = v
        return v
      end
    end
    return nil
  end

  local function isModified()
    return F.cfg.enabled and F.defaults ~= nil and not same(F.cfg.weights, F.defaults)
  end

  local function apply(force)
    local C = constants()
    if type(C) ~= "table" or type(C.slot) ~= "table" then return end
    local st = coresState()

    if not F.defaults then
      local base = (st and st._weightsApplied and st._baseSymbolWeights) or C.slot.symbolWeights
      if type(base) ~= "table" then return end
      local keys, defaults = T.gameSymbols(base), {}
      if #keys == 0 then return end
      for _, k in ipairs(keys) do defaults[k] = tonumber(base[k]) end
      F.defaults, F.keys = defaults, keys
      local parts = {}
      for _, k in ipairs(keys) do
        if tonumber(F.cfg.weights[k]) == nil or F.cfg.weights[k] < 0 then F.cfg.weights[k] = defaults[k] end
        parts[#parts + 1] = string.format("%s=%.3f", k, defaults[k])
      end
      T.log("symbol_weights: game defaults %s", table.concat(parts, " "))
    end

    -- only the game's symbols, so stale config entries never reach the game
    local src = F.cfg.enabled and F.cfg.weights or F.defaults
    local want = {}
    for _, k in ipairs(F.keys) do want[k] = tonumber(src[k]) or 0 end
    -- While a core effect is active this spin, only swap the base: the game
    -- restores it at the end of the spin and future core effects build on it.
    if st and st._baseSymbolWeights and (force or not same(st._baseSymbolWeights, want)) then
      st._baseSymbolWeights = copy(want)
    end
    if not (st and st._weightsApplied) and (force or not same(C.slot.symbolWeights, want)) then
      C.slot.symbolWeights = copy(want)
    end
    if isModified() then T.taint("symbol weights") end
  end

  --------------------------------------------------------------------------
  -- panel tab (weights.lua)
  --------------------------------------------------------------------------
  local function icon(k)
    local assets = package.loaded["src.data.assets"]
    local img = type(assets) == "table" and type(assets.icons) == "table" and assets.icons[k]
    if type(img) == "userdata" and img.typeOf and img:typeOf("Texture") then return img end
    return nil
  end

  -- "W Warrior": the symbol plus the game's name for its unit
  local function rows()
    if F.rows or not F.keys then return F.rows or {} end
    local out = {}
    for _, k in ipairs(F.keys) do
      local name = T.picker.enText("merc_contract_unit_" .. k)
      out[#out + 1] = { key = k, label = name and (k .. " " .. name) or k, icon = function() return icon(k) end }
    end
    F.rows = out
    return out
  end

  local editor = T.weights.tab({
    id = "symbol_weights", title = "Symbol Weights",
    intro = "Weights the slot machine uses for each symbol.",
    rows = rows,
    cfg = F.cfg,
    defaults = function() return F.defaults end,
    save = save,
    apply = apply,
  })

  function F.update(dt)
    editor.update(dt)
    F.checkTimer = F.checkTimer - dt
    if F.checkTimer > 0 then return end
    F.checkTimer = 0.25
    apply(false)
  end

  return F
end
