-- 日本語。用語はゲームの日本語版に合わせる（レア度、シンボル、スロットマシン、刻印、コア……）。
-- 足りないキーは lang/en.lua にフォールバックする。
return {
  -- panel
  ["panel.hint"] = "Tab 切り替え   F8/Esc 閉じる",
  ["panel.tainted"] = "このセッションは変更済み：ゲームを再起動するまでランキングに送信されません。",
  ["panel.clean"] = "まだ変更なし：ランキング送信に影響はありません。",

  -- shared
  ["on"] = "オン",
  ["off"] = "オフ",
  ["level"] = "Lv %d/%d",
  ["lock.battle"] = "戦闘中は変更できません。",
  ["lock.spinning"] = "スロットマシンが止まるまでお待ちください。",

  -- bar editor
  ["weights.loading"] = "ゲームの読み込みを待っています…",
  ["weights.help1"] = "↑/↓ 選択   ←/→ ±0.01（Shift ±0.05、長押しで加速）   O これだけ   0 ゼロ",
  ["weights.help2"] = "R ゲームの初期値に戻す   E オン/オフ   （白い目盛り = ゲームの初期値）",

  -- slots + catalog
  ["picker.browse"] = "カタログは閲覧できます。",
  ["picker.empty"] = "（空き）",
  ["picker.none"] = "（なし）",
  ["picker.all"] = "すべて",
  ["picker.hint"] = "左の枠を選んでから、右の項目をクリックして入れます。\n金の角 = 所持中、緑の点 = 提示中。",
  ["rarity.C"] = "ノーマル",
  ["rarity.U"] = "上級",
  ["rarity.R"] = "レア",
  ["rarity.L"] = "伝説",
  ["icon.gold"] = "ゴールド",
  ["icon.essence"] = "精髄",
  ["icon.joker"] = "ジョーカー",

  -- Symbol Weights
  ["tab.symbol_weights"] = "シンボルの重み",
  ["symbol_weights.intro"] = "スロットマシンが各シンボルを引くときの重み。",

  -- Unit Grades
  ["tab.unit_grades"] = "ユニットのレア度",
  ["unit_grades.intro"] = "当たりラインでユニットが出るときの各レア度の確率。",
  ["unit_grades.note"] = "ゲームの確率と異なる間は、レア/伝説の天井が無効になります。ストーンパック、コア、転職は通常どおりレア度を変えます。",

  -- Items
  ["items.unavailable"] = "ランを開始または再開するとアイテムを編集できます。",
  ["items.help"] = "枠、アイテムの順にクリック   ↑/↓ 枠   ←/→ レベル   Del 削除   次の戦闘から反映",
  ["items.slots"] = "アイテム枠  %d/%d",
  ["items.empty_add"] = "（空き）  アイテムをクリックして追加",
  ["items.in_slot"] = "%s は既に %d 番目の枠にあります。",
  ["items.full"] = "アイテム枠がいっぱいです。",
  ["items.stage"] = "ステージ %d のアイテム",
  ["items.shop_none"] = "（ショップに商品がありません）",
  ["items.sold"] = "売り切れ",

  -- Cores
  ["cores.unavailable"] = "ランを開始または再開するとコアを編集できます。",
  ["cores.help"] = "枠、コアの順にクリック   ↑/↓ 枠   Del 外す   新しいコアは現在のウェーブから",
  ["cores.empty_add"] = "（空き）  コアをクリックして追加",
  ["cores.selection"] = "コア選択",
  ["cores.selection_none"] = "（ゲームがコアを提示している間に表示）",
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
  ["imprints.unavailable"] = "ランを開始または再開するとユニットの刻印を編集できます。",
  ["imprints.help"] = "ユニット、刻印枠、刻印の順にクリック   ←/→ レベル   Del 外す",
  ["imprints.modal"] = "先にゲームの刻印選択を済ませてください。",
  ["imprints.list"] = "ユニット %d の刻印枠  %d/%d",
  ["imprints.no_units"] = "（盤面にユニットがいません）",
  ["imprints.select_unit"] = "（ユニットを選択）",
  ["imprints.empty_add"] = "（空き）  刻印をクリックして追加",
  ["imprints.locked"] = "（ロック）",
  ["imprints.has"] = "このユニットは既に %s を持っています（%d 番目の枠）。",
  ["imprints.full"] = "このユニットの刻印枠がいっぱいです。",
  ["imprints.none"] = "刻印なし。",
  ["imprints.passes"] = "吸収されると渡す刻印：%s",
  ["imprints.unit_meta"] = "%s  ★%s  刻印 %d/%d",
}
