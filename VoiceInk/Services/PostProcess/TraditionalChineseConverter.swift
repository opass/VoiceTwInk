import Foundation
import OpenCC

/// Converts simplified Chinese characters to Traditional Chinese (Taiwan) using
/// OpenCC's s2twp profile (`.traditionalize + .TWStandard + .TWIdiom`).
/// English / non-CJK content passes through untouched.
///
/// Deterministic safety net beneath the prompt-level `[CRITICAL LANGUAGE RULE]` —
/// the LLM may still emit simplified characters on short utterances (see OPA-117
/// spike); this converter catches them before the text reaches history / paste.
///
/// Gated by the `useTraditionalChineseConversion` UserDefault (default true).
/// On init failure (dictionary missing, etc.), `convert(_:)` is a no-op —
/// fail open rather than break the paste pipeline.
@MainActor
final class TraditionalChineseConverter {
    static let shared = TraditionalChineseConverter()

    private let converter: ChineseConverter?

    private init() {
        do {
            self.converter = try ChineseConverter(option: [.traditionalize, .TWStandard, .TWIdiom])
        } catch {
            self.converter = nil
        }
    }

    /// Returns the input unchanged if the conversion is disabled or the
    /// converter failed to initialize. Otherwise returns simplified→traditional
    /// (Taiwan, with phrase substitution e.g., 软件 → 軟體).
    func convert(_ text: String) -> String {
        guard UserDefaults.standard.bool(forKey: "useTraditionalChineseConversion") else {
            return text
        }
        guard let converter else { return text }
        return converter.convert(text)
    }
}
