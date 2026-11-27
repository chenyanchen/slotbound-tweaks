-- Weights tab: the shared bar editor behind Symbol Weights and Unit Grades.
--
--   T.weights.tab(spec)       -- adds the tab to the F8 panel
--
-- spec:
--   id, title                 panel tab (title: string or function, see panel.lua)
--   intro, note               optional lines of text (strings or functions returning one)
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
  local inside = T.panel.inside
  local weights = {}

  local function round2(x) return math.floor(x * 100 + 0.5) / 100 end
  local function text(v) if type(v) == "function" then return v() end return v end
  local function stepSize(accel)
    local step = love.keyboard.isDown("lshift", "rshift") and BIG_STEP or STEP
    return accel and step * 5 or step
  end

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

    local function flushSave()
      if E.dirty then E.dirty = false; spec.save() end
    end

    local function adjust(k, delta, deferSave)
      local w = cfg().weights
      local old = tonumber(w[k]) or 0
      local nxt = math.max(0, round2(old + delta))
      if nxt == old then return false end
      w[k] = nxt
      if total(w) <= 1e-9 then w[k] = old; return false end -- keep one entry rollable
      spec.apply(true)
      if deferSave then E.dirty = true else spec.save() end
      return true
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
      if spec.intro then g.print(text(spec.intro), x, y + 8 * s) end
      if #rows == 0 then
        g.setColor(1, 1, 1, 0.5); g.print(T.tr("weights.loading"), x, y + 60 * s)
        return
      end

      local tot, dtot = total(wts), total(defaults)
      local ry = y + 50 * s
      g.setFont(T.font(20 * s))
      for i, r in ipairs(rows) do
        local k = r.key
        local curW = tonumber(wts[k]) or 0
        local pct = tot > 0 and curW / tot or 0
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
        local sbw, sbh, gap = 38 * s, rowH - 12 * s, 6 * s
        local canMinus = curW > 1e-9 and (tot - curW > 1e-9 or curW > STEP + 1e-9)
        E.hit["row" .. i] = { x, ry, w, rowH }
        T.panel.stepper({
          id = k,
          x = x + w - (sbw * 2 + gap + 2 * s), y = ry + 4 * s, w = sbw, h = sbh, gap = gap,
          font = T.font(20 * s),
          canMinus = canMinus, canPlus = true,
          onStep = function(dir, accel)
            E.sel = i
            return adjust(k, dir * stepSize(accel), true)
          end,
          onStop = flushSave,
        })
        ry = ry + rowH
      end

      g.setFont(T.font(15 * s)); g.setColor(0.8, 0.8, 0.85, 1)
      local fy = ry + 12 * s
      g.print(T.tr("weights.help"), x, fy)
      if spec.note then
        g.setColor(0.7, 0.7, 0.78, 1)
        g.printf(text(spec.note), x, fy + 32 * s, w)
      end
    end

    function tab.keypressed(key)
      if #rows == 0 then return end
      local k = rows[E.sel].key
      if key == "up" or key == "down" then
        local dir = key == "up" and -1 or 1
        E.sel = (E.sel - 1 + dir) % #rows + 1
        T.panel.hold({
          key = key,
          step = function()
            if #rows == 0 then return false end
            E.sel = (E.sel - 1 + dir) % #rows + 1
          end,
        })
      elseif key == "left" or key == "right" then
        local dir = key == "left" and -1 or 1
        if adjust(k, dir * stepSize(false), true) then
          T.panel.hold({
            key = key, id = k, dir = dir,
            step = function(accel)
              local cur = rows[E.sel]
              return cur ~= nil and adjust(cur.key, dir * stepSize(accel), true)
            end,
            onStop = flushSave,
          })
        end
      elseif key == "0" then T.panel.stopHold(); adjust(k, -(tonumber(cfg().weights[k]) or 0))
      elseif key == "o" then T.panel.stopHold(); setOnly(k)
      elseif key == "r" then T.panel.stopHold(); resetDefaults()
      elseif key == "e" then T.panel.stopHold(); toggleEnabled()
      end
    end

    function tab.mousepressed(x, y, button)
      if button ~= 1 then return end
      if inside(E.hit.toggle, x, y) then toggleEnabled(); return end
      for i = 1, #rows do
        if inside(E.hit["row" .. i], x, y) then E.sel = i; return end
      end
    end

    T.panel.addTab(tab)

    return { tab = tab, _state = E }
  end

  T.weights = weights
  return weights
end
