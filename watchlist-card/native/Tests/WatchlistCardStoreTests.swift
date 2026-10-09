import NotesPluginKit
import SwiftUI
import XCTest
@testable import WatchlistCardPlugin

@MainActor
final class WatchlistCardStoreTests: XCTestCase {
    private final class Box { var value: JSONValue? }

    func testRefreshWritesOnlyChanges() async {
        let box = Box()
        let value = Binding(get: { box.value }, set: { box.value = $0 })
        box.value = WatchCardLogic.json([WatchCard(itemId: "w1", title: "Old title", type: "show"), WatchCard(itemId: "gone", title: "Gone", type: "movie")])
        let host = WatchSamples.host()
        let store = WatchlistCardStore(host: host, defaults: UserDefaults(suiteName: "watchlist-card-tests")!)
        await store.refresh(value)
        let cards = WatchCardLogic.cards(box.value)
        XCTAssertEqual(cards[0].title, "Severance")
        XCTAssertEqual(WatchCardLogic.progressLabel(cards[0]), "S2 · 5/10")
        XCTAssertEqual(cards[1].broken, true)
        XCTAssertNil(store.failure)
        XCTAssertNotNil(store.fetchedAt)

        host.client.failViews = .network
        let before = box.value
        await store.refresh(value)
        XCTAssertEqual(store.failure, .network)
        XCTAssertEqual(box.value, before, "offline keeps the cached cards")
    }

    func testRemoveTakesTheEmbedToo() {
        let box = Box()
        let value = Binding(get: { box.value }, set: { box.value = $0 })
        var body = NoteBody()
        let bodyBinding = Binding(get: { body }, set: { body = $0 })
        let card = WatchCard(WatchSamples.library[1])
        box.value = WatchCardLogic.json([card])
        body.blocks = [Block(text: "Hi"), WatchCardLogic.embedBlock(for: card)]
        WatchlistCardStore(host: WatchSamples.host()).remove(card, value: value, body: bodyBinding)
        XCTAssertNil(box.value)
        XCTAssertEqual(body.blocks.count, 1)
    }

    func testActivationAsksForTheScope() async {
        let ok = await WatchlistCardPlugin().activate(host: WatchSamples.host())
        XCTAssertTrue(ok)
        XCTAssertEqual(WatchlistCardPlugin().manifest.id, "watchlist-card")
        XCTAssertEqual(WatchlistCardPlugin.scopes, ["read:watchlist/library"])
    }
}
