-- Symbol Weights: edit the slot machine's symbol weights in-game (F8 panel tab).
--
-- How the game rolls symbols (v1.0.3):
--   src/game/slot.lua picks W/A/S/M/H/D by weight from
--   require("src.data.constants").slot.symbolWeights, read fresh on every roll.
--   Some cores (MirageGoblet, OldCrown, SporeShroom, BanStamp) temporarily swap
--   that table for one spin, keeping a copy of the "base" weights in the cores
--   module's private state (_baseSymbolWeights) and restoring it afterwards.
--   This feature replaces the base weights, so core effects still stack on top.

return function(T)
  local ORDER = { "W", "A", "S", "M", "H", "D" }
  local NAMES = { W = "Warrior", A = "Archer", S = "Spearman", M = "Mage", H = "Cavalry", D = "Duelist" }
  local FALLBACK_DEFAULTS = { W = 0.2, A = 0.2, S = 0.2, M = 0.15, H = 0.15, D = 0.1 }

  local F = {
    defaults = nil,
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
    for _, k in ipairs(ORDER) do
      if math.abs((tonumber(a and a[k]) or 0) - (tonumber(b and b[k]) or 0)) > 1e-9 then return false end
    end
    return true
  end

  local function round2(x) return math.floor(x * 100 + 0.5) / 100 end

  local function save()
    local w = {}
    for _, k in ipairs(ORDER) do w[k] = round2(F.cfg.weights[k] or 0) end
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
      F.defaults = copy(base)
      for _, k in ipairs(ORDER) do
        if tonumber(F.defaults[k]) == nil then F.defaults[k] = FALLBACK_DEFAULTS[k] end
        if tonumber(F.cfg.weights[k]) == nil or F.cfg.weights[k] < 0 then F.cfg.weights[k] = F.defaults[k] end
      end
      T.log("symbol_weights: game defaults W=%.3f A=%.3f S=%.3f M=%.3f H=%.3f D=%.3f",
        F.defaults.W, F.defaults.A, F.defaults.S, F.defaults.M, F.defaults.H, F.defaults.D)
    end

    local want = F.cfg.enabled and F.cfg.weights or F.defaults
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

  local rows = {}
  for _, k in ipairs(ORDER) do
    rows[#rows + 1] = { key = k, label = k .. " " .. NAMES[k], icon = function() return icon(k) end }
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
