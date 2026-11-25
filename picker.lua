-- Picker tab: the shared UI behind the Items and Cores tabs.
--
-- Left: sections of slots (e.g. owned items, shop offers). Right: a catalog
-- grid with filters and a detail box. The player selects a slot, then clicks
-- a catalog entry to put it there.
--
--   T.picker.tab(spec) -> tab, already added to the F8 panel
--
-- spec:
--   id, title                     panel tab
--   context()                     -> ctx, lockedReason | nil (nothing to edit)
--   unavailableText               shown when context() returns nil
--   catalog()                     -> list of defs ({ id, rarity, ... })
--   filters() -> { { key, label } }, filterOf(def) -> key ("all" shows everything)
--   name(def), effect(def, level), icon(def) -> Image|nil
--   meta(def, level)              -> one line under the name
--   help                          -> hint line at the bottom
--   sections = { {
--     title(ctx)                  -> header text
--     slots(ctx)                  -> rows to draw
--     selectable(ctx)             -> rows that can be selected (<= slots)
--     get(ctx, i)                 -> def-like entry in row i, or nil
--     put(ctx, i, def)            place a catalog entry in row i
--     mark = "owned" | "offer"    catalog badge for entries of this section
--     right(ctx, i, e)            -> text at the right of the row (optional)
--     dim(ctx, i, e)              -> draw the row faded (optional)
--     emptyText(ctx, i)           -> label of an empty row (optional)
--     noneText                    -> label when slots(ctx) == 0
--     level(e), maxLevel(e), setLevel(ctx, i, level)   optional -/+ buttons
--     remove(ctx, i)              optional x button
--   } }
--
-- Entries are matched by `id`. The returned tab has flash(fmt, ...) for a
-- short message in the detail box.

