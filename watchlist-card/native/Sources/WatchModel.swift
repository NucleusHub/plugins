import Foundation
import NotesPluginKit

/// One title of Watchlist's published `library` view.
public struct LibraryTitle: Decodable, Identifiable, Hashable, Sendable {
    public struct Season: Decodable, Hashable, Identifiable, Sendable {
        public var number: Int
        public var name: String
        public var episodeCount: Int
        public var watched: Int

        public var id: Int { number }
        public var title: String { name.isEmpty ? String(localized: "Season \(number)") : name }
        public var finished: Bool { watched >= episodeCount }

        public init(number: Int, name: String = "", episodeCount: Int, watched: Int = 0) {
            self.number = number
            self.name = name
            self.episodeCount = episodeCount
            self.watched = watched
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            number = try c.decode(Int.self, forKey: .number)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            episodeCount = (try? c.decodeIfPresent(Int.self, forKey: .episodeCount)) ?? 0
            watched = min((try? c.decodeIfPresent(Int.self, forKey: .watched)) ?? 0, episodeCount)
        }

        private enum CodingKeys: String, CodingKey { case number, name, episodeCount, watched }
    }

    public var id: String
    public var title: String
    /// "movie" or "show".
    public var type: String
    public var poster: String?
    /// "planned", "watching" or "completed".
    public var status: String?
    public var seasons: [Season]

    public init(id: String, title: String, type: String, poster: String? = nil, status: String? = nil, seasons: [Season] = []) {
        self.id = id
        self.title = title
        self.type = type
        self.poster = poster
        self.status = status
        self.seasons = seasons
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "movie"
        poster = (try? c.decodeIfPresent(String.self, forKey: .poster)) ?? nil
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil
        // Seasons without episodes (specials not out yet) aren't anything to track.
        seasons = ((try? c.decodeIfPresent([Season].self, forKey: .seasons)) ?? []).filter { $0.episodeCount > 0 }
    }

    private enum CodingKeys: String, CodingKey { case id, title, type, poster, status, seasons }

    /// Items that don't parse are skipped rather than failing the whole library.
    public static func library(_ value: JSONValue) -> [LibraryTitle] {
        (value["items"]?.array ?? []).compactMap { try? $0.decode(LibraryTitle.self) }
    }

    /// The first season not finished, else the last.
    public var currentSeason: Season? { seasons.first { !$0.finished } ?? seasons.last }

    public var episodeTotals: (watched: Int, total: Int) {
        seasons.reduce((0, 0)) { ($0.0 + $1.watched, $0.1 + $1.episodeCount) }
    }
}

/// A Watchlist title on a note, as last seen, so the card, chip and search work offline.
public struct WatchCard: Codable, Hashable, Sendable, Identifiable {
    public var itemId: String
    public var title: String
    /// "movie" or "show".
    public var type: String
    public var poster: String?
    public var status: String?
    /// The season picked; nil for a movie or the whole show.
    public var season: Int?
    public var seasonName: String?
    /// The season the progress bar shows: the picked one, or the show's current one.
    public var progressSeason: Int?
    public var episodeCount: Int?
    public var watched: Int?
    /// The title isn't in Watchlist's library any more.
    public var broken: Bool?

    /// One card per title and season.
    public var id: String { season.map { "\(itemId)#\($0)" } ?? itemId }

    public init(itemId: String, title: String, type: String, poster: String? = nil, status: String? = nil, season: Int? = nil,
                seasonName: String? = nil, progressSeason: Int? = nil, episodeCount: Int? = nil, watched: Int? = nil, broken: Bool? = nil) {
        self.itemId = itemId
        self.title = title
        self.type = type
        self.poster = poster
        self.status = status
        self.season = season
        self.seasonName = seasonName
        self.progressSeason = progressSeason
        self.episodeCount = episodeCount
        self.watched = watched
        self.broken = broken
    }

    /// A card for a library title, or one of its seasons.
    public init(_ item: LibraryTitle, season: Int? = nil) {
        self.init(itemId: item.id, title: item.title, type: item.type, season: season,
                  seasonName: season.flatMap { n in item.seasons.first { $0.number == n } }.flatMap { $0.name.isEmpty ? nil : $0.name })
        self = WatchCardLogic.updated(self, from: item)
    }

    public var isMovie: Bool { type == "movie" }

    /// "Severance · S2".
    public var label: String { season.map { "\(title) · S\($0)" } ?? title }
}
