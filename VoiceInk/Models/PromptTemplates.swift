import Foundation

struct TemplatePrompt: Identifiable {
    let id: UUID
    let title: String
    let promptText: String
    let icon: PromptIcon
    let description: String
    
    func toCustomPrompt() -> CustomPrompt {
        CustomPrompt(
            id: UUID(),  // Generate new UUID for custom prompt
            title: title,
            promptText: promptText,
            icon: icon,
            description: description,
            isPredefined: false
        )
    }
}

enum PromptTemplates {
    static var all: [TemplatePrompt] {
        createTemplatePrompts()
    }
    
    
    static func createTemplatePrompts() -> [TemplatePrompt] {
        [
            TemplatePrompt(
                id: UUID(),
                title: "System Default",
                promptText: """
                    [VERBATIM MODE - Preserve every sentence the speaker said]

                    PRIMARY DIRECTIVE: The speaker is dictating raw thoughts. Your job is to clean up disfluencies only, NOT to summarize, rephrase, or restructure. The output should read like a faithful transcription of what was actually said, just without verbal noise.

                    PRESERVE (do NOT drop, merge, or rephrase):
                    - Every substantive sentence, even if redundant or restated differently
                    - Thinking-aloud phrases: "讓我想想", "我想想看", "我覺得", "其實", "等一下", "let me think", "actually", "you know", "I mean"
                    - Verbal repetitions used for emphasis: "對對對", "yes yes yes", "好好好"
                    - Hedges and qualifiers: "可能", "也許", "大概", "maybe", "kind of", "sort of"
                    - Original sentence boundaries — do NOT merge two sentences into one

                    REMOVE (only these):
                    - Pure micro-fillers with no semantic content: 嗯, 呃, 喔, 啊, um, uh, er, ah
                    - Literal stutters where the SAME word repeats with no pause-meaning: "我我我覺得" → "我覺得". Note: "對對對" is emphasis, not stutter — KEEP it.
                    - Self-correction COMMANDS that explicitly instruct removal of prior content: "刪掉剛剛那句", "刪掉剛才講的", "重新講", "wait scratch that", "actually no let me restart", "I mean", "no wait", "sorry not that" → When you see one, remove the SPECIFIC content the speaker is correcting, AND remove the command phrase itself.

                    ALLOWED (representation-level only, not content):
                    - Convert spoken numbers to numerals ('five' → '5', '三個' → '3 個', '五百塊' → '$500')
                    - Apply smart punctuation ('vs' → 'vs.', 'eg' → 'e.g.', 'etc' → 'etc.')
                    - When the speaker uses English technical terms or code identifiers (React, useState, npm install, git rebase, file paths), preserve them EXACTLY as said. Do not auto-correct capitalization or spelling. EXCEPTION: if a term in <CUSTOM_VOCABULARY> matches phonetically, use the vocabulary spelling.

                    DO NOT:
                    - Restructure into "2-4 sentence paragraphs" — preserve speaker's natural rhythm
                    - Translate, rephrase, or improve word choice
                    - Add information, explanations, or section headings
                    - Format as a list unless the speaker explicitly said "first... second... third..."

                    OUTPUT FORMAT:
                    - Keep paragraph breaks where the speaker paused noticeably or said "new line" / "new paragraph" / "換行" / "換段"
                    - Otherwise output as one continuous paragraph matching speech flow
                    """,
                icon: "checkmark.seal.fill",
                description: "Verbatim transcription — preserve every sentence"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Summary",
                promptText: """
                    [SUMMARY MODE - Cleanup with minimum compression]

                    PRIMARY DIRECTIVE: Smooth the speaker's speech into readable text WITHOUT condensing ideas. The speaker's content, tone, and the LENGTH itself carry information. If output is < 70% of input length, you are over-summarizing.

                    OUTPUT TARGET: Preserve approximately 80% of the speaker's distinct sentences or propositions. The speaker may have said something seemingly "obvious" — keep it. They said it for a reason.

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
                    - LOCAL REORDERING: move a clarification next to what it clarifies, group related side-remarks together. OK.

                    DO NOT:
                    - Drop a complete proposition even if it seems redundant
                    - HIGH-LEVEL RESTRUCTURE: do NOT rearrange the overall argument flow or topic ordering
                    - Use synonyms unnecessarily
                    - Bullet-ify unless speaker said "first, second, third"
                    - Restructure into multiple paragraphs unless speaker had clear topic shifts
                    """,
                icon: "doc.text",
                description: "Light cleanup, ≥80% sentence retention"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Chat",
                promptText: """
                    - Rewrite the <TRANSCRIPT> text as a chat message: informal, concise, and conversational.
                    - Keep emotive markers and emojis if present; don't invent new ones.
                    - Lightly fix grammar, remove fillers and repeated words, and improve flow without changing meaning.
                    - Keep the original tone; only be professional if the <TRANSCRIPT> already is.
                    - Automatically detect and format lists properly: if the <TRANSCRIPT> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                    - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                    - Format like a modern chat message - short lines, natural breaks, emoji-friendly.
                    - Do not add greetings, sign-offs, or commentary.
                    - Output only the chat message.
                    - Don't add any information not available in the <TRANSCRIPT> text ever.
                    """,
                icon: "bubble.left.and.bubble.right.fill",
                description: "Casual chat-style formatting"
            ),
            
            TemplatePrompt(
                id: UUID(),
                title: "Email",
                promptText: """
                    - Rewrite the <TRANSCRIPT> text as a complete email with proper formatting: include a greeting (Hi), body paragraphs (2-4 sentences each), and closing (Thanks).
                    - Use clear, friendly, non-formal language unless the <TRANSCRIPT> is clearly professional—in that case, match that tone.
                    - Improve flow and coherence; fix grammar and spelling; remove fillers; keep all facts, names, dates, and action items.
                    - Automatically detect and format lists properly: if the <TRANSCRIPT> mentions a number (e.g., "3 things", "5 items"), uses ordinal words (first, second, third), implies sequence or steps, or has a count before it, format as an ordered list; otherwise, format as an unordered list.
                    - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                    - Do not invent new content, but structure it as a proper email format.
                    - Don't add any information not available in the <TRANSCRIPT> text ever.
                    """,
                icon: "envelope.fill",
                description: "Professional email formatting"
            ),
            TemplatePrompt(
                id: UUID(),
                title: "Rewrite",
                promptText: """
                    - Rewrite the <TRANSCRIPT> text with enhanced clarity, improved sentence structure, and rhythmic flow while preserving the original meaning and tone.
                    - Restructure sentences for better readability and natural progression.
                    - Improve word choice and phrasing where appropriate, but maintain the original voice and intent.
                    - Fix grammar and spelling errors, remove fillers and stutters, and collapse repetitions.
                    - Format any lists as proper bullet points or numbered lists.
                    - Write numbers as numerals (e.g., 'five' → '5', 'twenty dollars' → '$20').
                    - Organize content into well-structured paragraphs of 2–4 sentences for optimal readability.
                    - Preserve all names, numbers, dates, facts, and key information exactly as they appear.
                    - Do not add explanations, labels, metadata, or instructions.
                    - Output only the rewritten text.
                    - Don't add any information not available in the <TRANSCRIPT> text ever.
                    """,
                icon: "pencil.circle.fill",
                description: "Rewrites with better clarity."
            )
        ]
    }
}
