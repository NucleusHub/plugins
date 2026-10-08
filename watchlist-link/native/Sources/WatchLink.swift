import Foundation
import TodoPluginKit

/// A task's Watchlist title, kept in `pluginData["watchlist-link"]`.
public struct WatchLink: Codable, Hashable, Sendable {
    public struct Mark: Codable, Hashable, Sendable {
        /// The `markWatched` command.
        public var id: String
        public var status: CrossAppCommand.Status
        /// What Watchlist had before, from the command's result; what "mark unwatched" restores.
        public var previousWatched: Int?
        public var previousStatus: String?
        /// The season's count right after the mark; past it means you've watched more since.
        public var watched: Int?
        /// Each season's count before a whole-show mark.
        public var previousSeasons: [SeasonCount]?

        public init(id: String, status: CrossAppCommand.Status, previousWatched: Int? = nil, previousStatus: String? = nil,
                    watched: Int? = nil, previousSeasons: [SeasonCount]? = nil) {
            self.id = id
            self.status = status
            self.previousWatched = previousWatched
            self.previousStatus = previousStatus
            self.watched = watched
            self.previousSeasons = previousSeasons
        }
    }

    public struct SeasonCount: Codable, Hashable, Sendable {
        public var number: Int
        public var watched: Int

        public init(number: Int, watched: Int) {
            self.number = number
            self.watched = watched
        }
    }

    public var itemId: String
    public var title: String
    /// "movie" or "show".
    public var type: String
    public var poster: String?
    public var season: Int?
    public var seasonName: String?
    public var fromEp: Int?
    public var toEp: Int?
    public var mark: Mark?
    /// Reopened with "also mark unwatched" while the mark was still on its way; unmark once it lands.
    public var unwatchPending: Bool?
    /// Why Watchlist rejected the mark, e.g. "itemNotFound".
    public var broken: String?

    public init(itemId: String, title: String, type: String, poster: String? = nil, season: Int? = nil, seasonName: String? = nil, fromEp: Int? = nil, toEp: Int? = nil,
                mark: Mark? = nil, unwatchPending: Bool? = nil, broken: String? = nil) {
        self.itemId = itemId
        self.title = title
        self.type = type
        self.poster = poster
        self.season = season
        self.seasonName = seasonName
        self.fromEp = fromEp
        self.toEp = toEp
        self.mark = mark
        self.unwatchPending = unwatchPending
        self.broken = broken
    }

    public init?(_ json: JSONValue?) {
        guard let json, let link = try? json.decode(WatchLink.self) else { return nil }
        self = link
    }

    public var json: JSONValue { (try? JSONValue(encoding: self)) ?? .null }

    /// Same title, season and episodes.
    public func sameTarget(as other: WatchLink) -> Bool {
        (itemId, season, fromEp, toEp) == (other.itemId, other.season, other.fromEp, other.toEp)
    }

    /// "S2 E5–8", "S2", or nil for a movie or a whole show.
    public var range: String? {
        guard let season else { return nil }
        guard let from = fromEp, let to = toEp else { return "S\(season)" }
        return from == to ? "S\(season) E\(from)" : "S\(season) E\(from)–\(to)"
    }

    /// "Severance · S2 E5–8".
    public var label: String { [title, range].compactMap { $0 }.joined(separator: " · ") }
}

/// One title of Watchlist's published `library` view.
struct LibraryTitle: Decodable, Identifiable, Hashable {
    struct Season: Decodable, Hashable, Identifiable {
        var number: Int
        var name: String
        var episodeCount: Int
        var watched: Int

        var id: Int { number }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            number = try c.decode(Int.self, forKey: .number)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            episodeCount = try c.decodeIfPresent(Int.self, forKey: .episodeCount) ?? 0
            watched = try c.decodeIfPresent(Int.self, forKey: .watched) ?? 0
        }

        private enum CodingKeys: String, CodingKey { case number, name, episodeCount, watched }
    }

    var id: String
    var title: String
    var type: String
    var poster: String?
    var status: String?
    var seasons: [Season]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "movie"
        poster = try? c.decodeIfPresent(String.self, forKey: .poster)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        seasons = ((try? c.decodeIfPresent([Season].self, forKey: .seasons)) ?? []).filter { $0.episodeCount > 0 }
    }

    private enum CodingKeys: String, CodingKey { case id, title, type, poster, status, seasons }

    /// Items that don't parse are skipped rather than failing the whole library.
    static func library(_ value: JSONValue) -> [LibraryTitle] {
        (value["items"]?.array ?? []).compactMap { try? $0.decode(LibraryTitle.self) }
    }
}
