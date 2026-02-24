import SwiftUI
import AppKit

// MARK: - Console View

struct ConsoleView: View {
    let output: String
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Console Output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear console")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)

            Divider()

            // Terminal text view
            ConsoleTextRepresentable(text: output)
        }
    }
}

// MARK: - NSViewRepresentable for NSTextView

/// High-performance console text display using NSTextView.
/// Tracks previous content length to efficiently append-only new text,
/// avoiding full re-render on every update.
struct ConsoleTextRepresentable: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
        textView.textColor = NSColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1.0)
        textView.insertionPointColor = NSColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1.0)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.drawsBackground = true

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let newLength = text.count
        let prevLength = context.coordinator.previousLength

        if newLength > prevLength && prevLength > 0 {
            // Efficient append: only add the new content
            let startIdx = text.index(text.startIndex, offsetBy: prevLength)
            let newContent = String(text[startIdx...])
            let wasAtBottom = isNearBottom(scrollView)

            textView.textStorage?.append(NSAttributedString(
                string: newContent,
                attributes: Self.textAttributes
            ))

            if wasAtBottom {
                textView.scrollToEndOfDocument(nil)
            }
        } else if newLength != prevLength {
            // Content was cleared, truncated, or set for the first time
            let attrString = NSAttributedString(string: text, attributes: Self.textAttributes)
            textView.textStorage?.setAttributedString(attrString)
            textView.scrollToEndOfDocument(nil)
        }

        context.coordinator.previousLength = newLength
    }

    // MARK: - Helpers

    private static let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1.0)
    ]

    private func isNearBottom(_ scrollView: NSScrollView) -> Bool {
        let clipView = scrollView.contentView
        let docHeight = scrollView.documentView?.frame.height ?? 0
        let clipHeight = clipView.bounds.height
        let scrollY = clipView.bounds.origin.y
        return scrollY >= docHeight - clipHeight - 50
    }

    // MARK: - Coordinator

    class Coordinator {
        var textView: NSTextView?
        var scrollView: NSScrollView?
        var previousLength: Int = 0
    }
}
