import Foundation
import WatchlistPluginKit

/// Anime search on Kitsu (https://kitsu.docs.apiary.io), which needs no key.
struct KitsuSource: SearchSource {
    static let sourceID = "kitsu-anime"

    var id: String { Self.sourceID }
    var name: String { "Anime (Kitsu)" }

    var session: URLSession = .shared
    var endpoint = URL(string: "https://kitsu.io/api/edge/anime")!

    func search(_ query: String) async throws -> [SearchHit] {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "filter[text]", value: query), URLQueryItem(name: "page[limit]", value: "10")]
        var request = URLRequest(url: components.url!)
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw KitsuError.http(http.statusCode) }
        return try Self.hits(from: data)
    }

    func draft(for hit: SearchHit) async throws -> SourceDraft {
        try Self.draft(from: JSONDecoder().decode(Entry.self, from: hit.payload))
    }

    // MARK: Mapping

    static func hits(from data: Data) throws -> [SearchHit] {
        try JSONDecoder().decode(Response.self, from: data).data.map { entry in
            let a = entry.attributes
            return SearchHit(
                id: "kitsu:\(entry.id)",
                title: a.title,
                subtitle: [a.year.map(String.init), a.subtypeLabel].compactMap { $0 }.joined(separator: " · "),
                thumbnail: (a.posterImage?.small ?? a.posterImage?.medium ?? a.posterImage?.tiny).flatMap(URL.init(string:)),
                kind: a.kind,
                payload: (try? JSONEncoder().encode(entry)) ?? Data()
            )
        }
    }

    static func draft(from entry: Entry) -> SourceDraft {
        let a = entry.attributes
        var draft = SourceDraft(
            title: a.title, kind: a.kind, year: a.year,
            posterURL: a.posterImage?.original ?? a.posterImage?.large ?? a.posterImage?.medium
        )
        let perEpisode = a.episodeLength ?? 0
        if a.kind == .movie {
            if perEpisode > 0 { draft.runtime = perEpisode }
        } else {
            draft.seasons = 1
            if let episodes = a.episodeCount, episodes > 0 {
                draft.episodes = episodes
                if perEpisode > 0 { draft.showRuntime = episodes * perEpisode }
                draft.seasonList = [SourceSeason(number: 1, episodeCount: episodes)]
            }
        }
        return draft
    }

    enum KitsuError: LocalizedError {
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .http(let code): "Kitsu answered \(code)."
            }
        }
    }

    struct Response: Decodable {
        let data: [Entry]
    }

    struct Entry: Codable {
        let id: String
        let attributes: Attributes
    }

    struct Attributes: Codable {
        struct Titles: Codable {
            let en: String?
            let en_jp: String?
            let ja_jp: String?
        }

        struct Poster: Codable {
            let tiny: String?
            let small: String?
            let medium: String?
            let large: String?
            let original: String?
        }

        let canonicalTitle: String?
        let titles: Titles?
        let startDate: String?
        let subtype: String?
        let episodeCount: Int?
        let episodeLength: Int?
        let posterImage: Poster?

        var title: String {
            [canonicalTitle, titles?.en, titles?.en_jp, titles?.ja_jp].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        }

        var year: Int? { startDate.flatMap { Int($0.prefix(4)) } }
        var kind: MediaKind { subtype == "movie" ? .movie : .show }

        var subtypeLabel: String? {
            switch subtype {
            case "TV": "TV"
            // Movies are already marked as movies next to the subtitle.
            case "movie": nil
            case "OVA", "ONA": subtype
            case "special": "Special"
            case "music": "Music"
            default: nil
            }
        }
    }
}
