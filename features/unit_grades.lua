-- Unit Grades: edit the odds of each grade for units spawned by winning lines
-- (F8 panel tab, built on weights.lua).
--
-- How the game rolls grades (v1.0.3):
--   src/game/battlefield.lua spawn() reads
--   require("src.data.constants").unitGrades.probabilities fresh on every
--   spawn, passes it through require("src.game.luck").grade.boostedProbs
--   (the rare/legendary pity: returns a boosted copy, or nil for no boost),
--   then rolls along unitGrades.order: normal, advanced, rare, legendary,
--   prism. The probabilities sum to 1; anything left over falls back to
--   normal. src/ui/upgrade.lua applyUpgradeEffects() rewrites the table from
--   the meta upgrades, so a rewrite we did not make becomes the new default.
--
-- While the odds differ from the game's, the pity boost is switched off so
-- the odds shown are the odds rolled. Stone packs, core effects (Joker Grin,
-- Golden Lever) and promotions have their own grade paths and are untouched.

return function(T)
  local GRADES = { "normal", "advanced", "rare", "legendary", "prism" }
  local LABELS = { normal = "Normal", advanced = "Advanced", rare = "Rare", legendary = "Legendary", prism = "Prism" }
  local FALLBACK_DEFAULTS = { normal = 0.83, advanced = 0.15, rare = 0.02, legendary = 0, prism = 0 }

  local F = {
    cfg = T.config.load("unit_grades", { enabled = true, weights = {} }),
    defaults = nil, -- the game's own probabilities (normalized), by grade
    written = nil,  -- what we last wrote, to notice the game rewriting it
    checkTimer = 0,
  }

  local function copy(src)
    local t = {}
    for _, g in ipairs(GRADES) do t[g] = tonumber(src and src[g]) or 0 end
    return t
  end

  local function same(a, b)
    for _, g in ipairs(GRADES) do
      if math.abs((tonumber(a and a[g]) or 0) - (tonumber(b and b[g]) or 0)) > 1e-9 then return false end
    end
    return true
  end

  local function normalized(w)
    local t, sum = copy(w), 0
    for _, g in ipairs(GRADES) do sum = sum + t[g] end
    if sum <= 0 then return nil end
    for _, g in ipairs(GRADES) do t[g] = t[g] / sum end
    return t
  end

  local function round2(x) return math.floor(x * 100 + 0.5) / 100 end

  local function save()
    local w = {}
    for _, g in ipairs(GRADES) do w[g] = round2(tonumber(F.cfg.weights[g]) or 0) end
    T.config.save("unit_grades", { enabled = F.cfg.enabled, weights = w })
  end

  local function isModified()
    if not (F.cfg.enabled and F.defaults) then return false end
    local want = normalized(F.cfg.weights)
    return want ~= nil and not same(want, F.defaults)
  end

  --------------------------------------------------------------------------
  -- game access
  --------------------------------------------------------------------------
  local function probabilities()
    local C = package.loaded["src.data.constants"]
    local ug = type(C) == "table" and C.unitGrades
    return type(ug) == "table" and type(ug.probabilities) == "table" and ug.probabilities or nil
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
    local probs = probabilities()
    if not probs then return end
    hookPity()

    -- first look, or the game rewrote the table (meta upgrades): new defaults
    if not F.defaults or (F.written and not same(probs, F.written)) then
      F.defaults = normalized(probs) or copy(FALLBACK_DEFAULTS)
      for _, g in ipairs(GRADES) do
        if tonumber(F.cfg.weights[g]) == nil or F.cfg.weights[g] < 0 then F.cfg.weights[g] = round2(F.defaults[g]) end
      end
      T.log("unit_grades: game defaults normal=%.3f advanced=%.3f rare=%.3f legendary=%.3f prism=%.3f",
        F.defaults.normal, F.defaults.advanced, F.defaults.rare, F.defaults.legendary, F.defaults.prism)
    end

    local want = isModified() and normalized(F.cfg.weights) or F.defaults
    if force or not same(probs, want) then
      for _, g in ipairs(GRADES) do probs[g] = want[g] end -- in place: keeps `special` and any other keys
    end
    F.written = copy(probs)
    if isModified() then T.taint("unit grades") end
  end

  --------------------------------------------------------------------------
  -- panel tab (weights.lua)
  --------------------------------------------------------------------------
  local function gradeColor(g)
    local C = package.loaded["src.data.constants"]
    local c = type(C) == "table" and type(C.unitGrades) == "table" and type(C.unitGrades.colors) == "table"
      and C.unitGrades.colors[g]
    return type(c) == "table" and c or { 1, 1, 1 }
  end

  local rows = {}
  for _, g in ipairs(GRADES) do rows[#rows + 1] = { key = g, label = LABELS[g], color = function() return gradeColor(g) end } end

  local editor = T.weights.tab({
    id = "unit_grades", title = "Unit Grades",
    intro = "Odds of each grade when a winning line spawns a unit.",
    rows = rows,
    cfg = F.cfg,
    defaults = function() return F.defaults end,
    save = save,
    apply = apply,
    note = "While these differ from the game's odds, the rare/legendary pity is off. "
      .. "Stone packs, cores and promotions still change grades their own way.",
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
