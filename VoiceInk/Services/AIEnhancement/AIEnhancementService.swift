import Foundation
import SwiftData
import AppKit
import os
import LLMkit

enum EnhancementPrompt {
    case transcriptionEnhancement
    case aiAssistant
}

@MainActor
class AIEnhancementService: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AIEnhancementService")

    /// Shared formatter for <SYSTEM_CONTEXT> ISO timestamps. `ISO8601DateFormatter`'s
    /// date-to-string path is thread-safe, so reusing one instance avoids per-call allocation.
    private static let iso8601Formatter = ISO8601DateFormatter()

    @Published var isEnhancementEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnhancementEnabled, forKey: "isAIEnhancementEnabled")
            if isEnhancementEnabled && selectedPromptId == nil {
                selectedPromptId = customPrompts.first?.id
            }
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .enhancementToggleChanged, object: nil)
        }
    }

    @Published var useClipboardContext: Bool {
        didSet {
            UserDefaults.standard.set(useClipboardContext, forKey: "useClipboardContext")
        }
    }

    @Published var useScreenCaptureContext: Bool {
        didSet {
            UserDefaults.standard.set(useScreenCaptureContext, forKey: "useScreenCaptureContext")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @Published var useSelectedTextContext: Bool {
        didSet {
            UserDefaults.standard.set(useSelectedTextContext, forKey: "useSelectedTextContext")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @Published var useCustomVocabularyContext: Bool {
        didSet {
            UserDefaults.standard.set(useCustomVocabularyContext, forKey: "useCustomVocabularyContext")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @Published var customPrompts: [CustomPrompt] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customPrompts) {
                UserDefaults.standard.set(encoded, forKey: "customPrompts")
            }
        }
    }

    @Published var selectedPromptId: UUID? {
        didSet {
            UserDefaults.standard.set(selectedPromptId?.uuidString, forKey: "selectedPromptId")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .promptSelectionChanged, object: nil)
        }
    }

    @Published var lastSystemMessageSent: String?
    @Published var lastUserMessageSent: String?

    var activePrompt: CustomPrompt? {
        allPrompts.first { $0.id == selectedPromptId }
    }

    var allPrompts: [CustomPrompt] {
        return customPrompts
    }

    private let aiService: AIService
    private let screenCaptureService: ScreenCaptureService
    private let customVocabularyService: CustomVocabularyService
    private var baseTimeout: TimeInterval {
        let stored = UserDefaults.standard.integer(forKey: "EnhancementTimeoutSeconds")
        return stored > 0 ? TimeInterval(stored) : 7
    }
    private let rateLimitInterval: TimeInterval = 1.0
    private var lastRequestTime: Date?
    private let modelContext: ModelContext
    
    @Published var lastCapturedClipboard: String?
    @Published var lastCapturedSelectedText: String?
    @Published var lastCapturedVocabulary: String?
    @Published var lastCapturedSystemContext: SystemContextValue?

    @Published var currentPrivacyPayload: PrivacyPayload?

    init(aiService: AIService = AIService(), modelContext: ModelContext) {
        self.aiService = aiService
        self.modelContext = modelContext
        self.screenCaptureService = ScreenCaptureService()
        self.customVocabularyService = CustomVocabularyService.shared

        self.isEnhancementEnabled = UserDefaults.standard.bool(forKey: "isAIEnhancementEnabled")
        self.useClipboardContext = UserDefaults.standard.bool(forKey: "useClipboardContext")
        self.useScreenCaptureContext = UserDefaults.standard.bool(forKey: "useScreenCaptureContext")
        // Default ON to match upstream behaviour (selected text was always sent if AX granted)
        self.useSelectedTextContext = UserDefaults.standard.object(forKey: "useSelectedTextContext") as? Bool ?? true
        // Default ON to match upstream behaviour (vocabulary was always sent if non-empty)
        self.useCustomVocabularyContext = UserDefaults.standard.object(forKey: "useCustomVocabularyContext") as? Bool ?? true
        if let savedPromptsData = UserDefaults.standard.data(forKey: "customPrompts"),
           let decodedPrompts = try? JSONDecoder().decode([CustomPrompt].self, from: savedPromptsData) {
            self.customPrompts = decodedPrompts
        } else {
            self.customPrompts = []
        }

        if let savedPromptId = UserDefaults.standard.string(forKey: "selectedPromptId") {
            self.selectedPromptId = UUID(uuidString: savedPromptId)
        }

        if isEnhancementEnabled && (selectedPromptId == nil || !allPrompts.contains(where: { $0.id == selectedPromptId })) {
            self.selectedPromptId = allPrompts.first?.id
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChange),
            name: .aiProviderKeyChanged,
            object: nil
        )

        initializePredefinedPrompts()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAPIKeyChange() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            if !self.aiService.isAPIKeyValid {
                self.isEnhancementEnabled = false
            }
        }
    }

    func getAIService() -> AIService? {
        return aiService
    }

    var isConfigured: Bool {
        aiService.isAPIKeyValid
    }

    private func waitForRateLimit() async throws {
        if let lastRequest = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < rateLimitInterval {
                try await Task.sleep(nanoseconds: UInt64((rateLimitInterval - timeSinceLastRequest) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }

    private func getSystemMessage(for mode: EnhancementPrompt) async -> String {
        // Selected text — read property first; fall back to on-demand fetch if HUD
        // coordinator never ran (defensive — keeps upstream behaviour as a safety net).
        let selectedTextContext: String = await {
            guard useSelectedTextContext else { return "" }
            guard AXIsProcessTrusted() else { return "" }
            // `??` would be cleaner but its right-hand autoclosure doesn't support
            // `await`, so fall back to an explicit if/else.
            let captured: String?
            if let cached = lastCapturedSelectedText {
                captured = cached
            } else {
                captured = await SelectedTextService.fetchSelectedText()
            }
            guard let text = captured, !text.isEmpty else { return "" }
            return "\n\n<CURRENTLY_SELECTED_TEXT>\n\(text)\n</CURRENTLY_SELECTED_TEXT>"
        }()

        let clipboardContext = if useClipboardContext,
                              let clipboardText = lastCapturedClipboard,
                              !clipboardText.isEmpty {
            "\n\n<CLIPBOARD_CONTEXT>\n\(clipboardText)\n</CLIPBOARD_CONTEXT>"
        } else {
            ""
        }

        let screenCaptureContext = if useScreenCaptureContext,
                                   let capturedText = screenCaptureService.lastCapturedText,
                                   !capturedText.isEmpty {
            "\n\n<CURRENT_WINDOW_CONTEXT>\n\(capturedText)\n</CURRENT_WINDOW_CONTEXT>"
        } else {
            ""
        }

        // Custom vocabulary — property first, fall back to on-demand
        let customVocabulary: String = {
            guard useCustomVocabularyContext else { return "" }
            if let cached = lastCapturedVocabulary { return cached }
            return customVocabularyService.getCustomVocabulary(from: modelContext)
        }()

        // System context (OPA-113) — no user toggle; low-sensitivity metadata always sent when captured
        let systemContextSection: String = {
            guard let sys = lastCapturedSystemContext else { return "" }
            let iso = Self.iso8601Formatter.string(from: sys.timestamp)
            return """


            <SYSTEM_CONTEXT>
            Current time: \(iso)
            Timezone: \(sys.timezone)
            Day of week: \(sys.dayOfWeek)
            Locale: \(sys.locale)
            </SYSTEM_CONTEXT>
            """
        }()

        let allContextSections = systemContextSection + selectedTextContext + clipboardContext + screenCaptureContext

        let customVocabularySection = if !customVocabulary.isEmpty {
            """


            The following are important vocabulary words, proper nouns, and technical terms. When these words or similar-sounding words appear in the <TRANSCRIPT>, ensure they are spelled EXACTLY as shown below:
            <CUSTOM_VOCABULARY>
            \(customVocabulary)
            </CUSTOM_VOCABULARY>
            """
        } else {
            ""
        }

        let finalContextSection = allContextSections + customVocabularySection

        if let activePrompt = activePrompt {
            if activePrompt.id == PredefinedPrompts.assistantPromptId {
                return activePrompt.promptText + finalContextSection
            } else {
                return activePrompt.finalPromptText + finalContextSection
            }
        } else {
            let defaultPrompt = allPrompts.first(where: { $0.id == PredefinedPrompts.defaultPromptId }) ?? allPrompts.first!
            return defaultPrompt.finalPromptText + finalContextSection
        }
    }

    private func makeRequest(text: String, mode: EnhancementPrompt) async throws -> String {
        guard isConfigured else {
            throw EnhancementError.notConfigured
        }

        guard !text.isEmpty else {
            return ""
        }

        let formattedText = "\n<TRANSCRIPT>\n\(text)\n</TRANSCRIPT>"
        let systemMessage = await getSystemMessage(for: mode)

        await MainActor.run {
            self.lastSystemMessageSent = systemMessage
            self.lastUserMessageSent = formattedText
        }

        if aiService.selectedProvider == .ollama {
            do {
                let result = try await aiService.enhanceWithOllama(
                    text: formattedText,
                    systemPrompt: systemMessage,
                    timeout: baseTimeout
                )
                return AIEnhancementOutputFilter.filter(result)
            } catch {
                if let localError = error as? LocalAIError {
                    switch localError {
                    case .timeout:
                        throw EnhancementError.timeout
                    default:
                        throw EnhancementError.customError(localError.errorDescription ?? "An unknown Ollama error occurred.")
                    }
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        if aiService.selectedProvider == .localCLI {
            do {
                let result = try await aiService.enhanceWithLocalCLI(systemPrompt: systemMessage, userPrompt: formattedText)
                return AIEnhancementOutputFilter.filter(result)
            } catch {
                if let localError = error as? LocalCLIError {
                    throw EnhancementError.customError(localError.errorDescription ?? "An unknown Local CLI error occurred.")
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        try await waitForRateLimit()

        do {
            let result: String
            switch aiService.selectedProvider {
            case .anthropic:
                result = try await AnthropicLLMClient.chatCompletion(
                    apiKey: aiService.apiKey,
                    model: aiService.currentModel,
                    messages: [.user(formattedText)],
                    systemPrompt: systemMessage,
                    timeout: baseTimeout
                )
            default:
                guard let baseURL = URL(string: aiService.selectedProvider.baseURL) else {
                    throw EnhancementError.customError("\(aiService.selectedProvider.rawValue) has an invalid API endpoint URL. Please update it in AI settings.")
                }
                let temperature = aiService.currentModel.lowercased().hasPrefix("gpt-5") ? 1.0 : 0.3
                let reasoningEffort = ReasoningConfig.getReasoningParameter(
                    for: aiService.selectedProvider,
                    modelName: aiService.currentModel
                )
                let extraBody = ReasoningConfig.getExtraBodyParameters(
                    for: aiService.selectedProvider,
                    modelName: aiService.currentModel
                )
                result = try await OpenAILLMClient.chatCompletion(
                    baseURL: baseURL,
                    apiKey: aiService.apiKey,
                    model: aiService.currentModel,
                    messages: [.user(formattedText)],
                    systemPrompt: systemMessage,
                    temperature: temperature,
                    reasoningEffort: reasoningEffort,
                    extraBody: extraBody,
                    timeout: baseTimeout
                )
            }
            return AIEnhancementOutputFilter.filter(result.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch let error as LLMKitError {
            throw mapLLMKitError(error)
        } catch let error as EnhancementError {
            throw error
        } catch {
            throw EnhancementError.customError(error.localizedDescription)
        }
    }

    private func mapLLMKitError(_ error: LLMKitError) -> EnhancementError {
        switch error {
        case .missingAPIKey:
            return .notConfigured
        case .httpError(let statusCode, let message):
            if statusCode == 429 { return .rateLimitExceeded }
            if (500...599).contains(statusCode) { return .serverError }
            return .customError("HTTP \(statusCode): \(message)")
        case .noResultReturned:
            return .enhancementFailed
        case .networkError:
            return .networkError
        case .timeout:
            return .timeout
        case .invalidURL, .decodingError, .encodingError:
            return .customError(error.localizedDescription ?? "An unknown error occurred.")
        }
    }

    private var retryOnTimeout: Bool {
        UserDefaults.standard.bool(forKey: "EnhancementRetryOnTimeout")
    }

    private func makeRequestWithRetry(text: String, mode: EnhancementPrompt, maxRetries: Int = 3, initialDelay: TimeInterval = 1.0) async throws -> String {
        var retries = 0
        var currentDelay = initialDelay

        while retries < maxRetries {
            do {
                return try await makeRequest(text: text, mode: mode)
            } catch let error as EnhancementError {
                switch error {
                case .networkError, .serverError, .rateLimitExceeded:
                    retries += 1
                    if retries < maxRetries {
                        logger.warning("Request failed, retrying in \(currentDelay, privacy: .public)s... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Request failed after \(maxRetries, privacy: .public) retries.")
                        throw error
                    }
                case .timeout:
                    if retryOnTimeout {
                        retries += 1
                        if retries < maxRetries {
                            logger.warning("Request timed out, retrying immediately... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        } else {
                            logger.error("Request timed out after \(maxRetries, privacy: .public) retries.")
                            throw error
                        }
                    } else {
                        logger.error("Request timed out, failing immediately (retry disabled).")
                        throw error
                    }
                default:
                    throw error
                }
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost].contains(nsError.code) {
                    retries += 1
                    if retries < maxRetries {
                        logger.warning("Request failed with network error, retrying in \(currentDelay, privacy: .public)s... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Request failed after \(maxRetries, privacy: .public) retries with network error.")
                        throw EnhancementError.networkError
                    }
                } else {
                    throw error
                }
            }
        }

        throw EnhancementError.enhancementFailed
    }

    func enhance(_ text: String) async throws -> (String, TimeInterval, String?) {
        let startTime = Date()
        let enhancementPrompt: EnhancementPrompt = .transcriptionEnhancement
        let promptName = activePrompt?.title

        do {
            let result = try await makeRequestWithRetry(text: text, mode: enhancementPrompt)
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            return (result, duration, promptName)
        } catch {
            throw error
        }
    }

    func captureScreenContext() async {
        guard CGPreflightScreenCaptureAccess() else {
            return
        }

        if let capturedText = await screenCaptureService.captureAndExtractText() {
            await MainActor.run {
                self.objectWillChange.send()
            }
        }
    }

    func captureClipboardContext() {
        lastCapturedClipboard = NSPasteboard.general.string(forType: .string)
    }

    func captureSelectedTextContext() async {
        guard AXIsProcessTrusted() else {
            lastCapturedSelectedText = nil
            return
        }
        lastCapturedSelectedText = await SelectedTextService.fetchSelectedText()
    }

    func captureVocabularyContext() {
        let vocab = customVocabularyService.getCustomVocabulary(from: modelContext)
        lastCapturedVocabulary = vocab.isEmpty ? nil : vocab
    }

    func captureSystemContext() {
        let now = Date()
        let calendar = Calendar.current
        let weekdayIndex = calendar.component(.weekday, from: now) - 1
        let weekday = calendar.weekdaySymbols[weekdayIndex]
        lastCapturedSystemContext = SystemContextValue(
            timestamp: now,
            timezone: TimeZone.current.identifier,
            dayOfWeek: weekday,
            locale: Locale.current.identifier
        )
    }

    func clearCapturedContexts() {
        lastCapturedClipboard = nil
        lastCapturedSelectedText = nil
        lastCapturedVocabulary = nil
        lastCapturedSystemContext = nil
        screenCaptureService.lastCapturedText = nil
    }

    /// Compose a PrivacyPayload from current captured state + toggle state + destination.
    /// Called at record-start after all capture methods have fired and again whenever
    /// async OCR completes (so the screenContext field transitions pending → present).
    func assemblePrivacyPayload() {
        let selectedField: ContextField<String> = {
            guard useSelectedTextContext else { return .disabled }
            guard AXIsProcessTrusted() else { return .disabled }
            guard let text = lastCapturedSelectedText, !text.isEmpty else { return .empty }
            return .present(text)
        }()

        let clipboardField: ContextField<String> = {
            guard useClipboardContext else { return .disabled }
            guard let text = lastCapturedClipboard, !text.isEmpty else { return .empty }
            return .present(text)
        }()

        let screenField: ContextField<ScreenContextValue> = {
            guard useScreenCaptureContext else { return .disabled }
            guard CGPreflightScreenCaptureAccess() else { return .disabled }
            // ScreenCaptureService.lastCapturedText stores a single string blob
            // ("Active Window: ...\nApplication: ...\nWindow Content: ...\n<ocr text>").
            // Splitting into structured (windowTitle, appName, extractedText) is a
            // follow-up; for now, preserve the raw string in extractedText so the
            // HUD has something to display.
            // NOTE: This reads ScreenCaptureService.lastCapturedText, which captureScreenContext()
            // writes as a side effect. If captureAndExtractText() ever stops storing into
            // lastCapturedText, screenField would silently stay .pending — keep this coupling
            // in mind when refactoring ScreenCaptureService.
            guard let raw = screenCaptureService.lastCapturedText, !raw.isEmpty else { return .pending }
            return .present(parseScreenCaptureRaw(raw))
        }()

        let vocabField: ContextField<String> = {
            guard useCustomVocabularyContext else { return .disabled }
            guard let v = lastCapturedVocabulary, !v.isEmpty else { return .empty }
            return .present(v)
        }()

        let systemField: ContextField<SystemContextValue> = {
            // Intentional asymmetry: system context (time / timezone / locale) has no user
            // toggle. It's low-sensitivity metadata always sent when capture has run; if a
            // future use case needs an opt-out, add a useSystemContext toggle here and gate
            // with the same .disabled pattern as the other fields.
            guard let sys = lastCapturedSystemContext else { return .empty }
            return .present(sys)
        }()

        let destination = determinePrivacyDestination()

        // Use SystemContextValue.timestamp as the payload timestamp so both
        // fields refer to the same captured instant.
        currentPrivacyPayload = PrivacyPayload(
            timestamp: lastCapturedSystemContext?.timestamp ?? Date(),
            transcript: .recording,
            selectedText: selectedField,
            clipboard: clipboardField,
            screenContext: screenField,
            customVocabulary: vocabField,
            systemContext: systemField,
            destination: destination
        )
    }

    /// Classify the currently selected LLM provider as local or cloud for HUD display.
    private func determinePrivacyDestination() -> PrivacyDestination {
        let providerLabel = privacyProviderLabel()
        let baseURL = privacyProviderBaseURL()
        return PrivacyDestination.detect(providerLabel: providerLabel, baseURL: baseURL)
    }

    /// Friendly label for the current provider (used in the HUD footer).
    /// AIProvider.rawValue is already the human-readable name (e.g., "Anthropic", "Ollama",
    /// "Local CLI"), so no extra property is needed on AIService.
    private func privacyProviderLabel() -> String {
        return aiService.selectedProvider.rawValue
    }

    /// Base URL of the currently selected provider — used for local/cloud detection.
    /// AIProvider.baseURL returns a String; convert to URL here. Local CLI has an empty
    /// baseURL, which we treat as local by falling back to localhost.
    private func privacyProviderBaseURL() -> URL {
        let provider = aiService.selectedProvider
        // localCLI has no network URL at all — treat as local
        if provider == .localCLI {
            return URL(string: "http://localhost")!
        }
        let rawURL = provider.baseURL
        return URL(string: rawURL) ?? URL(string: "http://localhost")!
    }

    /// Parses the string format produced by ScreenCaptureService.captureAndExtractText():
    ///   "Active Window: <title>\nApplication: <app>\n\nWindow Content:\n<ocr>"
    /// Returns the structured ScreenContextValue with windowTitle / appName / extractedText
    /// split apart. Falls back to dumping the whole raw into extractedText if the format
    /// doesn't match (defensive).
    private func parseScreenCaptureRaw(_ raw: String) -> ScreenContextValue {
        let lines = raw.components(separatedBy: "\n")
        var windowTitle = ""
        var appName = ""
        var contentStartIndex: Int? = nil

        for (i, line) in lines.enumerated() {
            if line.hasPrefix("Active Window: ") {
                windowTitle = String(line.dropFirst("Active Window: ".count))
            } else if line.hasPrefix("Application: ") {
                appName = String(line.dropFirst("Application: ".count))
            } else if line == "Window Content:" {
                contentStartIndex = i + 1
                break
            }
        }

        let extractedText: String
        if let start = contentStartIndex, start < lines.count {
            extractedText = lines[start..<lines.count].joined(separator: "\n")
        } else {
            // Unexpected format — keep raw so we don't lose information
            extractedText = raw
        }

        return ScreenContextValue(
            windowTitle: windowTitle,
            appName: appName,
            extractedText: extractedText
        )
    }

    func clearPrivacyPayload() {
        currentPrivacyPayload = nil
        clearCapturedContexts()
    }

    func addPrompt(title: String, promptText: String, icon: PromptIcon = "doc.text.fill", description: String? = nil, triggerWords: [String] = [], useSystemInstructions: Bool = true) {
        let newPrompt = CustomPrompt(title: title, promptText: promptText, icon: icon, description: description, isPredefined: false, triggerWords: triggerWords, useSystemInstructions: useSystemInstructions)
        customPrompts.append(newPrompt)
        if customPrompts.count == 1 {
            selectedPromptId = newPrompt.id
        }
    }

    func updatePrompt(_ prompt: CustomPrompt) {
        if let index = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
            customPrompts[index] = prompt
        }
    }

    func deletePrompt(_ prompt: CustomPrompt) {
        customPrompts.removeAll { $0.id == prompt.id }
        if selectedPromptId == prompt.id {
            selectedPromptId = allPrompts.first?.id
        }
    }

    func setActivePrompt(_ prompt: CustomPrompt) {
        selectedPromptId = prompt.id
    }

    /// Upsert predefined prompts by UUID (preserving user state like triggerWords/isActive),
    /// then reorder so predefined prompts appear in source order, with user-created prompts
    /// appended after. Idempotent: safe to run on every launch.
    private func initializePredefinedPrompts() {
        let predefinedTemplates = PredefinedPrompts.createDefaultPrompts()
        let predefinedUUIDs = Set(predefinedTemplates.map { $0.id })

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

        let orderedPredefined = predefinedTemplates.compactMap { upserted[$0.id] }
        let userCreated = customPrompts.filter { !predefinedUUIDs.contains($0.id) }
        customPrompts = orderedPredefined + userCreated
    }
}

enum EnhancementError: Error {
    case notConfigured
    case invalidResponse
    case enhancementFailed
    case networkError
    case serverError
    case rateLimitExceeded
    case timeout
    case customError(String)
}

extension EnhancementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI provider not configured. Please check your API key."
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .enhancementFailed:
            return "AI enhancement failed to process the text."
        case .networkError:
            return "Network connection failed. Check your internet."
        case .serverError:
            return "The AI provider's server encountered an error. Please try again later."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .timeout:
            return "Enhancement request timed out. Check your connection or increase the timeout duration."
        case .customError(let message):
            return message
        }
    }
}
