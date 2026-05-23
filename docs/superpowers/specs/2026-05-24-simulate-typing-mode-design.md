# Simulate Typing Mode — 設計規格

**Date**: 2026-05-24
**Linear**: [OPA-115](https://linear.app/opass/issue/OPA-115)
**Status**: Design approved, ready for implementation plan
**Related**: 無前置 issue；此 feature 獨立

---

## 1. 背景與動機

VoiceTwInk 的輸出機制目前是 `CursorPaster.performPasteSession`：

1. 把整段 transcript 寫進 `NSPasteboard.general`
2. 模擬 `Cmd+V`（CGEvent 或 AppleScript）
3. 可選還原 clipboard

對絕大多數 macOS app 是最快、最可靠的輸出方式。但在 **Claude Code CLI**（owner 的日常 AI 協作工具，跑在 Ghostty + tmux 裡）出現問題：

- Claude CC 偵測到 bracketed paste 模式 + 多行內容 → 自動把貼上內容收摺成 `[Pasted text +N lines]` symbol
- 使用者**無法在送出前 inline 編輯**這段文字（必須 expand、複製到外部編輯、再貼回）
- 對「邊講邊改」的工作流是嚴重 friction

問題不是 VoiceInk 的 bug，是 Claude CC 對「大段 paste」的 UX 設計。VoiceTwInk 要在輸出端做變通。

## 2. Goals / Non-Goals

### Goals

1. 提供 **opt-in 全域 toggle**，使用者可選擇用「模擬鍵盤輸入」取代「貼上」輸出 transcript
2. 模擬輸入需**繞過 IME**（owner 為 zh-TW 用戶，注音輸入法 active 時不可被攔截轉換）
3. 在此模式下**不**自動送 Enter（即使 Power Mode 有設 AutoSend）— 使用者可先檢視 transcript 再手動 Enter
4. 預設 OFF，不破壞既有 paste 行為與 AutoSend 行為
5. 影響面**最小**：只動 `CursorPaster.swift` + `SettingsView.swift` + `AppDefaults.swift` + `TranscriptionPipeline.swift`（AutoSend gate）

### Non-Goals

- **不**做 per-CustomPrompt typing toggle（owner 明確要「一個開關」）
- **不**做 per-Power-Mode app 自動偵測切換（YAGNI；之後若手切煩了再加）
- **不**做 typing 速度的 UI 控制（先用 default 5ms/char；真有掉字問題再加）
- **不**做 preview-edit HUD（整個 motivation 就是避開 preview 的複雜性）
- **不**動 `VoiceInkEngine` 的 paste caller（branch 邏輯封裝在 `CursorPaster` 內）
- **不**承諾這方案一定解決 Claude CC 的摺疊問題 — owner 已知是 probe 性質的實作

## 3. 設計決定 — 行為矩陣

| 模式 | Output 方式 | AutoSend | Clipboard 行為 | AppleScript Paste 設定 |
|---|---|---|---|---|
| Typing OFF（預設） | Paste（既有，整段 Cmd+V） | 依 Power Mode 設定 | 寫 clipboard，可選還原 | 生效 |
| Typing ON | 逐字 unicode 注入（CGEvent） | **永遠 OFF**（不論 Power Mode） | 不碰 clipboard | 不適用 |

「Typing ON → AutoSend OFF」是設計約束，不是 UI 選項。理由：typing mode 的整個語意就是「我要先檢視再送」，自動 Enter 跟這個語意矛盾。

## 4. 架構決定

**選 A：在 `CursorPaster` 內 branch**

```swift
// performPasteSession 開頭
let simulateTyping = UserDefaults.standard.bool(forKey: "simulateTypingInsteadOfPaste")
if simulateTyping {
    return await typeAtCursor(text)
}
// ... 既有 paste 路徑
```

理由：
- 影響面最小（單一檔案）
- upstream merge 衝突面最小（其他 caller 不變）
- 語意可接受（CursorPaster = 「把 transcript 放進游標位置」，不限於 paste 機制）

否決選項：
- **抽 `CursorOutputProvider` protocol**：over-engineering，違反 YAGNI
- **新檔 `CursorTyper.swift` + VoiceInkEngine 分流**：影響面更廣，merge 摩擦大

## 5. 核心 typing 機制

```swift
// CursorPaster.swift 新增 // MARK: - Simulated typing 區塊
@MainActor
private static func typeAtCursor(_ text: String) async -> PasteResult {
    guard AXIsProcessTrusted() else {
        logger.error("Accessibility permission required for simulated typing")
        return .commandNotPosted
    }

    let source = CGEventSource(stateID: .privateState)
    for char in text {
        let str = String(char)
        let utf16 = Array(str.utf16)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            logger.error("Failed to create typing key events for char: \(str, privacy: .public)")
            continue
        }

        utf16.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress {
                keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
                keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
            }
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms inter-char delay
    }

    return .commandPosted
}
```

關鍵點：
- **`CGEventKeyboardSetUnicodeString`** 繞過 keyboard layout 與 IME — 注音輸入法 active 時，inject 的 unicode 字直接出現、不被攔截轉換
- **逐字注入**而非一次整段：確保接收 app 把每個 char 當「typed input」處理、避免被誤判成 paste-like batch
- **5ms inter-char delay**：default 值。500 字段落約 2.5 秒。若 Ghostty / Claude CC 在此速度下仍丟字，調大到 10-20ms（不開 UI 控制，直接改常數重 build）
- **`cghidEventTap`**：跟既有 paste 路徑一致，全 system-level
- **AX 權限門檻**：跟既有 `pasteFromClipboard` 一致（line 176）

## 6. AutoSend Gate

`TranscriptionPipeline.swift:228-237` 是 codebase 唯一的 AutoSend 觸發點。加一行 gate：

```swift
let simulateTyping = UserDefaults.standard.bool(forKey: "simulateTypingInsteadOfPaste")
if let autoSendKey, autoSendKey.isEnabled, !simulateTyping {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 500_000_000)
        CursorPaster.performAutoSend(autoSendKey)
    }
}
```

## 7. Settings UI

加在 `SettingsView.swift:198-203`「Use AppleScript Paste」toggle 下方，同一個 `Section("Recording Feedback")` 內：

```swift
Toggle(isOn: $simulateTypingInsteadOfPaste) {
    HStack(spacing: 4) {
        Text("Simulate Typing Instead of Paste")
        InfoTip("Types each character as a simulated key event instead of pasting. Slower for long text, but avoids paste-collapse in apps like Claude Code CLI. Bypasses IME via direct Unicode injection. Note: Auto Send is disabled in this mode — press Enter manually after reviewing.")
    }
}
```

伴隨：
- `@AppStorage("simulateTypingInsteadOfPaste") private var simulateTypingInsteadOfPaste = false` 在 SettingsView 內宣告
- `AppDefaults.swift` 加 `"simulateTypingInsteadOfPaste": false` 到 register dict
- 不改 Section 名稱（保持上游一致，降低 merge 衝突）

## 8. Edge cases / 風險

| 風險 | 處理 |
|---|---|
| 某些 app 在 5ms 速度下掉字 | 先試 default，掉字回頭調 delay |
| 使用者中途切走 focus | 部分字進舊 app，後續字進新 app — 跟既有 paste 中斷一樣，不特別處理 |
| AX 權限被撤銷 | `AXIsProcessTrusted()` 檢查，return `.commandNotPosted` 並 log（同既有 `pasteFromClipboard`） |
| `CGEventKeyboardSetUnicodeString` 對某些 Unicode（emoji、surrogate pair）行為異常 | 上面用 `String(char)` 確保每次處理一個 Character（多 unit grapheme），UTF-16 編碼正常處理 surrogate pair |
| Claude CC 仍然摺疊 | **這是 probe**。若實測證明摺疊邏輯跟 unicode 注入無關（例如 Ghostty 把所有 inject 都包成 bracketed paste），revert toggle、考慮其他方向 |
| 使用者忘了 toggle 已開、進入 Slack 變慢 | InfoTip 已說明；不另設 hint |
| typing 中按 ESC | 跟既有 paste 中斷一樣，部分字已注入留在 app 內；不特別處理（未來若需要可加 cancellation token） |

## 9. Testing

**手動測試矩陣**（toggle ON 狀態下）：

1. **Ghostty + tmux + claude CC**：錄一段 300+ 字 zh-TW，確認 inline 顯示、無 `[Pasted text]` 摺疊、可編輯
2. **Slack**：同段話，確認文字正確出現、AutoSend 沒 fire（即使 Power Mode 有設）
3. **Notion / 一般 SwiftUI app**：確認逐字輸入流暢、無掉字
4. **注音輸入法 active 中**：確認 inject 的 zh-TW 字直接出現，不被注音攔截
5. **Emoji / 符號**：講「我覺得 👍」確認 emoji 正常注入
6. **長段落（1000+ 字）**：確認不會 timeout / 不會崩

**Regression**（toggle OFF 狀態下）：
- 所有既有行為 unchanged（paste 速度、AutoSend、AppleScript Paste、clipboard restore 全部正常）

**Unit test**：
- 不寫。`CursorPaster` 整體就無 unit test（依賴系統 CGEvent + AX，難 mock）。沿用既有「靠手動測試」慣例

## 10. Open Questions / 後續

- 若 default 5ms 普遍掉字 → 是否需要 UI 速度控制？（先不做，掉字才加）
- 若 toggle 用一段時間發現「特定 app 才需要」，是否升級為 per-Power-Mode 配置？（user explicitly says no for now）
- 是否值得加 menu bar 快速 toggle？（先不做，Settings 切就好）

## 11. 檔案異動清單

| 檔案 | 異動 |
|---|---|
| `VoiceInk/CursorPaster.swift` | 新增 `typeAtCursor()` + `performPasteSession` 開頭 branch |
| `VoiceInk/Views/Settings/SettingsView.swift` | 新增 `@AppStorage` + Toggle UI |
| `VoiceInk/AppDefaults.swift` | register `"simulateTypingInsteadOfPaste": false` |
| `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` | AutoSend gate |
| `CLAUDE.md` | 完成後追加 append-only log 一條 |

---

## 12. 概要

> 加一個 Settings toggle「Simulate Typing Instead of Paste」。打開時，VoiceTwInk 用 `CGEventKeyboardSetUnicodeString` 逐字模擬鍵盤輸入取代 paste，繞過 IME，並強制關閉 AutoSend 讓使用者先檢視再手動 Enter。Probe 性質 — 不確定能解決 Claude CC 的 `[paste]` 摺疊問題，先做先測。
