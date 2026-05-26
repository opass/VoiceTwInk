# Notch Mode Label + Privacy HUD Collapse Toggle — 設計規格

**Date**: 2026-05-26
**Linear**: [OPA-121](https://linear.app/opass/issue/OPA-121)
**Status**: Design approved, ready for implementation plan
**Related**: OPA-120（三模式 prompt 系統剛 ship、`Cmd+1/2/0` 切換 mode 是這個 feature 的主要使用場景）；OPA-111 / OPA-112 / OPA-113（Privacy HUD design + capture-at-record-start architecture，本 ticket 在 HUD 上加 collapse toggle）

---

## 1. 背景與動機

兩個獨立的 UX polish 項目，合在一個 spec 因為都是錄音器 UI 層的小改、可以同一週 ship、各自 commit。

1. **Notch / Mini Recorder 缺乏「當前 mode 是哪個」的明顯指示** — OPA-120 上線後共有 10 個 prompt slot（Verbatim / Summary / 7 dummies / Assistant），切換頻率變高。目前 `RecorderPromptButton` 只 render 一個 20pt icon，icon 之間視覺辨識度不足，owner 在快速切換 `Cmd+1/2/0` 時容易看不出當前 mode。
2. **Privacy HUD 過大時遮擋螢幕視線** — Owner 主要使用情境是「邊看螢幕邊錄音」，當 clipboard / screen context 內容長時 HUD 會占據可觀的螢幕區域。Owner 希望有一個 toggle 可以收起 HUD 內容、減少視覺干擾，但仍保留「現在有送 cloud / local」的視覺 anchor，避免完全隱形導致忘記 HUD 還在運作。

## 2. Goals / Non-Goals

### Goals

1. Notch + Mini recorder 的 `RecorderPromptButton` 顯示 `activePrompt.title`（持久 label，不是 toast）
2. Privacy HUD 新增 collapse / expand toggle，狀態存 UserDefault 跨 launch
3. Collapsed 狀態仍保留 destination 色（🟢 local / 🟡 cloud），避免完全失去 privacy 視覺 anchor
4. 不動 Privacy HUD 的核心 capture-at-record-start 邏輯（OPA-111/112/113 不受影響）
5. 不動任何 hotkey / popover / hover 既有行為

### Non-Goals

- **不**做 per-field collapse（owner 明確要單一 toggle）
- **不**做 collapse hotkey（YAGNI；按鈕已經夠近）
- **不**做 toast / 切換動畫（owner 選 A. 持久 label，不是 transient 提示）
- **不**新增 reset collapse 的機制（owner 接受「永久記憶 + 自己負責」的 tradeoff）
- **不**動 mini recorder 跟 notch 之間其他差異——只統一 prompt button 的 label 行為

## 3. Feature 1：Notch + Mini Recorder Mode Label

### 3.1 行為

`RecorderPromptButton`（位於 `VoiceInk/Views/Recorder/RecorderComponents.swift:145`）從「純 icon button」改成「icon + label 的 HStack」。Label 顯示 `enhancementService.activePrompt?.title ?? "Default"`。

Notch 跟 Mini Recorder 共用此 component（見 `NotchRecorderView.swift:124` + 對應的 MiniRecorderView），所以一改兩 recorder 都生效。

### 3.2 視覺

```
Before (current):
   ╭──────────────────────────────╮
   │ ✓  ✨   ●●●●●  ⏺ 0:08      │
   ╰──────────────────────────────╯

After:
   ╭──────────────────────────────────────╮
   │ ✓ Verbatim  ✨   ●●●●●  ⏺ 0:08    │
   ╰──────────────────────────────────────╯
```

### 3.3 寬度約束

- Label `Text` 使用 `.lineLimit(1)` + `.truncationMode(.tail)` + `.frame(maxWidth: 110)` 防止長 title 撐爆 notch
- 短名（Verbatim / Summary / Assistant）正常顯示
- 長名（Slot 5 (Unassigned) / 使用者自訂的 Translate to English 等）截斷顯示為 `Slot 5 (Unas…`
- Notch active 狀態下單側擴 90pt（`recordingSideExpansion`），扣掉 icon (20pt) + spacing (6pt) + outer padding 後 label 仍有 ~50-60pt 可用
- Mini recorder 橫向空間比 notch 更寬，同一個 cap 不會被擠壓

### 3.4 不受影響的部分

- Collapsed (idle) 狀態：notch 收回去 0 高度，整個 button 不 render，label 不存在問題
- Popover hover 行為：保留現有 `syncPopoverVisibility` 邏輯不動
- Hotkey 行為：`Cmd+1/2/...0` 仍走既有的 `MiniRecorderShortcutManager.handlePromptShortcut`
- Icon 部分：完全保留，新加的是 icon 「旁邊」的 label，不取代 icon

## 4. Feature 2：Privacy HUD Collapse Toggle

### 4.1 行為

新增 UserDefault `privacyHUDCollapsed` (Bool, default `false`)。`PrivacyHUDView`（位於 `VoiceInk/Views/Recorder/PrivacyHUDView.swift`）讀取此值決定 render 哪個 layout：

- **Expanded (default)**：完整 fields + destination footer + 新增 minimize 按鈕（chevron-up，右上角）
- **Collapsed**：縮成一個 ~30pt 圓形 pill、bg color = destination color（OPA-111/112/113 既有的 light green / light yellow）、點擊展開

Toggle 透過 minimize 按鈕（expanded 時）或點擊整個 pill（collapsed 時）切換。狀態寫入 UserDefault，跨 app launch 仍記得。

### 4.2 視覺

```
Expanded (current + new button top-right):
╭──────────────────────────────── ─ ╮
│ ✂️ Selected  hello                 │
│ 📋 Clipboard text...               │
│ 🖥 Screen  [Slack] window text     │
│ 📚 Vocab  Whisper, OpenCC          │
│ 🕐 Time  Mon 14:30                 │
│ ─────────────────                  │
│ → Sending to: Groq (cloud) 🟡      │
╰───────────────────────────────────╯

Collapsed:
╭──╮
│▼ │   <- 30pt 圓形，bg color = destination color
╰──╯
```

### 4.3 為什麼保留 destination 色

完全隱形 = 退化到上游「silent inclusion」狀態，違背 CLAUDE.md「Privacy is the bar」+ OPA-111/112/113 Privacy HUD 一系列 ticket 的設計初衷。Collapsed pill 保留一個 30pt 點 + destination 色是「最小但仍可辨認」的 anchor：

- 一片黃色 pill 在錄音時出現 → 你知道「這次有送 cloud」
- 一片綠色 pill → 「這次只去 local Whisper」
- Pill 不存在 → HUD 還沒啟動

### 4.4 切換來源

- **Expanded 時**：右上角 chevron-up 按鈕（24pt × 24pt overlay topTrailing），點下 → collapse
- **Collapsed 時**：點擊整個 pill → expand
- **不**新增全域 hotkey（YAGNI、按鈕已經夠近）

### 4.5 Window resize 機制

`PrivacyHUDWindowManager`（位於 `VoiceInk/Views/Recorder/PrivacyHUDWindowManager.swift`）目前只在 `currentPrivacyPayload` 變化時 re-measure + reposition。Collapse toggle 在 SwiftUI 內部切換時，外層 NSPanel 不會自動 resize。

**解法**：新增 NotificationCenter notification `.privacyHUDCollapseDidChange`，view 在 toggle 時 post，window manager observe 後觸發 `showOrUpdate(with: currentPrivacyPayload)` 重新 measure。

- Pros: 明確的 trigger 來源、不會被其他 UserDefault 變化打到
- Cons: 多一個 NotificationCenter event，但這是 Swift / AppKit 標準做法、可接受

Alternative 是 UserDefaults KVO，但更脆弱（其他地方寫同一個 key 也會觸發）。

### 4.6 不受影響的部分

- Privacy HUD 的 **capture-at-record-start architecture**（OPA-111）不動
- ESC 取消錄音邏輯（OPA-112）不動
- System context 注入（OPA-113）不動
- `activeRecordingStartID` lifecycle token（OPA-116 race fix）不動
- 完全沒改 `AIEnhancementService.currentPrivacyPayload` 或 `assemblePrivacyPayload` 路徑

## 5. 實作 phasing

單 PR + 2 commits review-friendly。Branch: `feat/notch-label-and-hud-collapse`。

| Commit | 範圍 | 主要檔案 | 風險 |
|---|---|---|---|
| 1 | Notch + Mini mode label | `VoiceInk/Views/Recorder/RecorderComponents.swift` (RecorderPromptButton.body) | 低（純視覺、無 hotkey / popover 變更） |
| 2 | Privacy HUD collapse toggle | `VoiceInk/Views/Recorder/PrivacyHUDView.swift`, `VoiceInk/AppDefaults.swift`, `VoiceInk/Views/Recorder/PrivacyHUDWindowManager.swift` | 中（window resize 重算 + NotificationCenter observer） |

不需 dog-food 緩衝期——純視覺改、無新 dependency、無 privacy 行為改變。Smoke pass 就可 merge。

## 6. Test plan

**No unit tests** — established codebase pattern（同 OPA-115 / OPA-120）。Verification via `make local` + manual smoke。

### 6.1 Feature 1 smoke

- `make dev` 後，notch 啟動錄音，看到 prompt icon 旁邊有 label "Verbatim"
- 按 `Cmd+2` 切到 Summary，notch label 立即更新為 "Summary"
- 按 `Cmd+0` 切到 Assistant，label 變 "Assistant"
- 按 `Cmd+5` 切到 Slot 5 (Unassigned)，label 顯示截斷後的字串 `Slot 5 (Unas…` 或類似
- 切到 Mini Recorder（Settings → Interface → Recorder Style → Mini），同樣行為
- 切換到不需要 enhancement 的狀態（disable enhancement），button 仍 render 但 label 為 "Default" 或 fallback

### 6.2 Feature 2 smoke

- 啟動錄音，Privacy HUD 出現、顯示完整 fields
- 點右上角 chevron-up，HUD 收成圓形 pill，bg 色保留（cloud → 黃、local → 綠）
- 點 pill，HUD 重新展開
- 完全結束錄音，下次再錄，HUD 應該還在 collapsed 狀態（UserDefault 持續）
- 完全 quit + relaunch app，下次錄音 HUD 仍 collapsed
- 手動展開後 quit + relaunch，下次 HUD 應 expanded（雙向 persist 都驗證）
- Collapse 後切換 Power Mode 或切換 prompt → destination 變化 → pill 顏色應該跟著變（綠 ↔ 黃）

### 6.3 整合 / 回歸

- ESC 取消錄音功能不受影響（OPA-112/OPA-119）
- Simulate Typing Mode 仍正常（OPA-115）
- OpenCC 轉換仍跑（OPA-120）
- 切換 Cmd+1/2/0 + collapse toggle 互動下，HUD 跟 recorder label 都正確刷新

## 7. Rollback plan

每個 commit 獨立可 revert：

- **Commit 1 revert**：`RecorderPromptButton` 回到純 icon。Notch + Mini 都恢復原樣，無 state loss。
- **Commit 2 revert**：移除 collapse toggle + UserDefault 註冊 + NotificationCenter observer。Privacy HUD 回到 always-expanded 行為。既有 UserDefault `privacyHUDCollapsed` 若曾被寫為 `true`、revert 後變成 unread garbage——無害。

最壞情況：整個 PR revert → 回到 main HEAD (OPA-120 之後)。

## 8. 風險評估

| 風險 | 機率 | 衝擊 | Mitigation |
|---|---|---|---|
| 長 title 截斷視覺感差 | 中 | 低 | maxWidth 110pt + tail truncation。Owner customize dummies 後 title 會變短，問題自然消失。 |
| Window resize 後 panel 位置跳動 | 中 | 中 | NotificationCenter trigger + `PrivacyHUDPositioner.calculateFrame` 重新計算。已是現成路徑。 |
| User 忘記 HUD collapsed，誤以為沒在送 sensitive context | 低 | 中 | Pill 保留 destination 色作為視覺 anchor。Owner 明確接受此 tradeoff。 |
| Mini recorder layout 因 label 變寬而破版 | 低 | 中 | Mini 橫向空間比 notch 更寬；smoke test 6.1 涵蓋此 case。 |

## 9. Open questions

- **Label 字型 size**：System default 11pt 應該對齊 notch 既有字級。實作時 visually inspect、必要時微調到 10pt。
- **Minimize button icon 形狀**：`chevron.up` vs `minus` vs `chevron.compact.up`——實作時挑視覺最 clean 的、不在 spec 預設定。
- **Collapsed pill 點擊區域**：整個 30pt 圓盤都可點，還是只有中央 icon 區可點？實作時用整個 button frame 確保 touch target 足夠大。
