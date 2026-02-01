import AppKit
import SwiftUI

private enum SnippetEditorMode {
    case new
    case edit(Snippet)
}

struct SnippetsView: View {
    @State private var snippetStore = SnippetStore.shared
    @State private var isShowingEditor = false
    @State private var editorMode: SnippetEditorMode = .new
    @State private var draft = SnippetDraft.empty()

    var body: some View {
        @Bindable var snippetStore = snippetStore

        Form {
            Section {
                if snippetStore.snippets.isEmpty {
                    Text("No snippets yet. Add one to expand voice triggers into formatted text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snippetStore.snippets) { snippet in
                        SnippetRow(snippet: snippet) {
                            beginEdit(snippet)
                        } onDelete: {
                            snippetStore.delete(snippet)
                        }
                    }
                }

                Button("Add Snippet") {
                    beginAdd()
                }
                .buttonStyle(.borderedProminent)
            } header: {
                Text("Snippet Library")
            } footer: {
                Text("Triggers are case-insensitive and will be replaced with the expansion text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isShowingEditor) {
            SnippetEditorView(
                draft: $draft,
                mode: editorMode,
                onCancel: { isShowingEditor = false },
                onSave: { saveDraft() }
            )
        }
    }

    private func beginAdd() {
        editorMode = .new
        draft = SnippetDraft.empty()
        isShowingEditor = true
    }

    private func beginEdit(_ snippet: Snippet) {
        editorMode = .edit(snippet)
        draft = SnippetDraft.from(snippet)
        isShowingEditor = true
    }

    private func saveDraft() {
        let trigger = draft.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trigger.isEmpty else { return }

        switch editorMode {
        case .new:
            let snippet = Snippet(
                trigger: trigger,
                expansionRTF: draft.expansionRTF,
                requiresIsolation: false
            )
            snippetStore.add(snippet)
        case .edit(let existing):
            let updated = Snippet(
                id: existing.id,
                trigger: trigger,
                expansionRTF: draft.expansionRTF,
                requiresIsolation: false
            )
            snippetStore.update(updated)
        }

        isShowingEditor = false
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.trigger)
                    .fontWeight(.medium)

                let preview = snippet.expansionPlainText
                if !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit snippet")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete snippet")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SnippetDraft {
    var trigger: String
    var expansionRTF: Data

    static func empty() -> SnippetDraft {
        SnippetDraft(trigger: "", expansionRTF: emptyRTF())
    }

    static func from(_ snippet: Snippet) -> SnippetDraft {
        SnippetDraft(trigger: snippet.trigger, expansionRTF: snippet.expansionRTF)
    }

    private static func emptyRTF() -> Data {
        let attributed = NSAttributedString(string: "")
        let range = NSRange(location: 0, length: attributed.length)
        return (try? attributed.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
    }
}

private struct SnippetEditorView: View {
    @Binding var draft: SnippetDraft
    let mode: SnippetEditorMode
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(modeTitle)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Trigger Phrase")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g. my email", text: $draft.trigger)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Expansion Text")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                RichTextEditor(rtfData: $draft.expansionRTF)
                    .frame(minHeight: 200)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480, height: 400)
    }

    private var modeTitle: String {
        switch mode {
        case .new:
            return "New Snippet"
        case .edit:
            return "Edit Snippet"
        }
    }
}

private final class ClickableTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }
}

private struct RichTextEditor: NSViewRepresentable {
    @Binding var rtfData: Data

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ClickableTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.usesFindPanel = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.drawsBackground = true
        textView.autoresizingMask = [.width, .height]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(decodeRTF(rtfData))

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true

        context.coordinator.textView = textView
        context.coordinator.lastRTFData = rtfData

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if context.coordinator.lastRTFData != rtfData {
            textView.textStorage?.setAttributedString(decodeRTF(rtfData))
            context.coordinator.lastRTFData = rtfData
        }
    }

    private func decodeRTF(_ data: Data) -> NSAttributedString {
        guard !data.isEmpty else {
            return NSAttributedString(
                string: "",
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                    .foregroundColor: NSColor.textColor
                ]
            )
        }

        if let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            return attributed
        }

        if let fallback = String(data: data, encoding: .utf8) {
            return NSAttributedString(
                string: fallback,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                    .foregroundColor: NSColor.textColor
                ]
            )
        }

        return NSAttributedString(string: "")
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?
        var lastRTFData: Data = Data()

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let attributed = textView.attributedString()
            let range = NSRange(location: 0, length: attributed.length)
            if let data = try? attributed.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                lastRTFData = data
                parent.rtfData = data
            }
        }
    }
}
