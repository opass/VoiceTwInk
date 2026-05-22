import Testing
import Foundation
@testable import VoiceInk

@Suite("PrivacyDestination") struct PrivacyDestinationTests {
    @Test("Anthropic URL is classified cloud")
    func anthropicIsCloud() {
        let dest = PrivacyDestination.detect(
            providerLabel: "Claude",
            baseURL: URL(string: "https://api.anthropic.com")!
        )
        #expect(dest == .cloud(providerLabel: "Claude"))
    }

    @Test("OpenAI URL is classified cloud")
    func openaiIsCloud() {
        let dest = PrivacyDestination.detect(
            providerLabel: "OpenAI",
            baseURL: URL(string: "https://api.openai.com")!
        )
        #expect(dest == .cloud(providerLabel: "OpenAI"))
    }

    @Test("Ollama localhost is classified local")
    func ollamaIsLocal() {
        let dest = PrivacyDestination.detect(
            providerLabel: "Ollama",
            baseURL: URL(string: "http://localhost:11434")!
        )
        #expect(dest == .local(providerLabel: "Ollama"))
    }

    @Test("127.0.0.1 is classified local")
    func ipv4LocalhostIsLocal() {
        let dest = PrivacyDestination.detect(
            providerLabel: "Custom",
            baseURL: URL(string: "http://127.0.0.1:8080")!
        )
        #expect(dest == .local(providerLabel: "Custom"))
    }

    @Test("IPv6 loopback [::1] is classified local")
    func ipv6LocalhostIsLocal() {
        let dest = PrivacyDestination.detect(
            providerLabel: "Ollama",
            baseURL: URL(string: "http://[::1]:11434")!
        )
        #expect(dest == .local(providerLabel: "Ollama"))
    }

    @Test("Custom remote URL with localhost suffix is still cloud")
    func cloudHostWithLocalhostInName() {
        let dest = PrivacyDestination.detect(
            providerLabel: "Custom",
            baseURL: URL(string: "https://localhost-proxy.example.com")!
        )
        #expect(dest == .cloud(providerLabel: "Custom"))
    }
}
