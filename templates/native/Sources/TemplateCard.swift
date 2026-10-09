import NotesPluginKit
import NucleusUI
import SwiftUI

extension NoteColor? {
    /// The card tint: a palette tint, a custom hex, or slate for no color.
    var swatch: (tint: NucleusTint, color: Color) {
        switch self {
        case .tint(let name)?:
            let tint = NucleusTint(rawValue: name) ?? .slate
            return (tint, tint.color)
        case .hex(let hex)?:
            return (.slate, Color(hex: UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x64748B))
        case nil:
            return (.slate, NucleusTint.slate.color)
        }
    }
}

/// A template as a little note card: icon, name and a miniature of its first lines.
struct TemplateCard: View {
    let template: NoteTemplate
    var editing = false
    var onDelete: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let swatch = template.color.swatch
        let preview = PlaceholderFiller().fill(template.body, on: Date())
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconTile(template.icon, tint: swatch.tint, size: 32)
                Text(template.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(preview.blocks.filter { !$0.type.isMedia }.prefix(5))) { block in
                    PreviewLine(block: block, color: swatch.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(height: 168)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [swatch.color.opacity(scheme == .dark ? 0.32 : 0.2), swatch.color.opacity(scheme == .dark ? 0.1 : 0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .nucleusGlass(cornerRadius: 22)
        .overlay(alignment: .topTrailing) {
            if editing, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Nucleus.danger)
                }
                .buttonStyle(NucleusPressStyle())
                .offset(x: 6, y: -6)
                .accessibilityLabel("Delete \(template.name)")
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

/// One line of a miniature: headings bold, list items with their marker, empty lines as soft bars.
private struct PreviewLine: View {
    let block: Block
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            switch block.type {
            case .check:
                Image(systemName: block.checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
            case .bullet:
                Circle().fill(color).frame(width: 4, height: 4).padding(.horizontal, 2)
            case .numbered:
                Text("1.").font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
            case .quote:
                Capsule().fill(color.opacity(0.7)).frame(width: 2, height: 10)
            default:
                EmptyView()
            }
            let text = block.text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                Capsule().fill(Nucleus.primaryText.opacity(0.08)).frame(height: 5).frame(maxWidth: block.type.isList ? 70 : 90)
            } else {
                Text(text)
                    .font(.system(size: isHeading ? 11 : 10, weight: isHeading ? .bold : .regular))
                    .foregroundStyle(isHeading ? Nucleus.primaryText.opacity(0.85) : Nucleus.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(height: 12)
    }

    private var isHeading: Bool { [.heading1, .heading2, .heading3].contains(block.type) }
}
