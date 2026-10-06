import Foundation
import WatchlistPluginKit

/// What Discover ranks by: genre weights, titles to find more like, and people to follow.
/// Built from MovieDNA, or, with it off, from finished titles the way the old For You did.
struct Taste: Sendable {
    struct Seed: Hashable, Sendable {
        let kind: MediaKind
        let tmdbID: Int
        let title: String
        /// 0 … 1.
        let weight: Double
    }

    /// Lowercased genre name → -1 (avoid) … 1 (love).
    var genres: [String: Double] = [:]
    /// Lowercased → the name as TMDb writes it.
    var genreNames: [String: String] = [:]
    var seeds: [Seed] = []
    var followed: [PluginPersonTrait] = []
    /// `movie:603` keys never to suggest: already in the library, or turned down.
    var excluded: Set<String> = []
    var fromDNA = false

    static let maxSeeds = 5

    static func from(dna: PluginMovieDNA, library: [PluginLibraryTitle]) -> Taste {
        var t = Taste()
        t.fromDNA = true
        for g in dna.genres {
            t.genres[g.name.lowercased()] = g.strength / 100
            t.genreNames[g.name.lowercased()] = g.name
        }
        let strong = dna.titles.filter { $0.strength >= 30 }.prefix(maxSeeds * 3)
            .map { Seed(kind: $0.kind, tmdbID: $0.tmdbID, title: $0.name, weight: $0.strength / 100) }
        let genresByTitle = Dictionary(library.compactMap { t in t.tmdbID.map { (PluginMovieDNA.key(t.kind, $0), t.genres) } },
                                       uniquingKeysWith: { a, _ in a })
        t.seeds = diverseSeeds(Array(strong), genresOf: { genresByTitle[PluginMovieDNA.key($0.kind, $0.tmdbID)] ?? [] }, limit: maxSeeds)
        t.followed = dna.people.filter(\.followed)
        t.excluded = dna.notInterested.union(owned(library))
        return t
    }

    /// The old For You: finished titles, weighted by rating, favorites and how recently they were watched.
    static func from(library: [PluginLibraryTitle], notInterested: Set<String>, now: Date = Date()) -> Taste {
        var t = Taste()
        let finished = library.filter(\.isCompleted)
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
            .prefix(60)
        var raw: [String: Double] = [:]
        var seeds: [Seed] = []
        for title in finished {
            let days = max(0, now.timeIntervalSince(title.finishedAt ?? now) / 86400)
            let recency = pow(0.5, days / 60)
            var quality = title.rating.map { ($0 - 5.5) / 2.5 } ?? 1
            quality = min(2, max(-1.5, quality)) + (title.favorite ? 0.5 : 0)
            let weight = recency * quality
            if let id = title.tmdbID, weight > 0, seeds.count < 4 {
                seeds.append(Seed(kind: title.kind, tmdbID: id, title: title.title, weight: min(1, weight)))
            }
            guard !title.genres.isEmpty else { continue }
            let share = weight / Double(title.genres.count).squareRoot()
            for g in title.genres {
                raw[g.lowercased(), default: 0] += share
                if t.genreNames[g.lowercased()] == nil { t.genreNames[g.lowercased()] = g }
            }
        }
        let top = raw.values.map(abs).max() ?? 0
        if top > 0 { t.genres = raw.mapValues { $0 / top } }
        t.seeds = seeds
        t.excluded = notInterested.union(owned(library))
        return t
    }

    private static func owned(_ library: [PluginLibraryTitle]) -> Set<String> {
        Set(library.compactMap { item in item.tmdbID.map { PluginMovieDNA.key(item.kind, $0) } })
    }

    /// What a genre the person never showed interest in counts; untouched isn't the same as wanted.
    static let unknownGenre = -0.15

    /// How well a title's genres fit, about -1 … 1; titles with many genres don't win just by having more.
    func fit(_ genreNames: [String]) -> Double {
        guard !genreNames.isEmpty, !genres.isEmpty else { return 0 }
        let sum = genreNames.reduce(0) { $0 + (genres[$1.lowercased()] ?? Self.unknownGenre) }
        return sum / Double(genreNames.count).squareRoot()
    }

    /// TMDb's popular action, sci-fi and fantasy TV is mostly anime, so animation only comes in when it's liked.
    var wantsAnimation: Bool { (genres["animation"] ?? 0) >= 0.2 }

