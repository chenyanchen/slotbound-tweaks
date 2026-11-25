-- Items: pick, swap, level or remove the run's items, and choose what the
-- item shop offers (F8 panel tab).
--
-- How the game keeps items (v1.0.3):
--   ui._itemPurchased      owned items: copies of the item defs plus `level`
--   ui._itemPurchasedKeys  parallel list of panel keys ("p<n>"), next id in
--                          ui._itemPanelNextId
--   ui._itemOffers         the shop's offers: references to the item defs
--   ui._itemShopPurchased  shop slots already bought this cycle
--   restorePurchasedItems(list) (global, main.lua) rebuilds owned entries
--   from saved {id, level, ...} tables; the run save uses it, and so do we.
--
-- Leaderboard guard: every entry this feature creates or changes carries
-- MARK, which the run save keeps, so continuing a modified run after a
-- restart taints that session too. Shop offers are saved as bare ids, so
-- planted offer ids are remembered in config/items.lua until the shop
-- rerolls them away; buying one marks the bought entry.

return function(T)
  local MARK = "__slotboundTweaks"
  local RARITY_RANK = { C = 1, U = 2, R = 3, L = 4 }
  local RARITY_NAME = { C = "Common", U = "Uncommon", R = "Rare", L = "Legendary" }
  local RARITY_COLOR = {
    C = { 0.78, 0.78, 0.8 }, U = { 0.45, 0.86, 0.45 }, R = { 0.42, 0.66, 1 }, L = { 1, 0.64, 0.22 },
  }
  local TYPE_NAME = { BATTLE = "Battle", TRAINING = "Training" }
  local FILTERS = { { "all", "All" }, { "BATTLE", "Battle" }, { "TRAINING", "Training" } }
  local STAT_WORDS = { hp = "HP", atk = "ATK", aspd = "ASPD", def = "DEF", range = "RANGE" }

  local F = {
    cfg = T.config.load("items", { planted = {} }),
    sel = { kind = "owned", i = 1 },
    filter = "all",
    hit = {},
    checkTimer = 0,
  }

  local function flash(fmt, ...)
    F.msg = string.format(fmt, ...)
    F.msgUntil = love.timer.getTime() + 3
  end

  --------------------------------------------------------------------------
  -- game access
  --------------------------------------------------------------------------
  local function itemMod() return package.loaded["src.game.item"] end

  -- The game's `ui` table when a run's items are available, plus a reason
  -- string when they can be viewed but not edited.
  local function runUI()
    local ui = rawget(_G, "ui")
    if type(ui) ~= "table" or type(ui._itemPurchased) ~= "table" then return nil end
    local phase = rawget(_G, "phase")
    if phase == "menu" then return nil end
    if phase == "battle" then return ui, "Items can't be changed during a battle." end
    return ui
  end

  local function capacity(ui)
    local fn = rawget(_G, "getItemInventoryCapacity")
    local ok, cap = false, nil
    if type(fn) == "function" then ok, cap = pcall(fn) end
    cap = (ok and tonumber(cap)) or 6
    return math.max(cap, #ui._itemPurchased)
  end

  local function catalog()
    if F.catalog then return F.catalog end
    local M = itemMod()
    if type(M) ~= "table" or type(M.getAll) ~= "function" then return {} end
    local list = {}
    for _, d in ipairs(M.getAll()) do
      if type(d) == "table" and d.id then
        local ok, avail = pcall(M.isAvailableInEdition, d)
        if not ok or avail ~= false then list[#list + 1] = d end
      end
    end
    table.sort(list, function(a, b)
      if a.type ~= b.type then return tostring(a.type) < tostring(b.type) end
      local ra, rb = RARITY_RANK[a.rarity] or 9, RARITY_RANK[b.rarity] or 9
      if ra ~= rb then return ra < rb end
      return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
    end)
    F.catalog = list
    return list
  end

  local function icon(d)
    local M = itemMod()
    if not d or type(M) ~= "table" or type(M.getIcon) ~= "function" then return nil end
    local ok, img = pcall(M.getIcon, d)
    if ok and type(img) == "userdata" and img.typeOf and img:typeOf("Texture") then return img end
    return nil
  end

  local function maxLevel(d) return math.max(1, tonumber(d and d.maxLevel) or 1) end

  --------------------------------------------------------------------------
  -- localized text (the game's language tables, falling back to English)
  --------------------------------------------------------------------------
  local function langText(key)
    local L = package.loaded["src.data.language"]
    if type(L) ~= "table" then return nil end
    local cur = L[rawget(_G, "currentGameLang") or "en"]
    return (type(cur) == "table" and cur[key]) or (type(L.en) == "table" and L.en[key]) or nil
  end

  local function itemName(d)
    local L = package.loaded["src.data.language"]
    return langText("item.name." .. d.id)
      or (type(L) == "table" and type(L.itemNameMap) == "table" and L.itemNameMap[d.id])
      or tostring(d.key or d.id)
  end

  local function itemEffect(d, level)
    local txt = langText("item.effect." .. d.id .. "." .. level)
    if not txt and type(d.getEffectDescription) == "function" then
      local ok, r = pcall(d.getEffectDescription, d, level)
      if ok then txt = r end
    end
    txt = tostring(txt or d.effect or "")
    return (txt:gsub("{(%w+)%.png}", function(w) return STAT_WORDS[w] or w:upper() end))
  end

  -- The game's own font for the current language (item names may be CJK).
  local gameFonts = {}
  local function gameFont(px)
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

  --------------------------------------------------------------------------
  -- leaderboard guard
  --------------------------------------------------------------------------
  local function savePlanted() T.config.save("items", F.cfg) end

  local function isPlanted(id)
    for _, p in ipairs(F.cfg.planted) do if p == id then return true end end
    return false
  end

  local function plant(id)
    if isPlanted(id) then return end
    table.insert(F.cfg.planted, id)
    savePlanted()
  end

  local function guard(ui)
    for _, e in ipairs(ui._itemPurchased) do
      if type(e) == "table" then
        if not e[MARK] and isPlanted(e.id) then e[MARK] = true end
        if e[MARK] then T.taint("item editor") end
      end
    end
    if #F.cfg.planted == 0 then return end
    local offered = {}
    for _, d in pairs(type(ui._itemOffers) == "table" and ui._itemOffers or {}) do
      if type(d) == "table" and d.id then offered[d.id] = true end
    end
    local keep = {}
    for _, id in ipairs(F.cfg.planted) do
      if offered[id] then keep[#keep + 1] = id; T.taint("item editor") end
    end
    if #keep ~= #F.cfg.planted then F.cfg.planted = keep; savePlanted() end
  end

  --------------------------------------------------------------------------
  -- editing
  --------------------------------------------------------------------------
  -- ui._itemPanelNextId holds the last id handed out (keys p7..p11 -> 11).
  local function newKey(ui)
    local used = {}
    for _, k in pairs(type(ui._itemPurchasedKeys) == "table" and ui._itemPurchasedKeys or {}) do used[k] = true end
    local n = tonumber(ui._itemPanelNextId) or (#ui._itemPurchased + 1000)
    repeat n = n + 1 until not used["p" .. n]
    ui._itemPanelNextId = n
    return "p" .. n
  end

  -- A fresh owned entry built the way the game restores a saved run.
  local function buildEntry(ui, d, level)
    local restore = rawget(_G, "restorePurchasedItems")
    if type(restore) == "function" then
      local saved = ui._itemPurchased
      local ok, err = pcall(restore, { { id = d.id, level = level, [MARK] = true } })
      local e = ui._itemPurchased[1]
      ui._itemPurchased = saved
      if ok and type(e) == "table" and e.id == d.id then return e end
      T.log("items: restorePurchasedItems failed (%s), building entry by hand", tostring(err))
    end
    local e = {}
    for k, v in pairs(d) do e[k] = v end
    e.level, e[MARK] = level, true
    if type(e.updateEffectString) == "function" then pcall(e.updateEffectString, e) end
    return e
  end

  local function ownedIndex(ui, id)
    for j, e in ipairs(ui._itemPurchased) do
      if type(e) == "table" and e.id == id then return j end
    end
    return nil
  end

  local function putOwned(ui, i, d)
    local owned = ui._itemPurchased
    local j = ownedIndex(ui, d.id)
    if j == i then return end
    if j then
      flash("%s is already in slot %d.", itemName(d), j)
      F.sel = { kind = "owned", i = j }
      return
    end
    if i > #owned + 1 then i = #owned + 1 end
    if i > capacity(ui) then flash("The item inventory is full."); return end
    local keys = ui._itemPurchasedKeys
    if type(keys) ~= "table" then keys = {}; ui._itemPurchasedKeys = keys end
    for k = 1, #owned do keys[k] = keys[k] or newKey(ui) end
    local old = owned[i]
    owned[i] = buildEntry(ui, d, 1)
    keys[i] = newKey(ui)
    F.sel = { kind = "owned", i = i }
    T.taint("item editor")
    T.log("items: slot %d %s -> %s", i, old and tostring(old.id) or "empty", d.id)
  end

  local function setLevel(ui, i, level)
    local e = ui._itemPurchased[i]
    if type(e) ~= "table" then return end
    level = math.max(1, math.min(maxLevel(e), level))
    if level == e.level then return end
    e.level = level
    if type(e.updateEffectString) == "function" then pcall(e.updateEffectString, e) end
    e[MARK] = true
    T.taint("item editor")
  end

  local function removeOwned(ui, i)
    local e = ui._itemPurchased[i]
    if type(e) ~= "table" then return end
    table.remove(ui._itemPurchased, i)
    if type(ui._itemPurchasedKeys) == "table" then table.remove(ui._itemPurchasedKeys, i) end
    T.taint("item editor")
    T.log("items: removed %s from slot %d", tostring(e.id), i)
  end

  local function putOffer(ui, j, d)
    if type(ui._itemOffers) ~= "table" or ui._itemOffers[j] == nil then return end
    ui._itemOffers[j] = d
    local bought = ui._itemShopPurchased
    if type(bought) == "table" then bought[j] = nil; bought[tostring(j)] = nil end
    plant(d.id)
    T.taint("item editor")
    T.log("items: shop offer %d -> %s", j, d.id)
  end

  local function selectedItem(ui)
    if not ui then return nil end
    if F.sel.kind == "owned" then return ui._itemPurchased[F.sel.i] end
    return type(ui._itemOffers) == "table" and ui._itemOffers[F.sel.i] or nil
  end

  local function place(d)
    local ui, locked = runUI()
    if not ui then return end
    if locked then flash("%s", locked); return end
    if F.sel.kind == "owned" then putOwned(ui, F.sel.i, d) else putOffer(ui, F.sel.i, d) end
  end

  --------------------------------------------------------------------------
  -- drawing
  --------------------------------------------------------------------------
  local inside = T.panel.inside
  local tab = { id = "items", title = "Items" }

  local function drawIcon(d, x, y, size, alpha)
    local img = icon(d)
    if not img then return end
    local iw, ih = img:getDimensions()
    local sc = size / math.max(iw, ih)
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(img, x + (size - iw * sc) / 2, y + (size - ih * sc) / 2, 0, sc, sc)
  end

  local function setRarityColor(d, a)
    local c = RARITY_COLOR[d and d.rarity] or RARITY_COLOR.C
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
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

  -- one owned / shop row; returns the hovered item if the mouse is on it
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
    local nameFont = gameFont(20 * s)
    local ty = y + (h - 4 * s - nameFont:getHeight()) / 2
    if not d then
      g.setFont(T.font(16 * s)); g.setColor(1, 1, 1, 0.35)
      g.print(opts.emptyLabel or "(empty)", x + isz + 18 * s, y + (h - 4 * s - T.font(16 * s):getHeight()) / 2)
      return nil
    end
    drawIcon(d, x + 6 * s, y + 4 * s, isz, opts.dim and 0.4 or 1)
    g.setFont(nameFont); setRarityColor(d, opts.dim and 0.45 or 1)
    g.print(fitText(nameFont, itemName(d), opts.nameW), x + isz + 18 * s, ty)
    if opts.right then
      g.setFont(T.font(16 * s)); g.setColor(1, 1, 1, opts.dim and 0.4 or 0.85)
      g.printf(opts.right, x, y + (h - 4 * s - T.font(16 * s):getHeight()) / 2, opts.rightX - x, "right")
    end
    if inside({ x, y, w, h }, mx, my) then return d end
    return nil
  end

  function tab.draw(x, y, w, h, s)
    local g = love.graphics
    local mx, my = love.mouse.getPosition()
    local ui, locked = runUI()
    F.hit = { owned = {}, minus = {}, plus = {}, del = {}, shop = {}, cells = {}, filters = {} }
    local hover, hoverLevel

    local helpFont = T.font(15 * s)
    local helpY = y + h - helpFont:getHeight()
    local leftW = math.floor(430 * s)
    local headFont = T.font(18 * s)

    ---------------- left: owned items + shop offers ----------------
    g.setFont(headFont)
    if not ui then
      g.setColor(1, 1, 1, 0.6)
      g.printf("Start or continue a run to edit its items.\nYou can still browse the catalog.", x, y + 8 * s, leftW)
    else
      local owned = ui._itemPurchased
      local cap = capacity(ui)
      local offers = type(ui._itemOffers) == "table" and ui._itemOffers or {}
      local nOffers = #offers
      local avail = helpY - 12 * s - y - 2 * 30 * s - 14 * s
      local rowH = math.floor(math.min(46 * s, avail / (cap + math.max(nOffers, 1))))
      if F.sel.kind == "owned" and F.sel.i > math.min(#owned + 1, cap) then F.sel.i = math.max(1, math.min(#owned + 1, cap)) end
      if F.sel.kind == "shop" and F.sel.i > nOffers then F.sel = { kind = "owned", i = 1 } end

      g.setColor(1, 1, 1, 1)
      g.print(string.format("Owned  %d/%d", #owned, cap), x, y)
      local ry = y + 30 * s
      local bw = math.floor(30 * s)
      for i = 1, cap do
        local e = owned[i]
        local r = { x, ry, leftW, rowH }
        F.hit.owned[i] = r
        local bx = x + leftW - 3 * (bw + 4 * s) - 2 * s
        local lv = e and maxLevel(e) > 1 and string.format("Lv %d/%d", e.level or 1, maxLevel(e))
          or (e and "Lv 1/1") or nil
        local hv = drawRow(r, e, {
          selected = F.sel.kind == "owned" and F.sel.i == i,
          nameW = bx - (x + rowH + 12 * s) - 64 * s,
          right = lv, rightX = bx - 6 * s,
          emptyLabel = i == #owned + 1 and "(empty)  click an item to add" or "(empty)",
        }, s, mx, my)
        if hv then hover, hoverLevel = hv, e.level or 1 end
        if e then
          local by, bh = ry + (rowH - 4 * s - bw) / 2, bw
          local canEdit = not locked
          F.hit.minus[i] = T.panel.button({ bx, by, bw, bh }, "-", T.font(18 * s), false, canEdit and (e.level or 1) > 1)
          F.hit.plus[i] = T.panel.button({ bx + bw + 4 * s, by, bw, bh }, "+", T.font(18 * s), false,
            canEdit and (e.level or 1) < maxLevel(e))
          F.hit.del[i] = T.panel.button({ bx + 2 * (bw + 4 * s), by, bw, bh }, "x", T.font(18 * s), false, canEdit)
        end
        ry = ry + rowH
      end

      ry = ry + 14 * s
      g.setFont(headFont); g.setColor(1, 1, 1, 1)
      g.print("Shop offers", x, ry)
      ry = ry + 30 * s
      if nOffers == 0 then
        g.setFont(T.font(16 * s)); g.setColor(1, 1, 1, 0.35)
        g.print("(no offers right now)", x, ry + 8 * s)
      end
      local bought = type(ui._itemShopPurchased) == "table" and ui._itemShopPurchased or {}
      for j = 1, nOffers do
        local d = offers[j]
        local r = { x, ry, leftW, rowH }
        F.hit.shop[j] = r
        local isBought = bought[j] or bought[tostring(j)]
        local price = d and d.price and string.format("%s%d", isBought and "sold  " or "", d.price) or nil
        local hv = drawRow(r, d, {
          selected = F.sel.kind == "shop" and F.sel.i == j,
          nameW = leftW - rowH - 90 * s, right = price, rightX = x + leftW - 10 * s, dim = isBought,
        }, s, mx, my)
        if hv then hover, hoverLevel = hv, 1 end
        ry = ry + rowH
      end
    end

    ---------------- right: catalog ----------------
    local cx = x + leftW + 26 * s
    local cw = x + w - cx
    local fx = cx
    for _, f in ipairs(FILTERS) do
      local fw = T.font(16 * s):getWidth(f[2]) + 26 * s
      F.hit.filters[f[1]] = T.panel.button({ fx, y - 2 * s, fw, 28 * s }, f[2], T.font(16 * s), F.filter == f[1])
      fx = fx + fw + 6 * s
    end

    local items = {}
    for _, d in ipairs(catalog()) do
      if F.filter == "all" or d.type == F.filter then items[#items + 1] = d end
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
    local ownedIds, offerIds = {}, {}
    if ui then
      for _, e in ipairs(ui._itemPurchased) do if type(e) == "table" then ownedIds[e.id] = e.level or 1 end end
      for _, d in pairs(type(ui._itemOffers) == "table" and ui._itemOffers or {}) do
        if type(d) == "table" then offerIds[d.id] = true end
      end
    end
    local cur = selectedItem(ui)
    for n, d in ipairs(items) do
      local col, row = (n - 1) % cols, math.floor((n - 1) / cols)
      local r = { cx + col * cell, gridY + row * cell, cell - 4 * s, cell - 4 * s }
      F.hit.cells[n] = { r, d }
      local isHover = inside(r, mx, my)
      setRarityColor(d, isHover and 0.4 or 0.16); g.rectangle("fill", r[1], r[2], r[3], r[4], 5 * s)
      setRarityColor(d, (cur and cur.id == d.id) and 1 or 0.55)
      g.setLineWidth(math.max(1, ((cur and cur.id == d.id) and 2.5 or 1) * s))
      g.rectangle("line", r[1], r[2], r[3], r[4], 5 * s)
      drawIcon(d, r[1] + 5 * s, r[2] + 5 * s, r[3] - 10 * s, ownedIds[d.id] and 0.45 or 1)
      if ownedIds[d.id] then
        g.setColor(0.95, 0.78, 0.3, 1)
        g.polygon("fill", r[1] + r[3] - 14 * s, r[2], r[1] + r[3], r[2], r[1] + r[3], r[2] + 14 * s)
      elseif offerIds[d.id] then
        g.setColor(0.45, 0.86, 0.45, 1); g.circle("fill", r[1] + r[3] - 6 * s, r[2] + 6 * s, 3.5 * s)
      end
      if isHover then hover, hoverLevel = d, ownedIds[d.id] or 1 end
    end

    ---------------- detail box ----------------
    local dy = helpY - 12 * s - detailH + 8 * s
    local dd, dl = hover, hoverLevel
    if not dd and cur then dd, dl = cur, cur.level or 1 end
    g.setColor(1, 1, 1, 0.05); g.rectangle("fill", cx, dy, cw, detailH - 8 * s, 6 * s)
    local px, pw = cx + 10 * s, cw - 20 * s
    if F.msg and love.timer.getTime() < (F.msgUntil or 0) then
      g.setFont(T.font(16 * s)); g.setColor(1, 0.75, 0.45, 1)
      g.printf(F.msg, px, dy + 8 * s, pw, "right")
    end
    if dd then
      local nf = gameFont(20 * s)
      g.setFont(nf); setRarityColor(dd)
      g.print(fitText(nf, itemName(dd), pw * 0.55), px, dy + 8 * s)
      local meta = string.format("%s  %s  Lv %d/%d", RARITY_NAME[dd.rarity] or tostring(dd.rarity),
        TYPE_NAME[dd.type] or tostring(dd.type), dl or 1, maxLevel(dd))
      if tonumber(dd.stage) then meta = meta .. string.format("  stage %d item", dd.stage) end
      local mf = T.font(15 * s)
      g.setFont(mf); g.setColor(1, 1, 1, 0.6)
      g.print(meta, px, dy + 8 * s + nf:getHeight() + 4 * s)
      local ef = gameFont(20 * s)
      local _, lines = ef:getWrap(itemEffect(dd, dl or 1), pw)
      local ly = dy + 8 * s + nf:getHeight() + mf:getHeight() + 12 * s
      g.setFont(ef); g.setColor(1, 1, 1, 0.9)
      for _, line in ipairs(lines) do
        if ly + ef:getHeight() > dy + detailH - 10 * s then break end
        g.print(line, px, ly)
        ly = ly + ef:getHeight() + 2 * s
      end
    else
      g.setFont(T.font(16 * s)); g.setColor(1, 1, 1, 0.5)
      g.printf("Select a slot on the left, then click an item to put it there.\n"
        .. "Gold corner = owned, green dot = in the shop.", px, dy + 10 * s, pw)
    end

    ---------------- help ----------------
    g.setFont(helpFont)
    if locked then
      g.setColor(1, 0.75, 0.45, 1); g.print(locked, x, helpY)
    else
      g.setColor(0.8, 0.8, 0.85, 1)
      g.print("Click a slot, then an item   Up/Down slot   Left/Right level   Del remove   "
        .. "Changes apply from the next battle", x, helpY)
    end
  end

  --------------------------------------------------------------------------
  -- input
  --------------------------------------------------------------------------
  local function slotCount(ui)
    local owned = math.min(#ui._itemPurchased + 1, capacity(ui))
    local offers = type(ui._itemOffers) == "table" and #ui._itemOffers or 0
    return owned, offers
  end

  local function moveSel(ui, dir)
    local nOwned, nOffers = slotCount(ui)
    local flat = (F.sel.kind == "owned" and F.sel.i or nOwned + F.sel.i) + dir
    local total = nOwned + nOffers
    flat = (flat - 1) % total + 1
    if flat <= nOwned then F.sel = { kind = "owned", i = flat } else F.sel = { kind = "shop", i = flat - nOwned } end
  end

  function tab.keypressed(key)
    local ui, locked = runUI()
    if not ui then return end
    if key == "up" then moveSel(ui, -1); return end
    if key == "down" then moveSel(ui, 1); return end
    if F.sel.kind ~= "owned" then return end
    local e = ui._itemPurchased[F.sel.i]
    if not e then return end
    if locked and (key == "left" or key == "right" or key == "delete" or key == "backspace") then
      flash("%s", locked); return
    end
    if key == "left" then setLevel(ui, F.sel.i, (e.level or 1) - 1)
    elseif key == "right" then setLevel(ui, F.sel.i, (e.level or 1) + 1)
    elseif key == "delete" or key == "backspace" then removeOwned(ui, F.sel.i) end
  end

  function tab.mousepressed(x, y, button)
    if button ~= 1 then return end
    local h = F.hit
    for name, r in pairs(h.filters or {}) do
      if inside(r, x, y) then F.filter = name; return end
    end
    for _, c in ipairs(h.cells or {}) do
      if inside(c[1], x, y) then place(c[2]); return end
    end
    local ui, locked = runUI()
    if not ui then return end
    for i, r in pairs(h.minus) do
      if inside(r, x, y) then
        F.sel = { kind = "owned", i = i }
        if locked then flash("%s", locked) else setLevel(ui, i, (ui._itemPurchased[i].level or 1) - 1) end
        return
      end
    end
    for i, r in pairs(h.plus) do
      if inside(r, x, y) then
        F.sel = { kind = "owned", i = i }
        if locked then flash("%s", locked) else setLevel(ui, i, (ui._itemPurchased[i].level or 1) + 1) end
        return
      end
    end
    for i, r in pairs(h.del) do
      if inside(r, x, y) then
        if locked then flash("%s", locked) else removeOwned(ui, i) end
        return
      end
    end
    local nOwned = slotCount(ui)
    for i, r in pairs(h.owned) do
      if inside(r, x, y) then F.sel = { kind = "owned", i = math.min(i, nOwned) }; return end
    end
    for j, r in pairs(h.shop) do
      if inside(r, x, y) then F.sel = { kind = "shop", i = j }; return end
    end
  end

  T.panel.addTab(tab)

  --------------------------------------------------------------------------
  -- feature hooks
  --------------------------------------------------------------------------
  local F2 = {}

  function F2.update(dt)
    F.checkTimer = F.checkTimer - dt
    if F.checkTimer > 0 then return end
    F.checkTimer = 0.5
    local ui = rawget(_G, "ui")
    if type(ui) == "table" and type(ui._itemPurchased) == "table" then guard(ui) end
  end

  F2._state = F -- for tools/selftest.lua
  return F2
end
