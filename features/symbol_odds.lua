-- Symbol Odds: edit the slot machine's symbol weights in-game (F8).
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
  local NAMES = { W = "Warrior", A = "Archer", S = "Spear", M = "Mage", H = "Horse", D = "Duelist" }
  local FALLBACK_DEFAULTS = { W = 0.2, A = 0.2, S = 0.2, M = 0.15, H = 0.15, D = 0.1 }
  local TOGGLE_KEY = "f8"
  local STEP, BIG_STEP = 0.01, 0.05
  local REPEAT_DELAY, REPEAT_FAST, REPEAT_FASTEST, ACCEL_AFTER = 0.35, 0.07, 0.03, 1.5

  local F = {
    cfg = T.config.load("symbol_odds", { enabled = true, weights = {} }),
    defaults = nil,
    open = false,
    sel = 1,
    checkTimer = 0,
    swallowRelease = {},
    hit = {},
  }

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
    T.config.save("symbol_odds", { enabled = F.cfg.enabled, weights = w })
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
      T.log("symbol_odds: game defaults W=%.3f A=%.3f S=%.3f M=%.3f H=%.3f D=%.3f",
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
    if isModified() then T.taint("symbol odds") end
  end

  --------------------------------------------------------------------------
  -- editing
  --------------------------------------------------------------------------
  local function total()
    local s = 0
    for _, k in ipairs(ORDER) do s = s + (F.cfg.weights[k] or 0) end
    return s
  end

  local function adjust(k, delta, deferSave)
    local old = F.cfg.weights[k]
    F.cfg.weights[k] = math.max(0, round2((old or 0) + delta))
    if total() <= 1e-9 then F.cfg.weights[k] = old; return end -- keep one symbol rollable
    apply(true)
    if deferSave then F.dirty = true else save() end
  end

  local function setOnly(k)
    for _, s in ipairs(ORDER) do F.cfg.weights[s] = (s == k) and 1 or 0 end
    save(); apply(true)
  end

  local function resetDefaults()
    if not F.defaults then return end
    F.cfg.weights = copy(F.defaults)
    save(); apply(true)
  end

  local function toggleEnabled()
    F.cfg.enabled = not F.cfg.enabled
    save(); apply(true)
  end

  -- hold-to-repeat (arrows and the -/+ buttons)
  local function startHold(h)
    h.t, h.nextAt = 0, REPEAT_DELAY
    F.hold = h
  end

  local function stopHold()
    F.hold = nil
    if F.dirty then F.dirty = false; save() end
  end

  local function updateHold(dt)
    local h = F.hold
    if not h then return end
    local down = h.mouse and love.mouse.isDown(h.mouse) or (h.key and love.keyboard.isDown(h.key))
    if not F.open or not down then stopHold(); return end
    h.t = h.t + dt
    local fires = 0
    while h.t >= h.nextAt and fires < 8 do
      fires = fires + 1
      h.nextAt = h.nextAt + (h.t > ACCEL_AFTER and REPEAT_FASTEST or REPEAT_FAST)
      if h.action == "sel" then
        F.sel = (F.sel - 1 + h.dir) % #ORDER + 1
      else
        local step = love.keyboard.isDown("lshift", "rshift") and BIG_STEP or STEP
        if h.t > ACCEL_AFTER then step = step * 5 end
        adjust(ORDER[F.sel], h.dir * step, true)
      end
    end
  end

  --------------------------------------------------------------------------
  -- overlay
  --------------------------------------------------------------------------
  local function icon(k)
    local assets = package.loaded["src.data.assets"]
    local img = type(assets) == "table" and type(assets.icons) == "table" and assets.icons[k]
    if type(img) == "userdata" and img.typeOf and img:typeOf("Texture") then return img end
    return nil
  end

  local function inside(r, x, y)
    return r and x >= r[1] and y >= r[2] and x <= r[1] + r[3] and y <= r[2] + r[4]
  end

  function F.draw()
    if not F.open then return end
    local g = love.graphics
    local sw, sh = g.getDimensions()
    local s = math.max(0.6, sh / 1080)
    local pad, rowH, w = 18 * s, 46 * s, 640 * s
    local h = pad * 2 + 54 * s + rowH * #ORDER + 116 * s
    local x, y = math.floor((sw - w) / 2), math.floor(sh * 0.12)
    local on = F.cfg.enabled
    F.hit = {}
    F.panel = { x, y, w, h }

    g.push("all")
    g.origin(); g.setCanvas(); g.setShader(); g.setScissor()
    g.setColor(0.06, 0.06, 0.1, 0.94); g.rectangle("fill", x, y, w, h, 12 * s)
    g.setColor(0.95, 0.78, 0.3, 1); g.setLineWidth(2 * s); g.rectangle("line", x, y, w, h, 12 * s)

    g.setFont(T.font(26 * s)); g.setColor(1, 1, 1, 1)
    g.print("Symbol Odds", x + pad, y + pad)
    local btn = { x + w - pad - 150 * s, y + pad, 150 * s, 34 * s }
    F.hit.toggle = btn
    g.setColor(on and 0.2 or 0.35, on and 0.6 or 0.2, 0.25, 1)
    g.rectangle("fill", btn[1], btn[2], btn[3], btn[4], 6 * s)
    g.setColor(1, 1, 1, 1); g.setFont(T.font(18 * s))
    g.printf(on and "ON" or "OFF", btn[1], btn[2] + 7 * s, btn[3], "center")

    local tot = total()
    local dtot = 0
    for _, k in ipairs(ORDER) do dtot = dtot + ((F.defaults and F.defaults[k]) or 0) end
    local ry = y + pad + 54 * s
    g.setFont(T.font(20 * s))
    for i, k in ipairs(ORDER) do
      local pct = tot > 0 and (F.cfg.weights[k] or 0) / tot or 0
      local defPct = dtot > 0 and (F.defaults[k] or 0) / dtot or 0
      if i == F.sel then
        g.setColor(1, 1, 1, 0.08); g.rectangle("fill", x + 6 * s, ry, w - 12 * s, rowH - 4 * s, 6 * s)
      end
      local ix = x + pad
      local img = icon(k)
      if img then
        local iw, ih = img:getDimensions()
        local sc = (rowH - 12 * s) / math.max(iw, ih)
        g.setColor(1, 1, 1, on and 1 or 0.5)
        g.draw(img, ix, ry + 4 * s, 0, sc, sc)
      end
      g.setColor(1, 1, 1, on and 1 or 0.5)
      g.print(string.format("%s %s", k, NAMES[k]), ix + rowH, ry + 8 * s)
      local bx, bw, bh = x + 250 * s, 170 * s, 14 * s
      local by = ry + (rowH - 4 * s - bh) / 2
      g.setColor(1, 1, 1, 0.12); g.rectangle("fill", bx, by, bw, bh, 3 * s)
      if bw * pct >= 1 then
        g.setColor(0.95, 0.78, 0.3, on and 1 or 0.4); g.rectangle("fill", bx, by, bw * pct, bh, math.min(3 * s, bw * pct / 2))
      end
      g.setColor(1, 1, 1, 0.8); g.rectangle("fill", bx + bw * defPct - 1, by - 3 * s, 2, bh + 6 * s)
      g.setColor(1, 1, 1, on and 1 or 0.5)
      g.printf(string.format("%.1f%%", pct * 100), bx + bw + 6 * s, ry + 8 * s, 80 * s, "right")
      local b1 = { x + w - pad - 84 * s, ry + 4 * s, 36 * s, rowH - 12 * s }
      local b2 = { x + w - pad - 40 * s, ry + 4 * s, 36 * s, rowH - 12 * s }
      F.hit["minus" .. k], F.hit["plus" .. k], F.hit["row" .. k] = b1, b2, { x, ry, w, rowH }
      for _, b in ipairs({ b1, b2 }) do
        g.setColor(1, 1, 1, 0.15); g.rectangle("fill", b[1], b[2], b[3], b[4], 5 * s)
      end
      g.setColor(1, 1, 1, 1)
      g.printf("-", b1[1], b1[2] + 4 * s, b1[3], "center")
      g.printf("+", b2[1], b2[2] + 4 * s, b2[3], "center")
      ry = ry + rowH
    end

    g.setFont(T.font(15 * s)); g.setColor(0.8, 0.8, 0.85, 1)
    local fy = ry + 10 * s
    g.print("Up/Down select   Left/Right +-0.01 (Shift +-0.05, hold = fast)   O only   0 zero", x + pad, fy)
    g.print("R reset to defaults   E toggle   F8/Esc close   (white tick = game default)", x + pad, fy + 24 * s)
    if T.tainted then
      g.setColor(1, 0.55, 0.45, 1)
      g.print("Leaderboard submissions disabled until the game restarts.", x + pad, fy + 52 * s)
    else
      g.setColor(0.6, 0.85, 0.6, 1)
      g.print("Default odds: leaderboard submissions unaffected.", x + pad, fy + 52 * s)
    end
    g.pop()
  end

  --------------------------------------------------------------------------
  -- input
  --------------------------------------------------------------------------
  function F.keypressed(key)
    if key == TOGGLE_KEY then F.open = not F.open; return true end
    if not F.open then return false end
    local k = ORDER[F.sel]
    local step = love.keyboard.isDown("lshift", "rshift") and BIG_STEP or STEP
    if key == "escape" then F.open = false
    elseif key == "up" then F.sel = (F.sel - 2) % #ORDER + 1; startHold({ key = key, action = "sel", dir = -1 })
    elseif key == "down" then F.sel = F.sel % #ORDER + 1; startHold({ key = key, action = "sel", dir = 1 })
    elseif key == "left" then adjust(k, -step, true); startHold({ key = key, action = "adj", dir = -1 })
    elseif key == "right" then adjust(k, step, true); startHold({ key = key, action = "adj", dir = 1 })
    elseif key == "0" then adjust(k, -(F.cfg.weights[k] or 0))
    elseif key == "o" then setOnly(k)
    elseif key == "r" then resetDefaults()
    elseif key == "e" then toggleEnabled()
    end
    return true -- swallow all keys while the panel is open
  end

  function F.mousepressed(x, y, button)
    if not F.open or not inside(F.panel, x, y) then return false end
    F.swallowRelease[button] = true
    if button ~= 1 then return true end
    if inside(F.hit.toggle, x, y) then toggleEnabled(); return true end
    local step = love.keyboard.isDown("lshift", "rshift") and BIG_STEP or STEP
    for i, k in ipairs(ORDER) do
      if inside(F.hit["minus" .. k], x, y) then
        F.sel = i; adjust(k, -step, true); startHold({ mouse = button, action = "adj", dir = -1 }); return true
      end
      if inside(F.hit["plus" .. k], x, y) then
        F.sel = i; adjust(k, step, true); startHold({ mouse = button, action = "adj", dir = 1 }); return true
      end
      if inside(F.hit["row" .. k], x, y) then F.sel = i; return true end
    end
    return true
  end

  function F.mousereleased(_, _, button)
    if F.swallowRelease[button] then F.swallowRelease[button] = nil; return true end
    return false
  end

  function F.update(dt)
    updateHold(dt)
    if not F.hold and F.dirty then F.dirty = false; save() end
    F.checkTimer = F.checkTimer - dt
    if F.checkTimer > 0 then return end
    F.checkTimer = 0.25
    apply(false)
  end

  return F
end
