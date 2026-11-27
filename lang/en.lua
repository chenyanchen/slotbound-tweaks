-- The tweaks' own UI text, English. Other languages (lang/<code>.lua, named
-- after the game's language codes) may leave keys out: missing keys fall
-- back to this file. Keep the %s / %d placeholders in the same order.
-- Words the game already translates (Items, Cores, Units, Shop)
-- come from the game; see GAME_WORDS in i18n.lua.
return {
  -- panel
  ["panel.hint"] = "Tab switch   F8/Esc close",
  ["panel.tainted"] = "Session modified: leaderboard submissions disabled until the game restarts.",
  ["panel.clean"] = "Nothing changed yet: leaderboard submissions unaffected.",

  -- shared
  ["items"] = "Items",
  ["cores"] = "Cores",
  ["units"] = "Units",
  ["shop"] = "Shop",
  ["on"] = "ON",
  ["off"] = "OFF",
  ["level"] = "Lv %d/%d",
  ["lock.battle"] = "Can't be changed during a battle.",
  ["lock.spinning"] = "Wait for the slot machine to stop.",

  -- bar editor (Symbol Weights, Unit Grades)
  ["weights.loading"] = "Waiting for the game to load...",
  ["weights.help1"] = "Up/Down select   Left/Right +-0.01 (Shift +-0.05, hold = fast)   O only   0 zero",
  ["weights.help2"] = "R reset to defaults   E toggle   (white tick = game default)",

  -- slots + catalog (Items, Cores, Imprints)
  ["picker.browse"] = "You can still browse the catalog.",
  ["picker.empty"] = "(empty)",
  ["picker.none"] = "(none)",
  ["picker.all"] = "All",
  ["picker.hint"] = "Select a slot on the left, then click an entry to put it there.\nGold corner = owned, green dot = offered.",
  ["rarity.C"] = "Common",
  ["rarity.U"] = "Uncommon",
  ["rarity.R"] = "Rare",
  ["rarity.L"] = "Legendary",
  ["icon.gold"] = "Gold",
  ["icon.essence"] = "Essence",
  ["icon.joker"] = "Joker",

  -- Symbol Weights
  ["tab.symbol_weights"] = "Symbol Weights",
  ["symbol_weights.intro"] = "Weights the slot machine uses for each symbol.",

  -- Unit Grades
  ["tab.unit_grades"] = "Unit Grades",
  ["unit_grades.intro"] = "Odds of each grade when a winning line spawns a unit.",
  ["unit_grades.note"] = "While these differ from the game's odds, the rare/legendary pity is off. "
    .. "Stone packs, cores and promotions still change grades their own way.",

  -- Items
  ["items.unavailable"] = "Start or continue a run to edit its items.",
  ["items.help"] = "Click a slot, then an item   Up/Down slot   Left/Right level   Del delete   "
    .. "Changes apply from the next battle",
  ["items.slots"] = "Item slots  %d/%d",
  ["items.empty_add"] = "(empty)  click an item to add",
  ["items.in_slot"] = "%s is already in slot %d.",
  ["items.full"] = "All item slots are full.",
  ["items.stage"] = "stage %d item",
  ["items.shop_none"] = "(nothing in the shop right now)",
  ["items.sold"] = "sold",

  -- Cores
  ["cores.unavailable"] = "Start or continue a run to edit its cores.",
  ["cores.help"] = "Click a slot, then a core   Up/Down slot   Del remove   New cores count from the current wave",
  ["cores.empty_add"] = "(empty)  click a core to add",
  ["cores.selection"] = "Core selection",
  ["cores.selection_none"] = "(shown while the game offers cores)",
  ["cores.manual"] = "manual use",
  ["cores.consumable"] = "consumable",
  ["cores.active_slot"] = "%s is already active (slot %d).",
  ["cores.active"] = "%s is already active.",
  ["cores.offered"] = "%s is already offered.",
  ["cores.full"] = "All core slots are full.",
  ["cores.add_failed"] = "Could not add %s.",
  ["cores.remove_failed"] = "Could not remove %s.",

  -- Imprints
  ["tab.imprints"] = "Imprints",
  ["imprints.unavailable"] = "Start or continue a run to edit its units' imprints.",
  ["imprints.help"] = "Click a unit, then an imprint slot, then an imprint   Left/Right level   Del remove",
  ["imprints.modal"] = "Finish the game's imprint choice first.",
  ["imprints.list"] = "Imprints of unit %d  %d/%d",
  ["imprints.no_units"] = "(no units on the board)",
  ["imprints.select_unit"] = "(select a unit)",
  ["imprints.empty_add"] = "(empty)  click an imprint to add",
  ["imprints.locked"] = "(locked)",
  ["imprints.has"] = "This unit already has %s (slot %d).",
  ["imprints.full"] = "All imprint slots of this unit are full.",
  ["imprints.none"] = "No imprints.",
  ["imprints.passes"] = "Passes on when absorbed: %s",
  ["imprints.unit_meta"] = "%s  rank %s  imprints %d/%d",
}
