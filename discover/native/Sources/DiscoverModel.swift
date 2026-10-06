import Foundation
import Observation
import WatchlistPluginKit

/// Discover's rows, fetched from TMDb and ranked by the person's taste. Kept for the session so switching
/// tabs doesn't refetch; it reloads when it's old or MovieDNA changed underneath it.
@MainActor
@Observable
final class DiscoverModel {
    struct Trailer: Identifiable, Hashable, Sendable {
        let key: String
        let title: Suggestion
        var id: String { key }
    }

    struct Feed {
        var picks: [Suggestion] = []
        var trailers: [Trailer] = []
        var following: [Suggestion] = []
        var newReleases: [Suggestion] = []
        var trending: [Suggestion] = []
        var different: [Suggestion] = []

        var isEmpty: Bool { picks.isEmpty && following.isEmpty && newReleases.isEmpty && trending.isEmpty && different.isEmpty }
    }

    static let shared = DiscoverModel()
    static let maxAge: TimeInterval = 30 * 60
    static let minVotes = 100

    private(set) var feed = Feed()
    private(set) var loading = false
    private(set) var failed = false
    private(set) var usesDNA = true
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var fingerprint = ""
    @ObservationIgnored private var genreMap: GenreMap?

    /// Loads unless what's there is fresh and was built from the same taste.
    func refresh(_ host: any WatchlistHost, force: Bool = false) async {
        let dna = host.movieDNA
        let print = Self.fingerprint(dna)
        if !force, !loading, let loadedAt, Date().timeIntervalSince(loadedAt) < Self.maxAge, print == fingerprint, !feed.isEmpty { return }
        guard host.hasTMDbKey, !loading else { return }
        loading = true
        defer { loading = false }
        let taste = dna.enabled ? Taste.from(dna: dna, library: host.library)
                                : Taste.from(library: host.library, notInterested: dna.notInterested)
        do {
            let genres = try await loadGenres(host)
            let next = await build(host, taste: taste, genres: genres)
            feed = next
            // Loaded ahead of a tap, so the first trailer starts at once.
            if let first = next.trailers.first { host.prepareTrailer(first.key) }
            usesDNA = dna.enabled
            failed = false
            loadedAt = Date()
            fingerprint = print
        } catch {
            failed = feed.isEmpty
        }
    }

    /// Drops a title from every row at once, after the person said no or added it.
    func remove(_ id: String) {
        feed.picks.removeAll { $0.id == id }
        feed.trailers.removeAll { $0.title.id == id }
        feed.following.removeAll { $0.id == id }
        feed.newReleases.removeAll { $0.id == id }
        feed.trending.removeAll { $0.id == id }
        feed.different.removeAll { $0.id == id }
    }

    /// What the feed depends on; Interested presses and strength edits beyond rounding change it.
    nonisolated static func fingerprint(_ dna: PluginMovieDNA) -> String {
        guard dna.enabled else { return "off" }
        let genres = dna.genres.prefix(5).map { "\($0.name)\(Int($0.strength / 20))" }
        let titles = dna.titles.prefix(Taste.maxSeeds).map { "\($0.tmdbID)" }
        let people = dna.people.filter(\.followed).map { "\($0.personID)" }
        return (genres + ["|"] + titles + ["|"] + people).joined(separator: ",")
    }

    private func loadGenres(_ host: any WatchlistHost) async throws -> GenreMap {
        if let genreMap { return genreMap }
        async let movie = host.tmdb("/genre/movie/list", query: [:])
        async let tv = host.tmdb("/genre/tv/list", query: [:])
        let map = GenreMap(names: [.movie: GenreMap.parse(try await movie), .show: GenreMap.parse(try await tv)])
        genreMap = map
        return map
    }

