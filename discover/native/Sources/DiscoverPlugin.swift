import NucleusPlugins
import SwiftUI
import WatchlistPluginKit

/// Discover: a Home tab of suggestions built from MovieDNA.
public struct DiscoverPlugin: Plugin {
    public let manifest: PluginManifest

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: "discover", name: "Discover", version: "1.0.0", target: ["watchlist"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .homeTabs, id: "discover", DiscoverTab() as any PluginTab)
        registrar.contribute(to: .movieDNAUses, id: "discover", MovieDNAUse(purpose: String(localized: "Picks what Discover shows you")))
    }
}

struct DiscoverTab: PluginTab {
    var title: String { "Discover" }

    @MainActor
    func view(host: any WatchlistHost) -> AnyView {
        AnyView(DiscoverView(host: host))
    }
}
