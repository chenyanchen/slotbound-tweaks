-- Imprints: change the imprints of the units on the board (add, swap, level
-- or remove them). F8 panel tab, built on picker.lua.
--
-- How the game keeps imprints (v1.0.3):
--   constants.imprint.definitions   id -> { id, name, icon, tag, condition, shortDesc,
--                                   levels = { { desc, shortDesc, stats }, ... } }
--   constants.imprint.slots         grade -> imprint slots of a unit of that grade
--   battlefield.rosterUnits[i]      the board's units (a sparse list); each has
--     .imprints = { inst, ... }     inst = copy of the def without `levels`, plus
--                                   level, maxLevel, rarity, and desc/shortDesc/stats
--                                   of its level
--     .maxImprintSlots
--   src.game.battlefield.signatureImprint(unit) -> the imprint a unit passes on
--     when it is absorbed, by symbol and grade; that grade is the imprint's rarity.
--   The absorb code refreshes an inst's level with a local helper
--   (inst, level) found among battlefield.dropRoster's upvalues.
-- The run save deep-copies rosterUnits, imprints included.
--
-- Leaderboard guard: every imprint this feature creates or changes carries
-- MARK, which the run save keeps; while any unit on the board has one, the
-- session is tainted, so continuing a modified run after a restart taints too.

