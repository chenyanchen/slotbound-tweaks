-- 日本語。用語はゲームの日本語版に合わせる（レア度、シンボル、スロットマシン、刻印、コア……）。
-- 足りないキーは lang/en.lua にフォールバックする。
return {
  -- panel
  ["panel.hint"] = "Tab 切り替え   F8/Esc 閉じる",
  ["panel.tainted"] = "変更済み：再起動するまでランキングに送信されません。",
  ["panel.clean"] = "未変更：ランキングに送信されます。",

  -- shared
  ["on"] = "オン",
  ["off"] = "オフ",
  ["level"] = "Lv %d/%d",
  ["lock.battle"] = "戦闘中は変更できません。",
  ["lock.spinning"] = "スロットマシンが止まるまでお待ちください。",

  -- bar editor
  ["weights.loading"] = "ゲームの読み込みを待っています…",
  ["weights.help"] = "O これだけ   0 ゼロ   R リセット   E オン/オフ   白い目盛り：ゲームの初期値",

  -- slots + catalog
  ["picker.no_run"] = "ランを開始または再開すると編集できます。",
  ["picker.empty"] = "（空き）",
  ["picker.none"] = "（なし）",
  ["picker.all"] = "すべて",
  ["picker.hint"] = "金の角：所持中   緑の点：提示中",
  ["rarity.C"] = "ノーマル",
  ["rarity.U"] = "上級",
  ["rarity.R"] = "レア",
  ["rarity.L"] = "伝説",
  ["icon.gold"] = "ゴールド",
  ["icon.essence"] = "精髄",
  ["icon.joker"] = "ジョーカー",

  -- Symbol Weights
  ["tab.symbol_weights"] = "シンボルの重み",

  -- Unit Grades
  ["tab.unit_grades"] = "ユニットのレア度",
  ["unit_grades.note"] = "ゲームの確率と異なる間は天井が無効になります。",

  -- Items
  ["items.help"] = "枠、アイテムの順にクリック   Del 削除",
  ["items.slots"] = "アイテム枠  %d/%d",
  ["items.in_slot"] = "%s は既に %d 番目の枠にあります。",
  ["items.full"] = "アイテム枠がいっぱいです。",
  ["items.stage"] = "ステージ %d のアイテム",
  ["items.sold"] = "売り切れ",

  -- Cores
  ["cores.help"] = "枠、コアの順にクリック   Del 外す",
  ["cores.selection"] = "コア選択",
  ["cores.manual"] = "手動使用",
  ["cores.consumable"] = "消耗品",
  ["cores.active_slot"] = "%s は既に有効です（%d 番目の枠）。",
  ["cores.active"] = "%s は既に有効です。",
  ["cores.offered"] = "%s は既に提示されています。",
  ["cores.full"] = "コア枠がいっぱいです。",
  ["cores.add_failed"] = "%s を追加できませんでした。",
  ["cores.remove_failed"] = "%s を外せませんでした。",

  -- Imprints
  ["tab.imprints"] = "刻印",
  ["imprints.help"] = "ユニット、枠、刻印の順にクリック   Del 外す",
  ["imprints.modal"] = "先にゲームの刻印選択を済ませてください。",
  ["imprints.list"] = "ユニット %d の刻印枠  %d/%d",
  ["imprints.locked"] = "（ロック）",
  ["imprints.has"] = "このユニットは既に %s を持っています（%d 番目の枠）。",
  ["imprints.full"] = "このユニットの刻印枠がいっぱいです。",
  ["imprints.none"] = "刻印なし。",
  ["imprints.passes"] = "吸収されると渡す刻印：%s",
  ["imprints.unit_meta"] = "%s  ★%s  刻印 %d/%d",
}
