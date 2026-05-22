# Privacy HUD — 設計規格

**Date**: 2026-05-22  
**Linear**: OPA-111 (implementation) / OPA-112 (this design)  
**Status**: Design approved, ready for implementation plan  
**Related**: OPA-107 (data-egress audit), OPA-113 (system context), OPA-114 (Action Mode)

---

## 1. 背景與動機

VoiceTwInk 是 VoiceInk 的個人 fork，定位於「隱私可審計」的本地 daily-driver 語音輸入。OPA-107 的資料外送審計顯示：當 AI Enhancement 啟用時，每次 LLM 請求會帶上 transcript 之外、使用者不一定意識到的多個 context 欄位 ——

- **選取文字**（透過 macOS Accessibility 讀取，若 AX 權限已給則「無 toggle、無預覽、無確認」自動夾帶）
- **剪貼簿內容**（global toggle 開啟時夾帶，但讀取時機不透明、且 cache 不會自動清）
- **Screen Context**（截圖 → Vision OCR → 純文字夾帶，原圖不離機，但 OCR 後的文字可能含敏感資訊）
- **Custom Vocabulary**（個人字典，目前無 toggle，有資料就送）
- **System context**（time / timezone / locale；OPA-113 將補上）

`AIEnhancementService.getSystemMessage()` (line 145-202) 組裝 system prompt 時把所有非空欄位以 `<TAG>` 包裝拼進去；使用者在 UI 上看不到「這次送了什麼」。

對隱私敏感的使用者而言，這是高風險：剪貼簿可能含 API key、選取文字可能是密碼、Screen OCR 可能擷取到他人通訊內容，全部「無感」地走進雲端 LLM。

Privacy HUD 的目標是 **讓每次 LLM 請求的完整 payload 在送出前可預覽、可中止**。

---

## 2. Goals / Non-Goals

### Goals

1. **可見**：每次 enhancement 觸發時，HUD 即時顯示將送 LLM 的所有 context 欄位
2. **可中止**：使用者在錄音中可隨時 ESC 取消，已捕獲的 context 不會外送
3. **可信**：HUD 顯示什麼，送 LLM 就是什麼（WYSIWYG，single source of truth）
4. **可控**：補完 silent 欄位的 global toggle（選取文字、個人字典）
5. **可區分**：雲端 LLM vs 本地 LLM 視覺上明確區別
6. **可審計**：HUD 失靈不破壞 enhance pipeline；fallback 回上游行為

### Non-Goals

- **自動遮蔽 / scrubbing 敏感資料**（roadmap #4，獨立 issue）
- **逐欄位偵測 API key / SSN / PII**（Q6 決定 raw display 即可）
- **Per-prompt context defaults**（Q4 決定 YAGNI，僅 global toggle）
- **解決 Screen OCR 時機問題**（沿用上游既有行為：未及時 = omit）
- **改寫 enhance() 的網路層 / 重試邏輯**
- **Action Mode 的 tool call payload 顯示**（OPA-114 後續再處理）

---

## 3. 已 align 的設計決定

| ID | 問題 | 決定 |
|---|---|---|
| Q1 | HUD 顯示觸發條件 | **AI Enhancement 啟用時一律顯示**（不論 context 是否為空，仍以一行「Only transcript will be sent」呈現） |
| Q2 | 錄音中可即時 toggle 欄位嗎 | **不能 — HUD 錄音中純展示**。要 toggle 預設靠 global setting |
| Q3 | 取消機制 | **ESC anytime during recording = full cancel**（取消 = 丟棄 audio buffer + 不 transcribe + 不 LLM call + 不 paste） |
| Q4 | Per-prompt context config | **不加 per-prompt ContextFieldSet**；維持 global only。副產物：為 silent 的選取文字與個人字典補上 global toggle |
| Q5 | Screen OCR 沒及時 | **HUD 顯示 pending → 完成 / pending → omitted 三狀態**；upstream timing 不動 |
| Q6 | 敏感資料偵測 | **不做** —raw display 已足夠讓使用者判斷 |
| Q7 | Local vs Cloud 視覺區分 | **顏色 + icon 區分**；HUD 仍顯示資料、不因 local 就隱藏 |
| Layout | HUD 位置 | **獨立 NSPanel 緊鄰 active recorder**（MiniRecorder 模式：HUD 浮動於 recorder 上方；Notch 模式：HUD 自 notch 下方延伸） |

