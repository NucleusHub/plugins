import NucleusPlugins
import WatchlistPluginKit
import XCTest
@testable import AnimeSourcePlugin

final class KitsuSourceTests: XCTestCase {
    private let sample = Data("""
    {"data":[
      {"id":"1","attributes":{"canonicalTitle":"Cowboy Bebop","titles":{"en":"Cowboy Bebop"},"startDate":"1998-04-03","subtype":"TV","episodeCount":26,"episodeLength":24,
       "posterImage":{"tiny":"https://x/t.jpg","small":"https://x/s.jpg","medium":"https://x/m.jpg","large":"https://x/l.jpg","original":"https://x/o.jpg"}}},
      {"id":"2","attributes":{"titles":{"en_jp":"Sen to Chihiro"},"startDate":"2001-07-20","subtype":"movie","episodeCount":1,"episodeLength":125,"posterImage":{"medium":"https://x/m2.jpg"}}}
    ]}
    """.utf8)

    func testSearchHitsCarryTitleSubtitleThumbnailAndKind() throws {
        let hits = try KitsuSource.hits(from: sample)
        XCTAssertEqual(hits.map(\.id), ["kitsu:1", "kitsu:2"])
        XCTAssertEqual(hits[0].title, "Cowboy Bebop")
        XCTAssertEqual(hits[0].subtitle, "1998 · TV")
        XCTAssertEqual(hits[0].thumbnail?.absoluteString, "https://x/s.jpg")
        XCTAssertEqual(hits[0].kind, .show)
        XCTAssertEqual(hits[1].title, "Sen to Chihiro", "falls back through the other titles")
        XCTAssertEqual(hits[1].kind, .movie)
        XCTAssertEqual(hits[1].subtitle, "2001")
    }

    /// A real response from the Kitsu API, trimmed to the fields the source reads.
    func testDecodesARealKitsuResponse() throws {
        let data = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "kitsu-search", withExtension: "json")))
        let hits = try KitsuSource.hits(from: data)
        XCTAssertEqual(hits.count, 5)
        XCTAssertEqual(hits.first?.title, "Cowboy Bebop")
        XCTAssertEqual(hits.first?.subtitle, "1998 · TV")
        XCTAssertEqual(hits.first?.kind, .show)
        XCTAssertEqual(hits[1].kind, .movie)
        XCTAssertTrue(hits.allSatisfy { $0.thumbnail != nil })
    }

    func testShowDraftHasEpisodesRuntimeAndOneSeason() async throws {
        let hit = try KitsuSource.hits(from: sample)[0]
        let draft = try await KitsuSource().draft(for: hit)
        XCTAssertEqual(draft.kind, .show)
        XCTAssertEqual(draft.year, 1998)
        XCTAssertEqual(draft.posterURL, "https://x/o.jpg")
        XCTAssertEqual(draft.seasons, 1)
        XCTAssertEqual(draft.episodes, 26)
        XCTAssertEqual(draft.showRuntime, 26 * 24)
        XCTAssertEqual(draft.seasonList, [SourceSeason(number: 1, episodeCount: 26)])
    }

    func testMovieDraftHasRuntimeOnly() async throws {
        let hit = try KitsuSource.hits(from: sample)[1]
        let draft = try await KitsuSource().draft(for: hit)
        XCTAssertEqual(draft.kind, .movie)
        XCTAssertEqual(draft.runtime, 125)
        XCTAssertNil(draft.episodes)
        XCTAssertTrue(draft.seasonList.isEmpty)
    }

    @MainActor
    func testPluginReadsItsBundledManifestAndContributesTheSource() throws {
        let plugin = AnimeSourcePlugin()
        XCTAssertEqual(plugin.manifest.id, "anime-source")
        XCTAssertEqual(plugin.manifest.target, ["watchlist"])
        XCTAssertTrue(plugin.manifest.validationErrors.isEmpty)
        let registry = PluginRegistry(app: "watchlist", state: InMemoryPluginStateStore())
        registry.install(plugin)
        let sources = registry.contributions(to: .searchSources)
        XCTAssertEqual(sources.map(\.id), ["kitsu-anime"])
        XCTAssertEqual(sources.first?.value.name, "Anime (Kitsu)")
    }
}
