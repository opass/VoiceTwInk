# README Rewrite — 設計規格

**Date**: 2026-05-24
**Status**: Design approved, ready for implementation
**Related**: Fork mission per CLAUDE.md; positions VoiceTwInk for public visibility ahead of owner's upcoming blog post

---

## 1. 動機

現有 `README.md` 是上游 `Beingpax/VoiceInk` 的內容、完全沒反映 fork 的存在或差異。對任何 land on this repo 的人會嚴重誤導：

- 連結指向 `tryvoiceink.com`（上游商業網站）
- 建議使用 `brew install --cask voiceink`（裝到的是上游 binary、不是本 fork）
- 沒提隱私改進、繁中調整、Simulate Typing Mode 等 fork-specific value
- 沒解釋「為什麼這個 fork 存在」

Owner 即將寫 blog 介紹語音輸入工具心得，README 需要對得起 blog 把讀者導過來看 repo 的場景。

## 2. Goals / Non-Goals

### Goals

1. **30 秒內讓 evaluator 知道**這個 fork 加了什麼、為什麼、值不值得試
2. **明確「不要裝上游 binary」**：移除所有 download / homebrew 連結，replace with build-from-source
3. **凸顯 5 個改進**：Privacy HUD、繁中調整、build workflow、Simulate Typing Mode、GPL inherited
4. **保持對上游的尊重**：明確 credit Beingpax/VoiceInk、不要 framing 成「比 upstream 強」的姿態 — fork 是 personal customization, not competition
5. **連到深度資源**：CLAUDE.md（mission depth）、新檔 `FORK-CHANGES.md`（per-improvement deep dive，取代私人 Linear 引用）、之後的 blog
6. **Acknowledgments 保留 upstream + dependencies credit**（GPL 義務）

### Non-Goals

- **不**寫成 marketing landing page（不寫 emotional CTA、不過度推銷）
- **不**寫成完整 user manual（指向 BUILDING.md 跟 CLAUDE.md）
- **不**做雙語版本（英文為主、Taiwan context 必要時 inline 中文片段；不維護兩個版本）
- **不**搬上游全部 features 列表（保留共通的 features 描述、加 fork-specific 改進；不重複描述 upstream 已寫過的）
- **不**新建 BUILDING.md / CONTRIBUTING.md / CODE_OF_CONDUCT.md（這些上游檔案直接保留 / 後續再評估）

## 3. 結構選擇

### 雙語檔案 layout

Bilingual two-file pattern：

- `README.md` — English primary（GitHub repo 首頁預設顯示）
- `README.zh-TW.md` — 台灣繁體中文版

兩個檔案頂端各放一行 language switcher：
- `README.md` 頂端：「**繁體中文版** → [README.zh-TW.md](./README.zh-TW.md)」
- `README.zh-TW.md` 頂端：「**English** → [README.md](./README.md)」

中文版**不直譯**英文版、用自然台灣繁中口語（同 CLAUDE.md 風格、技術詞英文保留）。內容對齊但 prose 各自寫。

維護承諾：之後若同步漂移，加 footer disclaimer「以英文版為準」即可，不為了完美同步阻塞發 README。

### 整體結構（兩語共用）

**選 Approach B（Feature-diff-first）**

順序：
1. Hero + tagline
2. TL;DR
3. **What this fork adds**（5 個改進子段落）
4. Privacy posture summary
5. Build & first-run
6. For Traditional Chinese users
7. Status & scope
8. Upstream credit
9. License & Acknowledgments

### 為什麼不選別的

- **Approach A（Mission-first）**：blog-style 故事優先 — 但 mission 內容更適合 blog；README 給 evaluator 看，直接看「加了什麼」比較直接
- **Approach C（Comparison-first）**：side-by-side 比較表 — 放大「vs upstream」的競爭姿態，跟 personal-fork 定位衝突

## 4. 各段內容綱要

### Header
- Logo（沿用上游 icon 路徑）
- Title：VoiceTwInk
- Badges：GPL-v3 / macOS 14+ / Fork of Beingpax/VoiceInk（link）
- Tagline（1 line）：「Privacy-auditable, Traditional Chinese tuned, build-from-source-only fork of VoiceInk.」
- **不**保留上游的「Download Now」big-button、tryvoiceink.com 連結、YouTube 連結

### TL;DR（~80 英文字）
3-4 sentences 涵蓋：
- 是什麼：upstream VoiceInk 的個人 fork
- 為什麼存在：upstream 不收 PR、owner 需要 zh-TW + privacy 客製
- 給誰用：privacy 敏感的 macOS 使用者、台灣繁中使用者、想看 fork 怎麼做的人
- 怎麼用：build from source（no binary）