---

## 4. 架構

### 4.1 元件關係

```
VoiceInkEngine (既有，狀態機)
  └── 錄音 start → 呼叫 enhancementService.captureXxx() (5 個 capture method)
                 → enhancementService.assemblePrivacyPayload()

AIEnhancementService (既有，擴充)
  ├── 既有 @Published: lastCapturedClipboard, screenCaptureService.lastCapturedText
  ├── 新增 @Published: lastCapturedSelectedText
  ├── 新增 @Published: lastCapturedVocabulary
  ├── 新增 @Published: lastCapturedSystemContext
  └── 新增 @Published: currentPrivacyPayload: PrivacyPayload?

PrivacyHUDPanel (新增 NSPanel)
  ├── observes enhancementService.currentPrivacyPayload
  ├── contentView = PrivacyHUDView (SwiftUI)
  └── 位置由 PrivacyHUDPositioner 計算

PrivacyHUDPositioner (新增 helper)
  └── 根據 active recorder mode 回傳 NSRect

EscCancelHandler (新增 hotkey 註冊)
  ├── 錄音開始時註冊
  ├── 錄音結束 / cancel 時 unregister
  └── 觸發 → engine.cancelRecording() + clearPrivacyPayload()
```

### 4.2 設計取向

| 決定 | 理由 |
|---|---|
| 獨立 NSPanel，不嵌進 MiniRecorder / NotchRecorder | 跟既有 view code 解耦 → upstream merge 風險低 |
| State 寄生在 AIEnhancementService、不開新 coordinator class | 既有 `lastCaptured*` pattern 自然延伸；避免依賴注入鏈變複雜 |
| Capture-at-record-start | 與 push-to-talk 心智模型一致；HUD WYSIWYG |
| `getSystemMessage()` 改為先讀 `lastCaptured*` property、property nil 才 fallback on-demand | HUD 失靈不破壞 upstream enhance；也方便 A/B 測試 |
| Selected text / Vocabulary 的捕獲時機從 send-time 移到 record-start | **fork divergence**，但符合 capture-at-record-start 原則。記在 CLAUDE.md 上游 merge 注意點 |
| Mode-aware positioning（dispatcher）vs fixed position | 視覺上跟 recorder 一體；使用者直覺把 HUD 與錄音連結 |

---

## 5. 新增 / 修改的 components

### 5.1 新增 — Data model

**檔案**：`VoiceInk/Models/PrivacyPayload.swift`（新增）

```swift
struct PrivacyPayload {
    let timestamp: Date
    let transcript: TranscriptState
    let selectedText: ContextField<String>
    let clipboard: ContextField<String>
    let screenContext: ContextField<ScreenContextValue>
    let customVocabulary: ContextField<String>
    let systemContext: ContextField<SystemContextValue>
    let destination: PrivacyDestination
}

enum TranscriptState {
    case recording
    case finished(String)
}

/// 一個欄位的「會不會被送 / 送什麼」明確狀態
enum ContextField<T> {
    case disabled    // global toggle 關著（或 AX/Screen 權限沒給）
    case empty       // toggle on 但 value 空（例：沒選文字、剪貼簿空）
    case pending     // 還在處理（目前僅 screen OCR）
    case omitted     // 曾經 pending，但 release 時還沒完成
    case present(T)
}

struct ScreenContextValue {
    let windowTitle: String
    let appName: String
    let extractedText: String
}

struct SystemContextValue {
    let timestamp: Date
    let timezone: String
    let dayOfWeek: String
    let locale: String
}

enum PrivacyDestination {
    case local(providerLabel: String)
    case cloud(providerLabel: String)
}
```

### 5.2 新增 — View + Panel

**檔案**：`VoiceInk/Views/Recorder/PrivacyHUDView.swift`、`PrivacyHUDPanel.swift`（新增）