    private func build(_ host: any WatchlistHost, taste: Taste, genres: GenreMap) async -> Feed {
        func fresh(_ s: Suggestion) -> Bool { !taste.excluded.contains(s.id) }
        func ranked(_ list: [Suggestion], seedWeight: Double = 0) -> [Suggestion] {
            list.filter { fresh($0) && $0.voteCount >= Self.minVotes && !taste.isUnwantedAnimation($0) }
                .map { var s = $0; s.score = taste.score(s, seedWeight: seedWeight); return s }
                .filter { $0.score > -0.1 }
                .sorted { $0.score > $1.score }
        }

        // Picks: one list per seed title and per top genre, each ranked, then taken in turns.
        var picks = taste.seeds.map {
            ListRequest(path: "/\($0.kind == .movie ? "movie" : "tv")/\($0.tmdbID)/recommendations", kind: $0.kind, reason: .because($0.title))
        }
        let skip = taste.wantsAnimation ? [:] : ["without_genres": "16"]
        for name in taste.topGenres() {
            for kind in [MediaKind.movie, .show] {
                guard let id = genres.id(name, kind) else { continue }
                let query = ["with_genres": String(id), "sort_by": "popularity.desc", "vote_count.gte": "200"].merging(skip) { a, _ in a }
                picks.append(ListRequest(path: kind == .movie ? "/discover/movie" : "/discover/tv", query: query, kind: kind, reason: .genres([])))
            }
        }
        let current = [
            ListRequest(path: "/movie/now_playing", kind: .movie, reason: .newRelease),
            ListRequest(path: "/tv/on_the_air", kind: .show, reason: .newRelease),
            ListRequest(path: "/trending/all/week", kind: nil, reason: .trending),
        ]
        // Outside the comfort zone: highly rated titles from genres the person hasn't touched.
        var different: [ListRequest] = []
        if taste.fromDNA {
            let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
            let all = Array(Set(genres.names[.movie]?.values.map { $0 } ?? []))
            different = taste.unexplored(from: all, day: day).compactMap { name in
                genres.id(name, .movie).map {
                    ListRequest(path: "/discover/movie", query: ["with_genres": String($0), "sort_by": "vote_average.desc",
                                                                 "vote_count.gte": "800", "vote_average.gte": "7.3"],
                                kind: .movie, reason: .different(name))
                }
            }
        }

        // Every list and every followed person at once; one after another took seconds.
        async let followed = Self.following(taste, host: host)
        let lists = await Self.fetch(picks + current + different, host: host, genres: genres)
        let pickLists = lists[..<picks.count]
        let currentLists = Array(lists[picks.count..<(picks.count + current.count)])
        let differentLists = lists[(picks.count + current.count)...]

        var feed = Feed()
        let seeds = taste.seeds.count
        feed.picks = Taste.blend(pickLists.enumerated().map { i, list in
            i < seeds ? ranked(list, seedWeight: taste.seeds[i].weight)
                      : ranked(list.map { var s = $0; s.reason = .genres(taste.liked(s.genres)); return s })
        }, limit: 20)
        feed.trailers = await Self.trailers(for: Array(feed.picks.prefix(8)), host: host)
        feed.following = await followed.filter(fresh)

        // New and trending, ranked by taste but still new and trending first.
        let releases = (currentLists[0] + currentLists[1]).filter { fresh($0) && !taste.isUnwantedAnimation($0) }
        let byFit = releases.enumerated()
            .sorted { taste.fit($0.element.genres) - Double($0.offset) * 0.01 > taste.fit($1.element.genres) - Double($1.offset) * 0.01 }
            .map(\.element)
        feed.newReleases = Taste.alternateKinds(Array(byFit.prefix(20)))
        // Trending stays what's trending; unwanted animation just goes last.
        let trending = currentLists[2].filter(fresh)
        feed.trending = Array((trending.filter { !taste.isUnwantedAnimation($0) } + trending.filter(taste.isUnwantedAnimation)).prefix(20))

        for list in differentLists {
            feed.different += list.filter { fresh($0) && !feed.different.contains($0) }.prefix(8)
        }
        return feed
    }

    private struct ListRequest: Sendable {
        let path: String
        var query: [String: String] = [:]
        let kind: MediaKind?
        let reason: Suggestion.Reason
    }

    /// TMDb lists fetched side by side, in the order asked for; a list that fails comes back empty.
    nonisolated private static func fetch(_ requests: [ListRequest], host: any WatchlistHost, genres: GenreMap) async -> [[Suggestion]] {
        await withTaskGroup(of: (Int, [Suggestion]).self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask {
                    guard let data = try? await host.tmdb(request.path, query: request.query) else { return (index, []) }
                    return (index, TMDbList.parse(data, kind: request.kind, genres: genres, reason: request.reason))
                }
            }
            var out = [[Suggestion]](repeating: [], count: requests.count)
            for await (index, list) in group { out[index] = list }
            return out
        }
    }

    /// A trailer for each of these titles that has one, keeping their order.
    nonisolated private static func trailers(for titles: [Suggestion], host: any WatchlistHost) async -> [Trailer] {
        await withTaskGroup(of: (Int, Trailer?).self) { group in
            for (index, title) in titles.enumerated() {
                let path = title.kind == .movie ? "/movie/\(title.tmdbID)/videos" : "/tv/\(title.tmdbID)/videos"
                group.addTask {
                    guard let data = try? await host.tmdb(path, query: ["include_video_language": "en,null"]),
                          let key = TMDbList.trailer(data) else { return (index, nil) }
                    return (index, Trailer(key: key, title: title))
                }
            }
            var found = [Trailer?](repeating: nil, count: titles.count)
            for await (index, trailer) in group { found[index] = trailer }
            return Array(found.compactMap { $0 }.prefix(6))
        }
    }

    /// What people they follow made lately or are making now.
    nonisolated private static func following(_ taste: Taste, host: any WatchlistHost) async -> [Suggestion] {
        guard taste.fromDNA else { return [] }
        let people = Array(taste.followed.prefix(8))
        let found = await withTaskGroup(of: (Int, PluginPerson?).self) { group in
            for (index, person) in people.enumerated() {
                group.addTask { (index, try? await host.person(person.personID)) }
            }
            var out = [PluginPerson?](repeating: nil, count: people.count)
            for await (index, person) in group { out[index] = person }
            return out
        }
        let cutoff = Calendar.current.date(byAdding: .year, value: -2, to: Date()).map { PluginPersonCredit.dateFormat.string(from: $0) } ?? ""
        var seen = Set<String>()
        var out: [Suggestion] = []
        for (person, details) in zip(people, found) {
            guard let details else { continue }
            let recent = details.credits
                .filter { ($0.date ?? "9999") >= cutoff && !$0.isSelf && $0.posterURL != nil }
                .sorted { ($0.date ?? "9999") > ($1.date ?? "9999") }
            for c in recent.prefix(4) {
                let s = Suggestion(kind: c.kind, tmdbID: c.titleID, title: c.title, date: c.date, posterURL: c.posterURL,
                                   genres: [], voteAverage: 0, voteCount: c.voteCount, reason: .following(person.name))
                if seen.insert(s.id).inserted { out.append(s) }
            }
        }
        return out
    }
}
