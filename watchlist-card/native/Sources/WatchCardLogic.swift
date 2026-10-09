import Foundation
import NotesPluginKit

/// The card's rules, pure so they can be tested without a server or a view.
public enum WatchCardLogic {
    public static let pluginID = "watchlist-card"
    static let app = "watchlist"
    static let view = "library"
    /// Titles one note holds.
    public static let maxCards = 10

    // MARK: Data

    /// The note's cards; entries that don't parse are skipped.
    public static func cards(_ json: JSONValue?) -> [WatchCard] {
        (json?.array ?? []).compactMap { try? $0.decode(WatchCard.self) }
    }

    /// nil when there's nothing, so a note without titles carries no data.
    public static func json(_ cards: [WatchCard]) -> JSONValue? {
        cards.isEmpty ? nil : try? JSONValue(encoding: cards)
    }

    public enum AddResult: Equatable, Sendable {
        case added([WatchCard])
        case alreadyThere
        case full
    }

    public static func add(_ card: WatchCard, to cards: [WatchCard]) -> AddResult {
        if cards.contains(where: { $0.id == card.id }) { return .alreadyThere }
        if cards.count >= maxCards { return .full }
        return .added(cards + [card])
    }

    public static func remove(_ id: String, from cards: [WatchCard]) -> [WatchCard] { cards.filter { $0.id != id } }

    // MARK: Fresh library

    /// The card with what the library says now: title, poster, status and season progress.
    public static func updated(_ card: WatchCard, from item: LibraryTitle) -> WatchCard {
        var c = card
        c.title = item.title.isEmpty ? card.title : item.title
        c.type = item.type
        c.poster = item.poster
        c.status = item.status
        c.broken = nil
        let shown = card.season.flatMap { n in item.seasons.first { $0.number == n } } ?? (card.season == nil ? item.currentSeason : nil)
        if item.type == "movie" || shown == nil {
            c.progressSeason = nil
            c.episodeCount = nil
            c.watched = nil
        } else if let shown {
            c.progressSeason = shown.number
            c.episodeCount = shown.episodeCount
            c.watched = shown.watched
            if card.season != nil, !shown.name.isEmpty { c.seasonName = shown.name }
        }
        return c
    }

    /// Every card brought up to date; a title gone from the library is marked broken and keeps what it last showed.
    public static func refreshed(_ cards: [WatchCard], with library: [LibraryTitle]) -> [WatchCard] {
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return cards.map { card in
            guard let item = byID[card.itemId] else {
                var c = card
                c.broken = true
                return c
            }
            return updated(card, from: item)
        }
    }

    // MARK: Body

    public static func embedBlock(for card: WatchCard) -> Block {
        var ref: [String: JSONValue] = ["itemId": .string(card.itemId), "title": .string(card.title), "type": .string(card.type)]
        if let season = card.season { ref["season"] = .number(Double(season)) }
        return Block(.embed, plugin: pluginID, ref: .object(ref))
    }

    /// Titles embedded in the body but missing from the data (e.g. inserted on another device) get a card too.
    public static func adopt(_ body: NoteBody, into cards: [WatchCard]) -> [WatchCard] {
        var out = cards
        for block in body.blocks where block.type == .embed && block.plugin == pluginID {
            guard let ref = block.ref, let itemId = ref["itemId"]?.string, !itemId.isEmpty else { continue }
            let card = WatchCard(itemId: itemId, title: ref["title"]?.string ?? "", type: ref["type"]?.string ?? "movie", season: ref["season"]?.int)
            if out.count < maxCards, !out.contains(where: { $0.id == card.id }) { out.append(card) }
        }
        return out
    }

    public static func removingEmbeds(_ id: String, from body: NoteBody) -> NoteBody {
        var b = body
        b.blocks.removeAll { block in
            guard block.type == .embed, block.plugin == pluginID, let itemId = block.ref?["itemId"]?.string else { return false }
            let season = block.ref?["season"]?.int
            return (season.map { "\(itemId)#\($0)" } ?? itemId) == id
        }
        return b
    }

    // MARK: Showing

    /// "S2 · 5/9" for a show's season; nil for a movie or before the library has loaded.
    public static func progressLabel(_ card: WatchCard) -> String? {
        guard !card.isMovie, let season = card.progressSeason, let total = card.episodeCount, total > 0 else { return nil }
        return "S\(season) · \(card.watched ?? 0)/\(total)"
    }

    public static func progress(_ card: WatchCard) -> Double? {
        guard progressLabel(card) != nil, let total = card.episodeCount else { return nil }
        return Double(card.watched ?? 0) / Double(total)
    }

    /// "Planned", "Watching" or "Completed", as Watchlist calls them.
    public static func statusTitle(_ status: String?) -> String? {
        switch status {
        case "planned": String(localized: "Planned")
        case "watching": String(localized: "Watching")
        case "completed": String(localized: "Completed")
        default: nil
        }
    }

    /// Watchlist's status colors.
    public static func statusHex(_ status: String?) -> UInt32? {
        switch status {
        case "planned": 0xEB6834
        case "watching": 0x2A78D6
        case "completed": 0x1BAF7A
        default: nil
        }
    }

    /// "Movie", "TV show" or "TV show · Season 2".
    public static func subtitle(_ card: WatchCard) -> String {
        if card.isMovie { return String(localized: "Movie") }
        guard let season = card.season else { return String(localized: "TV show") }
        return String(localized: "TV show · \(card.seasonName ?? String(localized: "Season \(season)"))")
    }

    public static func chip(_ cards: [WatchCard]) -> NoteChip? {
        guard let first = cards.first else { return nil }
        let icon = cards.allSatisfy { $0.broken == true } ? "exclamationmark.triangle" : (first.isMovie ? "film" : "tv")
        return NoteChip(icon: icon, text: cards.count > 1 ? "\(first.label) +\(cards.count - 1)" : first.label)
    }

    public static func shareText(_ cards: [WatchCard]) -> String? {
        guard !cards.isEmpty else { return nil }
        return cards.map { card in
            statusTitle(card.status).map { "🎬 \(card.label) (\($0))" } ?? "🎬 \(card.label)"
        }.joined(separator: "\n")
    }

    public static func searchText(_ cards: [WatchCard]) -> String? {
        cards.isEmpty ? nil : cards.map(\.title).joined(separator: " ")
    }

    /// `com.nucleushome.watchlist://item/<id>`.
    public static func url(itemId: String) -> URL? {
        itemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap { URL(string: "com.nucleushome.watchlist://item/\($0)") }
    }
}
