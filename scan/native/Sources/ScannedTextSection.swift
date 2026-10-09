import NotesPluginKit
import NucleusUI
import SwiftUI
import UIKit

/// "Scanned text": a card per scanned page with its recognized text, to copy or put into the note.
struct ScannedTextSection: View {
    let note: PluginNote
    let host: any NotesHost
    @Binding var noteBody: NoteBody
    @Binding var value: JSONValue?

    private var pages: [(id: String, text: String)] {
        let texts = ScanTexts.decode(value)
        return noteBody.attachmentIDs.compactMap { id in texts[id].flatMap { $0.isEmpty ? nil : (id, $0) } }
    }

    var body: some View {
        let pages = self.pages
        Group {
            if !pages.isEmpty {
                NucleusSection("Scanned text") {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        ScannedPageCard(number: index + 1, text: page.text, attachment: attachment(page.id), host: host,
                                        insert: { insertText(page.text, after: page.id) })
                    }
                }
            }
        }
        .onAppear(perform: adoptPending)
    }

    private func attachment(_ id: String) -> Attachment? {
        note.attachments.first { $0.id == id } ?? PendingScans.shared.attachments[id]
    }

    /// Takes texts the insert action made into this note's data, and drops texts of pages no longer in it.
    private func adoptPending() {
        guard !note.hidden else { return }
        var texts = ScanTexts.decode(value)
        let ids = Set(noteBody.attachmentIDs)
        for (id, text) in PendingScans.shared.texts where ids.contains(id) && texts[id] == nil { texts[id] = text }
        let next = ScanTexts.pruned(texts, body: noteBody) ?? texts
        if next != ScanTexts.decode(value) { value = ScanTexts.encode(next) }
    }

    private func insertText(_ text: String, after attachmentID: String) {
        let blocks = ScanTexts.blocks(for: text)
        withAnimation(NucleusMotion.quick) {
            if let index = noteBody.blocks.firstIndex(where: { $0.attachment == attachmentID }) {
                noteBody.blocks.insert(contentsOf: blocks, at: index + 1)
            } else {
                noteBody.blocks.append(contentsOf: blocks)
            }
        }
        Haptics.success()
        host.show(String(localized: "Text added to the note"), icon: "text.insert")
    }
}

struct ScannedPageCard: View {
    let number: Int
    let text: String
    let attachment: Attachment?
    let host: any NotesHost
    let insert: () -> Void
    @State private var expanded = false
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumb
                VStack(alignment: .leading, spacing: 4) {
                    Text("Page \(number)")
                        .font(.system(size: 13, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundStyle(Nucleus.secondaryText)
                    Text(verbatim: text)
                        .font(.system(size: 15))
                        .foregroundStyle(Nucleus.primaryText)
                        .lineLimit(expanded ? nil : 4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if text.split(separator: "\n").count > 4 || text.count > 160 {
                        Button(expanded ? "Show less" : "Show all") {
                            withAnimation(NucleusMotion.quick) { expanded.toggle() }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Nucleus.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                action("Copy text", icon: "doc.on.doc") {
                    UIPasteboard.general.string = text
                    Haptics.tap()
                    host.show(String(localized: "Text copied"), icon: "doc.on.doc")
                }
                action("Insert into note", icon: "text.insert", action: insert)
            }
        }
        .padding(14)
        .task(id: attachment?.id) { await loadThumbnail() }
    }

    private var thumb: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Nucleus.well)
            .frame(width: 54, height: 70)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Nucleus.secondaryText)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Nucleus.separator))
    }

    private func action(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Nucleus.accent)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(Nucleus.accent.opacity(0.12)))
        }
        .buttonStyle(NucleusPressStyle())
    }

    private func loadThumbnail() async {
        guard thumbnail == nil, let attachment, let data = try? await host.attachmentData(attachment) else { return }
        thumbnail = await Task.detached { UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 160, height: 210)) }.value
    }
}
