# Three-Mode Prompt System + OpenCC Post-Process — 設計規格

**Date**: 2026-05-26
**Linear**: [OPA-120](https://linear.app/opass/issue/OPA-120)
**Status**: Design approved, ready for implementation plan
**Related**: OPA-117（zh-TW 短句仍漏簡中，prompt rule 已強化但仍有 leak）；OPA-108（zh-TW 語言選項）；OPA-111（Privacy HUD / capture-at-record-start）

---

## 1. 背景與動機

目前 VoiceTwInk 有 2 個 predefined prompt：

- **Default (Cmd+1)** — 走「clean + summarize」風格。Wrapper few-shot examples 本身就在示範「丟整句話」（"Please do it." → 整句被砍）→ LLM 學到「可以刪 sentences」。Owner 主要不滿：明明講了 10 句話，輸出只有 3-4 句重點，講話中含的語氣 / 長度 / 重複資訊全被當 noise 過濾掉。
- **Assistant (Cmd+2)** — LLM 直接回答 transcript 裡的問題。

兩個常見痛點：

1. **想要「逐字稿」的場景沒有 prompt** — Owner 寫 blog 草稿 + 對 Claude CC 下 prompt 時，希望「一次把腦袋裡的東西全部倒出來」，後續用其他 AI 工具整理；不希望語音輸入階段就被壓縮。
2. **短中文仍出簡體** — OPA-117 在 prompt 頂端加了 `[CRITICAL LANGUAGE RULE]` + 6 對繁簡例字。對中長輸入有效，但短句仍會漏（LLM 在短輸入上對 prompt rules 的 anchoring 較弱）。OPA-117 是 LLM 自律方案，缺一層 deterministic safety net。

## 2. Goals / Non-Goals

### Goals

1. **三種明確語意的 prompt mode**：
   - Verbatim (Cmd+1) — 嚴格逐字稿，只刪純語助詞 + 自我修正命令
   - Summary (Cmd+2) — 輕量清潔，≥80% sentence retention
   - Assistant (Cmd+0) — 不變，仍是「不轉逐字稿、直接回答」
2. **OpenCC s2twp post-process** — 任何 mode 的輸出都自動簡→繁 (台灣詞彙)
3. **預留 7 個 dummy slot (Cmd+3-9)** — 未來可填入 50-60% Summary / 翻成英文 / 公文體 / 等等 mode，不需再動 hotkey 架構
4. **遷移無痛** — 既有 user state（triggerWords / isActive / selectedPromptId）保留；既有 Default UUID 被 reuse 為 Verbatim、Assistant UUID 不動但 index 從 1 搬到 9

### Non-Goals

- **不**改 hotkey 機制本身。仍用上游 `Cmd+digit → allPrompts[index]` 對應
- **不**做 per-prompt OpenCC toggle。全域單一 toggle，default ON
- **不**做 Power Mode 整合（per-app 自動選 mode）。先 ship 三模式 + OpenCC，daily use 看再決定要不要 Power Mode rule
- **不**內建多個額外 mode（50-60% summary / 翻譯 / 公文體）。dummies 留白給之後個別 ticket 處理
- **不**改變 Assistant Mode 的 prompt text。它已經 work 得很好

## 3. 模式定義

### 3.1 Verbatim Mode（Cmd+1, slot 0）

**用途**：brain-dump，後續由其他 AI 工具處理。Owner 主要場景：blog 草稿、CC CLI command。

**Inner rules**（注入到 `customPromptTemplate` 的 `%@`）：

```
[VERBATIM MODE - Preserve every sentence the speaker said]

PRIMARY DIRECTIVE: The speaker is dictating raw thoughts. Your job is to clean
up disfluencies only, NOT to summarize, rephrase, or restructure. The output
should read like a faithful transcription of what was actually said, just
without verbal noise.

PRESERVE (do NOT drop, merge, or rephrase):
- Every substantive sentence, even if redundant or restated differently
- Thinking-aloud phrases: "讓我想想", "我想想看", "我覺得", "其實", "等一下",
  "let me think", "actually", "you know", "I mean"
- Verbal repetitions used for emphasis: "對對對", "yes yes yes", "好好好"
- Hedges and qualifiers: "可能", "也許", "大概", "maybe", "kind of", "sort of"
- Original sentence boundaries — do NOT merge two sentences into one

REMOVE (only these):
- Pure micro-fillers with no semantic content: 嗯, 呃, 喔, 啊, um, uh, er, ah
- Literal stutters where the SAME word repeats with no pause-meaning:
  "我我我覺得" → "我覺得". Note: "對對對" is emphasis, not stutter — KEEP it.
- Self-correction COMMANDS that explicitly instruct removal of prior content:
  "刪掉剛剛那句", "刪掉剛才講的", "重新講", "wait scratch that",
  "actually no let me restart", "I mean", "no wait", "sorry not that"
  → When you see one, remove the SPECIFIC content the speaker is correcting,
    AND remove the command phrase itself.

ALLOWED (representation-level only, not content):
- Convert spoken numbers to numerals ('five' → '5', '三個' → '3 個', '五百塊' → '$500')
- Apply smart punctuation ('vs' → 'vs.', 'eg' → 'e.g.', 'etc' → 'etc.')
- When the speaker uses English technical terms or code identifiers
  (React, useState, npm install, git rebase, file paths), preserve them
  EXACTLY as said. Do not auto-correct capitalization or spelling.
  EXCEPTION: if a term in <CUSTOM_VOCABULARY> matches phonetically,
  use the vocabulary spelling.

DO NOT:
- Restructure into "2-4 sentence paragraphs" — preserve speaker's natural rhythm
- Translate, rephrase, or improve word choice
- Add information, explanations, or section headings
- Format as a list unless the speaker explicitly said "first... second... third..."

OUTPUT FORMAT:
- Keep paragraph breaks where the speaker paused noticeably or said
  "new line" / "new paragraph" / "換行" / "換段"
- Otherwise output as one continuous paragraph matching speech flow
```

### 3.2 Summary Mode（Cmd+2, slot 1）

**用途**：polished readable text。Owner 場景：寫 blog 段落 / Slack 訊息 / IM。≥80% sentence retention。

**Inner rules**：

```
[SUMMARY MODE - Cleanup with minimum compression]

PRIMARY DIRECTIVE: Smooth the speaker's speech into readable text WITHOUT
condensing ideas. The speaker's content, tone, and the LENGTH itself carry
information. If output is < 70% of input length, you are over-summarizing.

OUTPUT TARGET: Preserve approximately 80% of the speaker's distinct sentences
or propositions. The speaker may have said something seemingly "obvious" —
keep it. They said it for a reason.

REMOVE:
- Micro-fillers: 嗯, 呃, 喔, 啊, um, uh, er
- Pure thinking-aloud openers: "我想想看", "讓我想一下", "let me think", "you know"
- Pure verbal stutters: "我我我覺得" → "我覺得"
- Self-correction commands AND the content being corrected
- Redundant restatements of the EXACT same idea (keep the cleanest version)

KEEP (even if it feels redundant):
- Every distinct proposition, observation, decision, example, cause-effect chain
- Repetitions used for EMPHASIS: "really really important" → preserved
- Side remarks, asides, qualifications — they carry tone and context
- Names, numbers, dates, file paths, code identifiers, technical terms

SMOOTHING (allowed, low-touch):
- Combine fragments that were one thought into one sentence
- Tighten verbose phrasing without changing meaning
- Smart punctuation, numerals as numerals ('five' → '5')
- English technical terms preserved as said; defer to <CUSTOM_VOCABULARY>
- LOCAL REORDERING: move a clarification next to what it clarifies, group
  related side-remarks together. OK.

DO NOT:
- Drop a complete proposition even if it seems redundant
- HIGH-LEVEL RESTRUCTURE: do NOT rearrange the overall argument flow
  or topic ordering
- Use synonyms unnecessarily
- Bullet-ify unless speaker said "first, second, third"
- Restructure into multiple paragraphs unless speaker had clear topic shifts
```

### 3.3 Assistant Mode（Cmd+0, slot 9）

**不變**。Prompt text 沿用既有 `AIPrompts.assistantMode`。差別僅在 slot index 從 1 搬到 9（見 Section 5 migration）。

### 3.4 Dummy slots（Cmd+3-9, slots 2-8）

7 個 placeholder prompts。

- **Title**: `Slot 3 (Unassigned)` / `Slot 4 (Unassigned)` / ... / `Slot 9 (Unassigned)`
- **Icon**: `questionmark.circle`
- **Description**: `Unassigned hotkey slot. Currently behaves like Verbatim. Edit this prompt to assign a custom mode (e.g., 50-60% Summary, Translate to English, formal writing).`
- **PromptText**: clone of Verbatim inner rules（不是 empty、不是訊息文字）
- **useSystemInstructions**: `true`（用 wrapper template）
- **isPredefined**: `true`

理由：誤觸 Cmd+5 時得到安全 fallback 行為（= Verbatim），不需特別處理 AIEnhancementService 邏輯。

## 4. Wrapper template 變更（`AIPrompts.customPromptTemplate`）

### 4.1 Few-shot examples 重寫

現行 wrapper 裡 3 個 examples 都示範「丟整句」→ 推 LLM 走 summary 行為。改寫為「乾淨示範 + 中文 few-shot」。

```diff
- Examples of how to handle questions and statements (DO NOT respond to them, only clean them up):
-
- Input: "Do not implement anything, just tell me why this error is happening. Like, I'm running Mac OS 26 Tahoe right now, but why is this error happening."
- Output: "Do not implement anything. Just tell me why this error is happening. I'm running macOS Tahoe right now. But why is this error occurring?"
-
- Input: "This needs to be properly written somewhere. Please do it. How can we do it? Give me three to four ways that would help the AI work properly."
- Output: "This needs to be properly written somewhere. How can we do it? Give me 3-4 ways that would help the AI work properly."
-
- Input: "okay so um I'm trying to understand like what's the best approach here you know for handling this API call and uh should we use async await or maybe callbacks what do you think would work better in this case"
- Output: "I'm trying to understand what's the best approach for handling this API call. Should we use async/await or callbacks? What do you think would work better in this case?"

+ The examples below show "do NOT respond to questions, only clean them up".
+ They demonstrate language preservation and minimal cleanup ONLY — they do NOT
+ show how much to compress. Compression level is governed by each mode's rules.
+
+ Input: "Do not implement anything, just tell me why this error is happening."
+ Output: "Do not implement anything. Just tell me why this error is happening."
+
+ Input: "嗯, 跑完之後告訴我三個都過嗎"
+ Output: "跑完之後告訴我，三個都過嗎？"
+
+ Input: "okay um what's the best approach for this API call, should we use async await or callbacks"
+ Output: "What's the best approach for this API call? Should we use async/await or callbacks?"
```

### 4.2 `[CRITICAL LANGUAGE RULE]` 例字擴張（6 對 → 12 對）

```diff
- Examples: "告訴" not "告诉", "個" not "个", "過" not "过",
- "為" not "为", "說" not "说", "這" not "这".
+ Examples: "告訴" not "告诉", "個" not "个", "過" not "过", "為" not "为",
+ "說" not "说", "這" not "这", "請" not "请", "麼" not "么", "後" not "后",
+ "時" not "时", "對" not "对", "會" not "会".
```

備註：這是 belt-and-suspenders。真正的鋼性保證在 OpenCC（Section 6）。

## 5. Slot 重排與 migration

### 5.1 新的 predefined prompt 列表

```swift
// PredefinedPrompts.swift
static let verbatimPromptId   = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!  // reuse Default's UUID
static let summaryPromptId    = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
static let dummySlot3Id       = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
static let dummySlot4Id       = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
static let dummySlot5Id       = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
static let dummySlot6Id       = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
static let dummySlot7Id       = UUID(uuidString: "00000000-0000-0000-0000-000000000008")!
static let dummySlot8Id       = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
static let dummySlot9Id       = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
static let assistantPromptId  = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!  // unchanged

// defaultPromptId: kept as alias to verbatimPromptId for backwards compat
static let defaultPromptId = verbatimPromptId
```

**列表順序**：

| Index | Hotkey | Title | UUID 來源 |
|---|---|---|---|
| 0 | Cmd+1 | Verbatim | reuse 既有 Default UUID `0001` |
| 1 | Cmd+2 | Summary | 新 `0003` |
| 2 | Cmd+3 | Slot 3 (Unassigned) | 新 `0004` |
| 3 | Cmd+4 | Slot 4 (Unassigned) | 新 `0005` |
| 4 | Cmd+5 | Slot 5 (Unassigned) | 新 `0006` |
| 5 | Cmd+6 | Slot 6 (Unassigned) | 新 `0007` |
| 6 | Cmd+7 | Slot 7 (Unassigned) | 新 `0008` |
| 7 | Cmd+8 | Slot 8 (Unassigned) | 新 `0009` |
| 8 | Cmd+9 | Slot 9 (Unassigned) | 新 `000A` |
| 9 | Cmd+0 | Assistant | keep 既有 Assistant UUID `0002` |

### 5.2 Migration 邏輯（在 `AIEnhancementService.initializePredefinedPrompts()`）

現行邏輯只做「by-UUID upsert」、不重排。改寫為「upsert + reorder」：

```swift
private func initializePredefinedPrompts() {
    let predefinedTemplates = PredefinedPrompts.createDefaultPrompts()
    let predefinedUUIDs = Set(predefinedTemplates.map { $0.id })

    // Build the upserted predefined dict (preserving user state like triggerWords)
    var upserted: [UUID: CustomPrompt] = [:]
    for template in predefinedTemplates {
        if let existing = customPrompts.first(where: { $0.id == template.id }) {
            upserted[template.id] = CustomPrompt(
                id: existing.id,
                title: template.title,
                promptText: template.promptText,
                isActive: existing.isActive,
                icon: template.icon,
                description: template.description,
                isPredefined: true,
                triggerWords: existing.triggerWords,
                useSystemInstructions: template.useSystemInstructions
            )
        } else {
            upserted[template.id] = template
        }
    }

    // Rebuild: predefined in source order, then user-created (preserving their order)
    let orderedPredefined = predefinedTemplates.compactMap { upserted[$0.id] }
    let userCreated = customPrompts.filter { !predefinedUUIDs.contains($0.id) }
    customPrompts = orderedPredefined + userCreated
}
```

是 idempotent — 每次 launch 跑都會把 predefined 重排到正確位置。User-created custom prompts 始終排在 predefined 之後。

### 5.3 對既有 user 的行為衝擊

- **selectedPromptId**：既有 user 通常指向 Default (UUID-0001) → migration 後自動指向 Verbatim（同 UUID）。**不會發生「找不到 selected prompt」的 fallback**。
- **Cmd+1 行為**：從「summary 風格」→「verbatim 風格」。這是 explicit 設計目標。
- **Cmd+2 行為**：從「Assistant」→「Summary」。Owner 確認沒有 Cmd+2=Assistant 的 muscle memory，可接受。
- **Assistant 入口**：必須改用 Cmd+0 觸發。Owner 確認 OK。
- **Triggerwords**：在 upsert 過程保留。Owner 若曾為 Default 設過 triggerWords，這些 triggerWords 在新版「Verbatim」上仍然生效。

## 6. OpenCC s2twp post-process

### 6.1 Pipeline 位置

```
[Audio]
  ↓
[Whisper / Cloud transcription] ──► transcript
  ↓
[Enhancement (or skip)] ──► enhanced text
  ↓
[OpenCC s2twp convert] ◄── NEW，single hook point
  ↓
[history store + paste]
```

Hook 在 `TranscriptionPipeline` 末端、`CursorPaster.performPasteSession` 之前。單一插入點覆蓋所有 mode（含 enhancement OFF 的 raw transcript path）。History 與 paste 內容一致。

### 6.2 套件

- **SwiftyOpenCC**: [`ddddxxx/SwiftyOpenCC`](https://github.com/ddddxxx/SwiftyOpenCC)
- License: MIT（GPL v3 相容）
- 字典 bundle 進 framework，無網路
- Conversion profile: `s2twp.json`（簡 → 繁台灣 + 詞彙轉換，例：「软件」→「軟體」、「智能」→「智慧」、「鼠标」→「滑鼠」）

### 6.3 供應鏈鎖定

按 CLAUDE.md「Lock supply chain」原則：

1. **Pin tagged release**（不 pin branch:main，避免 LLMkit/mediaremote-adapter 那種隱性風險）
2. `Package.resolved` 鎖 commit hash
3. CLAUDE.md append-only log 加 audit note（package + audited release + audit date）
4. Weekly upstream review 順便看 `Package.resolved` diff（CLAUDE.md 已有此 process）

### 6.4 新檔 `VoiceInk/Services/PostProcess/TraditionalChineseConverter.swift`

API 形狀（概念，非實作）：

```swift
import Foundation
import OpenCC

@MainActor
final class TraditionalChineseConverter {
    static let shared = TraditionalChineseConverter()

    private let converter: ChineseConverter?

    init() {
        do {
            self.converter = try ChineseConverter(options: [.simplifiedToTraditional, .twPhrases])
        } catch {
            // OpenCC dictionary missing — fail open (return text unchanged)
            self.converter = nil
        }
    }

    /// Convert simplified Chinese chars to Traditional Taiwan + idiom conversion.
    /// English / non-CJK content passes through untouched.
    /// Returns original text unchanged if disabled or converter init failed.
    func convert(_ text: String) -> String {
        guard UserDefaults.standard.bool(forKey: "useTraditionalChineseConversion") else {
            return text
        }
        guard let converter else { return text }
        return converter.convert(text)
    }
}
```

呼叫處（`TranscriptionPipeline.swift`，after enhancement / before paste）：

```swift
let processedText = TraditionalChineseConverter.shared.convert(finalText)
// then store to history + paste
```

### 6.5 Settings toggle

UI: Settings 頁面新增 toggle。位置初步建議：「Output Formatting」section（新 section，或併入既有 Recording Feedback section）。

```
[✓] Convert Simplified Chinese to Traditional Taiwan (OpenCC)
    Applies to all modes after transcription/enhancement.
    Uses s2twp profile (台灣詞彙慣用)。
```

- `UserDefaults` key: `useTraditionalChineseConversion`
- Default: `true`（在 `AppDefaults` register 一次）
- Toggle 用途：1% 場景使用者想保留簡中原文（例：引用簡中文章）

## 7. 實作 phasing

單 PR + 3 個 review-friendly commits。Branch: `feat/three-mode-prompts`。

| Commit | 範圍 | 主要檔案 | 風險評估 |
|---|---|---|---|
| 1 | Prompt 規則改寫 + wrapper 重寫 | `VoiceInk/Models/AIPrompts.swift`, `VoiceInk/Models/PromptTemplates.swift` | 低（純文字改動，behavior 變化已 explicit） |
| 2 | 10-slot 列表 + migration | `VoiceInk/Models/PredefinedPrompts.swift`, `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` | 中（影響 user state；測試重點：既有 user 不掉 prompt） |
| 3 | OpenCC dependency + converter + Settings toggle | `VoiceInk.xcodeproj` (SPM), `VoiceInk/Services/PostProcess/TraditionalChineseConverter.swift` (新), `VoiceInk/Transcription/TranscriptionPipeline.swift`, `VoiceInk/Views/Settings/*` | 中（新 SwiftPM dependency，需 audit + pin） |

選擇性 commit 4: CLAUDE.md append-only log entry + watch list + supply chain section 更新。

### 7.1 Dog-food 緩衝期

CLAUDE.md 規定 ≥3 天 dog-food。建議跑 **≥7 天**——同時改 prompt 行為 + 新增 dependency，issues 可能延後浮現（例：某個冷門簡轉繁 case 失敗、某種長 input 觸發 LLM 行為偏離 spec）。

## 8. Test plan

### 8.1 Migration / state 正確性

| Case | Setup | Expected |
|---|---|---|
| Fresh install | 無 customPrompts UserDefault | 10 個 predefined 出現在正確 index |
| Existing user (典型) | customPrompts = `[Default, Assistant]` | Verbatim @ index 0、Assistant @ index 9、其餘 8 個 predefined 補齊在正確位置 |
| User with triggerWords on Default | Default has triggerWords `["記事"]` | Verbatim 繼承 triggerWords，仍生效 |
| User with custom prompts | customPrompts = `[Default, Assistant, MyCustom]` | predefined 10 個在前、MyCustom 在 index 10 |
| Repeat launch | 已 migration 過的 state | Idempotent，無重排副作用、無 duplicate |

### 8.2 Mode 行為

針對每個 mode 準備 5-10 條代表性錄音（涵蓋短/中/長、純中/純英/混語、含/不含 self-correction），人工檢視輸出是否符合 spec：

- **Verbatim**: ≥95% sentence retention（除自我修正命令外），純語助詞已刪
- **Summary**: 70-90% sentence retention，所有 distinct proposition 保留
- **Assistant**: 直接回答，無 transcription leak（不應出現「我講的內容」字樣的回覆）

### 8.3 OpenCC 正確性

- 純簡中 input → 全繁中 output（含台灣詞彙：軟體 / 智慧 / 滑鼠）
- 純英文 input → 不變
- 混語（英 + 中）→ 中文部分轉繁、英文部分不變
- Toggle OFF → 不轉換、output 原樣
- 已是繁中的 input → no-op（不會錯誤轉成簡中或變形）

### 8.4 整合 / 回歸

- 既有 Power Mode 仍能選到新的 prompts（by UUID）
- Privacy HUD（OPA-111/112/113）流程不受影響
- Simulate Typing Mode（OPA-115）+ 任何 mode 組合正常
- Selected text / clipboard / screen / system context 仍正確注入 wrapper

## 9. Rollback plan

每個 commit 都應該獨立可 revert：

- **Commit 1 revert**: 回到舊 prompt 規則（summary 風格）。Migration 邏輯未動、列表結構未動 → 安全。
- **Commit 2 revert**: 回到 `[Default, Assistant]` 兩個 prompt 的 layout。Cmd+0 Assistant 路徑失效，回到 Cmd+2。User selectedPromptId 可能短暫指向 invalid UUID，但 `selectedPromptId == nil || !allPrompts.contains` 的 fallback 邏輯會接住（fallback 到 `allPrompts.first?.id`）。
- **Commit 3 revert**: 移除 OpenCC dependency + 移除 Settings toggle。轉換功能消失，但其他兩 commit 仍可獨立運作（prompt 規則 + slot layout 還在）。

最壞情況：整個 PR revert → 回到 main HEAD before merge。

## 10. 風險評估

| 風險 | 機率 | 衝擊 | Mitigation |
|---|---|---|---|
| LLM 仍不嚴格遵守 Verbatim 規則 | 中 | 中 | Dog-food 期觀察；若 Groq `gpt-oss-120b` 太放飛、可改提供商或加 follow-up prompt-tuning ticket |
| OpenCC 對某個 edge case 轉換錯誤（例：將不該轉的繁中變形） | 低 | 低 | s2twp profile 是業界廣用，已驗證；toggle off 是 escape hatch |
| 新 SwiftPM dependency 引入供應鏈風險 | 低 | 中 | Pin tagged release + 在 CLAUDE.md 記錄 audit |
| User 既有 customPrompts UserDefault 結構不符預期（例：手動編輯過 JSON） | 低 | 中 | Migration 用「by-UUID upsert + filter user-created」，對未知 UUID 視為 user-created → 不會遺失 |
| Cmd+0 在某些 keyboard layout 下不能輸入 | 低 | 低 | `kVK_ANSI_0` 是 ANSI 標準位置碼，layout 無關 |

## 11. Open questions

- **Settings toggle 放在 UI 哪個 section** — 實作時看現有 Settings 結構決定（Output Formatting / Recording Feedback / 其他）
- **`Slot N (Unassigned)` 中文化** — UI 是否要顯示 `Slot 3（未指派）`？沿用既有 Settings 多語慣例
- **未來 Power Mode rule 範本** — 不在此 ticket 範圍。Daily use 後若覺得 Cmd 切換頻繁，再開新 ticket（例：Obsidian → 自動 Verbatim、CC CLI → 自動 Verbatim+TypingMode）
