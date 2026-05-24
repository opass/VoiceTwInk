<div align="center">
  <img src="VoiceInk/Assets.xcassets/AppIcon.appiconset/256-mac.png" width="180" height="180" />
  <h1>VoiceTwInk</h1>
  <p>可審計隱私、針對台灣繁中調整、只能 build from source 的 VoiceInk fork。</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  ![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-brightgreen)
  [![Fork of](https://img.shields.io/badge/fork%20of-Beingpax%2FVoiceInk-orange)](https://github.com/Beingpax/VoiceInk)

  <p><strong>English</strong> → <a href="./README.md">README.md</a></p>
</div>

---

## TL;DR

VoiceTwInk 是 [VoiceInk](https://github.com/Beingpax/VoiceInk) 的個人 fork（VoiceInk 是 macOS 上的語音轉文字 app）。上游做得很好，但明確說不收 PR — 所以我開了這個 fork 來加上隱私可審計、台灣繁中調整、跟針對 Claude Code CLI 之類工具的 ergonomic 改進。**只能 build from source、沒有預編譯 binary、不需要 license**。

## 這個 fork 加了什麼

### 1. Privacy HUD — 送出前先看每一個 byte

上游的 AI Enhancement 啟用時，會默默把選取文字、剪貼簿內容、Screen OCR 結果、自訂字典等 context 全部塞進送 LLM 的請求 — 只要 Accessibility 權限有給。問題是你完全沒辦法 audit 它**正要**送什麼出去，它就送了。

VoiceTwInk 加了一個浮動 HUD，錄音時跟在 recorder 旁邊、即時顯示每一個即將離開機器的 context 欄位 — 還有視覺標記（綠 / 黃）區分本地 vs 雲端目的地。錄音中按 ESC 在任何資料送出前全部取消。新加的 global toggle 讓你完全 opt out 選取文字 / 自訂字典的夾帶。

詳細：[FORK-CHANGES.md § 1. Privacy HUD](./FORK-CHANGES.md#1-privacy-hud)（英文）。

### 2. 台灣繁中調整

Whisper 預設中文輸出是簡中、雲端 LLM 在輸入很短的時候常常會把繁中 normalize 回簡中。VoiceTwInk 兩層都處理：

- 新增 Settings 內「Chinese (Taiwan)」語言選項，背後接一段台灣特化的 seed prompt，把 Whisper 偏置到繁中 + 台灣用詞（`捷運` 不是 `地铁`、`軟體` 不是 `软件` 等等）
- 預設 enhancement prompt 開頭加一條最高優先的 `[CRITICAL LANGUAGE RULE]`，用具體繁簡字對比例子強迫 LLM 輸出繁中

**推薦設定**：語言用 **Auto-detect** + 開 AI Enhancement。原因是「Chinese (Taiwan)」的 Whisper seed prompt 過度 aggressive、會把英文 audio 翻譯成中文（這是非預期的副作用）；auto-detect 繞開這個、enhancement layer 那條規則照樣會把任何簡中輸出轉成繁中。

詳細：[FORK-CHANGES.md § 2. Traditional Chinese tuning](./FORK-CHANGES.md#2-traditional-chinese-tuning)（英文）。

### 3. 預設 build from source

上游的開源模式是：程式碼完全開放、但買 license 才有自動更新跟 support。這個 fork 沒接 license server — 直接 `make local` 一次、永久免費可用、簽好的 app。

Build 用免費的 Apple Developer Personal Team 憑證簽（**不**需要 $99/年的 paid account），這帶來的好處是 macOS TCC 在每次 rebuild 之間保留麥克風 / Accessibility 權限 — 修掉了之前每次 rebuild 都被當新 app、要重新授權所有權限的痛點。

```bash
make check       # 檢查 Xcode 環境
make local       # build + 部署到 /Applications/
make dev         # build + 重啟 running VoiceInk（日常 iterate 用這個）
```

詳細：[BUILDING.md](./BUILDING.md)（第一次設定）、[CLAUDE.md 的 Build and first-run 段](./CLAUDE.md#build-and-first-run)（hybrid 簽章策略）。

### 4. Simulate Typing Mode — 繞開 Claude Code CLI 的 `[Pasted text]` 摺疊

Claude Code CLI 會把大段 paste 自動收摺成 `[Pasted text +N lines]` symbol、根本沒辦法在送出前 inline 編輯。VoiceTwInk 加了一個 Settings toggle，把 paste pipeline 換成逐字 `CGEventKeyboardSetUnicodeString` 注入，模擬實際打字。

打開時還會：
- **繞過 macOS IME** — 注音輸入法 active 時不會攔截注入的字符
- **強制關閉 AutoSend** — 你可以先檢視 / 編輯 transcript 再手動按 Enter 送出
- **把 `\n` 翻譯成 Shift+Return** — 保留段落結構但不會在 Slack / Discord / Claude Code CLI 這類 chat-style app 中提早送出

詳細：[FORK-CHANGES.md § 4. Simulate Typing Mode](./FORK-CHANGES.md#4-simulate-typing-mode)（英文）。

### 5. 永遠 GPL v3

上游是 GPL v3、fork 也是。每一個改動都必須維持開源 — 對隱私敏感的工具來說這是 feature 不是 bug。你可以 fork 這個 fork 再 audit 一切；沒有 proprietary code path、沒有隱藏 telemetry、沒有 closed-source dependency 哪天悄悄改 posture。

詳細：[LICENSE](./LICENSE)、[CLAUDE.md 的 GPL v3 obligations 段](./CLAUDE.md#gpl-v3-obligations)。

## 隱私 posture

這個 fork 保留上游的 open-source / no-telemetry posture、外加 runtime audit 能見度。

對外連線一覽：

| Host | 觸發時機 | Payload |
|---|---|---|
| 雲端 LLM（使用者選） | AI Enhancement 啟用時 | system prompt + transcript + 選擇的 context 欄位 |
| 雲端 transcription（使用者選） | 沒用 Local Whisper 時 | raw WAV + 選擇性 prompt |
| `huggingface.co` | 手動下載 Whisper model 時 | GET only |
| `beingpax.github.io` | Sparkle 自動更新 + announcements | GET only、無 body、無 UA personalization |
| `api.polar.sh` | License 啟用 | **商業 build 限定 — `make local` build 永遠不會呼叫** |

沒有任何 telemetry SDK（`grep` 過 Sentry / Crashlytics / PostHog / Mixpanel / Amplitude / Firebase / Datadog：零命中）。沒有啟動 ping、沒有 quit 時 beacon、沒有 crash uploader。

完整 audit：[CLAUDE.md 的 Privacy audit summary 段](./CLAUDE.md#privacy-audit-summary)。

## Build 跟首次啟動

前置：
- Xcode（免費、Mac App Store 下載），Settings → Accounts 加入你的 Apple ID — 這會自動生成 Personal Team 憑證
- repo root 放一個 `.local-team` 檔案、內容是你的 Apple Developer Team ID（這個檔已 gitignore）
- macOS 14.0 以上

```bash
make check       # 檢查工具鏈
make local       # build + 部署到 /Applications/
make dev         # build + 重啟 running app
```

首次啟動後，依 fork 的隱私 posture 設這幾個：
1. Transcription provider：**Local Whisper**（避開把錄音上傳到雲端）
2. Settings → Cleanup → Audio cleanup：**開啟**（預設關、不開的話錄音檔會永遠累積）
3. Settings → Show Announcements：**關閉**（避開每 4 小時 GET `beingpax.github.io`）
4. AI Enhancement：**關閉**、或者用 **Ollama**（避開把 transcript 上雲端 LLM）

完整設定（含 TCC 權限的眉角）：[BUILDING.md](./BUILDING.md)。專案完整 rationale：[CLAUDE.md](./CLAUDE.md)。

## 給台灣繁中使用者

推薦設定：
- **語言**：Auto-detect（**不要**選 "Chinese (Taiwan)"，原因見 [FORK-CHANGES.md § 2 known trade-offs](./FORK-CHANGES.md#2-traditional-chinese-tuning)）
- **AI Enhancement**：開啟（這是強制繁中輸出的關鍵）
- **可選**：自建 Custom Prompt 加入你的領域 vocabulary（隊員名字、專案 code name 等等）

這樣設下去，中英混的語音輸入會自然處理 — 例如「我覺得這個 implementation 很 elegant」會保持中英混、英文技術詞不會被翻譯。

## 狀態跟範圍

- 個人 fork、owner 的 daily driver
- 沒 SLA、沒 support、沒 release schedule。Pull `main` 自己 rebuild
- Issue 歡迎開（追蹤 shared interest 用），PR 可能慢回 / 也可能 reject 不符 fork mission（隱私優先、zh-TW、build-from-source）的 PR
- 完整專案 context 看 [CLAUDE.md](./CLAUDE.md) — 那個檔案是 fork 是什麼、不是什麼的 source of truth

## 上游

建立在 [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) 之上（GPL v3）。上游 README 明確說不收 PR；這個 fork 存在的原因就是要在那個 constraint 之外做個人客製。對上游沒有 ill will — 那是個 polished、做工紮實的 app，這個 fork 繼承了 maintainer 每一個好決定。

同步節奏：每週 review 上游 `main`、優先處理安全修補跟 audit-sensitive 路徑。

## License

GPL v3（繼承自上游、不能改）。見 [LICENSE](./LICENSE)。

## Acknowledgments

### Upstream

- [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) — 這個 fork 站在它的肩膀上

### Core technology

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — OpenAI Whisper 的高效推論
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Parakeet model 實作

### Essential dependencies

- [Sparkle](https://github.com/sparkle-project/Sparkle) — 自動更新框架（這個 fork 改成手動 pull 最新 source）
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — 使用者可自訂的快捷鍵
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin)
- [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter)
- [Zip](https://github.com/marmelroy/Zip)
- [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit)
- [Swift Atomics](https://github.com/apple/swift-atomics)
