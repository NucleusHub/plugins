import NucleusUI
import SwiftUI
import WatchlistPluginKit

/// The Discover tab: rows of suggestions, each addable in one tap or turned down for good.
struct DiscoverView: View {
    let host: any WatchlistHost
    @State private var model = DiscoverModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !host.hasTMDbKey {
                    NucleusEmptyState("key", title: "Discover needs a TMDb key", message: "Add a free TMDb API key in Settings and suggestions show up here.")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if model.feed.isEmpty {
                    if model.failed {
                        NucleusEmptyState("wifi.exclamationmark", title: "Couldn't load Discover", message: "Check your connection and pull to try again.")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 120)
                    }
                } else {
                    content
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await model.refresh(host, force: true) }
        .task { await model.refresh(host) }
    }

    @ViewBuilder
    private var content: some View {
        let feed = model.feed
        if !model.usesDNA {
            Label("MovieDNA is off, so these come from what you've watched.", systemImage: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(Nucleus.secondaryText)
                .padding(.horizontal, 20)
        }
        row(model.usesDNA ? "Picked for you" : "For you", subtitle: model.usesDNA ? "From your MovieDNA" : nil, feed.picks)
        if !feed.trailers.isEmpty {
            DiscoverRow(title: "Trailers for you", subtitle: nil) {
                ForEach(feed.trailers) { trailer in
                    TrailerCard(trailer: trailer, loading: host.trailerLoadingKey == trailer.key) {
                        Haptics.tap()
                        host.playTrailer(trailer.key)
                    }
                }
            }
        }
        row("From people you follow", subtitle: nil, feed.following)
        row("New releases", subtitle: "In cinemas and on air now", feed.newReleases)
        row("Trending this week", subtitle: nil, feed.trending)
        row("Outside your comfort zone", subtitle: "Highly rated, from genres you haven't tried", feed.different)
    }

    @ViewBuilder
    private func row(_ title: LocalizedStringKey, subtitle: LocalizedStringKey?, _ items: [Suggestion]) -> some View {
        if !items.isEmpty {
            DiscoverRow(title: title, subtitle: subtitle) {
                ForEach(items) { s in
                    SuggestionCard(suggestion: s, host: host) { notInterested(s) }
                }
            }
        }
    }

    private func notInterested(_ s: Suggestion) {
        Haptics.warning()
        host.markNotInterested(s.kind, tmdbID: s.tmdbID, title: s.title, genres: s.genres)
        withAnimation(.easeOut(duration: 0.25)) { model.remove(s.id) }
    }
}

/// A titled row that scrolls sideways.
struct DiscoverRow<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(Nucleus.primaryText)
                if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText) }
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) { content }
                    .padding(.horizontal, 20)
            }
        }
    }
}

/// A poster with one-tap add, a way to say no, and why it's here.
struct SuggestionCard: View {
    let suggestion: Suggestion
    let host: any WatchlistHost
    let notInterested: () -> Void
    @State private var adding = false
    @State private var failed = false

    private static let width: CGFloat = 128

    var body: some View {
        let added = host.inLibrary(suggestion.kind, tmdbID: suggestion.tmdbID)
        VStack(alignment: .leading, spacing: 6) {
            Button { host.open(.title(suggestion.kind, suggestion.tmdbID)) } label: {
                TitlePoster(url: suggestion.posterURL)
                    .frame(width: Self.width, height: Self.width * 1.5)
            }
            .buttonStyle(NucleusPressStyle(scale: 0.96))
            .overlay(alignment: .topTrailing) { addButton(added).padding(6) }
            .overlay(alignment: .topLeading) {
                if !added {
                    Button(action: notInterested) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.black.opacity(0.45)))
                    }
                    .accessibilityLabel("Not interested")
                    .padding(6)
                }
            }
            .contextMenu {
                if !added { Button { Task { await add() } } label: { Label("Add to watchlist", systemImage: "plus") } }
                Button { host.open(.title(suggestion.kind, suggestion.tmdbID)) } label: { Label("Open", systemImage: "arrow.up.right") }
                if !added { Button(role: .destructive, action: notInterested) { Label("Not interested", systemImage: "hand.thumbsdown") } }
            }
            Text(verbatim: suggestion.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Nucleus.primaryText)
                .lineLimit(2)
            if let why = Self.why(suggestion) {
                why.font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText).lineLimit(2)
            }
        }
        .frame(width: Self.width, alignment: .leading)
    }

    @ViewBuilder
    private func addButton(_ added: Bool) -> some View {
        Button { Task { await add() } } label: {
            Group {
                if adding {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: added ? "checkmark" : failed ? "exclamationmark" : "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 32, height: 32)
            .background(Circle().fill(added ? AnyShapeStyle(Color.inLibrary) : AnyShapeStyle(Nucleus.primaryGradient)))
        }
        .disabled(added || adding)
        .accessibilityLabel(added ? "In your watchlist" : "Add to watchlist")
    }

    private func add() async {
        guard !adding else { return }
        Haptics.tap()
        adding = true
        failed = false
        do {
            try await host.addToWatchlist(suggestion.kind, tmdbID: suggestion.tmdbID)
            Haptics.success()
        } catch {
            failed = true
            Haptics.error()
        }
        adding = false
    }

    static func why(_ s: Suggestion) -> Text? {
        let year = s.year.map { " · \($0)" } ?? ""
        switch s.reason {
        case .because(let title): return Text("Because you liked \(title)")
        case .following(let name): return Text(verbatim: name + year)
        case .genres(let names): return names.isEmpty ? s.year.map { Text(verbatim: $0) } : Text(verbatim: names.joined(separator: " · "))
        case .trending, .newRelease: return s.year.map { Text(verbatim: $0) }
        case .different(let genre): return Text("Something new: \(String(localized: String.LocalizationValue(genre)))")
        }
    }
}

struct TrailerCard: View {
    let trailer: DiscoverModel.Trailer
    let loading: Bool
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 6) {
                AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(trailer.key)/hqdefault.jpg")) { $0.resizable().scaledToFill() } placeholder: { Nucleus.well }
                    .frame(width: 240, height: 135)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        Group {
                            if loading { ProgressView().tint(.white) } else {
                                Image(systemName: "play.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.black.opacity(0.55)))
                    }
                Text(verbatim: trailer.title.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                    .lineLimit(1)
            }
            .frame(width: 240, alignment: .leading)
        }
        .buttonStyle(NucleusPressStyle(scale: 0.96))
        .accessibilityLabel(Text("Trailer: \(trailer.title.title)"))
    }
}
