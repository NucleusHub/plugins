import NucleusUI
import SwiftUI
import TodoPluginKit

/// The task editor's Watchlist section: the linked title as a card, or a way to add one.
struct WatchlistSection: View {
    @Binding var value: JSONValue?
    @Binding var title: String
    let host: any TodoHost
    @State private var picking = false

    private var link: WatchLink? { WatchLink(value) }

    var body: some View {
        NucleusSection("Watchlist") {
            if let link {
                card(link)
            } else {
                Button { picking = true } label: {
                    NucleusRow("Add something to watch", subtitle: Text("Finishing the task marks it watched"),
                               icon: IconTile("play.rectangle.on.rectangle.fill", tint: .pink)) { Chevron() }
                }
                .buttonStyle(NucleusRowButtonStyle())
            }
        }
        .sheet(isPresented: $picking) {
            WatchlistPicker(host: host, current: link) { picked in
                // Picking the same thing again keeps what was already sent for it.
                if let link, link.sameTarget(as: picked) { return }
                withAnimation(NucleusMotion.quick) { value = picked.json }
                if title.trimmingCharacters(in: .whitespaces).isEmpty { title = String(localized: "Watch \(picked.label)") }
            }
            .presentationDragIndicator(.visible)
        }
    }

    private func card(_ link: WatchLink) -> some View {
        HStack(spacing: 14) {
            Button { picking = true } label: {
                HStack(spacing: 14) {
                    Poster(url: link.poster, title: link.title, type: link.type, cornerRadius: 8)
                        .frame(width: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: link.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Nucleus.primaryText)
                            .lineLimit(2)
                        Text(verbatim: detail(link))
                            .font(.system(size: 14))
                            .foregroundStyle(Nucleus.secondaryText)
                        status(link)
                            .padding(.top, 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button { picking = true } label: { Label("Change", systemImage: "arrow.triangle.2.circlepath") }
                Button(role: .destructive) {
                    withAnimation(NucleusMotion.quick) { value = nil }
                } label: { Label("Remove", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Nucleus.glyph)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Nucleus.well))
            }
            .accessibilityLabel("More")
        }
        .padding(12)
    }

    /// Where the mark is: still to come, on its way to Watchlist, done, or refused.
    private func status(_ link: WatchLink) -> some View {
        let (icon, text, color): (String, LocalizedStringKey, Color) =
            if let reason = link.broken {
                ("exclamationmark.triangle.fill", "Watchlist couldn't apply this (\(reason)). Pick it again.", Nucleus.danger)
            } else if link.mark?.status == .applied {
                ("checkmark.circle.fill", "Marked watched in Watchlist", Nucleus.success)
            } else if link.mark != nil {
                ("arrow.triangle.2.circlepath", "Waiting for Watchlist to sync", Nucleus.accent)
            } else {
                ("eye", "Marks watched when you finish", Nucleus.secondaryText)
            }
        return Label { Text(text) } icon: { Image(systemName: icon) }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .labelStyle(TightLabel())
    }

    private func detail(_ link: WatchLink) -> String {
        if link.type == "movie" { return String(localized: "Movie") }
        guard let season = link.season else { return String(localized: "Whole show") }
        let name = link.seasonName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Season \(season)")
        guard let from = link.fromEp, let to = link.toEp else { return name }
        return from == to ? String(localized: "\(name) · Episode \(from)") : String(localized: "\(name) · Episodes \(from)–\(to)")
    }
}

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}
