import NotesPluginKit
import NucleusUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Export as Markdown": the file, a preview of it, and share and copy buttons.
struct ExportSheet: View {
    let context: NoteActionContext

    private let markdown: String
    private let fileName: String
    @State private var fileURL: URL?

    init(context: NoteActionContext) {
        self.context = context
        markdown = MarkdownFile.export(title: context.note.title, body: context.note.body)
        fileName = MarkdownFile.fileName(for: context.note.displayTitle ?? "")
    }

    var body: some View {
        NucleusSheetPage("Export as Markdown", onCancel: { context.dismiss() }) {
            content
        }
        .task { fileURL = Exporter.write(markdown, named: fileName) }
    }

    var content: some View {
        VStack(spacing: 0) {
            NucleusSection("File") {
                NucleusRow(verbatim: fileName,
                           subtitle: Text(ByteCountFormatter.string(fromByteCount: Int64(markdown.utf8.count), countStyle: .file)),
                           icon: IconTile("doc.plaintext.fill", tint: .slate))
            }
            NucleusSection("Preview", footer: Text(context.note.body.attachmentIDs.isEmpty
                    ? String(localized: "Underline and text colors have no Markdown and are left out.")
                    // String, not a LocalizedStringKey, so the reference isn't read as Markdown.
                    : String(localized: "Images and files are written as ![](attachment:<id>) references; their contents aren't in the file. Share them from the note."))) {
                Text(verbatim: preview)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Nucleus.primaryText.opacity(0.85))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
            VStack(spacing: 10) {
                if let fileURL {
                    ShareLink(item: fileURL) {
                        Label("Share file", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(NucleusPrimaryButtonStyle())
                } else {
                    Label("Share file", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .modifier(PrimaryLook())
                }
                Button {
                    Exporter.copy(markdown)
                    Haptics.success()
                    context.host.show(String(localized: "Copied as Markdown"), icon: "doc.on.doc")
                    context.dismiss()
                } label: {
                    Label("Copy Markdown", systemImage: "doc.on.doc")
                }
                .buttonStyle(NucleusSecondaryButtonStyle())
            }
        }
    }

    /// The first 40 lines; the file has them all.
    private var preview: String {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.count > 40 else { return markdown.trimmingCharacters(in: .newlines) }
        return lines.prefix(40).joined(separator: "\n") + "\n…"
    }
}

/// The primary button's look while the file is still being written.
private struct PrimaryLook: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .background(Capsule().fill(Nucleus.primaryGradient))
            .opacity(0.5)
    }
}

enum Exporter {
    /// Writes the file into its own temporary folder so it keeps its exact name.
    static func write(_ markdown: String, named name: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("markdown-export/\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(markdown.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// As plain text and as Markdown, so editors that know Markdown take it as such.
    @MainActor
    static func copy(_ markdown: String) {
        UIPasteboard.general.setItems([[
            UTType.plainText.identifier: markdown,
            "net.daringfireball.markdown": markdown,
        ]])
    }
}
