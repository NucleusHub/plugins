import NotesPluginKit
import NucleusUI
import SwiftUI

/// Watchlist's library as posters; a movie is one tap, a show opens its seasons.
struct WatchlistPicker: View {
    let host: any NotesHost
    /// Item ids the note already has.
    let attached: Set<String>
    let onPick: (WatchCard) -> Void
    let onCancel: () -> Void
    @State private var items: [LibraryTitle]?
    @State private var failure: LocalizedStringKey?
    @State private var show: LibraryTitle?

    var body: some View {
        NucleusSheetPage(show.map { LocalizedStringKey(stringLiteral: $0.title) } ?? "Watchlist", onCancel: onCancel) {
            if let show {
                ShowSeasons(show: show, pick: finish) {
                    withAnimation(NucleusMotion.quick) { self.show = nil }
                }
            } else if let items {
                LibraryGrid(items: items, attached: attached) { item in
                    if item.type == "movie" || item.seasons.isEmpty {
                        finish(WatchCard(item))
                    } else {
                        Haptics.tap()
                        withAnimation(NucleusMotion.quick) { show = item }
                    }
                }
            } else if let failure {
                NucleusEmptyState("exclamationmark.triangle", title: "Couldn't load Watchlist", message: failure)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            items = LibraryTitle.library(try await host.crossApp.view(app: WatchCardLogic.app, name: WatchCardLogic.view))
        } catch CrossAppError.notSignedIn {
            failure = "Sign in with Nucleus ID to see your Watchlist."
        } catch CrossAppError.scopeDenied {
            failure = "Turn the plugin off and on again to reconnect Watchlist."
        } catch CrossAppError.http(404, _) {
            failure = "Open Watchlist while signed in so it shares your library."
        } catch {
            failure = "Check your connection and try again."
        }
    }

    private func finish(_ card: WatchCard) {
        Haptics.success()
        onPick(card)
    }
}

/// Search, then Continue watching, Up next and (collapsed) Watched.
struct LibraryGrid: View {
    let items: [LibraryTitle]
    let attached: Set<String>
    let pick: (LibraryTitle) -> Void
    @State private var query = ""
    @State private var showWatched = false

    var body: some View {
        searchField
        if items.isEmpty {
            empty("tv", title: "Your Watchlist is empty", message: "Add titles in Watchlist first.")
        } else if !query.isEmpty {
            let found = items.filter { $0.title.localizedCaseInsensitiveContains(query) }
            if found.isEmpty {
                empty("magnifyingglass", title: "No matches", message: "No title in your Watchlist matches that.")
            } else {
                grid(found)
            }
        } else {
            sections
        }
    }

    @ViewBuilder
    private var sections: some View {
        let watching = items.filter { $0.status == "watching" }
        let watched = items.filter { $0.status == "completed" }
        let planned = items.filter { $0.status != "watching" && $0.status != "completed" }
        VStack(alignment: .leading, spacing: 28) {
            if !watching.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    heading("Continue watching")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(watching) { card($0).frame(width: 128) }
                        }
                    }
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                    .padding(.horizontal, -16)
                    .scrollClipDisabled()
                }
            }
            if !planned.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    heading("Up next")
                    grid(planned)
                }
            }
            if !watched.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation(NucleusMotion.quick) { showWatched.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            heading("Watched")
                            Text(verbatim: "\(watched.count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Nucleus.secondaryText)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Nucleus.secondaryText)
                                .rotationEffect(.degrees(showWatched ? 0 : -90))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showWatched { grid(watched) }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Nucleus.secondaryText)
            TextField("Search your Watchlist", text: $query).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Nucleus.secondaryText) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .frame(height: 48)
        .nucleusGlass(in: Capsule())
        .padding(.bottom, 22)
    }

    private func grid(_ items: [LibraryTitle]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 14, alignment: .top)], spacing: 20) {
            ForEach(items) { card($0) }
        }
    }

    private func card(_ item: LibraryTitle) -> some View {
        Button { pick(item) } label: {
            VStack(alignment: .leading, spacing: 7) {
                Poster(url: item.poster, title: item.title, type: item.type)
                    .overlay(alignment: .bottom) { progress(item) }
                    .overlay(alignment: .topTrailing) {
                        if attached.contains(item.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Nucleus.accent)
                                .padding(6)
                        }
                    }
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                Text(verbatim: item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(verbatim: subtitle(item))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Nucleus.secondaryText)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NucleusPressStyle(scale: 0.96))
        .accessibilityLabel(Text(verbatim: item.title))
    }

    /// How far into a show you are, as a thin bar along the poster's bottom.
    @ViewBuilder
    private func progress(_ item: LibraryTitle) -> some View {
        let totals = item.episodeTotals
        if totals.total > 0, totals.watched > 0 {
            GeometryReader { geo in
                Capsule().fill(.white.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Nucleus.accent).frame(width: geo.size.width * CGFloat(totals.watched) / CGFloat(totals.total))
                    }
            }
            .frame(height: 4)
            .padding(8)
        }
    }

    private func subtitle(_ item: LibraryTitle) -> String {
        if item.type == "movie" { return String(localized: "Movie") }
        guard let season = item.currentSeason else { return String(localized: "TV show") }
        if season.finished { return String(localized: "All watched") }
        return String(localized: "S\(season.number) · E\(season.watched + 1) next")
    }

    private func heading(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Nucleus.secondaryText)
    }

    private func empty(_ icon: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        NucleusEmptyState(icon, title: title, message: message)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }
}

/// A show: the whole show, or one of its seasons with how far you are.
struct ShowSeasons: View {
    let show: LibraryTitle
    let pick: (WatchCard) -> Void
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Button(action: back) {
                Label("All titles", systemImage: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .nucleusGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)

            header

            NucleusSection("Attach") {
                Button { pick(WatchCard(show)) } label: {
                    NucleusRow("Whole show", subtitle: Text("Shows the season you're on"), icon: IconTile("tv", tint: .violet)) { Chevron() }
                }
                .buttonStyle(NucleusRowButtonStyle())
                ForEach(show.seasons) { season in
                    Button { pick(WatchCard(show, season: season.number)) } label: {
                        NucleusRow(verbatim: season.title, subtitle: Text("\(season.watched) of \(season.episodeCount) watched"),
                                   icon: IconTile(season.finished ? "checkmark" : "\(min(season.number, 50)).square", tint: season.finished ? .emerald : .sky)) {
                            Chevron()
                        }
                    }
                    .buttonStyle(NucleusRowButtonStyle())
                }
            }
        }
    }

    private var header: some View {
        let totals = show.episodeTotals
        return HStack(alignment: .center, spacing: 16) {
            Poster(url: show.poster, title: show.title, type: show.type, cornerRadius: 10)
                .frame(width: 76)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: show.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Nucleus.primaryText)
                    .lineLimit(3)
                Text("\(totals.watched) of \(totals.total) episodes watched")
                    .font(.system(size: 14))
                    .foregroundStyle(Nucleus.secondaryText)
            }
        }
    }
}
