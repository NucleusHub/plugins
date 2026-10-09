import NotesPluginKit
import XCTest
@testable import WatchlistCardPlugin

final class WatchCardLogicTests: XCTestCase {
    private let severance = LibraryTitle(id: "w1", title: "Severance", type: "show", poster: "https://x/p.jpg", status: "watching", seasons: [
        .init(number: 1, episodeCount: 9, watched: 9), .init(number: 2, name: "Season Two", episodeCount: 10, watched: 5),
    ])
    private let movie = LibraryTitle(id: "m1", title: "Past Lives", type: "movie", status: "planned")

    func testDecodesTheLibraryLeniently() throws {
        let json = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"items":[
          {"id":"a","title":"Severance","type":"show","tmdbId":95396,"poster":"https://x/p.jpg","status":"watching",
           "seasons":[{"number":0,"name":"Specials","episodeCount":0,"watched":0},{"number":1,"name":"","episodeCount":9,"watched":12}]},
          {"id":"b","title":"Past Lives","type":"movie","poster":null,"status":"planned","seasons":[]},
          {"title":"no id"},
          {"id":"c","poster":7,"status":null,"seasons":"junk"}
        ]}
        """.utf8))
        let items = LibraryTitle.library(json)
        XCTAssertEqual(items.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(items[0].seasons.map(\.number), [1], "seasons without episodes are dropped")
        XCTAssertEqual(items[0].seasons[0].watched, 9, "watched is capped at the episode count")
        XCTAssertEqual(items[0].seasons[0].title, "Season 1")
        XCTAssertNil(items[1].poster)
        XCTAssertEqual(items[2].type, "movie")
        XCTAssertNil(items[2].poster)
        XCTAssertEqual(items[2].seasons, [])
        XCTAssertEqual(LibraryTitle.library(.null), [])
    }

    func testCardsFollowTheLibrary() {
        let whole = WatchCard(severance)
        XCTAssertEqual(whole.id, "w1")
        XCTAssertEqual(whole.progressSeason, 2, "the whole show shows the season you're on")
        XCTAssertEqual(WatchCardLogic.progressLabel(whole), "S2 · 5/10")
        XCTAssertEqual(WatchCardLogic.subtitle(whole), "TV show")

        let first = WatchCard(severance, season: 1)
        XCTAssertEqual(first.id, "w1#1")
        XCTAssertEqual(WatchCardLogic.progressLabel(first), "S1 · 9/9")
        XCTAssertEqual(WatchCardLogic.progress(first), 1)
        XCTAssertEqual(WatchCardLogic.subtitle(WatchCard(severance, season: 2)), "TV show · Season Two")
        XCTAssertEqual(WatchCard(severance, season: 2).label, "Severance · S2")

        let film = WatchCard(movie)
        XCTAssertNil(WatchCardLogic.progressLabel(film))
        XCTAssertEqual(WatchCardLogic.subtitle(film), "Movie")
        XCTAssertEqual(WatchCardLogic.statusTitle(film.status), "Planned")
        XCTAssertEqual(WatchCardLogic.statusHex("planned"), 0xEB6834)
        XCTAssertEqual(WatchCardLogic.statusHex("watching"), 0x2A78D6)
        XCTAssertEqual(WatchCardLogic.statusHex("completed"), 0x1BAF7A)
        XCTAssertNil(WatchCardLogic.statusHex("other"))
    }

    func testRefreshUpdatesAndMarksMissingTitles() {
        let cards = [WatchCard(severance, season: 2), WatchCard(movie)]
        var later = severance
        later.status = "completed"
        later.seasons[1].watched = 10
        later.poster = "https://x/new.jpg"
        let fresh = WatchCardLogic.refreshed(cards, with: [later])
        XCTAssertEqual(fresh[0].status, "completed")
        XCTAssertEqual(fresh[0].watched, 10)
        XCTAssertEqual(fresh[0].poster, "https://x/new.jpg")
        XCTAssertEqual(fresh[1].broken, true)
        XCTAssertEqual(fresh[1].title, "Past Lives", "keeps what it last showed")
        XCTAssertNil(WatchCardLogic.refreshed(fresh, with: [later, movie])[1].broken, "back again")
        XCTAssertEqual(WatchCardLogic.refreshed(cards, with: [severance, movie]), cards, "same library, same cards")

        var noSeason = severance
        noSeason.seasons = [.init(number: 1, episodeCount: 9)]
        XCTAssertNil(WatchCardLogic.refreshed(cards, with: [noSeason])[0].progressSeason, "a season that went away shows no bar")
    }

    func testAddingCapsAndDedupes() {
        let one = WatchCard(movie)
        guard case .added(let cards) = WatchCardLogic.add(one, to: []) else { return XCTFail() }
        XCTAssertEqual(WatchCardLogic.add(one, to: cards), .alreadyThere)
        guard case .added = WatchCardLogic.add(WatchCard(severance, season: 1), to: cards) else { return XCTFail("another season is another card") }
        let full = (0..<WatchCardLogic.maxCards).map { WatchCard(itemId: "i\($0)", title: "T\($0)", type: "movie") }
        XCTAssertEqual(WatchCardLogic.add(one, to: full), .full)
        XCTAssertEqual(WatchCardLogic.remove("i3", from: full).count, WatchCardLogic.maxCards - 1)
    }

    func testDataRoundTrips() {
        let cards = [WatchCard(severance, season: 2), WatchCard(movie)]
        XCTAssertEqual(WatchCardLogic.cards(WatchCardLogic.json(cards)), cards)
        XCTAssertNil(WatchCardLogic.json([]))
        XCTAssertEqual(WatchCardLogic.cards(.string("junk")), [])
        XCTAssertEqual(WatchCardLogic.cards([["itemId": "x", "title": "X", "type": "movie"], "junk"]).map(\.itemId), ["x"])
    }

    func testEmbedsAdoptAndRemove() {
        let card = WatchCard(severance, season: 2)
        let block = WatchCardLogic.embedBlock(for: card)
        XCTAssertEqual(block.type, .embed)
        XCTAssertEqual(block.plugin, "watchlist-card")
        XCTAssertEqual(block.ref?["itemId"]?.string, "w1")
        XCTAssertEqual(block.ref?["season"]?.int, 2)
        let movieBlock = WatchCardLogic.embedBlock(for: WatchCard(movie))
        XCTAssertNil(movieBlock.ref?["season"])

        let body = NoteBody(blocks: [Block(text: "Watch"), block, movieBlock, Block(.embed, plugin: "other", ref: ["itemId": "w1"])])
        let adopted = WatchCardLogic.adopt(body, into: [])
        XCTAssertEqual(adopted.map(\.id), ["w1#2", "m1"])
        XCTAssertEqual(adopted[0].title, "Severance")
        XCTAssertEqual(WatchCardLogic.adopt(body, into: adopted), adopted)

        let trimmed = WatchCardLogic.removingEmbeds("w1#2", from: body)
        XCTAssertEqual(trimmed.blocks.count, 3)
        XCTAssertTrue(trimmed.blocks.contains { $0.plugin == "other" })
    }

    func testChipShareAndSearch() {
        let cards = [WatchCard(severance, season: 2), WatchCard(movie)]
        XCTAssertEqual(WatchCardLogic.chip([cards[1]]), NoteChip(icon: "film", text: "Past Lives"))
        XCTAssertEqual(WatchCardLogic.chip(cards), NoteChip(icon: "tv", text: "Severance · S2 +1"))
        XCTAssertEqual(WatchCardLogic.shareText(cards), "🎬 Severance · S2 (Watching)\n🎬 Past Lives (Planned)")
        XCTAssertEqual(WatchCardLogic.searchText(cards), "Severance Past Lives")
        var gone = cards[1]
        gone.broken = true
        XCTAssertEqual(WatchCardLogic.chip([gone])?.icon, "exclamationmark.triangle")
        XCTAssertNil(WatchCardLogic.chip([]))
        XCTAssertNil(WatchCardLogic.shareText([]))
        XCTAssertNil(WatchCardLogic.searchText([]))
    }

    func testURL() {
        XCTAssertEqual(WatchCardLogic.url(itemId: "abc123")?.absoluteString, "com.nucleushome.watchlist://item/abc123")
    }
}
