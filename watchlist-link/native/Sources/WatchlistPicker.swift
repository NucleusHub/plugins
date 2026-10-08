import NucleusUI
import SwiftUI
import TodoPluginKit

/// Watchlist's library as posters; a movie is one tap, a show opens its seasons and episodes.
struct WatchlistPicker: View {
    let host: any TodoHost
    let current: WatchLink?
    let onPick: (WatchLink) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [LibraryTitle]?
    @State private var failure: LocalizedStringKey?
    @State private var query = ""
    @State private var showWatched = false
    @State private var show: LibraryTitle?
    @State private var season: LibraryTitle.Season?
    @State private var selection = EpisodeSelection(from: 1, to: 1)
    @State private var wholeShow = false

    var body: some View {
        NucleusSheetPage(show.map { LocalizedStringKey(stringLiteral: $0.title) } ?? "Watchlist", onCancel: { dismiss() }) {
            if let show {
                ShowPage(show: show, season: $season, selection: $selection, wholeShow: $wholeShow) {
                    withAnimation(NucleusMotion.quick) { self.show = nil }
                }
            } else {
                library
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let show { addBar(show) }
        }
        .task { await load() }
    }

    // MARK: Library

    @ViewBuilder
    private var library: some View {
        searchField
        if let items {
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
                sections(items)
            }
        } else if let failure {
            empty("exclamationmark.triangle", title: "Couldn't load Watchlist", message: failure)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
        }
    }

    @ViewBuilder
    private func sections(_ items: [LibraryTitle]) -> some View {
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
                        if current?.itemId == item.id {
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

    private func load() async {
        do {
            items = LibraryTitle.library(try await host.crossApp.view(app: LinkSync.app, name: "library"))
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

    private func pick(_ item: LibraryTitle) {
        guard item.type != "movie", let start = item.currentSeason else {
            finish(WatchLink(itemId: item.id, title: item.title, type: item.type, poster: item.poster))
            return
        }
        Haptics.tap()
        // Reopening the current pick shows it; anything else starts at the next unwatched episode.
        if let current, current.itemId == item.id {
            wholeShow = current.season == nil
            season = item.seasons.first { $0.number == current.season } ?? start
            if let from = current.fromEp, let to = current.toEp { selection = EpisodeSelection(from: from, to: to) } else { selection = .next(in: season!) }
        } else {
            wholeShow = false
            season = start
            selection = .next(in: start)
        }
        withAnimation(NucleusMotion.quick) { show = item }
    }

    // MARK: Adding

    private func addBar(_ show: LibraryTitle) -> some View {
        Button { add(show) } label: { Text(verbatim: addTitle) }
            .buttonStyle(NucleusPrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background {
                LinearGradient(colors: [Nucleus.base.opacity(0), Nucleus.base.opacity(0.9), Nucleus.base], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
    }

    private var addTitle: String {
        guard !wholeShow, let season else { return String(localized: "Add the whole show") }
        let range = selection.from == selection.to ? "E\(selection.from)" : "E\(selection.from)–\(selection.to)"
        return String(localized: "Add S\(season.number) · \(range)")
    }

    private func add(_ show: LibraryTitle) {
        guard !wholeShow, let season else {
            finish(WatchLink(itemId: show.id, title: show.title, type: show.type, poster: show.poster))
            return
        }
        finish(WatchLink(itemId: show.id, title: show.title, type: show.type, poster: show.poster, season: season.number,
                         seasonName: season.name.isEmpty ? nil : season.name, fromEp: selection.from, toEp: selection.to))
    }

    private func finish(_ link: WatchLink) {
        Haptics.success()
        onPick(link)
        dismiss()
    }
}

/// A show: its seasons as chips, the episodes as tiles, and quick picks.
private struct ShowPage: View {
    let show: LibraryTitle
    @Binding var season: LibraryTitle.Season?
    @Binding var selection: EpisodeSelection
    @Binding var wholeShow: Bool
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
            seasons
            if let season {
                episodes(season)
                    .opacity(wholeShow ? 0.35 : 1)
                quickPicks(season)
            }
        }
        .padding(.bottom, 24)
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

    private var seasons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(show.seasons) { s in
                    let on = s.number == season?.number
                    Button {
                        Haptics.selection()
                        withAnimation(NucleusMotion.quick) {
                            season = s
                            selection = .next(in: s)
                            wholeShow = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if s.finished { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                            Text(verbatim: s.title)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(on ? .white : Nucleus.primaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Capsule().fill(on ? AnyShapeStyle(Nucleus.primaryGradient) : AnyShapeStyle(Nucleus.well)))
                    }
                    .buttonStyle(NucleusPressStyle())
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
        .scrollClipDisabled()
    }

    private func episodes(_ season: LibraryTitle.Season) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tap an episode, then a later one for a range.")
                .font(.system(size: 13))
                .foregroundStyle(Nucleus.secondaryText)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(1...max(season.episodeCount, 1), id: \.self) { ep in
                    tile(ep, season: season)
                }
            }
        }
    }

    private func tile(_ ep: Int, season: LibraryTitle.Season) -> some View {
        let picked = !wholeShow && selection.contains(ep)
        let edge = picked && (ep == selection.from || ep == selection.to)
        let watched = ep <= season.watched
        return Button {
            Haptics.selection()
            withAnimation(NucleusMotion.quick) {
                if wholeShow { wholeShow = false; selection = EpisodeSelection(from: ep, to: ep) } else { selection.tap(ep) }
            }
        } label: {
            Text(verbatim: "\(ep)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(picked ? .white : (watched ? Nucleus.secondaryText : Nucleus.primaryText))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(picked ? AnyShapeStyle(Nucleus.accent.opacity(edge ? 1 : 0.55)) : AnyShapeStyle(Nucleus.well))
                }
                .overlay(alignment: .topTrailing) {
                    if watched {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(picked ? .white.opacity(0.8) : Nucleus.success)
                            .padding(5)
                    }
                }
        }
        .buttonStyle(NucleusPressStyle(scale: 0.9))
        .accessibilityLabel(Text("Episode \(ep)"))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private func quickPicks(_ season: LibraryTitle.Season) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            quick("Next episode", on: !wholeShow && selection == .next(in: season)) { selection = .next(in: season) }
            quick("Rest of season", on: !wholeShow && selection == .rest(of: season) && selection.from != selection.to) { selection = .rest(of: season) }
            quick("Whole season", on: !wholeShow && selection == .whole(season)) { selection = .whole(season) }
            quick("Whole show", on: wholeShow) { wholeShow = true }
        }
    }

    private func quick(_ title: LocalizedStringKey, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(NucleusMotion.quick) {
                wholeShow = false
                action()
            }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(on ? Nucleus.accent : Nucleus.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Capsule().strokeBorder(on ? Nucleus.accent : Nucleus.separator, lineWidth: on ? 1.5 : 1))
                .contentShape(Capsule())
        }
        .buttonStyle(NucleusPressStyle())
    }
}
