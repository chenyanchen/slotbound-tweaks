-- 简体中文。术语沿用游戏中文版的说法（品质、符号、老虎机、刻印、核心……）。
-- 缺少的键会退回 lang/en.lua。
return {
  -- panel
  ["panel.hint"] = "Tab 切换   F8/Esc 关闭",
  ["panel.tainted"] = "本次游戏已被修改：重启游戏前不会提交排行榜成绩。",
  ["panel.clean"] = "尚未修改：排行榜提交不受影响。",

  -- shared
  ["on"] = "已启用",
  ["off"] = "未启用",
  ["level"] = "Lv %d/%d",
  ["lock.battle"] = "战斗中无法修改。",
  ["lock.spinning"] = "请等老虎机停下。",

  -- bar editor
  ["weights.loading"] = "等待游戏加载……",
  ["weights.help1"] = "↑/↓ 选择   ←/→ ±0.01（Shift ±0.05，按住加速）   O 只要这一项   0 归零",
  ["weights.help2"] = "R 恢复游戏默认   E 开/关   （白色刻度 = 游戏默认值）",

  -- slots + catalog
  ["picker.browse"] = "仍可浏览右侧目录。",
  ["picker.empty"] = "（空）",
  ["picker.none"] = "（无）",
  ["picker.all"] = "全部",
  ["picker.hint"] = "先在左侧选一个栏位，再点右侧条目放进去。\n金色角标 = 已拥有，绿点 = 正在提供。",
  ["rarity.C"] = "普通",
  ["rarity.U"] = "高级",
  ["rarity.R"] = "稀有",
  ["rarity.L"] = "传说",
  ["icon.gold"] = "金币",
  ["icon.essence"] = "精华",
  ["icon.joker"] = "小丑",

  -- Symbol Weights
  ["tab.symbol_weights"] = "符号权重",
  ["symbol_weights.intro"] = "老虎机抽取每种符号所用的权重。",

  -- Unit Grades
  ["tab.unit_grades"] = "单位品质",
  ["unit_grades.intro"] = "中奖连线召唤单位时，各品质出现的概率。",
  ["unit_grades.note"] = "与游戏概率不同时，稀有/传说保底会关闭。石头包、核心和转职仍按各自的方式改变品质。",

  -- Items
  ["items.unavailable"] = "开始或继续一局后才能修改物品。",
  ["items.help"] = "先点栏位，再点物品   ↑/↓ 栏位   ←/→ 等级   Del 删除   下一场战斗起生效",
  ["items.slots"] = "物品栏  %d/%d",
  ["items.empty_add"] = "（空）  点一个物品放入",
  ["items.in_slot"] = "%s 已在第 %d 栏。",
  ["items.full"] = "物品栏已满。",
  ["items.stage"] = "第 %d 关物品",
  ["items.shop_none"] = "（商店当前没有商品）",
  ["items.sold"] = "已售",

  -- Cores
  ["cores.unavailable"] = "开始或继续一局后才能修改核心。",
  ["cores.help"] = "先点栏位，再点核心   ↑/↓ 栏位   Del 移除   新核心从当前波次起算",
  ["cores.empty_add"] = "（空）  点一个核心加入",
  ["cores.selection"] = "核心选择",
  ["cores.selection_none"] = "（游戏提供核心时显示）",
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
  ["imprints.unavailable"] = "开始或继续一局后才能修改单位的刻印。",
  ["imprints.help"] = "先点单位，再点刻印栏，再点刻印   ←/→ 等级   Del 移除",
  ["imprints.modal"] = "请先完成游戏的刻印选择。",
  ["imprints.list"] = "单位 %d 的刻印栏  %d/%d",
  ["imprints.no_units"] = "（场上没有单位）",
  ["imprints.select_unit"] = "（请选择单位）",
  ["imprints.empty_add"] = "（空）  点一个刻印放入",
  ["imprints.locked"] = "（锁定）",
  ["imprints.has"] = "该单位已有 %s（第 %d 栏）。",
  ["imprints.full"] = "该单位的刻印栏已满。",
  ["imprints.none"] = "没有刻印。",
  ["imprints.passes"] = "被吸收时传出：%s",
  ["imprints.unit_meta"] = "%s  %s 星  刻印 %d/%d",
}