- `PrivacyHUDView`：SwiftUI view、`@ObservedObject` binding 到 `AIEnhancementService.currentPrivacyPayload`
- `PrivacyHUDPanel`：NSPanel，`.nonactivatingPanel`、`.floating` level、transparent bg（跟 `MiniRecorderPanel` 一致的 panel 設定）
- HUD 內容（按欄位行）。注意：**不包含錄音計時 / recording indicator**，那些屬 MiniRecorder / Notch 的職責，避免兩個 UI 重複顯示狀態：

```
✂️ Selected   "Hello world..."        [present]
📋 Clipboard  "sk-abc123def..."        [present]
🖥 Screen     identifying...           [pending → 動畫]
📚 Vocab      Claude, LINE, IG         [present]
🕐 Time       2026-05-22 23:15 (TPE)  [present]
─────────────────────────
→ Sending to: Claude (cloud) 🟡
```

Render rules：
- `disabled` / `empty` 的欄位 → **整行不渲染**（減少視覺噪音）
- `pending` → 行末顯示 spinner 或「identifying...」
- `omitted` → 行末顯示「omitted (timing)」灰字
- `present(T)` → 顯示 truncated value（前 ~40 字 + ellipsis）
- Cloud destination → 黃 / 橘色 + cloud icon
- Local destination → 綠 / 藍色 + machine icon

### 5.3 新增 — Positioner helper

**檔案**：`VoiceInk/Views/Recorder/PrivacyHUDPositioner.swift`（新增）

```swift
enum PrivacyHUDPositioner {
    static func calculateFrame(hudSize: NSSize) -> NSRect {
        let mode = currentRecorderMode()  // 讀 UserDefaults "RecorderType"
        switch mode {
        case .miniRecorder:
            return frameAboveMiniRecorder(hudSize)
        case .notch:
            return frameBelowNotch(hudSize)
        }
    }
}
```

`frameAboveMiniRecorder` / `frameBelowNotch` 各自處理「相對 recorder 位置 + 對齊」。Recorder type 切換時 HUD 仍在錄音中的 edge case：不處理（罕見、錄音通常 < 10 秒）。

### 5.4 擴充 — AIEnhancementService

**檔案**：`VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`（修改）

新增 properties：

```swift
@Published var lastCapturedSelectedText: String?
@Published var lastCapturedVocabulary: String?
@Published var lastCapturedSystemContext: SystemContextValue?
@Published var currentPrivacyPayload: PrivacyPayload?
```

新增 methods：

```swift
func captureSelectedTextContext() async      // 移 fetchSelectedText() 至此
func captureVocabularyContext(modelContext: ModelContext)
func captureSystemContext()                   // 見下方 OPA-113 bundling 註記
func assemblePrivacyPayload()                 // 組成 currentPrivacyPayload
func clearPrivacyPayload()                    // 錄音結束 / cancel 時呼叫
```

**OPA-113 bundling 註記**：`SystemContextValue` 與 `captureSystemContext()` 屬於 OPA-113（系統 context — time / timezone / locale）的範圍，但因為 `PrivacyPayload` 結構需要它存在才能完整、且實作改動同樣集中在 `AIEnhancementService.getSystemMessage()`，**本 PR 一併實作 OPA-113**（避免兩次動同一個 file 的 merge cost）。OPA-113 的 Linear issue 標 Done 與本 issue 同步。

修改 `getSystemMessage()` 邏輯：

```
原: 直接 await fetchSelectedText() / 直接讀 vocab
改: 先讀 lastCapturedSelectedText / lastCapturedVocabulary
    若 nil → fallback on-demand fetch（保持上游相容）
```

### 5.5 擴充 — VoiceInkEngine

**檔案**：`VoiceInk/Transcription/Engine/VoiceInkEngine.swift`（修改 line ~219）

既有 capture block：

```swift
enhancementService.captureClipboardContext()
await enhancementService.captureScreenContext()
```

擴充為：

