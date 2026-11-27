-- Weights tab: the shared bar editor behind Symbol Weights and Unit Grades.
--
--   local ed = T.weights.tab(spec)   -- adds the tab to the F8 panel
--   ed.update(dt)                    -- call from the feature's update (hold-to-repeat, deferred save)
--
-- spec:
--   id, title                 panel tab (title: string or function, see panel.lua)
--   intro, note               lines of text (strings or functions returning one)
--   rows() -> { { key, label, icon = fn() -> Image|nil, color = fn() -> {r,g,b} } }
--                             read from the game, so it may be empty until the game has loaded
--   cfg                       { enabled = bool, weights = { [key] = number } }, edited in place
--   defaults()                -> the game's weights by key, or nil while unknown
--   save()                    persist cfg
--   apply(force)              push cfg to the game (called after every edit)
--
-- Percentages are weight / total. At least one weight stays above zero.

return function(T)
  local STEP, BIG_STEP = 0.01, 0.05
  local REPEAT_DELAY, REPEAT_FAST, REPEAT_FASTEST, ACCEL_AFTER = 0.35, 0.07, 0.03, 1.5
  local inside = T.panel.inside
  local weights = {}

  local function round2(x) return math.floor(x * 100 + 0.5) / 100 end
  local function text(v) if type(v) == "function" then return v() end return v end

  function weights.tab(spec)
    local rows = {}
    local E = { sel = 1, hit = {} }
    local tab = { id = spec.id, title = spec.title }

    local function cfg() return spec.cfg end

    local function total(w)
      local s = 0
      for _, r in ipairs(rows) do s = s + (tonumber(w and w[r.key]) or 0) end
      return s
    end

    local function adjust(k, delta, deferSave)
      local w = cfg().weights
      local old = w[k]
      w[k] = math.max(0, round2((old or 0) + delta))
      if total(w) <= 1e-9 then w[k] = old; return end -- keep one entry rollable
      spec.apply(true)
      if deferSave then E.dirty = true else spec.save() end
    end

    local function setOnly(k)
      for _, r in ipairs(rows) do cfg().weights[r.key] = (r.key == k) and 1 or 0 end
      spec.save(); spec.apply(true)
    end

    local function resetDefaults()
      local d = spec.defaults()
      if not d then return end
      for _, r in ipairs(rows) do cfg().weights[r.key] = tonumber(d[r.key]) or 0 end
      spec.save(); spec.apply(true)
    end

    local function toggleEnabled()
      cfg().enabled = not cfg().enabled
      spec.save(); spec.apply(true)
    end

    -- hold-to-repeat (arrows and the -/+ buttons)
    local function startHold(h)
      h.t, h.nextAt = 0, REPEAT_DELAY
      E.hold = h
    end

    local function stopHold()
      E.hold = nil
      if E.dirty then E.dirty = false; spec.save() end
    end

    local function updateHold(dt)
      local h = E.hold
      if not h then return end
      local down = h.mouse and love.mouse.isDown(h.mouse) or (h.key and love.keyboard.isDown(h.key))
      if not T.panel.isShowing(spec.id) or not down or #rows == 0 then stopHold(); return end
      h.t = h.t + dt
      local fires = 0
      while h.t >= h.nextAt and fires < 8 do
        fires = fires + 1
        h.nextAt = h.nextAt + (h.t > ACCEL_AFTER and REPEAT_FASTEST or REPEAT_FAST)
        if h.action == "sel" then
          E.sel = (E.sel - 1 + h.dir) % #rows + 1
        else
          local step = love.keyboard.isDown("lshift", "rshift") and BIG_STEP or STEP
          if h.t > ACCEL_AFTER then step = step * 5 end
          adjust(rows[E.sel].key, h.dir * step, true)
        end
      end
    end

    function tab.draw(x, y, w, h, s)
      local g = love.graphics
      rows = spec.rows()
      E.sel = math.max(1, math.min(E.sel, #rows))
      local on = cfg().enabled
      local wts = cfg().weights
      local defaults = spec.defaults()
      local rowH = math.floor(math.min(52 * s, (h - 120 * s) / math.max(#rows, 1)))
      E.hit = {}

      local btn = { x + w - 150 * s, y, 150 * s, 34 * s }
      E.hit.toggle = T.panel.button(btn, on and T.tr("on") or T.tr("off"), T.font(18 * s), on)
      g.setFont(T.font(17 * s)); g.setColor(0.8, 0.8, 0.85, 1)
      g.print(text(spec.intro), x, y + 8 * s)
      if #rows == 0 then
        g.setColor(1, 1, 1, 0.5); g.print(T.tr("weights.loading"), x, y + 60 * s)
        return
      end

      local tot, dtot = total(wts), total(defaults)
      local ry = y + 50 * s
      g.setFont(T.font(20 * s))
      for i, r in ipairs(rows) do
        local k = r.key
        local pct = tot > 0 and (tonumber(wts[k]) or 0) / tot or 0
        local defPct = dtot > 0 and (tonumber(defaults[k]) or 0) / dtot or nil
        if i == E.sel then
          g.setColor(1, 1, 1, 0.08); g.rectangle("fill", x - 6 * s, ry, w + 12 * s, rowH - 4 * s, 6 * s)
        end
        local isz = rowH - 12 * s
        local img = r.icon and r.icon()
        if img then
          local iw, ih = img:getDimensions()
          local sc = isz / math.max(iw, ih)
          g.setColor(1, 1, 1, on and 1 or 0.5)
          g.draw(img, x, ry + 4 * s, 0, sc, sc)
        elseif r.color then
          local c = r.color()
          g.setColor(c[1], c[2], c[3], on and 1 or 0.5)
          g.rectangle("fill", x + isz * 0.2, ry + 4 * s + isz * 0.2, isz * 0.6, isz * 0.6, 4 * s)
        end
        local ty = ry + (rowH - 4 * s - g.getFont():getHeight()) / 2
        g.setColor(1, 1, 1, on and 1 or 0.5)
        g.print(r.label, x + rowH, ty)
        local bx, bh = x + 250 * s, 16 * s
        local bw = w - 250 * s - 210 * s
        local by = ry + (rowH - 4 * s - bh) / 2
        g.setColor(1, 1, 1, 0.12); g.rectangle("fill", bx, by, bw, bh, 3 * s)
        if bw * pct >= 1 then
          g.setColor(0.95, 0.78, 0.3, on and 1 or 0.4)
          g.rectangle("fill", bx, by, bw * pct, bh, math.min(3 * s, bw * pct / 2))
        end
        if defPct then
          g.setColor(1, 1, 1, 0.8); g.rectangle("fill", bx + bw * defPct - 1, by - 3 * s, 2, bh + 6 * s)
        end
        g.setColor(1, 1, 1, on and 1 or 0.5)
        g.printf(string.format("%.1f%%", pct * 100), bx + bw + 6 * s, ty, 90 * s, "right")
        local b1 = { x + w - 84 * s, ry + 4 * s, 38 * s, rowH - 12 * s }
        local b2 = { x + w - 40 * s, ry + 4 * s, 38 * s, rowH - 12 * s }
        E.hit["minus" .. i], E.hit["plus" .. i], E.hit["row" .. i] = b1, b2, { x, ry, w, rowH }
        T.panel.button(b1, "-", T.font(20 * s))
        T.panel.button(b2, "+", T.font(20 * s))
        ry = ry + rowH
      end

      g.setFont(T.font(15 * s)); g.setColor(0.8, 0.8, 0.85, 1)
      local fy = ry + 12 * s
      g.print(T.tr("weights.help1"), x, fy)
      g.print(T.tr("weights.help2"), x, fy + 24 * s)
      if spec.note then
        g.setColor(0.7, 0.7, 0.78, 1)
        g.printf(text(spec.note), x, fy + 56 * s, w)
      end
    end

    function tab.keypressed(key)
      if #rows == 0 then return end
      local k = rows[E.sel].key
      local step = love.keyboard.isDown("lshift", "rshift") and BIG_STEP or STEP
      if key == "up" then E.sel = (E.sel - 2) % #rows + 1; startHold({ key = key, action = "sel", dir = -1 })
      elseif key == "down" then E.sel = E.sel % #rows + 1; startHold({ key = key, action = "sel", dir = 1 })
      elseif key == "left" then adjust(k, -step, true); startHold({ key = key, action = "adj", dir = -1 })
      elseif key == "right" then adjust(k, step, true); startHold({ key = key, action = "adj", dir = 1 })
      elseif key == "0" then adjust(k, -(cfg().weights[k] or 0))
      elseif key == "o" then setOnly(k)
      elseif key == "r" then resetDefaults()
      elseif key == "e" then toggleEnabled()
      end
    end

    function tab.mousepressed(x, y, button)
      if button ~= 1 then return end
      if inside(E.hit.toggle, x, y) then toggleEnabled(); return end
      local step = love.keyboard.isDown("lshift", "rshift") and BIG_STEP or STEP
      for i, r in ipairs(rows) do
        if inside(E.hit["minus" .. i], x, y) then
          E.sel = i; adjust(r.key, -step, true); startHold({ mouse = button, action = "adj", dir = -1 }); return
        end
        if inside(E.hit["plus" .. i], x, y) then
          E.sel = i; adjust(r.key, step, true); startHold({ mouse = button, action = "adj", dir = 1 }); return
        end
        if inside(E.hit["row" .. i], x, y) then E.sel = i; return end
      end
    end

    T.panel.addTab(tab)

    local ed = { tab = tab, _state = E }
    function ed.update(dt)
      updateHold(dt)
      if not E.hold and E.dirty then E.dirty = false; spec.save() end
    end
    return ed
  end

  T.weights = weights
  return weights
end