    func isUnwantedAnimation(_ s: Suggestion) -> Bool {
        !wantsAnimation && s.genres.contains { $0.caseInsensitiveCompare("Animation") == .orderedSame }
    }

    /// Takes the rows' sources in turns so no single recommendation or genre fills them, keeps any one main
    /// genre to about a third, and alternates movies and shows when both are there.
    static func blend(_ buckets: [[Suggestion]], limit: Int, maxShare: Double = 0.34) -> [Suggestion] {
        var queues = buckets.map { $0[...] }
        var out: [Suggestion] = []
        var seen = Set<String>()
        var genreCount: [String: Int] = [:]
        var deferred: [Suggestion] = []
        let cap = max(2, Int((Double(limit) * maxShare).rounded()))
        while out.count < limit, queues.contains(where: { !$0.isEmpty }) {
            for i in queues.indices where out.count < limit {
                guard let next = queues[i].popFirst(), seen.insert(next.id).inserted else { continue }
                let main = next.genres.first?.lowercased() ?? ""
                if !main.isEmpty, genreCount[main, default: 0] >= cap {
                    deferred.append(next)
                    continue
                }
                genreCount[main, default: 0] += 1
                out.append(next)
            }
        }
        // Only when nothing else is left does a genre go over its share.
        out += deferred.prefix(max(0, limit - out.count))
        return alternateKinds(out)
    }

    /// Movies and shows take turns, each kind in its own order.
    static func alternateKinds(_ list: [Suggestion]) -> [Suggestion] {
        var movies = list.filter { $0.kind == .movie }[...]
        var shows = list.filter { $0.kind == .show }[...]
        var out: [Suggestion] = []
        var movieTurn = list.first?.kind != .show
        while !movies.isEmpty || !shows.isEmpty {
            if movieTurn, let m = movies.popFirst() { out.append(m) } else if let s = shows.popFirst() { out.append(s) } else if let m = movies.popFirst() { out.append(m) }
            movieTurn.toggle()
        }
        return out
    }

    /// The seeds, spread over different genres: each next one is the strongest that adds the least overlap.
    static func diverseSeeds(_ candidates: [Seed], genresOf: (Seed) -> [String], limit: Int) -> [Seed] {
        var pool = candidates
        var picked: [Seed] = []
        var covered = Set<String>()
        while picked.count < limit, !pool.isEmpty {
            let best = pool.indices.max { a, b in
                func value(_ s: Seed) -> Double {
                    let g = Set(genresOf(s).map { $0.lowercased() })
                    let overlap = g.isEmpty ? 0 : Double(g.intersection(covered).count) / Double(g.count)
                    return s.weight * (1 - 0.6 * overlap)
                }
                return value(pool[a]) < value(pool[b])
            }!
            let seed = pool.remove(at: best)
            picked.append(seed)
            covered.formUnion(genresOf(seed).map { $0.lowercased() })
        }
        return picked
    }

    /// The strongest genres, for asking TMDb.
    func topGenres(_ n: Int = 4) -> [String] {
        genres.filter { $0.value > 0.05 }.sorted { $0.value > $1.value }.prefix(n).compactMap { genreNames[$0.key] }
    }

    /// The best-liked of these genres, as the person would name them.
    func liked(_ genreNames: [String], limit: Int = 2) -> [String] {
        genreNames.filter { (genres[$0.lowercased()] ?? 0) > 0.15 }
            .sorted { (genres[$0.lowercased()] ?? 0) > (genres[$1.lowercased()] ?? 0) }
            .prefix(limit).map { $0 }
    }

    /// Genres the person has never shown interest in, and doesn't dislike: where "outside your comfort zone" looks.
    func unexplored(from all: [String], limit: Int = 2, day: Int) -> [String] {
        let candidates = all.filter { name in
            let w = genres[name.lowercased()]
            return w == nil || abs(w!) < 0.1
        }.sorted()
        guard !candidates.isEmpty else { return [] }
        // A different set each day, the same all day.
        let start = day % candidates.count
        return (0..<min(limit, candidates.count)).map { candidates[(start + $0) % candidates.count] }
    }

    /// Ranks a candidate: how well it fits, how strongly it was recommended, and how good TMDb thinks it is.
    func score(_ s: Suggestion, seedWeight: Double = 0) -> Double {
        let quality = s.voteAverage > 0 ? (s.voteAverage - 6.5) * 0.12 : 0
        return seedWeight * 1.2 + fit(s.genres) + quality
    }
}