return function(T)
  local MARK = "__slotboundTweaks"
  local picker = T.picker

  local F = { checkTimer = 0 }
  local tab -- the picker tab, created at the end

  --------------------------------------------------------------------------
  -- game access
  --------------------------------------------------------------------------
  local function imprintData()
    local C = package.loaded["src.data.constants"]
    local im = type(C) == "table" and C.imprint
    if type(im) == "table" and type(im.definitions) == "table" then return im end
    return nil
  end

  local function definition(id)
    local im = imprintData()
    local d = im and im.definitions[id]
    return type(d) == "table" and type(d.levels) == "table" and d or nil
  end

  local function gradeOrder()
    local C = package.loaded["src.data.constants"]
    local ug = type(C) == "table" and C.unitGrades
    return type(ug) == "table" and type(ug.order) == "table" and ug.order or {}
  end

  local function gradeRank(g)
    for i, v in ipairs(gradeOrder()) do if v == g then return i end end
    return 99
  end

  local function gradeLabel(g)
    return T.gameText("grade.label." .. tostring(g)) or tostring(g or "?")
  end

  local function gradeColor(g)
    local C = package.loaded["src.data.constants"]
    local colors = type(C) == "table" and type(C.unitGrades) == "table" and C.unitGrades.colors
    local c = type(colors) == "table" and colors[g]
    if type(c) == "table" and tonumber(c[1]) then return c end
    return { 0.85, 0.85, 0.88 }
  end

  -- imprint id -> the grade of the units that pass it on (its rarity)
  local function rarities()
    if F.rarities then return F.rarities end
    local BF = package.loaded["src.game.battlefield"]
    local sig = type(BF) == "table" and BF.signatureImprint
    local out, found = {}, false
    if type(sig) == "function" then
      for _, sym in ipairs(T.gameSymbols()) do
        for _, g in ipairs(gradeOrder()) do
          local ok, r = pcall(sig, { sym = sym, grade = g })
          local id = ok and (type(r) == "table" and r.id or r)
          if type(id) == "string" and out[id] == nil then out[id] = g; found = true end
        end
      end
    end
    if found then F.rarities = out end
    return out
  end

  -- The game's helper that sets an inst's level, desc, shortDesc and stats:
  -- a 2-parameter upvalue of battlefield.dropRoster that reads
  -- definitions/levels and leaves the imprint list alone. Verified on a
  -- scratch copy before use; nil if not found.
  local function findLevelHelper()
    if F.levelHelper ~= nil then return F.levelHelper or nil end
    local bf = rawget(_G, "battlefield")
    local drop = type(bf) == "table" and rawget(bf, "dropRoster")
    local im = imprintData()
    if type(drop) ~= "function" or not im then return nil end
    local probeId = next(im.definitions)
    local def = definition(probeId)
    if not def or #def.levels < 2 then return nil end
    local helper = false
    for i = 1, 80 do
      local n, f = debug.getupvalue(drop, i)
      if n == nil then break end
      if type(f) == "function" and debug.getinfo(f, "u").nparams == 2 then
        local okD, bc = pcall(string.dump, f)
        if okD and bc:find("levels", 1, true) and bc:find("definitions", 1, true)
            and bc:find("stats", 1, true) and not bc:find("imprints", 1, true) then
          local scratch = { id = probeId, level = 1 }
          local ok = pcall(f, scratch, 2)
          if ok and scratch.level == 2 and scratch.desc == def.levels[2].desc and type(scratch.stats) == "table" then
            helper = f
            break
          end
        end
      end
    end
    F.levelHelper = helper
    T.log("imprints: level helper %s", helper and "found" or "not found (using a built-in copy)")
    return helper or nil
  end

  local function copyTable(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copyTable(v) end
    return out
  end

  local function setInstLevel(inst, level)
    local def = definition(inst.id)
    if not def then return false end
    level = math.max(1, math.min(#def.levels, level))
    local helper = findLevelHelper()
    if helper and pcall(helper, inst, level) and inst.level == level then return true end
    local L = def.levels[level]
    inst.level = level
    inst.desc = L.desc
    inst.shortDesc = L.shortDesc or def.shortDesc
    inst.stats = copyTable(L.stats or {})
    return true
  end

  local function newInst(def, level)
    local inst = {}
    for k, v in pairs(def) do if k ~= "levels" then inst[k] = v end end
    inst.maxLevel = #def.levels
    inst.rarity = rarities()[def.id] or "normal"
    setInstLevel(inst, level or 1)
    inst[MARK] = true
    return inst
  end

  -- The board's units in roster order: { { pos = i, unit = u }, ... }
  local function boardUnits()
    local bf = rawget(_G, "battlefield")
    local roster = type(bf) == "table" and rawget(bf, "rosterUnits")
    local list = {}
    if type(roster) ~= "table" then return list end
    for pos, u in pairs(roster) do
      if type(pos) == "number" and type(u) == "table" and u.grade then list[#list + 1] = { pos = pos, unit = u } end
    end
    table.sort(list, function(a, b) return a.pos < b.pos end)
    return list
  end

  local function imprintsOf(u)
    if type(u.imprints) ~= "table" then u.imprints = {} end
    return u.imprints
  end

  local function slotsOf(u)
    local n = tonumber(u.maxImprintSlots)
    if not n then
      local im = imprintData()
      n = im and type(im.slots) == "table" and tonumber(im.slots[u.grade]) or 1
    end
    return math.max(n, #imprintsOf(u))
  end

  -- The most imprint slots any unit can have (5 in 1.0.3: Prism). The
  -- imprint section always shows this many rows so its size doesn't change
  -- with the selected unit's grade.
  local function slotRows(ctx)
    local n = 1
    local im = imprintData()
    for _, v in pairs(im and type(im.slots) == "table" and im.slots or {}) do n = math.max(n, tonumber(v) or 0) end
    for _, e in ipairs(ctx.units) do n = math.max(n, slotsOf(e.unit)) end
    return n
  end

  local function modalOpen()
    for _, t in ipairs({ rawget(_G, "ui"), rawget(_G, "battlefield") }) do
      local m = type(t) == "table" and rawget(t, "imprintModal")
      if type(m) == "table" and m.active then return true end
    end
    return false
  end

  -- ctx = { units, unit, n } while a run is going, plus a reason string when
  -- the imprints can be viewed but not edited. ctx.unit is the unit whose
  -- imprints the second section shows (the last one selected in Units).
  local function runCtx()
    local phase = rawget(_G, "phase")
    if not imprintData() or phase == nil or phase == "menu" then return nil end
    local ctx = { units = boardUnits() }
    local sel = tab and tab._state.sel
    if sel and sel[1] == 1 and ctx.units[sel[2]] then F.unit = ctx.units[sel[2]].unit end
    for i, e in ipairs(ctx.units) do
      if e.unit == F.unit then ctx.unit, ctx.n = e.unit, i end
    end
    if not ctx.unit and ctx.units[1] then ctx.unit, ctx.n = ctx.units[1].unit, 1; F.unit = ctx.unit end
    if phase == "battle" then return ctx, T.tr("lock.battle") end
    if rawget(_G, "uiLocked") then return ctx, T.tr("lock.spinning") end
    if modalOpen() then return ctx, T.tr("imprints.modal") end
    return ctx
  end

  local function catalog()
    if F.catalog then return F.catalog end
    local im = imprintData()
    if not im then return {} end
    local rar = rarities()
    local list = {}
    for id, d in pairs(im.definitions) do
      if type(d) == "table" and type(d.levels) == "table" and #d.levels > 0 then
        list[#list + 1] = { id = id, def = d, rarity = rar[id] or "special", maxLevel = #d.levels }
      end
    end
    table.sort(list, function(a, b)
      local ra, rb = gradeRank(a.rarity), gradeRank(b.rarity)
      if ra ~= rb then return ra < rb end
      return a.id < b.id
    end)
    F.catalog = list
    return list
  end

  -- built on every draw: the labels follow the game's language
  local function filters()
    return picker.filtersFrom(catalog(), function(d) return d.rarity end, gradeLabel, gradeRank)
  end

  local icons = {}
  local function imprintIcon(id)
    if icons[id] == nil then
      local d = definition(id)
      local ok, img = false, nil
      if d and type(d.icon) == "string" then ok, img = pcall(love.graphics.newImage, d.icon) end
      icons[id] = ok and img or false
    end
    return icons[id] or nil
  end

  local function unitIcon(u)
    local A = package.loaded["src.data.assets"]
    local img = type(A) == "table" and type(A.icons) == "table" and A.icons[u.sym]
    return type(img) == "userdata" and img or nil
  end

  --------------------------------------------------------------------------
  -- localized text
  --------------------------------------------------------------------------
  local function imprintName(id)
    local L = package.loaded["src.data.language"]
    local d = definition(id)
    return T.gameText("imprint.name." .. id)
      or (type(L) == "table" and type(L.imprintNameMap) == "table" and L.imprintNameMap[id])
      or (d and d.name) or tostring(id)
  end

  local function imprintDesc(id, level)
    local d = definition(id)
    local L = d and d.levels[math.max(1, math.min(#d.levels, level or 1))]
    return picker.plainText(T.gameText("imprint.desc." .. id .. "_" .. (level or 1)) or (L and L.desc) or "")
  end

  -- A promoted unit's class name via the game's translateUnitName(key, lang)
  -- (it normalizes keys such as "엘프병사" through unit.display.* first;
  -- unknown keys come back as "unit.name.<key>" or "Unknown"). A unit
  -- without a class (normal grade) is named after its symbol, as the game
  -- does: merc_contract_unit_<sym>.
  local function unitName(u)
    local L = package.loaded["src.data.language"]
    local key = u.subclassKey or u.subclassName or u.subclass
    if key and type(L) == "table" and type(L.translateUnitName) == "function" then
      local ok, n = pcall(L.translateUnitName, key, T.lang())
      if ok and type(n) == "string" and n ~= "" and n ~= "Unknown" and not n:find("^unit%.name%.") then
        return n
      end
    end
    return (u.sym and T.gameText("merc_contract_unit_" .. tostring(u.sym)))
      or (key and tostring(key)) or tostring(u.sym or "?")
  end

  local function signatureOf(u)
    local BF = package.loaded["src.game.battlefield"]
    if type(BF) ~= "table" or type(BF.signatureImprint) ~= "function" then return nil end
    local ok, r = pcall(BF.signatureImprint, u)
    local id = ok and (type(r) == "table" and r.id or r)
    return type(id) == "string" and id or nil
  end

  -- Units rows are wrapped so the shared name/icon/effect callbacks can
  -- tell them from imprints (they have no `id`, so the catalog ignores them).
  local function unitEntry(u) return { unit = u } end

  local function levelOf(e) return tonumber(e and e.level) or 1 end
  local function maxLevelOf(e)
    local d = e and definition(e.id)
    return d and #d.levels or math.max(1, tonumber(e and e.maxLevel) or 1)
  end

  --------------------------------------------------------------------------
  -- editing
  --------------------------------------------------------------------------
  local function indexOf(u, id)
    for i, inst in ipairs(imprintsOf(u)) do if inst.id == id then return i end end
    return nil
  end

  local function changed(u, what, ...)
    T.taint("imprint editor")
    local qm = package.loaded["src.game.quest"]
    if type(qm) == "table" and type(qm.onMaxImprintsChange) == "function" then pcall(qm.onMaxImprintsChange, u) end
    T.log("imprints: %s (%s): " .. what, unitName(u), tostring(u.grade), ...)
  end

  -- put catalog entry `c` into imprint row i of unit u (i = #imprints + 1 adds)
  local function putImprint(u, i, c)
    local list = imprintsOf(u)
    local old = list[i]
    if old and old.id == c.id then return end
    local j = indexOf(u, c.id)
    if j then
      tab.flash("%s", T.tr("imprints.has", imprintName(c.id), j))
      tab.select(2, j)
      return
    end
    if not old then
      if #list >= slotsOf(u) then tab.flash("%s", T.tr("imprints.full")); return end
      i = #list + 1
    end
    list[i] = newInst(c.def, old and math.min(levelOf(old), #c.def.levels) or 1)
    changed(u, "slot %d %s -> %s", i, old and tostring(old.id) or "empty", c.id)
    tab.select(2, i)
  end

  local function setLevel(ctx, i, level)
    local inst = imprintsOf(ctx.unit)[i]
    if not inst or levelOf(inst) == level then return end
    if setInstLevel(inst, level) then
      inst[MARK] = true
      changed(ctx.unit, "%s Lv %d", tostring(inst.id), level)
    end
  end

  local function removeImprint(ctx, i)
    local list = imprintsOf(ctx.unit)
    local inst = list[i]
    if not inst then return end
    table.remove(list, i)
    changed(ctx.unit, "removed %s", tostring(inst.id))
  end

  --------------------------------------------------------------------------
  -- leaderboard guard
  --------------------------------------------------------------------------
  local function guard()
    for _, e in ipairs(boardUnits()) do
      for _, inst in ipairs(type(e.unit.imprints) == "table" and e.unit.imprints or {}) do
        if type(inst) == "table" and inst[MARK] then T.taint("imprint editor"); return end
      end
    end
  end

  --------------------------------------------------------------------------
  -- panel tab
  --------------------------------------------------------------------------
  local function name(d)
    if d.unit then return unitName(d.unit) end
    return imprintName(d.id)
  end

  local function effect(d, level)
    if d.unit then
      local u, parts = d.unit, {}
      for _, inst in ipairs(imprintsOf(u)) do
        parts[#parts + 1] = string.format("%s %s", imprintName(inst.id), T.tr("level", levelOf(inst), maxLevelOf(inst)))
      end
      local txt = #parts > 0 and table.concat(parts, ", ") or T.tr("imprints.none")
      local sig = signatureOf(u)
      if sig then txt = txt .. "\n" .. T.tr("imprints.passes", imprintName(sig)) end
      return txt
    end
    return imprintDesc(d.id, level)
  end

  local function meta(d, level)
    if d.unit then
      local u = d.unit
      return T.tr("imprints.unit_meta", gradeLabel(u.grade), tostring(u.rank or 1), #imprintsOf(u), slotsOf(u))
    end
    local m = string.format("%s  %s", gradeLabel(d.rarity), T.tr("level", level, maxLevelOf(d)))
    local short = T.gameText("imprint.short." .. d.id)
    if short then m = m .. "   " .. picker.plainText(short) end
    return m
  end

  tab = picker.tab({
    id = "imprints", title = function() return T.tr("tab.imprints") end,
    context = runCtx,
    catalog = catalog,
    filters = filters,
    filterOf = function(d) return d.rarity end,
    name = name, effect = effect, meta = meta,
    icon = function(d) return d.unit and unitIcon(d.unit) or imprintIcon(d.id) end,
    color = function(d) return gradeColor(d.unit and d.unit.grade or d.rarity) end,
    help = function() return T.tr("imprints.help") end,
    sections = {
      {
        title = function(ctx) return string.format("%s  %d", T.tr("units"), #ctx.units) end,
        slots = function(ctx) return #ctx.units end,
        get = function(ctx, i) return ctx.units[i] and unitEntry(ctx.units[i].unit) or nil end,
        put = function(ctx, i, c)
          local e = ctx.units[i]
          if e then F.unit = e.unit; putImprint(e.unit, #imprintsOf(e.unit) + 1, c) end
        end,
        right = function(_, _, e) return string.format("%d/%d", #imprintsOf(e.unit), slotsOf(e.unit)) end,
      },
      {
        title = function(ctx)
          if not ctx.unit then return T.tr("tab.imprints") end
          return T.tr("imprints.list", ctx.n, #imprintsOf(ctx.unit), slotsOf(ctx.unit))
        end,
        slots = function(ctx) return ctx.unit and slotRows(ctx) or 0 end,
        selectable = function(ctx)
          return ctx.unit and math.min(#imprintsOf(ctx.unit) + 1, slotsOf(ctx.unit)) or 0
        end,
        get = function(ctx, i) return ctx.unit and imprintsOf(ctx.unit)[i] or nil end,
        put = function(ctx, i, c) if ctx.unit then putImprint(ctx.unit, i, c) end end,
        mark = "owned",
        right = function(_, _, e) return T.tr("level", levelOf(e), maxLevelOf(e)) end,
        emptyText = function(ctx, i)
          if i > slotsOf(ctx.unit) then return T.tr("imprints.locked") end
          return nil -- (empty)
        end,
        level = levelOf, maxLevel = maxLevelOf, setLevel = setLevel,
        remove = removeImprint,
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
