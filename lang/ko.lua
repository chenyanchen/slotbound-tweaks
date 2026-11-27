-- 한국어. 용어는 게임 한국어판을 따른다 (등급, 심볼, 슬롯머신, 각인, 코어 등).
-- 없는 키는 lang/en.lua 로 대체된다.
return {
  -- panel
  ["panel.hint"] = "Tab 전환   F8/Esc 닫기",
  ["panel.tainted"] = "수정됨: 게임을 다시 시작할 때까지 순위표에 제출되지 않습니다.",
  ["panel.clean"] = "수정 안 됨: 순위표에 제출됩니다.",

  -- shared
  ["on"] = "켜짐",
  ["off"] = "꺼짐",
  ["level"] = "Lv %d/%d",
  ["lock.battle"] = "전투 중에는 바꿀 수 없습니다.",
  ["lock.spinning"] = "슬롯머신이 멈출 때까지 기다려 주세요.",

  -- bar editor
  ["weights.loading"] = "게임 로딩을 기다리는 중...",
  ["weights.help"] = "O 이것만   0 0으로   R 초기화   E 켜기/끄기   흰 눈금: 게임 기본값",

  -- slots + catalog
  ["picker.no_run"] = "런을 시작하거나 이어 하면 편집할 수 있습니다.",
  ["picker.empty"] = "(빈 슬롯)",
  ["picker.none"] = "(없음)",
  ["picker.all"] = "전체",
  ["picker.hint"] = "금색 모서리: 보유 중   초록 점: 제시 중",
  ["rarity.C"] = "일반",
  ["rarity.U"] = "고급",
  ["rarity.R"] = "희귀",
  ["rarity.L"] = "전설",
  ["icon.gold"] = "골드",
  ["icon.essence"] = "정수",
  ["icon.joker"] = "조커",

  -- Symbol Weights
  ["tab.symbol_weights"] = "심볼 가중치",

  -- Unit Grades
  ["tab.unit_grades"] = "유닛 등급",
  ["unit_grades.note"] = "게임 확률과 다를 때는 천장이 꺼집니다.",

  -- Items
  ["items.help"] = "슬롯, 아이템 순으로 클릭   Del 삭제",
  ["items.slots"] = "아이템 슬롯  %d/%d",
  ["items.in_slot"] = "%s 은(는) 이미 %d번 슬롯에 있습니다.",
  ["items.full"] = "아이템 슬롯이 가득 찼습니다.",
  ["items.stage"] = "%d 스테이지 아이템",
  ["items.sold"] = "판매됨",

  -- Cores
  ["cores.help"] = "슬롯, 코어 순으로 클릭   Del 제거",
  ["cores.selection"] = "코어 선택",
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
  ["imprints.help"] = "유닛, 슬롯, 각인 순으로 클릭   Del 제거",
  ["imprints.modal"] = "먼저 게임의 각인 선택을 마쳐 주세요.",
  ["imprints.list"] = "유닛 %d의 각인 칸  %d/%d",
  ["imprints.locked"] = "(잠김)",
  ["imprints.has"] = "이 유닛은 이미 %s 각인이 있습니다 (%d번 칸).",
  ["imprints.full"] = "이 유닛의 각인 칸이 가득 찼습니다.",
  ["imprints.none"] = "각인 없음.",
  ["imprints.passes"] = "흡수되면 전달하는 각인: %s",
  ["imprints.unit_meta"] = "%s  ★%s  각인 %d/%d",
}