```swift
enhancementService.captureClipboardContext()
await enhancementService.captureSelectedTextContext()
enhancementService.captureVocabularyContext(modelContext: modelContext)
enhancementService.captureSystemContext()
await enhancementService.captureScreenContext()
enhancementService.assemblePrivacyPayload()
```

注意：`captureScreenContext` 仍是 await，跟原來一致；其他 capture 都是 instant 或 detached Task，不阻塞。

錄音結束 / cancel path 加：

```swift
enhancementService.clearPrivacyPayload()
```

### 5.6 擴充 — Settings UI

**檔案**：`VoiceInk/Views/Settings/EnhancementSettingsPanel.swift`（修改）

新增兩個 toggle 補既有 silent 欄位：

- `useSelectedTextContext`（default ON，與上游既有預期相容）
- `useCustomVocabularyContext`（default ON）

兩者皆 master kill switch，與既有 `useClipboardContext` / `useScreenCaptureContext` 並列。

### 5.7 新增 — ESC global hotkey

**檔案**：`VoiceInk/Shortcuts/EscapeCancelHandler.swift`（新增）或整合進現有 `MiniRecorderShortcutManager.swift`

實作偏好：使用 `HotKeyManager` 註冊 ESC，與既有 hotkey 系統一致。錄音 start 時註冊、end / cancel 時 unregister。觸發後呼叫 `engine.cancelRecording()`（既有 method，若無則新增）。

---

## 6. 資料流

### 6.1 Happy path（push-to-talk 正常釋放）

```
USER          ENGINE              ENHANCE_SERVICE        HUD_PANEL          LLM
 │              │                       │                     │                │
 ├─ press ─────►│                       │                     │                │
 │              ├─ recording.start      │                     │                │
 │              ├──── captureAll ─────►│ (5 capture methods)  │                │
 │              │                       │── @Published ──────►│ panel.show()  │
 │              │   OCR done (~700ms)  │── @Published ──────►│ pending→present│
 ├─ release ───►│                       │                     ├─ panel.hide() │
 │              ├─ recording.end        │                     │                │
 │              ├─ transcribe (Whisper) │                     │                │
 │              ├──── enhance(text) ──►│                     │                │
 │              │                       ├─ getSystemMessage   │                │
 │              │                       │   讀 lastCaptured*  │                │
 │              │                       ├─── POST ────────────────────────────►│
 │              │                       │◄────────────────────────────────────│
 │              │◄── enhanced text ─────│                     │                │
 │ ◄─ paste ────│                       ├─ clearPrivacyPayload│                │
```

### 6.2 ESC 取消（錄音中）

```
... 同上至 capture ...
 │              │                       │                     │  使用者看到    │
 │              │                       │                     │  sensitive data│
 ├─ ESC ───────►│ (global hotkey 註冊)  │                     │                │
 │              ├─ recording.cancel     │                     │                │
 │              │  audio buffer discard │                     ├─ panel.hide() │
 │              │                       ├─ clearPayload       │                │
 │              │  (沒有 transcribe / enhance / LLM call / paste)
```

### 6.3 Screen OCR 沒及時

```
 ├─ press ─────►│                       │                     │                │
 │              ├──── captureScreen ───►│ OCR start (~700ms)  │                │
 │              ├──── captureOthers ──►│ (instant)            │                │
 │              │                       │── @Published ──────►│ HUD show       │
 │              │                       │                     │ 🖥 pending     │
 ├─ release ───►│  300ms 後             │                     │                │
 │              ├─ recording.end        │                     ├─ panel.hide() │
 │              ├─ transcribe / enhance │                     │                │
 │              │                       ├─ getSystemMessage   │                │
 │              │                       │   lastCapturedText  │                │
 │              │                       │   == nil → omit     │                │
 │              │                       ├──── POST (無 <CURRENT_WINDOW_CONTEXT>) ►│
```

### 6.4 關鍵 invariant

1. **HUD 顯示 ≡ 將要送出**（`currentPrivacyPayload` 為 single source of truth）
2. **HUD lifecycle = recording lifecycle**（HUD 不負責「sending 中」狀態，那是 MiniRecorder / Notch 的 processing 狀態）
3. **OCR 行為跟 upstream 一致**（沒及時就 omit、不阻塞、不警示）
4. **`getSystemMessage()` 仍是 LLM payload 組裝的唯一來源**（只是讀資料來源從 on-demand 改為 property + on-demand fallback）

