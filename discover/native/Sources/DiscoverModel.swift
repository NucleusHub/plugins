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
            let next = try await build(host, taste: taste, genres: genres)
            feed = next
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

    private func build(_ host: any WatchlistHost, taste: Taste, genres: GenreMap) async throws -> Feed {
        func list(_ path: String, _ query: [String: String] = [:], kind: MediaKind?, reason: Suggestion.Reason) async -> [Suggestion] {
            guard let data = try? await host.tmdb(path, query: query) else { return [] }
            return TMDbList.parse(data, kind: kind, genres: genres, reason: reason)
        }
        func fresh(_ s: Suggestion) -> Bool { !taste.excluded.contains(s.id) }

        // Picks: one source per seed title and per top genre, each ranked, then taken in turns.
        func ranked(_ list: [Suggestion], seedWeight: Double = 0) -> [Suggestion] {
            list.filter { fresh($0) && $0.voteCount >= Self.minVotes && !taste.isUnwantedAnimation($0) }
                .map { var s = $0; s.score = taste.score(s, seedWeight: seedWeight); return s }
                .filter { $0.score > -0.1 }
                .sorted { $0.score > $1.score }
        }
        var buckets: [[Suggestion]] = []
        for seed in taste.seeds {
            let path = seed.kind == .movie ? "/movie/\(seed.tmdbID)/recommendations" : "/tv/\(seed.tmdbID)/recommendations"
            buckets.append(ranked(await list(path, kind: seed.kind, reason: .because(seed.title)), seedWeight: seed.weight))
        }
        let skip = taste.wantsAnimation ? [:] : ["without_genres": "16"]
        for name in taste.topGenres() {
            for kind in [MediaKind.movie, .show] {
                guard let id = genres.id(name, kind) else { continue }
                let path = kind == .movie ? "/discover/movie" : "/discover/tv"
                let found = await list(path, ["with_genres": String(id), "sort_by": "popularity.desc", "vote_count.gte": "200"].merging(skip) { a, _ in a },
                                       kind: kind, reason: .genres([]))
                buckets.append(ranked(found.map { var s = $0; s.reason = .genres(taste.liked(s.genres)); return s }))
            }
        }
        var feed = Feed()
        feed.picks = Taste.blend(buckets, limit: 20)

        // Trailers for the top picks, fetched side by side.
        let trailerSources = Array(feed.picks.prefix(8))
        feed.trailers = await withTaskGroup(of: (Int, Trailer?).self) { group in
            for index in trailerSources.indices {
                let source = trailerSources[index]
                let path = source.kind == .movie ? "/movie/\(source.tmdbID)/videos" : "/tv/\(source.tmdbID)/videos"
                group.addTask {
                    guard let data = try? await host.tmdb(path, query: ["include_video_language": "en,null"]),
                          let key = TMDbList.trailer(data) else { return (index, nil) }
                    return (index, Trailer(key: key, title: source))
                }
            }
            var out: [(Int, Trailer)] = []
            for await result in group {
                if let trailer = result.1 { out.append((result.0, trailer)) }
            }
            return out.sorted { $0.0 < $1.0 }.map(\.1).prefix(6).map { $0 }
        }

        // What people they follow made lately or are making now.
        if taste.fromDNA {
            let cutoff = Calendar.current.date(byAdding: .year, value: -2, to: Date()).map { ISO8601DateFormatter.day.string(from: $0) } ?? ""
            var seen = Set<String>()
            for person in taste.followed.prefix(8) {
                guard let p = try? await host.person(person.personID) else { continue }
                let recent = p.credits
                    .filter { ($0.date ?? "9999") >= cutoff && !Self.isSelf($0.role) && $0.posterURL != nil }
                    .sorted { ($0.date ?? "9999") > ($1.date ?? "9999") }
                for c in recent.prefix(4) {
                    let s = Suggestion(kind: c.kind, tmdbID: c.titleID, title: c.title, date: c.date, posterURL: c.posterURL,
                                       genres: [], voteAverage: 0, voteCount: c.voteCount, reason: .following(person.name))
                    if fresh(s), seen.insert(s.id).inserted { feed.following.append(s) }
                }
            }
        }

        // New and trending, ranked by taste but still new and trending first.
        var releases = await list("/movie/now_playing", kind: .movie, reason: .newRelease)
            + list("/tv/on_the_air", kind: .show, reason: .newRelease)
        releases = releases.filter { fresh($0) && !taste.isUnwantedAnimation($0) }
        let byFit = releases.enumerated()
            .sorted { taste.fit($0.element.genres) - Double($0.offset) * 0.01 > taste.fit($1.element.genres) - Double($1.offset) * 0.01 }
            .map(\.element)
        feed.newReleases = Taste.alternateKinds(Array(byFit.prefix(20)))
        // Trending stays what's trending; unwanted animation just goes last.
        let trending = await list("/trending/all/week", kind: nil, reason: .trending).filter(fresh)
        feed.trending = Array((trending.filter { !taste.isUnwantedAnimation($0) } + trending.filter(taste.isUnwantedAnimation)).prefix(20))

        // Outside the comfort zone: highly rated titles from genres the person hasn't touched.
        if taste.fromDNA {
            let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
            let all = Array(Set(genres.names[.movie]?.values.map { $0 } ?? []))
            for name in taste.unexplored(from: all, day: day) {
                guard let id = genres.id(name, .movie) else { continue }
                let found = await list("/discover/movie", ["with_genres": String(id), "sort_by": "vote_average.desc",
                                                           "vote_count.gte": "800", "vote_average.gte": "7.3"],
                                       kind: .movie, reason: .different(name))
                feed.different += found.filter { fresh($0) && !feed.different.contains($0) }.prefix(8)
            }
        }
        return feed
    }

    nonisolated static func isSelf(_ role: String) -> Bool {
        let r = role.lowercased()
        return r == "self" || r.hasPrefix("self ") || r.hasPrefix("himself") || r.hasPrefix("herself") || r.hasPrefix("themselves")
    }
}

extension ISO8601DateFormatter {
    /// TMDb's `yyyy-mm-dd`.
    nonisolated(unsafe) static let day: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
