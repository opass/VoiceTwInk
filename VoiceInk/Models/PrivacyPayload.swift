import Foundation

/// The single snapshot of everything about to be sent to the LLM at this moment.
struct PrivacyPayload: Equatable {
    let timestamp: Date
    let transcript: TranscriptState
    let selectedText: ContextField<String>
    let clipboard: ContextField<String>
    let screenContext: ContextField<ScreenContextValue>
    let customVocabulary: ContextField<String>
    let systemContext: ContextField<SystemContextValue>
    let destination: PrivacyDestination
}

enum TranscriptState: Equatable {
    case recording
    case finished(String)
}

/// Five-state semantics for any single field that may or may not be in the outgoing payload.
enum ContextField<T: Equatable>: Equatable {
    /// Global toggle is off, or permission is denied.
    case disabled
    /// Toggle on but content is empty (no selection, empty clipboard, empty vocab).
    case empty
    /// Async capture in progress (only screen OCR uses this in practice).
    case pending
    /// Was pending; release happened before capture finished.
    case omitted
    /// Has a value that will be sent.
    case present(T)
}

struct ScreenContextValue: Equatable {
    let windowTitle: String
    let appName: String
    let extractedText: String
}

struct SystemContextValue: Equatable {
    let timestamp: Date
    let timezone: String
    let dayOfWeek: String
    let locale: String
}

enum PrivacyDestination: Equatable {
    case local(providerLabel: String)
    case cloud(providerLabel: String)

    /// Classify a destination by its base URL host. localhost / 127.0.0.1 / ::1 → local.
    static func detect(providerLabel: String, baseURL: URL) -> PrivacyDestination {
        let host = baseURL.host?.lowercased() ?? ""
        let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "0.0.0.0"]
        if localHosts.contains(host) {
            return .local(providerLabel: providerLabel)
        }
        return .cloud(providerLabel: providerLabel)
    }
}
