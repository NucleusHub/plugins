import Foundation
import WatchlistPluginKit

/// A TMDb title Discover might show, with why.
struct Suggestion: Identifiable, Hashable, Sendable {
    enum Reason: Hashable, Sendable {
        /// Recommended by TMDb for a title the person liked.
        case because(String)
        case following(String)
        case genres([String])
        case trending
        case newRelease
        /// From a genre the person hasn't shown any interest in yet.
        case different(String)
    }

    let kind: MediaKind
    let tmdbID: Int
    let title: String
    let date: String?
    let posterURL: URL?
    let genres: [String]
    let voteAverage: Double
    let voteCount: Int
    var reason: Reason
    var score: Double = 0

    var id: String { PluginMovieDNA.key(kind, tmdbID) }
    var year: String? { date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } }
}

/// TMDb's genre ids and names, both ways.
struct GenreMap: Sendable {
    var names: [MediaKind: [Int: String]] = [:]

    func name(_ id: Int, _ kind: MediaKind) -> String? { names[kind]?[id] }

    func id(_ name: String, _ kind: MediaKind) -> Int? {
        names[kind]?.first { $0.value.caseInsensitiveCompare(name) == .orderedSame }?.key
    }

    static func parse(_ data: Data) -> [Int: String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["genres"] as? [[String: Any]] else { return [:] }
        var out: [Int: String] = [:]
        for g in list { if let id = g["id"] as? Int, let name = g["name"] as? String { out[id] = name } }
        return out
    }
}

enum TMDbList {
    /// TMDb's paged list shape (`results`), keeping titles with a poster.
    /// `kind` is for endpoints of one type; mixed lists say it per result in `media_type`.
    static func parse(_ data: Data, kind: MediaKind?, genres: GenreMap, reason: Suggestion.Reason) -> [Suggestion] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            let type = (r["media_type"] as? String).map { $0 == "tv" ? MediaKind.show : $0 == "movie" ? .movie : nil } ?? kind
            guard let type, let id = r["id"] as? Int, let poster = r["poster_path"] as? String else { return nil }
            let title = (r["title"] as? String) ?? (r["name"] as? String) ?? ""
            guard !title.isEmpty else { return nil }
            let date = ((r["release_date"] as? String) ?? (r["first_air_date"] as? String)).flatMap { $0.isEmpty ? nil : $0 }
            let ids = r["genre_ids"] as? [Int] ?? []
            return Suggestion(kind: type, tmdbID: id, title: title, date: date,
                              posterURL: URL(string: "https://image.tmdb.org/t/p/w342\(poster)"),
                              genres: ids.compactMap { genres.name($0, type) },
                              voteAverage: (r["vote_average"] as? NSNumber)?.doubleValue ?? 0,
                              voteCount: (r["vote_count"] as? NSNumber)?.intValue ?? 0,
                              reason: reason)
        }
    }

    /// The first YouTube trailer of a `/videos` response, official ones first.
    static func trailer(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }
        let youtube = results.filter { $0["site"] as? String == "YouTube" && ($0["key"] as? String)?.isEmpty == false }
        let trailers = youtube.filter { $0["type"] as? String == "Trailer" }
        let pick = trailers.first { $0["official"] as? Bool == true } ?? trailers.first
            ?? youtube.first { $0["type"] as? String == "Teaser" }
        return pick?["key"] as? String
    }
}
