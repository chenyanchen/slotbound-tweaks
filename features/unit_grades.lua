-- Unit Grades: edit the odds of each grade for units spawned by winning lines
-- (F8 panel tab, built on weights.lua).
--
-- How the game rolls grades (v1.0.3):
--   battlefield.spawn() (the global `battlefield` object) reads
--   require("src.data.constants").unitGrades.probabilities fresh on every
--   spawn, passes it through require("src.game.luck").grade.boostedProbs
--   (the rare/legendary pity: returns a boosted copy, or nil for no boost),
--   then rolls along unitGrades.order (normal, advanced, rare, legendary,
--   prism at 1.0.3). The rolled grades should sum to 1; anything left over
--   falls back to normal. src/ui/upgrade.lua applyUpgradeEffects() rewrites
--   the table from the meta upgrades, so a rewrite we did not make becomes
--   the new default.
--
-- The grades listed are unitGrades.order and their names the game's
-- grade.label.<grade>, so grades the game adds later show up on their own.
--
-- While the odds differ from the game's, the pity boost is switched off so
-- the odds shown are the odds rolled. Stone packs, core effects (Joker Grin,
-- Golden Lever) and promotions have their own grade paths and are untouched.

return function(T)
  local F = {
    cfg = T.config.load("unit_grades", { enabled = true, weights = {} }),
    game = nil,     -- the game's own probabilities, as it wrote them
    defaults = nil, -- the same, normalized (what the white ticks show)
    written = nil,  -- what we last wrote, to notice the game rewriting it
    checkTimer = 0,
  }

  --------------------------------------------------------------------------
  -- game access
  --------------------------------------------------------------------------
  local function unitGrades()
    local C = package.loaded["src.data.constants"]
    local ug = type(C) == "table" and C.unitGrades
    if type(ug) == "table" and type(ug.probabilities) == "table" and type(ug.order) == "table" then return ug end
    return nil
  end

  -- the rolled grades, in the game's order
  local function grades()
    local ug = unitGrades()
    local out = {}
    for _, g in ipairs(ug and ug.order or {}) do
      if type(g) == "string" then out[#out + 1] = g end
    end
    return out
  end

  local function copy(src)
    local t = {}
    for _, g in ipairs(grades()) do t[g] = tonumber(src and src[g]) or 0 end
    return t
  end

  local function same(a, b)
    for _, g in ipairs(grades()) do
      if math.abs((tonumber(a and a[g]) or 0) - (tonumber(b and b[g]) or 0)) > 1e-9 then return false end
    end
    return true
  end

  local function normalized(w)
    local t, sum = copy(w), 0
    for _, g in ipairs(grades()) do sum = sum + t[g] end
    if sum <= 0 then return nil end
    for _, g in ipairs(grades()) do t[g] = t[g] / sum end
    return t
  end

  local function round2(x) return math.floor(x * 100 + 0.5) / 100 end

  local function save()
    local w = {}
    for k, v in pairs(F.cfg.weights) do
      if tonumber(v) then w[k] = round2(tonumber(v)) end
    end
    T.config.save("unit_grades", { enabled = F.cfg.enabled, weights = w })
  end

  local function isModified()
    if not (F.cfg.enabled and F.defaults) then return false end
    local want = normalized(F.cfg.weights)
    return want ~= nil and not same(want, F.defaults)
  end

  -- Switch the pity boost off while our odds are in effect.
  local function hookPity()
    local luck = package.loaded["src.game.luck"]
    local grade = type(luck) == "table" and luck.grade
    if type(grade) ~= "table" or type(grade.boostedProbs) ~= "function" then return end
    if grade.boostedProbs == F.pityHook then return end
    local orig = grade.boostedProbs
    F.pityHook = function(...)
      if isModified() then return nil end -- nil = no boost: the game rolls the base table
      return orig(...)
    end
    grade.boostedProbs = F.pityHook
    T.log("unit_grades: pity boost hooked")
  end

  local function apply(force)
    local ug = unitGrades()
    if not ug or #grades() == 0 then return end
    local probs = ug.probabilities
    hookPity()

    -- first look, or the game rewrote the table (meta upgrades): new defaults
    if not F.game or (F.written and not same(probs, F.written)) then
      F.game = copy(probs)
      F.defaults = normalized(F.game) or copy(F.game)
      local parts = {}
      for _, g in ipairs(grades()) do
        if tonumber(F.cfg.weights[g]) == nil or F.cfg.weights[g] < 0 then F.cfg.weights[g] = round2(F.defaults[g]) end
        parts[#parts + 1] = string.format("%s=%.3f", g, F.defaults[g])
      end
      T.log("unit_grades: game defaults %s", table.concat(parts, " "))
    end

    -- ours (normalized) while modified, otherwise exactly what the game wrote
    local want = isModified() and normalized(F.cfg.weights) or F.game
    if force or not same(probs, want) then
      for _, g in ipairs(grades()) do probs[g] = want[g] end -- in place: keeps `special` and any other keys
    end
    F.written = copy(probs)
    if isModified() then T.taint("unit grades") end
  end

  --------------------------------------------------------------------------
  -- panel tab (weights.lua)
  --------------------------------------------------------------------------
  local function gradeColor(g)
    local ug = unitGrades()
    local c = ug and type(ug.colors) == "table" and ug.colors[g]
    return type(c) == "table" and c or { 1, 1, 1 }
  end

  local function gradeLabel(g)
    return T.gameText("grade.label." .. g) or (g:sub(1, 1):upper() .. g:sub(2))
  end

  local function rows()
    local out = {}
    for _, g in ipairs(grades()) do
      out[#out + 1] = { key = g, label = gradeLabel(g), color = function() return gradeColor(g) end }
    end
    return out
  end

  local editor = T.weights.tab({
    id = "unit_grades", title = function() return T.tr("tab.unit_grades") end,
    rows = rows,
    cfg = F.cfg,
    defaults = function() return F.defaults end,
    save = save,
    apply = apply,
    note = function() return T.tr("unit_grades.note") end,
  })

  function F.update(dt)
    editor.update(dt)
    F.checkTimer = F.checkTimer - dt
    if F.checkTimer > 0 then return end
    F.checkTimer = 0.25
    apply(false)
  end

  F.isModified = isModified
  return F
end
