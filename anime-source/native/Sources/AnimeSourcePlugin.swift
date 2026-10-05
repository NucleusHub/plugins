import Foundation
import NucleusPlugins
import WatchlistPluginKit

/// Adds anime search to Watchlist, from the free Kitsu API. The Swift counterpart of `client/watchlistSources.js`.
public struct AnimeSourcePlugin: Plugin {
    public let manifest: PluginManifest

    public init() {
        // The bundled manifest is the source of truth; the fallback only guards a broken bundle.
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: "anime-source", name: "Anime Source", version: "1.0.0", target: ["watchlist"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .searchSources, id: KitsuSource.sourceID, KitsuSource() as any SearchSource)
    }
}
