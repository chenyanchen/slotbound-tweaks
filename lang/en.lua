-- The tweaks' own UI text, English. Other languages (lang/<code>.lua, named
-- after the game's language codes) may leave keys out: missing keys fall
-- back to this file. Keep the %s / %d placeholders in the same order.
-- Words the game already translates (Items, Cores, Units, Shop)
-- come from the game; see GAME_WORDS in i18n.lua.
return {
  -- panel
  ["panel.hint"] = "Tab switch   F8/Esc close",
  ["panel.tainted"] = "Modified: leaderboard submissions off until the game restarts.",
  ["panel.clean"] = "Unmodified: leaderboard submissions on.",

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
  ["weights.help"] = "O only   0 zero   R reset   E on/off   White tick: game default",

  -- slots + catalog (Items, Cores, Imprints)
  ["picker.no_run"] = "Start or continue a run to edit.",
  ["picker.empty"] = "(empty)",
  ["picker.none"] = "(none)",
  ["picker.all"] = "All",
  ["picker.hint"] = "Gold corner: owned   Green dot: offered",
  ["rarity.C"] = "Common",
  ["rarity.U"] = "Uncommon",
  ["rarity.R"] = "Rare",
  ["rarity.L"] = "Legendary",
  ["icon.gold"] = "Gold",
  ["icon.essence"] = "Essence",
  ["icon.joker"] = "Joker",

  -- Symbol Weights
  ["tab.symbol_weights"] = "Symbol Weights",

  -- Unit Grades
  ["tab.unit_grades"] = "Unit Grades",
  ["unit_grades.note"] = "Pity is off while these differ from the game's odds.",

  -- Items
  ["items.help"] = "Click a slot, then an item   Del delete",
  ["items.slots"] = "Item slots  %d/%d",
  ["items.in_slot"] = "%s is already in slot %d.",
  ["items.full"] = "All item slots are full.",
  ["items.stage"] = "stage %d item",
  ["items.sold"] = "sold",

  -- Cores
  ["cores.help"] = "Click a slot, then a core   Del remove",
  ["cores.selection"] = "Core selection",
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
  ["imprints.help"] = "Click a unit, a slot, then an imprint   Del remove",
  ["imprints.modal"] = "Finish the game's imprint choice first.",
  ["imprints.list"] = "Imprints of unit %d  %d/%d",
  ["imprints.locked"] = "(locked)",
  ["imprints.has"] = "This unit already has %s (slot %d).",
  ["imprints.full"] = "All imprint slots of this unit are full.",
  ["imprints.none"] = "No imprints.",
  ["imprints.passes"] = "Passes on when absorbed: %s",
  ["imprints.unit_meta"] = "%s  rank %s  imprints %d/%d",
}
