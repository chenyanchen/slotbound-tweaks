-- Items: pick, swap, level or remove the run's items, and choose what the
-- item shop offers (F8 panel tab, built on picker.lua).
--
-- How the game keeps items (v1.0.3):
--   ui._itemPurchased      owned items: copies of the item defs plus `level`
--   ui._itemPurchasedKeys  parallel list of panel keys ("p<n>"); the last id
--                          handed out is ui._itemPanelNextId
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
  local picker = T.picker

  local F = {
    cfg = T.config.load("items", { planted = {} }),
    checkTimer = 0,
  }
  local tab -- the picker tab, created at the end

  --------------------------------------------------------------------------
  -- game access
  --------------------------------------------------------------------------
  local function itemMod() return package.loaded["src.game.item"] end

  -- The game's `ui` table when a run's items are available, plus a reason
  -- string when they can be viewed but not edited.
  local function runUI()
    local ui = rawget(_G, "ui")
    local phase = rawget(_G, "phase")
    if type(ui) ~= "table" or phase == nil or phase == "menu" then return nil end
    if phase == "battle" then return ui, T.tr("lock.battle") end
    return ui
  end

  -- The game creates ui._itemPurchased on the first purchase of a run.
  local function owned(ui)
    return type(ui._itemPurchased) == "table" and ui._itemPurchased or {}
  end

  local function capacity(ui)
    local fn = rawget(_G, "getItemInventoryCapacity")
    local ok, cap = false, nil
    if type(fn) == "function" then ok, cap = pcall(fn) end
    cap = (ok and tonumber(cap)) or 6
    return math.max(cap, #owned(ui))
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
      local ra, rb = picker.rarityRank(a.rarity), picker.rarityRank(b.rarity)
      if ra ~= rb then return ra < rb end
      return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
    end)
    F.catalog = list
    return list
  end

  -- "Battle", "Training", ...: the game's own label for an item type
  local function typeLabel(t)
    return T.gameText("item_type_" .. tostring(t):lower()) or tostring(t)
  end

  -- built on every draw: the labels follow the game's language
  local function filters()
    return picker.filtersFrom(catalog(), function(d) return d.type end, typeLabel)
  end

  local function icon(d)
    local M = itemMod()
    if not d or type(M) ~= "table" or type(M.getIcon) ~= "function" then return nil end
    local ok, img = pcall(M.getIcon, d)
    if ok and type(img) == "userdata" and img.typeOf and img:typeOf("Texture") then return img end
    return nil
  end

  local function maxLevel(d) return math.max(1, tonumber(d and d.maxLevel) or 1) end
  local function levelOf(e) return tonumber(e and e.level) or 1 end

  --------------------------------------------------------------------------
  -- localized text (the game's language tables, falling back to English)
  --------------------------------------------------------------------------
  local function itemName(d)
    local L = package.loaded["src.data.language"]
    return T.gameText("item.name." .. d.id)
      or (type(L) == "table" and type(L.itemNameMap) == "table" and L.itemNameMap[d.id])
      or tostring(d.key or d.id)
  end

  local function itemEffect(d, level)
    local txt = T.gameText("item.effect." .. d.id .. "." .. level)
    if not txt and type(d.getEffectDescription) == "function" then
      local ok, r = pcall(d.getEffectDescription, d, level)
      if ok then txt = r end
    end
    return picker.plainText(txt or d.effect)
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
    for _, e in ipairs(owned(ui)) do
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
    local n = tonumber(ui._itemPanelNextId) or (#owned(ui) + 1000)
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
      local e = type(ui._itemPurchased) == "table" and ui._itemPurchased[1] or nil
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
    for j, e in ipairs(owned(ui)) do
      if type(e) == "table" and e.id == id then return j end
    end
    return nil
  end

  local function putOwned(ui, i, d)
    if type(ui._itemPurchased) ~= "table" then ui._itemPurchased = {} end
    local list = ui._itemPurchased
    local j = ownedIndex(ui, d.id)
    if j == i then return end
    if j then
      tab.flash("%s", T.tr("items.in_slot", itemName(d), j))
      tab.select(1, j)
      return
    end
    if i > #list + 1 then i = #list + 1 end
    if i > capacity(ui) then tab.flash("%s", T.tr("items.full")); return end
    local keys = ui._itemPurchasedKeys
    if type(keys) ~= "table" then keys = {}; ui._itemPurchasedKeys = keys end
    for k = 1, #list do keys[k] = keys[k] or newKey(ui) end
    local old = list[i]
    list[i] = buildEntry(ui, d, 1)
    keys[i] = newKey(ui)
    tab.select(1, i)
    T.taint("item editor")
    T.log("items: slot %d %s -> %s", i, old and tostring(old.id) or "empty", d.id)
  end

  local function setLevel(ui, i, level)
    local e = owned(ui)[i]
    if type(e) ~= "table" then return end
    level = math.max(1, math.min(maxLevel(e), level))
    if level == e.level then return end
    e.level = level
    if type(e.updateEffectString) == "function" then pcall(e.updateEffectString, e) end
    e[MARK] = true
    T.taint("item editor")
  end

  local function removeOwned(ui, i)
    local e = owned(ui)[i]
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

  --------------------------------------------------------------------------
  -- panel tab
  --------------------------------------------------------------------------
  tab = picker.tab({
    id = "items", title = function() return T.tr("items") end,
    context = runUI,
    unavailableText = function() return T.tr("items.unavailable") end,
    catalog = catalog,
    filters = filters,
    filterOf = function(d) return d.type end,
    name = itemName, effect = itemEffect, icon = icon,
    meta = function(d, level)
      local m = string.format("%s  %s  %s", picker.rarityName(d.rarity), typeLabel(d.type),
        T.tr("level", level, maxLevel(d)))
      if tonumber(d.stage) then m = m .. "  " .. T.tr("items.stage", d.stage) end
      return m
    end,
    help = function() return T.tr("items.help") end,
    sections = {
      {
        title = function(ui) return T.tr("items.slots", #owned(ui), capacity(ui)) end,
        slots = capacity,
        selectable = function(ui) return math.min(#owned(ui) + 1, capacity(ui)) end,
        get = function(ui, i) return owned(ui)[i] end,
        put = putOwned,
        mark = "owned",
        right = function(_, _, e) return T.tr("level", levelOf(e), maxLevel(e)) end,
        emptyText = function(ui, i) return i == #owned(ui) + 1 and T.tr("items.empty_add") or T.tr("picker.empty") end,
        level = levelOf, maxLevel = maxLevel, setLevel = setLevel,
        remove = removeOwned,
      },
      {
        title = function() return T.tr("shop") end,
        slots = function(ui) return type(ui._itemOffers) == "table" and #ui._itemOffers or 0 end,
        get = function(ui, j) return ui._itemOffers[j] end,
        put = putOffer,
        mark = "offer",
        noneText = function() return T.tr("items.shop_none") end,
        right = function(ui, j, d)
          local bought = type(ui._itemShopPurchased) == "table" and ui._itemShopPurchased or {}
          local sold = bought[j] or bought[tostring(j)]
          return d.price and string.format("%s%d", sold and (T.tr("items.sold") .. "  ") or "", d.price) or nil
        end,
        dim = function(ui, j)
          local bought = type(ui._itemShopPurchased) == "table" and ui._itemShopPurchased or {}
          return bought[j] or bought[tostring(j)]
        end,
      },
    },
  })

  --------------------------------------------------------------------------
  -- feature hooks
  --------------------------------------------------------------------------
  local feature = { _state = F, tab = tab }

  function feature.update(dt)
    F.checkTimer = F.checkTimer - dt
    if F.checkTimer > 0 then return end
    F.checkTimer = 0.5
    local ui = rawget(_G, "ui")
    if type(ui) == "table" then guard(ui) end
  end

  return feature
end