---

## 7. 錯誤處理

**核心原則**：HUD 是 non-critical。任何 HUD 失敗皆 graceful degrade 回上游行為，不阻塞錄音 / enhancement。

### 7.1 權限類錯誤

| 情境 | HUD 狀態 | Send 行為 |
|---|---|---|
| Accessibility 沒給 | `selectedText: .disabled`、那行不渲染 | `<CURRENTLY_SELECTED_TEXT>` 不附加 |
| Screen Recording 沒給 | `screenContext: .disabled` | `<CURRENT_WINDOW_CONTEXT>` 不附加 |

### 7.2 捕獲失敗

| 情境 | HUD 狀態 | Send 行為 |
|---|---|---|
| 沒選文字 | `.empty` 不渲染 | 不附加 |
| 剪貼簿空 | `.empty` 不渲染 | 不附加 |
| OCR 拋錯 / 沒及時 | `.omitted` 顯示 | 不附加 |
| Vocabulary 空 | `.empty` 不渲染 | 不附加 |

### 7.3 ESC edge cases

- ESC 在 `recording.start` 還沒完成時：guard 確保 idempotent，no-op
- ESC + 釋放熱鍵同時：第二個 cancel 看到 `recordingState != .recording` 直接 no-op
- ESC 在 `enhance()` 已 start 時：太晚了；HUD 已 hide，ESC 無法 cancel HTTP（記在 known limitations，未來考慮 cancel token）

### 7.4 HUD 自己的失敗

| 情境 | Fallback |
|---|---|
| `NSScreen.main` 為 nil | Positioner 回傳 centered default frame |
| `currentPrivacyPayload == nil` at send | `getSystemMessage()` fallback on-demand fetch（上游兼容） |
| NSPanel init 拋錯 | log + 不顯示，錄音正常 |

### 7.5 並發

- 快速 spam press-release：用 Task cancellation 確保前次 OCR 不寫進新 session 的 `lastCapturedText`
- Active recorder mode 在錄音中切換：罕見、不處理

---

## 8. 測試策略

### 8.1 Unit tests

- `PrivacyPayload` builder：給定 `lastCaptured*` → 對應 ContextField case 正確
- `ContextField<T>` 渲染決策：每個 case → 對應 HUD render 行為
- `PrivacyDestination` 偵測：baseURL / provider → local vs cloud 正確
- `PrivacyHUDPositioner`：mock NSScreen → 兩個 mode 的 NSRect 在正確區域

### 8.2 Integration tests

- 觸發 `record-start` → 5 個 capture method 都被呼叫
- `clearPrivacyPayload()` 後 → payload nil + observer 收到 publish
- **Fallback invariant**：強制 `currentPrivacyPayload = nil` + 呼叫 `enhance(text)` → `getSystemMessage()` 仍能組出 message（owner 認為稍微 over-defensive，可以視 implementation 成本選擇 skip 或保留）
- Disabled toggle 全關 → assembled payload 全 disabled → LLM message 不含任何 `<*_CONTEXT>` tag
- ESC cancel → mock recording.start → 確認 no enhance call + panel.hide() 一次

Mock 點：`SelectedTextService`、`ScreenCaptureService`、`NSPasteboard`、LLM HTTP client。若無依賴注入慣例，新增 protocol 介面化。

### 8.3 SwiftUI snapshot tests

對 `PrivacyHUDView` 用以下 input 跑 snapshot：empty、full、pending、omitted、cloud destination、local destination、長 clipboard。若 codebase 無 snapshot lib，初版可延後、靠 dog-food。

### 8.4 Dog-food checklist（spec 上線前 owner 親測）

