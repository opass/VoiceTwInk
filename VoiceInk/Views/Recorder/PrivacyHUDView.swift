import SwiftUI

/// Visual rendering of the PrivacyPayload. Pure presentation — no business logic.
/// Each ContextField is rendered as a single row; .disabled and .empty cases are
/// not rendered at all so the HUD shrinks naturally when fields are absent.
struct PrivacyHUDView: View {
    let payload: PrivacyPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            renderField(name: "Selected", icon: "✂️", field: payload.selectedText) { text in
                truncate(text, max: 50)
            }
            renderField(name: "Clipboard", icon: "📋", field: payload.clipboard) { text in
                truncate(text, max: 50)
            }
            renderField(name: "Screen", icon: "🖥", field: payload.screenContext) { val in
                truncate(val.extractedText, max: 50)
            }
            renderField(name: "Vocab", icon: "📚", field: payload.customVocabulary) { text in
                truncate(text, max: 50)
            }
            renderField(name: "Time", icon: "🕐", field: payload.systemContext) { val in
                "\(val.dayOfWeek) \(formatTime(val.timestamp)) (\(val.timezone))"
            }

            Divider().opacity(0.4)
            destinationFooter
        }
        .padding(10)
        .background(backgroundColor)
        .cornerRadius(10)
        .shadow(radius: 4)
        .frame(maxWidth: 280)
    }

    // MARK: - Field row

    @ViewBuilder
    private func renderField<T>(
        name: String,
        icon: String,
        field: ContextField<T>,
        valueFormatter: (T) -> String
    ) -> some View {
        switch field {
        case .disabled, .empty:
            EmptyView()                                 // hide row entirely
        case .pending:
            HStack(spacing: 6) {
                Text(icon).font(.system(size: 12))
                Text(name).font(.system(size: 11, weight: .semibold))
                Text("identifying...").font(.system(size: 11)).opacity(0.6)
                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
            }
        case .omitted:
            HStack(spacing: 6) {
                Text(icon).font(.system(size: 12)).opacity(0.5)
                Text(name).font(.system(size: 11, weight: .semibold)).opacity(0.5)
                Text("omitted (timing)").font(.system(size: 11)).italic().opacity(0.5)
            }
        case .present(let value):
            HStack(spacing: 6) {
                Text(icon).font(.system(size: 12))
                Text(name).font(.system(size: 11, weight: .semibold))
                Text(valueFormatter(value))
                    .font(.system(size: 11, design: .monospaced))
                    .opacity(0.8)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Destination footer

    private var destinationFooter: some View {
        HStack(spacing: 6) {
            Text("→ Sending to:")
                .font(.system(size: 10))
                .opacity(0.7)
            Text(destinationText)
                .font(.system(size: 10, weight: .semibold))
            Text(destinationIcon)
                .font(.system(size: 10))
        }
    }

    private var destinationText: String {
        switch payload.destination {
        case .local(let label): return "\(label) (local)"
        case .cloud(let label): return "\(label) (cloud)"
        }
    }

    private var destinationIcon: String {
        switch payload.destination {
        case .local: return "🟢"
        case .cloud: return "🟡"
        }
    }

    private var backgroundColor: Color {
        switch payload.destination {
        case .local: return Color(red: 0.85, green: 0.95, blue: 0.85).opacity(0.95)
        case .cloud: return Color(red: 1.0, green: 0.92, blue: 0.65).opacity(0.95)
        }
    }

    // MARK: - Helpers

    private func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        return String(s.prefix(max)) + "..."
    }

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