return function(T)
  -- Fallbacks; the game's own shop colors are used when available.
  local RARITY_COLOR = {
    C = { 0.78, 0.78, 0.8 }, U = { 0.45, 0.86, 0.45 }, R = { 0.42, 0.66, 1 }, L = { 1, 0.64, 0.22 },
  }
  -- The game has no labels for item/core rarities; unknown ones show their code.
  local RARITY_NAME = { C = "Common", U = "Uncommon", R = "Rare", L = "Legendary" }
  local RARITY_RANK = { C = 1, U = 2, R = 3, L = 4 }
  local inside = T.panel.inside
  local picker = {}

  -- The game's own font for the current language (names may be CJK).
  local gameFonts = {}
  function picker.gameFont(px)
    local ui = rawget(_G, "ui")
    local path = type(ui) == "table" and type(ui.fontPath) == "string" and ui.fontPath
    if not path then return T.font(px) end
    px = px >= 15 and math.floor(px / 10 + 0.5) * 10 or 10 -- pixel font: whole multiples
    local k = path .. "@" .. px
    if gameFonts[k] == nil then
      local ok, f = pcall(love.graphics.newFont, path, px)
      if ok and f then f:setFilter("nearest", "nearest") end
      gameFonts[k] = ok and f or false
    end
    return gameFonts[k] or T.font(px)
  end
  local gameFont = picker.gameFont

  -- A string from the game's language tables (current language, then English).
  function picker.langText(key)
    local L = package.loaded["src.data.language"]
    if type(L) ~= "table" then return nil end
    local cur = L[rawget(_G, "currentGameLang") or "en"]
    return (type(cur) == "table" and cur[key]) or (type(L.en) == "table" and L.en[key]) or nil
  end

  -- A string from the game's English table (the panel's own text is English).
  function picker.enText(key)
    local L = package.loaded["src.data.language"]
    return type(L) == "table" and type(L.en) == "table" and L.en[key] or nil
  end

  function picker.rarityName(r) return RARITY_NAME[r] or tostring(r) end

  -- for sorting: the known rarities in order, then anything else
  function picker.rarityRank(r) return RARITY_RANK[r] or 99 end

  function picker.rarityColor(r)
    local ui = rawget(_G, "ui")
    local game = type(ui) == "table" and type(ui.itemShop) == "table" and type(ui.itemShop.itemLayout) == "table"
      and ui.itemShop.itemLayout.nameRarityColors
    local c = type(game) == "table" and game[r]
    if type(c) == "table" and tonumber(c[1]) then return c end
    return RARITY_COLOR[r] or RARITY_COLOR.C
  end

  -- "All" plus one filter per distinct value of key(def) in the catalog.
  function picker.filtersFrom(list, key, label, rank)
    local seen, values = {}, {}
    for _, d in ipairs(list) do
      local v = key(d)
      if v ~= nil and not seen[v] then seen[v] = true; values[#values + 1] = v end
    end
    table.sort(values, function(a, b)
      local ra, rb = rank and rank(a) or 0, rank and rank(b) or 0
      if ra ~= rb then return ra < rb end
      return tostring(a) < tostring(b)
    end)
    local out = { { "all", "All" } }
    for _, v in ipairs(values) do out[#out + 1] = { v, label(v) } end
    return out
  end

  -- "{hp.png}" style inline icons -> words; other "{name}" via values[name].
  local ICON_WORDS = {
    hp = "HP", atk = "ATK", aspd = "ASPD", def = "DEF", range = "RANGE",
    gold = "Gold", essence = "Essence", joker_tooltip = "Joker",
  }
  function picker.plainText(txt, values)
    txt = tostring(txt or "")
    txt = txt:gsub("{([%w_]+)%.png}", function(w) return ICON_WORDS[w] or w end)
    txt = txt:gsub("{([%w_]+)}", function(w)
      local v = type(values) == "table" and values[w]
      return v ~= nil and tostring(v) or nil
    end)
    return txt
  end

  local function fitText(font, text, w)
    if font:getWidth(text) <= w then return text end
    local out = text
    while #out > 0 and font:getWidth(out .. "...") > w do
      out = out:sub(1, -2)
      while #out > 0 and out:byte(-1) >= 0x80 and out:byte(-1) < 0xC0 do out = out:sub(1, -2) end -- utf-8
      if #out > 0 and out:byte(-1) >= 0xC0 then out = out:sub(1, -2) end
    end
    return out .. "..."
  end

  local function setRarityColor(d, a)
    local c = picker.rarityColor(d and d.rarity)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
  end

  function picker.tab(spec)
    local F = { sel = { 1, 1 }, filter = "all", hit = {} } -- sel = { section, row }
    local tab = { id = spec.id, title = spec.title }

    function tab.flash(fmt, ...)
      F.msg = string.format(fmt, ...)
      F.msgUntil = love.timer.getTime() + 3
    end

    local function drawIcon(d, x, y, size, alpha)
      local ok, img = pcall(spec.icon, d)
      if not ok or type(img) ~= "userdata" then return end
      local iw, ih = img:getDimensions()
      local sc = size / math.max(iw, ih)
      love.graphics.setColor(1, 1, 1, alpha or 1)
      love.graphics.draw(img, x + (size - iw * sc) / 2, y + (size - ih * sc) / 2, 0, sc, sc)
    end

    local function selectable(ctx, si)
      local sec = spec.sections[si]
      return sec.selectable and sec.selectable(ctx) or sec.slots(ctx)
    end

    local function clampSel(ctx)
      local si, i = F.sel[1], F.sel[2]
      if not spec.sections[si] then si, i = 1, 1 end
      local n = selectable(ctx, si)
      if n < 1 then
        for sj = 1, #spec.sections do
          if selectable(ctx, sj) > 0 then F.sel = { sj, 1 }; return end
        end
        F.sel = { 1, 1 }
        return
      end
      F.sel = { si, math.max(1, math.min(i, n)) }
    end

    local function selected(ctx)
      local sec = spec.sections[F.sel[1]]
      return sec and sec.get(ctx, F.sel[2]) or nil
    end

    -- one slot row; returns true if the mouse is on it
    local function drawRow(r, d, opts, s, mx, my)
      local g = love.graphics
      local x, y, w, h = r[1], r[2], r[3], r[4]
      if opts.selected then
        g.setColor(0.95, 0.78, 0.3, 0.18); g.rectangle("fill", x, y, w, h - 4 * s, 6 * s)
        g.setColor(0.95, 0.78, 0.3, 0.9); g.setLineWidth(math.max(1, 1.5 * s))
        g.rectangle("line", x, y, w, h - 4 * s, 6 * s)
      else
        g.setColor(1, 1, 1, 0.05); g.rectangle("fill", x, y, w, h - 4 * s, 6 * s)
      end
      local isz = h - 12 * s
      if not d then
        local f = T.font(16 * s)
        g.setFont(f); g.setColor(1, 1, 1, 0.35)
        g.print(opts.emptyText or "(empty)", x + isz + 18 * s, y + (h - 4 * s - f:getHeight()) / 2)
        return false
      end
      local nameFont = gameFont(20 * s)
      drawIcon(d, x + 6 * s, y + 4 * s, isz, opts.dim and 0.4 or 1)
      g.setFont(nameFont); setRarityColor(d, opts.dim and 0.45 or 1)
      g.print(fitText(nameFont, spec.name(d), opts.nameW), x + isz + 18 * s, y + (h - 4 * s - nameFont:getHeight()) / 2)
      if opts.right then
        local f = T.font(16 * s)
        g.setFont(f); g.setColor(1, 1, 1, opts.dim and 0.4 or 0.85)
        g.printf(opts.right, x, y + (h - 4 * s - f:getHeight()) / 2, opts.rightX - x, "right")
      end
      return inside({ x, y, w, h }, mx, my)
    end

    function tab.draw(x, y, w, h, s)
      local g = love.graphics
      local mx, my = love.mouse.getPosition()
      local ctx, locked = spec.context()
      F.hit = { rows = {}, minus = {}, plus = {}, del = {}, cells = {}, filters = {} }
      local hover, hoverLevel

      local helpFont = T.font(15 * s)
      local helpY = y + h - helpFont:getHeight()
      local leftW = math.floor(430 * s)
      local headFont = T.font(18 * s)

      ---------------- left: sections ----------------
      if not ctx then
        g.setFont(headFont); g.setColor(1, 1, 1, 0.6)
        g.printf(spec.unavailableText .. "\nYou can still browse the catalog.", x, y + 8 * s, leftW)
      else
        clampSel(ctx)
        local rows, headers = 0, 0
        for _, sec in ipairs(spec.sections) do rows = rows + math.max(sec.slots(ctx), 1); headers = headers + 1 end
        local avail = helpY - 12 * s - y - headers * 30 * s - (headers - 1) * 14 * s
        local rowH = math.floor(math.min(46 * s, avail / math.max(rows, 1)))
        local bw = math.floor(math.min(30 * s, rowH - 10 * s))
        local ry = y
        for si, sec in ipairs(spec.sections) do
          if si > 1 then ry = ry + 14 * s end
          g.setFont(headFont); g.setColor(1, 1, 1, 1)
          g.print(sec.title(ctx), x, ry)
          ry = ry + 30 * s
          local n = sec.slots(ctx)
          if n == 0 then
            g.setFont(T.font(16 * s)); g.setColor(1, 1, 1, 0.35)
            g.print(sec.noneText or "(none)", x, ry + 8 * s)
            ry = ry + rowH
          end
          local nButtons = (sec.setLevel and 2 or 0) + (sec.remove and 1 or 0)
          for i = 1, n do
            local e = sec.get(ctx, i)
            local r = { x, ry, leftW, rowH }
            F.hit.rows[#F.hit.rows + 1] = { r, si, i }
            local bx = x + leftW - nButtons * (bw + 4 * s) - 2 * s
            local rightText = e and sec.right and sec.right(ctx, i, e) or nil
            local isHover = drawRow(r, e, {
              selected = F.sel[1] == si and F.sel[2] == i,
              nameW = bx - (x + rowH + 12 * s) - (rightText and 70 * s or 0),
              right = rightText, rightX = bx - 6 * s,
              dim = e and sec.dim and sec.dim(ctx, i, e),
              emptyText = sec.emptyText and sec.emptyText(ctx, i),
            }, s, mx, my)
            if isHover and e then hover, hoverLevel = e, sec.level and sec.level(e) or 1 end
            if e and nButtons > 0 then
              local by = ry + (rowH - 4 * s - bw) / 2
              local bf = T.font(18 * s)
              local b = bx
              if sec.setLevel then
                local lv, max = sec.level(e), sec.maxLevel(e)
                F.hit.minus[#F.hit.minus + 1] = { T.panel.button({ b, by, bw, bw }, "-", bf, false, not locked and lv > 1), si, i }
                b = b + bw + 4 * s
                F.hit.plus[#F.hit.plus + 1] = { T.panel.button({ b, by, bw, bw }, "+", bf, false, not locked and lv < max), si, i }
                b = b + bw + 4 * s
              end
              if sec.remove then
                F.hit.del[#F.hit.del + 1] = { T.panel.button({ b, by, bw, bw }, "x", bf, false, not locked), si, i }
              end
            end
            ry = ry + rowH
          end
        end
      end

      ---------------- right: catalog ----------------
      local cx = x + leftW + 26 * s
      local cw = x + w - cx
      local fx = cx
      for _, f in ipairs(spec.filters and spec.filters() or {}) do
        local ff = T.font(16 * s)
        local fw = ff:getWidth(f[2]) + 26 * s
        F.hit.filters[f[1]] = T.panel.button({ fx, y - 2 * s, fw, 28 * s }, f[2], ff, F.filter == f[1])
        fx = fx + fw + 6 * s
      end

      local items = {}
      for _, d in ipairs(spec.catalog()) do
        if F.filter == "all" or spec.filterOf(d) == F.filter then items[#items + 1] = d end
      end
      local gridY = y + 36 * s
      local detailH = 150 * s
      local gridH = helpY - 12 * s - detailH - gridY
      local cell = math.floor(52 * s)
      local cols, rows
      repeat
        cols = math.max(1, math.floor(cw / cell))
        rows = math.ceil(#items / cols)
        if rows * cell > gridH and cell > 20 then cell = cell - 2 end
      until rows * cell <= gridH or cell <= 20

      local marks, levels = {}, {}
      if ctx then
        for _, sec in ipairs(spec.sections) do
          if sec.mark then
            for i = 1, sec.slots(ctx) do
              local e = sec.get(ctx, i)
              if e and e.id then
                if sec.mark == "owned" or not marks[e.id] then marks[e.id] = sec.mark end
                if sec.mark == "owned" and sec.level then levels[e.id] = sec.level(e) end
              end
            end
          end
        end
      end
      local cur = ctx and selected(ctx)
      for n, d in ipairs(items) do
        local col, row = (n - 1) % cols, math.floor((n - 1) / cols)
        local r = { cx + col * cell, gridY + row * cell, cell - 4 * s, cell - 4 * s }
        F.hit.cells[n] = { r, d }
        local isHover = inside(r, mx, my)
        local isCur = cur and cur.id == d.id
        setRarityColor(d, isHover and 0.4 or 0.16); g.rectangle("fill", r[1], r[2], r[3], r[4], 5 * s)
        setRarityColor(d, isCur and 1 or 0.55)
        g.setLineWidth(math.max(1, (isCur and 2.5 or 1) * s))
        g.rectangle("line", r[1], r[2], r[3], r[4], 5 * s)
        drawIcon(d, r[1] + 5 * s, r[2] + 5 * s, r[3] - 10 * s, marks[d.id] == "owned" and 0.45 or 1)
        if marks[d.id] == "owned" then
          g.setColor(0.95, 0.78, 0.3, 1)
          g.polygon("fill", r[1] + r[3] - 14 * s, r[2], r[1] + r[3], r[2], r[1] + r[3], r[2] + 14 * s)
        elseif marks[d.id] == "offer" then
          g.setColor(0.45, 0.86, 0.45, 1); g.circle("fill", r[1] + r[3] - 6 * s, r[2] + 6 * s, 3.5 * s)
        end
        if isHover then hover, hoverLevel = d, levels[d.id] or 1 end
      end

      ---------------- detail box ----------------
      local dy = helpY - 12 * s - detailH + 8 * s
      local dd, dl = hover, hoverLevel
      if not dd and cur then
        local sec = spec.sections[F.sel[1]]
        dd, dl = cur, sec.level and sec.level(cur) or 1
      end
      g.setColor(1, 1, 1, 0.05); g.rectangle("fill", cx, dy, cw, detailH - 8 * s, 6 * s)
      local px, pw = cx + 10 * s, cw - 20 * s
      if F.msg and love.timer.getTime() < (F.msgUntil or 0) then
        g.setFont(T.font(16 * s)); g.setColor(1, 0.75, 0.45, 1)
        g.printf(F.msg, px, dy + 8 * s, pw, "right")
      end
      if dd then
        local nf = gameFont(20 * s)
        g.setFont(nf); setRarityColor(dd)
        g.print(fitText(nf, spec.name(dd), pw * 0.55), px, dy + 8 * s)
        local mf = gameFont(16 * s) -- may contain localized text (core triggers)
        g.setFont(mf); g.setColor(1, 1, 1, 0.6)
        g.print(spec.meta(dd, dl or 1), px, dy + 8 * s + nf:getHeight() + 4 * s)
        local ef = gameFont(20 * s)
        local _, lines = ef:getWrap(spec.effect(dd, dl or 1), pw)
        local ly = dy + 8 * s + nf:getHeight() + mf:getHeight() + 12 * s
        g.setFont(ef); g.setColor(1, 1, 1, 0.9)
        for _, line in ipairs(lines) do
          if ly + ef:getHeight() > dy + detailH - 10 * s then break end
          g.print(line, px, ly)
          ly = ly + ef:getHeight() + 2 * s
        end
      else
        g.setFont(T.font(16 * s)); g.setColor(1, 1, 1, 0.5)
        g.printf("Select a slot on the left, then click an entry to put it there.\n"
          .. "Gold corner = owned, green dot = offered.", px, dy + 10 * s, pw)
      end

      ---------------- help ----------------
      g.setFont(helpFont)
      if locked then
        g.setColor(1, 0.75, 0.45, 1); g.print(locked, x, helpY)
      else
        g.setColor(0.8, 0.8, 0.85, 1); g.print(spec.help, x, helpY)
      end
    end

    --------------------------------------------------------------------------
    -- input
    --------------------------------------------------------------------------
    local function moveSel(ctx, dir)
      local flat, total, at = {}, 0, nil
      for si = 1, #spec.sections do
        for i = 1, selectable(ctx, si) do
          total = total + 1
          flat[total] = { si, i }
          if F.sel[1] == si and F.sel[2] == i then at = total end
        end
      end
      if total == 0 then return end
      at = ((at or 0) - 1 + dir) % total + 1
      F.sel = { flat[at][1], flat[at][2] }
    end

    -- run an edit on row (si, i) unless editing is locked
    local function edit(si, i, fn)
      local ctx, locked = spec.context()
      if not ctx then return end
      if locked then tab.flash("%s", locked); return end
      local e = spec.sections[si].get(ctx, i)
      if e then fn(ctx, spec.sections[si], e) end
    end

    local function stepLevel(si, i, dir)
      edit(si, i, function(ctx, sec, e)
        if sec.setLevel then sec.setLevel(ctx, i, math.max(1, math.min(sec.maxLevel(e), sec.level(e) + dir))) end
      end)
    end

    local function removeRow(si, i)
      edit(si, i, function(ctx, sec) if sec.remove then sec.remove(ctx, i) end end)
    end

    function tab.keypressed(key)
      local ctx = spec.context()
      if not ctx then return end
      clampSel(ctx)
      if key == "up" then moveSel(ctx, -1)
      elseif key == "down" then moveSel(ctx, 1)
      elseif key == "left" then stepLevel(F.sel[1], F.sel[2], -1)
      elseif key == "right" then stepLevel(F.sel[1], F.sel[2], 1)
      elseif key == "delete" or key == "backspace" then removeRow(F.sel[1], F.sel[2]) end
    end

    function tab.mousepressed(x, y, button)
      if button ~= 1 then return end
      local h = F.hit
      for key, r in pairs(h.filters or {}) do
        if inside(r, x, y) then F.filter = key; return end
      end
      for _, c in ipairs(h.cells or {}) do
        if inside(c[1], x, y) then
          local ctx, locked = spec.context()
          if not ctx then return end
          if locked then tab.flash("%s", locked); return end
          clampSel(ctx)
          spec.sections[F.sel[1]].put(ctx, F.sel[2], c[2])
          return
        end
      end
      for _, b in ipairs(h.minus or {}) do
        if inside(b[1], x, y) then F.sel = { b[2], b[3] }; stepLevel(b[2], b[3], -1); return end
      end
      for _, b in ipairs(h.plus or {}) do
        if inside(b[1], x, y) then F.sel = { b[2], b[3] }; stepLevel(b[2], b[3], 1); return end
      end
      for _, b in ipairs(h.del or {}) do
        if inside(b[1], x, y) then removeRow(b[2], b[3]); return end
      end
      local ctx = spec.context()
      for _, row in ipairs(h.rows or {}) do
        if inside(row[1], x, y) then
          F.sel = { row[2], row[3] }
          if ctx then clampSel(ctx) end
          return
        end
      end
    end

    -- select row i of section si (e.g. after placing an entry)
    function tab.select(si, i) F.sel = { si, i } end

    tab._state, tab.spec = F, spec
    T.panel.addTab(tab)
    return tab
  end

  T.picker = picker
  return picker
end
