-- 한국어. 용어는 게임 한국어판을 따른다 (등급, 심볼, 슬롯머신, 각인, 코어 등).
-- 없는 키는 lang/en.lua 로 대체된다.
return {
  -- panel
  ["panel.hint"] = "Tab 전환   F8/Esc 닫기",
  ["panel.tainted"] = "이번 세션은 수정됨: 게임을 다시 시작할 때까지 순위표에 제출되지 않습니다.",
  ["panel.clean"] = "아직 변경 없음: 순위표 제출에 영향이 없습니다.",

  -- shared
  ["on"] = "켜짐",
  ["off"] = "꺼짐",
  ["level"] = "Lv %d/%d",
  ["lock.battle"] = "전투 중에는 바꿀 수 없습니다.",
  ["lock.spinning"] = "슬롯머신이 멈출 때까지 기다려 주세요.",

  -- bar editor
  ["weights.loading"] = "게임 로딩을 기다리는 중...",
  ["weights.help1"] = "↑/↓ 선택   ←/→ ±0.01 (Shift ±0.05, 누르고 있으면 빠르게)   O 이것만   0 0으로",
  ["weights.help2"] = "R 게임 기본값으로   E 켜기/끄기   (흰 눈금 = 게임 기본값)",

  -- slots + catalog
  ["picker.browse"] = "카탈로그는 둘러볼 수 있습니다.",
  ["picker.empty"] = "(빈 슬롯)",
  ["picker.none"] = "(없음)",
  ["picker.all"] = "전체",
  ["picker.hint"] = "왼쪽에서 슬롯을 고른 뒤, 오른쪽 항목을 클릭해 넣습니다.\n금색 모서리 = 보유 중, 초록 점 = 제시 중.",
  ["rarity.C"] = "일반",
  ["rarity.U"] = "고급",
  ["rarity.R"] = "희귀",
  ["rarity.L"] = "전설",
  ["icon.gold"] = "골드",
  ["icon.essence"] = "정수",
  ["icon.joker"] = "조커",

  -- Symbol Weights
  ["tab.symbol_weights"] = "심볼 가중치",
  ["symbol_weights.intro"] = "슬롯머신이 각 심볼을 뽑을 때 쓰는 가중치.",

  -- Unit Grades
  ["tab.unit_grades"] = "유닛 등급",
  ["unit_grades.intro"] = "당첨 라인으로 유닛이 나올 때 각 등급의 확률.",
  ["unit_grades.note"] = "게임 확률과 다를 때는 희귀/전설 천장이 꺼집니다. 스톤 팩, 코어, 전직은 평소대로 등급을 바꿉니다.",

  -- Items
  ["items.unavailable"] = "런을 시작하거나 이어 하면 아이템을 편집할 수 있습니다.",
  ["items.help"] = "슬롯, 아이템 순으로 클릭   ↑/↓ 슬롯   ←/→ 레벨   Del 삭제   다음 전투부터 적용",
  ["items.slots"] = "아이템 슬롯  %d/%d",
  ["items.empty_add"] = "(빈 슬롯)  아이템을 클릭해 추가",
  ["items.in_slot"] = "%s 은(는) 이미 %d번 슬롯에 있습니다.",
  ["items.full"] = "아이템 슬롯이 가득 찼습니다.",
  ["items.stage"] = "%d 스테이지 아이템",
  ["items.shop_none"] = "(지금 상점에 상품이 없습니다)",
  ["items.sold"] = "판매됨",

  -- Cores
  ["cores.unavailable"] = "런을 시작하거나 이어 하면 코어를 편집할 수 있습니다.",
  ["cores.help"] = "슬롯, 코어 순으로 클릭   ↑/↓ 슬롯   Del 제거   새 코어는 현재 웨이브부터",
  ["cores.empty_add"] = "(빈 슬롯)  코어를 클릭해 추가",
  ["cores.selection"] = "코어 선택",
  ["cores.selection_none"] = "(게임이 코어를 제시하는 동안 표시)",
  ["cores.manual"] = "수동 사용",
  ["cores.consumable"] = "소모품",
  ["cores.active_slot"] = "%s 은(는) 이미 활성화되어 있습니다 (%d번 슬롯).",
  ["cores.active"] = "%s 은(는) 이미 활성화되어 있습니다.",
  ["cores.offered"] = "%s 은(는) 이미 제시되어 있습니다.",
  ["cores.full"] = "코어 슬롯이 가득 찼습니다.",
  ["cores.add_failed"] = "%s 을(를) 추가하지 못했습니다.",
  ["cores.remove_failed"] = "%s 을(를) 제거하지 못했습니다.",

  -- Imprints
  ["tab.imprints"] = "각인",
  ["imprints.unavailable"] = "런을 시작하거나 이어 하면 유닛의 각인을 편집할 수 있습니다.",
  ["imprints.help"] = "유닛, 각인 칸, 각인 순으로 클릭   ←/→ 레벨   Del 제거",
  ["imprints.modal"] = "먼저 게임의 각인 선택을 마쳐 주세요.",
  ["imprints.list"] = "유닛 %d의 각인 칸  %d/%d",
  ["imprints.no_units"] = "(필드에 유닛이 없습니다)",
  ["imprints.select_unit"] = "(유닛을 선택하세요)",
  ["imprints.empty_add"] = "(빈 슬롯)  각인을 클릭해 추가",
  ["imprints.locked"] = "(잠김)",
  ["imprints.has"] = "이 유닛은 이미 %s 각인이 있습니다 (%d번 칸).",
  ["imprints.full"] = "이 유닛의 각인 칸이 가득 찼습니다.",
  ["imprints.none"] = "각인 없음.",
  ["imprints.passes"] = "흡수되면 전달하는 각인: %s",
  ["imprints.unit_meta"] = "%s  ★%s  각인 %d/%d",
}
