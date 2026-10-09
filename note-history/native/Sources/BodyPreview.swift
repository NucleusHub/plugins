import NotesPluginKit
import NucleusUI
import SwiftUI

/// A read-only rendering of a note body: headings, lists, checks, quotes, code; enough to read a version.
struct BodyPreview: View {
    let title: String
    let noteBody: NoteBody
    var attachments: [Attachment] = []

    var body: some View {
        let numbers = BodyNumbering.numbers(for: noteBody.blocks)
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(verbatim: title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Nucleus.primaryText)
                    .padding(.bottom, 4)
            }
            ForEach(Array(noteBody.blocks.enumerated()), id: \.element.id) { index, block in
                blockView(block, number: numbers[index])
            }
            if title.isEmpty, noteBody.isEmpty {
                Text("This version was empty.")
                    .font(.system(size: 15))
                    .foregroundStyle(Nucleus.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: Block, number: Int?) -> some View {
        switch block.type {
        case .heading1: text(block, size: 22, weight: .bold).padding(.top, 6)
        case .heading2: text(block, size: 19, weight: .bold).padding(.top, 4)
        case .heading3: text(block, size: 17, weight: .semibold).padding(.top, 2)
        case .bullet:
            listItem(block) { Text(verbatim: "•").font(.system(size: 16, weight: .bold)).foregroundStyle(Nucleus.accent) }
        case .numbered:
            listItem(block) { Text(verbatim: "\(number ?? 1).").font(.system(size: 16, weight: .semibold).monospacedDigit()).foregroundStyle(Nucleus.accent) }
        case .check:
            listItem(block, dimmed: block.checked) {
                Image(systemName: block.checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(block.checked ? Nucleus.accent : Nucleus.secondaryText)
            }
        case .quote:
            HStack(spacing: 10) {
                Capsule().fill(Nucleus.accent.opacity(0.6)).frame(width: 3)
                text(block, size: 16, weight: .regular).italic()
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code:
            Text(verbatim: block.text)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Nucleus.primaryText)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Nucleus.well))
        case .divider:
            Rectangle().fill(Nucleus.separator).frame(height: 1).padding(.vertical, 6)
        case .image, .file:
            attachmentChip(block)
        case .embed:
            EmptyView()
        case .paragraph:
            if block.runs.isEmpty { Color.clear.frame(height: 6) } else { text(block, size: 16, weight: .regular) }
        }
    }

    private func text(_ block: Block, size: CGFloat, weight: Font.Weight) -> some View {
        Text(Self.attributed(block.runs))
            .font(.system(size: size, weight: weight))
            .foregroundStyle(Nucleus.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func listItem<Marker: View>(_ block: Block, dimmed: Bool = false, @ViewBuilder marker: () -> Marker) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker().frame(minWidth: 18)
            Text(Self.attributed(block.runs, struck: dimmed))
                .font(.system(size: 16))
                .foregroundStyle(dimmed ? Nucleus.secondaryText : Nucleus.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(block.indent) * 20)
    }

    private func attachmentChip(_ block: Block) -> some View {
        let attachment = attachments.first { $0.id == block.attachment }
        let icon = switch attachment?.kind {
        case .audio: "waveform"
        case .drawing: "scribble"
        case .file: "doc"
        default: block.type == .image ? "photo" : "doc"
        }
        let name = attachment?.name ?? (block.type == .image ? String(localized: "Image") : String(localized: "File"))
        return Label { Text(verbatim: name).lineLimit(1) } icon: { Image(systemName: icon) }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Nucleus.glyph)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(Nucleus.well))
    }

    static func attributed(_ runs: [Run], struck: Bool = false) -> AttributedString {
        var out = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.bold { intent.insert(.stronglyEmphasized) }
            if run.italic { intent.insert(.emphasized) }
            if run.code { intent.insert(.code) }
            if run.strike || struck { intent.insert(.strikethrough) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if run.underline { piece.underlineStyle = .single }
            if run.link != nil {
                piece.foregroundColor = Nucleus.accent
                piece.underlineStyle = .single
            }
            if let highlight = run.highlight.flatMap(NucleusTint.init(rawValue:)) {
                piece.backgroundColor = highlight.color.opacity(0.25)
            }
            out += piece
        }
        return out
    }
}
