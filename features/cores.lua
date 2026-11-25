-- Cores: choose the run's cores (add, swap or remove them), and choose what
-- the core selection screen offers (F8 panel tab, built on picker.lua).
--
-- How the game keeps cores (v1.0.3), all in src.game.cores:
--   getActive()            copy of the active list: { key, def, stacks, startWave, ... }
--   select(def, wave)      activate a core from `wave` on (the game's own pick path)
--   remove(key)            deactivate one core
--   isOwned(def)           whether a core is active
--   getIds() / getById(id) the catalog
-- ui._coreSelect (while the selection screen is open) has .offers, a list of
-- core defs; ui._coreSelectOffersCache keeps the wave's offers for re-opening.
-- CoreSelectFlow.getCapacity() returns (?, capacity).
--
-- Leaderboard guard: the run save stores cores as bare ids, so the keys of
-- cores this feature adds or offers are remembered in config/cores.lua.
-- While any of them is active or offered the session is tainted; keys are
-- dropped once they are neither, so a modified run continued after a
-- restart still taints that session.

return function(T)
  local RARITY_RANK = { C = 1, U = 2, R = 3, L = 4 }
  local RARITY_NAME = { C = "Common", U = "Uncommon", R = "Rare", L = "Legendary" }
  local picker = T.picker

  local F = {
    cfg = T.config.load("cores", { tweaked = {} }),
    checkTimer = 0,
  }
  local tab -- the picker tab, created at the end

  --------------------------------------------------------------------------
  -- game access
  --------------------------------------------------------------------------
  local function coresMod()
    local C = package.loaded["src.game.cores"]
    if type(C) == "table" and type(C.getActive) == "function" and type(C.select) == "function"
        and type(C.remove) == "function" and type(C.getById) == "function" then
      return C
    end
    return nil
  end

  local function activeList(C)
    local ok, list = pcall(C.getActive)
    return ok and type(list) == "table" and list or {}
  end

  local function defOf(o)
    if type(o) ~= "table" then return nil end
    if type(o.def) == "table" then return o.def end
    if type(o.core) == "table" then return o.core end
    return o.key and o or nil
  end

  -- The open core selection screen, if any.
  local function selection(ui)
    local cs = ui._coreSelect
    if type(cs) == "table" and cs.active and type(cs.offers) == "table" then return cs end
    return nil
  end

  -- ctx = { ui, C, active } while a run is going, plus a reason string when
  -- the cores can be viewed but not edited.
  local function runCtx()
    local ui, C = rawget(_G, "ui"), coresMod()
    local phase = rawget(_G, "phase")
    if type(ui) ~= "table" or not C or phase == nil or phase == "menu" then return nil end
    local ctx = { ui = ui, C = C, active = activeList(C) }
    if phase == "battle" then return ctx, "Cores can't be changed during a battle." end
    if rawget(_G, "uiLocked") then return ctx, "Wait for the slot machine to stop." end
    return ctx
  end

  local function capacity(ctx)
    local flow = rawget(_G, "CoreSelectFlow")
    local cap
    if type(flow) == "table" and type(flow.getCapacity) == "function" then
      local ok, a, b = pcall(flow.getCapacity)
      if ok then cap = tonumber(b) or tonumber(a) end
    end
    return math.max(cap or 8, #ctx.active)
  end

  local function currentWave()
    local bf = rawget(_G, "battlefield")
    return type(bf) == "table" and type(bf.wave) == "table" and tonumber(bf.wave.id) or 1
  end

  local function catalog()
    if F.catalog then return F.catalog end
    local C = coresMod()
    if not C or type(C.getIds) ~= "function" then return {} end
    local list = {}
    for _, id in ipairs(C.getIds()) do
      local ok, d = pcall(C.getById, id)
      if ok and type(d) == "table" and d.key then list[#list + 1] = d end
    end
    table.sort(list, function(a, b)
      local ra, rb = RARITY_RANK[a.rarity] or 9, RARITY_RANK[b.rarity] or 9
      if ra ~= rb then return ra < rb end
      return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
    end)
    F.catalog = list
    return list
  end

  local function icon(d)
    local C = coresMod()
    if not d or not C or type(C.getIcon) ~= "function" then return nil end
    local ok, img = pcall(C.getIcon, d)
    if ok and type(img) == "userdata" and img.typeOf and img:typeOf("Texture") then return img end
    return nil
  end

  --------------------------------------------------------------------------
  -- localized text
  --------------------------------------------------------------------------
  local function coreName(d)
    local L = package.loaded["src.data.language"]
    return picker.langText("core.name." .. d.key)
      or (type(L) == "table" and type(L.coreNameMap) == "table" and L.coreNameMap[d.key])
      or tostring(d.key)
  end

  local function coreDesc(d)
    local C = coresMod()
    local values
    if C and type(C.descValues) == "function" then
      local ok, v = pcall(C.descValues, d.key)
      if ok then values = v end
    end
    return picker.plainText(picker.langText("core.desc." .. d.key) or d.desc, values)
  end

  local function coreMeta(d)
    local parts = { RARITY_NAME[d.rarity] or tostring(d.rarity) }
    local trigger = picker.langText("core.trigger." .. d.key)
    if trigger then parts[#parts + 1] = picker.plainText(trigger) end
    if d.manualUse then parts[#parts + 1] = "manual use" end
    if d.consumable then parts[#parts + 1] = "consumable" end
    return table.concat(parts, "   ")
  end

  --------------------------------------------------------------------------
  -- leaderboard guard
  --------------------------------------------------------------------------
  local function saveCfg() T.config.save("cores", F.cfg) end

  local function isTweaked(key)
    for _, k in ipairs(F.cfg.tweaked) do if k == key then return true end end
    return false
  end

  local function record(key)
    T.taint("core editor")
    if isTweaked(key) then return end
    table.insert(F.cfg.tweaked, key)
    saveCfg()
  end

  local function guard()
    local ctx = runCtx()
    if not ctx or #F.cfg.tweaked == 0 then return end
    local live = {}
    for _, a in ipairs(ctx.active) do if a.key then live[a.key] = true end end
    local cs = selection(ctx.ui)
    for _, o in ipairs(cs and cs.offers or {}) do
      local d = defOf(o)
      if d then live[d.key] = true end
    end
    local cache = ctx.ui._coreSelectOffersCache
    for _, o in ipairs(type(cache) == "table" and type(cache.offers) == "table" and cache.offers or {}) do
      local d = defOf(o)
      if d then live[d.key] = true end
    end
    local keep = {}
    for _, k in ipairs(F.cfg.tweaked) do
      if live[k] then keep[#keep + 1] = k; T.taint("core editor") end
    end
    if #keep ~= #F.cfg.tweaked then F.cfg.tweaked = keep; saveCfg() end
  end

  --------------------------------------------------------------------------
  -- editing
  --------------------------------------------------------------------------
  local function activeIndex(ctx, key)
    for i, a in ipairs(activeList(ctx.C)) do
      if a.key == key then return i end
    end
    return nil
  end

  local function putActive(ctx, i, d)
    local old = ctx.active[i]
    if old and old.key == d.key then return end
    local j = activeIndex(ctx, d.key)
    if j then
      tab.flash("%s is already active (slot %d).", coreName(d), j)
      tab.select(1, j)
      return
    end
    if not old and #ctx.active >= capacity(ctx) then tab.flash("All core slots are full."); return end
    if old then
      local ok, err = pcall(ctx.C.remove, old.key)
      if not ok then tab.flash("Could not remove %s.", coreName(old.def or old)); T.log("cores: remove failed: %s", tostring(err)); return end
    end
    local ok, err = pcall(ctx.C.select, d, currentWave())
    if not ok then
      T.log("cores: select %s failed: %s", d.key, tostring(err))
      tab.flash("Could not add %s.", coreName(d))
      return
    end
    record(d.key)
    tab.select(1, activeIndex(ctx, d.key) or i)
    T.log("cores: slot %d %s -> %s", i, old and tostring(old.key) or "empty", d.key)
  end

  local function removeActive(ctx, i)
    local a = ctx.active[i]
    if not a or not a.key then return end
    local ok, err = pcall(ctx.C.remove, a.key)
    if not ok then T.log("cores: remove failed: %s", tostring(err)); return end
    T.taint("core editor")
    T.log("cores: removed %s", a.key)
  end

  local function putOffer(ctx, j, d)
    local cs = selection(ctx.ui)
    if not cs or cs.offers[j] == nil then return end
    local old = cs.offers[j]
    if defOf(old) and defOf(old).key == d.key then return end
    for k, o in ipairs(cs.offers) do
      local od = defOf(o)
      if k ~= j and od and od.key == d.key then tab.flash("%s is already offered.", coreName(d)); return end
    end
    if activeIndex(ctx, d.key) then tab.flash("%s is already active.", coreName(d)); return end
    cs.offers[j] = d
    local cache = ctx.ui._coreSelectOffersCache
    if type(cache) == "table" and type(cache.offers) == "table" then
      for k, o in ipairs(cache.offers) do if o == old then cache.offers[k] = d end end
    end
    record(d.key)
    T.log("cores: selection offer %d -> %s", j, d.key)
  end

  --------------------------------------------------------------------------
  -- panel tab
  --------------------------------------------------------------------------
  tab = picker.tab({
    id = "cores", title = "Cores",
    context = runCtx,
    unavailableText = "Start or continue a run to edit its cores.",
    catalog = catalog,
    filters = { { "all", "All" }, { "C", "Common" }, { "U", "Uncommon" }, { "R", "Rare" }, { "L", "Legendary" } },
    filterOf = function(d) return d.rarity end,
    name = coreName, effect = coreDesc, icon = icon,
    meta = coreMeta,
    help = "Click a slot, then a core   Up/Down slot   Del remove   New cores count from the current wave",
    sections = {
      {
        title = function(ctx) return string.format("Cores  %d/%d", #ctx.active, capacity(ctx)) end,
        slots = capacity,
        selectable = function(ctx) return math.min(#ctx.active + 1, capacity(ctx)) end,
        get = function(ctx, i) return defOf(ctx.active[i]) end,
        put = putActive,
        mark = "owned",
        emptyText = function(ctx, i) return i == #ctx.active + 1 and "(empty)  click a core to add" or "(empty)" end,
        remove = removeActive,
      },
      {
        title = function() return "Core selection" end,
        slots = function(ctx)
          local cs = selection(ctx.ui)
          return cs and #cs.offers or 0
        end,
        get = function(ctx, j)
          local cs = selection(ctx.ui)
          return cs and defOf(cs.offers[j]) or nil
        end,
        put = putOffer,
        mark = "offer",
        noneText = "(shown while the game offers cores)",
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
    guard()
  end

  return feature
end