### What this fork adds（核心段落、~600 英文字 total）

每個改進子段落 ~80-150 字，結構：「**what it does** → **why it matters** → **details elsewhere**」

#### 1. Privacy HUD — see every byte before it leaves
- WHAT: 錄音中 HUD 即時顯示將送 LLM 的 context（selected text / clipboard / screen OCR / vocabulary / time）
- WHY: 上游 LLM enhancement 啟用時、selected text + clipboard 等 silently 夾帶、使用者無法 audit
- DETAILS: 連 `FORK-CHANGES.md#1-privacy-hud`

#### 2. Traditional Chinese tuning
- WHAT: 新增 "Chinese (Taiwan)" 語言選項、enhancement prompt 強制繁中
- WHY: Whisper default 輸出簡中、雲端 LLM 對短輸入 fallback 到簡中
- DETAILS: 連 `FORK-CHANGES.md#2-traditional-chinese-tuning`；recommended setting = auto-detect + enhancement on（避開 Whisper seed prompt 的英文翻譯副作用，FORK-CHANGES § 2 known trade-offs 解釋）

#### 3. Build from source by default
- WHAT: `make local` / `make dev` / `make relaunch` 用 Apple Developer Personal Team cert 自簽
- WHY: 上游商業模式 = code 開源、買 license 只買自動更新；fork 沒有 license server，自己 build 就免費永久使用 + 真正可審計
- DETAILS: 連 BUILDING.md（上游既有檔案）+ CLAUDE.md「Build and first-run」section

#### 4. Simulate Typing Mode — bypass Claude Code CLI's [Pasted text] collapse
- WHAT: Settings toggle，把 paste 改成 per-character unicode injection + Shift+Return for newlines
- WHY: Claude Code CLI 把大段 paste 摺疊成 `[Pasted text +N lines]` 無法 inline 編輯 / 中間 newline 變 Enter 提早送出
- DETAILS: 連 `FORK-CHANGES.md#4-simulate-typing-mode`

#### 5. GPL v3 inherited
- WHAT: Fork 維持 GPL v3、所有改動 open source
- WHY: 上游就是 GPL，傳染性確保 fork 也必須開源 — 對 privacy-focused tool 來說是 feature 不是 bug
- DETAILS: License 段落

### Privacy posture（~100 英文字 + 小表）

簡短 callout：「This fork preserves upstream's open-source, no-telemetry posture and adds runtime audit visibility.」

小表：what hosts get contacted, when:
| Host | Trigger | Payload |
| Cloud LLM (user-selected) | AI Enhancement enabled | system prompt + transcript + chosen context |
| Cloud transcription (user-selected) | not using Local Whisper | raw audio |
| `huggingface.co` | manual model download | GET only |
| `beingpax.github.io` | announcements + Sparkle update | GET only, no body |

Footer 一行：「Full audit in CLAUDE.md → Privacy audit summary」+ link

### Build & first-run（~80 英文字 + commands）

```bash
make check       # verify Xcode setup
make local       # build + deploy to /Applications
make dev         # build + relaunch running app
```

3 個 prerequisites bullet：
- Xcode + free Apple ID (Personal Team cert)
- `.local-team` file with your Team ID
- macOS 14+

Pointer：「Full setup including TCC re-permission gotchas → BUILDING.md」

### For Traditional Chinese users（~60 英文字 + Taiwan context phrases）

Recommended settings：
- Language: **Auto-detect**（避開 `language=zh` 對純英文 audio 的翻譯行為）
- AI Enhancement: **On**（enhancement-layer language rule 救簡→繁）
- Optional: 自建 Custom Prompt 加入你的領域 vocabulary

Footer：「Trade-off → FORK-CHANGES.md § 2 known trade-offs」

### Status & scope（~50 英文字）

- 個人 fork、daily driver
- 不接 issue tickets / 無 SLA / 無 user support
- PR welcome 但 owner 可能 slow / 可能 reject 不符 fork mission 的 PR
- 沒有 release schedule — pull latest main + rebuild

### Upstream（~40 英文字）

- Credit Beingpax/VoiceInk（GPL v3）
- 點出 upstream 明確 stated「does not accept PRs」、這是 fork 存在的原因
- 沒有 ill will — upstream 做得很好、fork 只是個人需求 divergence

### License & Acknowledgments

- License: GPL v3 inherited
- Upstream credit (link)
- Dependencies list：保留上游 README 既有的 list（whisper.cpp / FluidAudio / Sparkle / KeyboardShortcuts / LaunchAtLogin / MediaRemoteAdapter / Zip / SelectedTextKit / Swift Atomics）

