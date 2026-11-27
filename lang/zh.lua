-- 简体中文。术语沿用游戏中文版的说法（品质、符号、老虎机、刻印、核心……）。
-- 缺少的键会退回 lang/en.lua。
return {
  -- panel
  ["panel.hint"] = "Tab 切换   F8/Esc 关闭",
  ["panel.tainted"] = "已修改：重启游戏前不提交排行榜成绩。",
  ["panel.clean"] = "未修改：正常提交排行榜成绩。",

  -- shared
  ["on"] = "已启用",
  ["off"] = "未启用",
  ["level"] = "Lv %d/%d",
  ["lock.battle"] = "战斗中无法修改。",
  ["lock.spinning"] = "请等老虎机停下。",

  -- bar editor
  ["weights.loading"] = "等待游戏加载……",
  ["weights.help"] = "O 只要这一项   0 归零   R 重置   E 开关   白色刻度：游戏默认值",

  -- slots + catalog
  ["picker.no_run"] = "开始或继续一局后才能修改。",
  ["picker.empty"] = "（空）",
  ["picker.none"] = "（无）",
  ["picker.all"] = "全部",
  ["picker.hint"] = "金色角标：已拥有   绿点：正在提供",
  ["rarity.C"] = "普通",
  ["rarity.U"] = "高级",
  ["rarity.R"] = "稀有",
  ["rarity.L"] = "传说",
  ["icon.gold"] = "金币",
  ["icon.essence"] = "精华",
  ["icon.joker"] = "小丑",

  -- Symbol Weights
  ["tab.symbol_weights"] = "符号权重",

  -- Unit Grades
  ["tab.unit_grades"] = "单位品质",
  ["unit_grades.note"] = "与游戏概率不同时，保底关闭。",

  -- Items
  ["items.help"] = "先点栏位，再点物品   Del 删除",
  ["items.slots"] = "物品栏  %d/%d",
  ["items.in_slot"] = "%s 已在第 %d 栏。",
  ["items.full"] = "物品栏已满。",
  ["items.stage"] = "第 %d 关物品",
  ["items.sold"] = "已售",

  -- Cores
  ["cores.help"] = "先点栏位，再点核心   Del 移除",
  ["cores.selection"] = "核心选择",
  ["cores.manual"] = "手动使用",
  ["cores.consumable"] = "消耗品",
  ["cores.active_slot"] = "%s 已生效（第 %d 栏）。",
  ["cores.active"] = "%s 已生效。",
  ["cores.offered"] = "%s 已在选项中。",
  ["cores.full"] = "核心栏已满。",
  ["cores.add_failed"] = "无法加入 %s。",
  ["cores.remove_failed"] = "无法移除 %s。",

  -- Imprints
  ["tab.imprints"] = "刻印",
  ["imprints.help"] = "依次点单位、栏位、刻印   Del 移除",
  ["imprints.modal"] = "请先完成游戏的刻印选择。",
  ["imprints.list"] = "单位 %d 的刻印栏  %d/%d",
  ["imprints.locked"] = "（锁定）",
  ["imprints.has"] = "该单位已有 %s（第 %d 栏）。",
  ["imprints.full"] = "该单位的刻印栏已满。",
  ["imprints.none"] = "没有刻印。",
  ["imprints.passes"] = "被吸收时传出：%s",
  ["imprints.unit_meta"] = "%s  %s 星  刻印 %d/%d",
}
