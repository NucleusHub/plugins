import NotesPluginKit
import NucleusUI
import SwiftUI

/// "Linked from": the notes that link to this one. Shows nothing when none do.
struct LinkedFromSection: View {
    let note: PluginNote
    let host: any NotesHost
    @State private var showsAll = false
    private let indexer = BacklinkIndexer.shared
    static let collapsedCount = 4

    var body: some View {
        let sources = indexer.index(for: host).backlinks(to: note)
        if !sources.isEmpty {
            NucleusSection("Linked from") {
                ForEach(showsAll ? sources : Array(sources.prefix(Self.collapsedCount))) { source in
                    Button { host.open(noteID: source.id) } label: { row(source) }
                        .buttonStyle(NucleusRowButtonStyle())
                }
                if sources.count > Self.collapsedCount {
                    Button {
                        withAnimation(NucleusMotion.quick) { showsAll.toggle() }
                    } label: {
                        Text(showsAll ? "Show fewer" : "Show all \(sources.count)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Nucleus.accent)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(NucleusRowButtonStyle())
                }
            }
        }
    }

    private func row(_ source: BacklinkIndex.Source) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile("arrow.uturn.left", tint: .violet)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: source.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                    .lineLimit(1)
                if !source.context.isEmpty, source.context != source.title {
                    Text(verbatim: source.context)
                        .font(.system(size: 14))
                        .foregroundStyle(Nucleus.secondaryText)
                        .lineLimit(2)
                }
                Text(source.updatedAt, format: .relative(presentation: .named))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Nucleus.secondaryText.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Chevron()
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