### Footer

- Maintained by [owner GitHub handle]
- Blog post：「TBD — will add link when published」（或留空）
- 不寫「Made with ❤️」這種 emotional flourish（跟 fork 的 factual tone 不一致）

## 5. 風格 / 規範

- **Language**: 英文為主；Taiwan-specific examples 可保留中文片段（例如：「跑完告訴我三個都過嗎」這類 owner 案例若引用）
- **長度**: 150-200 lines（不含 Acknowledgments）
- **Emoji**: 無（fork tone factual、跟 CLAUDE.md 一致）
- **Code blocks**: 標 `bash` / `swift` lang hint
- **Links**: 全部用 absolute URL（README 會被 GitHub web UI / `cat README.md` / 各種 viewer 看）
- **不引用私人 Linear**：所有 per-improvement deep dive 統一指向 `FORK-CHANGES.md` 的 anchor sections（`#1-privacy-hud` / `#2-traditional-chinese-tuning` / `#3-build-from-source-by-default` / `#4-simulate-typing-mode` / `#5-gpl-v3-forever`）
- **Section headers**: H2 (`##`) for top-level, H3 (`###`) for sub-sections inside "What this fork adds"

## 6. GitHub repo metadata 同步調整

實作階段用 `gh repo edit opass/VoiceTwInk` 一次設好：

| 欄位 | 目前 | 改成 |
|---|---|---|
| Description | "A fork of VoiceInk with a Taiwanese twist." | "Privacy-auditable VoiceInk fork tuned for Traditional Chinese (Taiwan) voice input on macOS." |
| Homepage URL | `https://tryvoiceink.com`（上游 — 誤導） | 留空 |
| Topics | 無 | `macos`, `voice-input`, `voice-to-text`, `whisper`, `traditional-chinese`, `privacy`, `swift`, `gpl-v3` |

## 7. 不在範圍內

- **Logo / icon 改動**：沿用上游 `VoiceInk/Assets.xcassets/AppIcon.appiconset/256-mac.png`（沒理由換、reduces upstream merge conflict）
- **BUILDING.md 改動**：上游 doc 仍然準確（build commands 跟上游同樣 work、Personal Team 細節 fork 已在 CLAUDE.md 補充）
- **CONTRIBUTING.md / CODE_OF_CONDUCT.md 改動**：仍然 reflect upstream policy，fork 沒不同 policy
- **新建 separate marketing site**：blog 是 owner 個人的，不在 repo
- **截圖 / 影片**：先不放（保持簡潔；之後 blog 寫完可以加 link）
- **Release 機制**：fork 不發 GitHub release（owner 個人 rebuild、不維護 versioned binary）

## 8. 風險 / Trade-off

- **上游 merge 衝突風險**：上游 README 之後更動，merge `git merge upstream/main` 會在 README.md 衝突。預期 — 接受、手動解
- **5 個改進子段落需要保持與 `FORK-CHANGES.md` 同步**：FORK-CHANGES.md 是 source of truth、README 是 summary。對應：FORK-CHANGES 改了 README 通常不用動（只引 anchor）；只有 anchor 改名才要 README 跟著動
- **Owner 寫的 blog 上線後 README footer 要回填 link**：實作階段先留 TBD、blog 上線時補

## 9. Acceptance criteria

- [ ] `README.md`（英）重寫完成，符合上述結構
- [ ] `README.zh-TW.md`（繁中）完成，內容對齊英文版但 prose 自然台灣口語
- [ ] 兩檔頂端 language switcher 互連
- [ ] 移除所有上游 marketing 連結（Download Now button、tryvoiceink.com、YouTube）
- [ ] 移除 `brew install --cask voiceink` 建議
- [ ] 保留上游 Acknowledgments 段落（dependencies + GPL credit）
- [ ] Privacy posture 段落準確（與 CLAUDE.md audit 段落一致）
- [ ] GitHub repo description / homepage / topics 設好
- [ ] Owner review README prose 通過後 commit + push

---

## 10. 概要

> 完整重寫 `README.md` 從上游 boilerplate 變成 fork-specific positioning。Approach B（feature-diff-first）：Hero → TL;DR → 5 個改進子段落（含 Privacy HUD / 繁中 / build / Simulate Typing / GPL）→ Privacy posture summary 表 → Build & first-run → 繁中使用者推薦設定 → Status & scope → Upstream credit → License & Acknowledgments。150-200 lines、英文為主、無 emoji、factual tone。同步用 `gh repo edit` 更新 GitHub repo description / homepage / topics。Owner blog 上線後 footer 補 link。