- [ ] MiniRecorder mode：HUD 出現在 recorder 上方
- [ ] Notch mode：HUD 出現在 notch 下方
- [ ] OPA-107 三段測試錄音跑過，HUD 內容與 LLM payload 一致
- [ ] 沒選任何字 / 剪貼簿空 → 對應行不渲染
- [ ] 剪貼簿含 `sk-abc123...` → HUD 顯示 raw 內容
- [ ] Screen Context 關 → screen 行不渲染
- [ ] Screen Context 開 + < 300ms 釋放 → HUD 顯示 omitted
- [ ] ESC 中斷 → 無 paste、無 network egress（用 `tcpdump` / Charles 驗證）
- [ ] 切 Ollama → destination indicator 變色
- [ ] Disable 全部 global toggle → enhance 仍能跑、HUD 僅顯示 transcript + destination
- [ ] OPA-108 zh-TW 流程仍正常（seed prompt 仍送、`<TRANSCRIPT>` 包裝不變）

### 8.5 不測什麼（YAGNI）

- HUD pixel-perfect 位置（only 驗證「上方 / 下方」邏輯）
- Performance benchmark
- Memory leak（trust ARC）
- RTL 語言 layout

---

## 9. Open considerations / 未來工作

- **Action Mode 整合**（OPA-114）：未來 tool call 也是 send payload 一部分，HUD 須擴充顯示 tool schema 與 tool call plan
- **Privacy HUD 永遠顯示 vs auto-hide**：使用者操作熟練後可能想關掉 HUD；考慮加 global setting「Show Privacy HUD: always / first-time only / never」
- **OCR cancellation**：用 Task cancellation API 在 ESC 時主動 cancel OCR（節省 CPU），實作時看 ScreenCaptureService 是否好接 hook
- **HUD 上的 hover preview**：長 clipboard / selected text 可 hover 展開全文。初版用 truncation + ellipsis 即可

---

## 10. Acceptance criteria（implementation 完成定義）

- [ ] 新檔 `PrivacyPayload.swift`、`PrivacyHUDView.swift`、`PrivacyHUDPanel.swift`、`PrivacyHUDPositioner.swift` 都已建立
- [ ] `AIEnhancementService` 含 4 個新 `@Published` 與 5 個新 method
- [ ] `VoiceInkEngine.swift` capture block 擴充為 5 個 capture method
- [ ] `getSystemMessage()` 改為「property 優先 / on-demand fallback」邏輯
- [ ] `EnhancementSettingsPanel.swift` 新增 2 個 global toggle（selected text + vocab）
- [ ] ESC global hotkey 在錄音中觸發 → cancel + 不送 LLM
- [ ] PrivacyHUDPanel 在 MiniRecorder 模式出現於 recorder 上方
- [ ] PrivacyHUDPanel 在 Notch 模式出現於 notch 下方
- [ ] Cloud / Local destination 視覺區分明確
- [ ] Dog-food checklist 全數通過
- [ ] CLAUDE.md「known privacy gap」段落更新：標記為已修
- [ ] CLAUDE.md Append-only log 加一筆 fork divergence 紀錄（特別記「selected text + vocab 捕獲時機從 send-time 移到 record-start」+ 「OPA-113 system context 與本 PR bundle」）
- [ ] Linear OPA-111 / OPA-112 / OPA-113 三張 issue 標 Done；OPA-114 相依關係更新（blocked-by 解除）

---

## 11. References

- **OPA-107**：完整資料外送審計（Linear comment + commit 中已 squash 的 `docs/research/zh-tw-spike-results.md` 思路）
- **OPA-111**：原 Privacy HUD issue（這份 spec 取代其「設計問題」段落）
- **OPA-112**：本設計的 design ticket（Q1-Q7）
- **OPA-113**：系統 context（SystemContextValue 來自此 issue）
- **OPA-114**：Action Mode 研究（HUD 未來擴充顯示 tool calls）
- **CLAUDE.md**：fork mission #1（隱私是底線）、known privacy gap 段落
- `AIEnhancementService.swift` lines 145-202（既有 system message 組裝）
- `VoiceInkEngine.swift` lines 219-222（既有 capture block hook）
- `MiniRecorderPanel.swift` / `NotchRecorderPanel.swift`（HUD 樣式 / panel 設定參考）
