import NucleusPlugins
import SwiftUI
import WatchlistPluginKit

/// News: film and TV news behind a header button, matched to the person's titles and people.
public struct NewsPlugin: Plugin {
    public let manifest: PluginManifest

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: "news", name: "News", version: "1.0.0", target: ["watchlist"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .pages, id: NewsPage.id, NewsPage() as any PluginPage)
        registrar.contribute(to: .headerButtons, id: "news", HeaderButton(symbol: "newspaper", title: "News", pageID: NewsPage.id))
        registrar.contribute(to: .personSections, id: "news", PersonNews() as any PersonSection)
        registrar.contribute(to: .movieDNAUses, id: "news", MovieDNAUse(purpose: String(localized: "Picks the news in For you")))
    }
}

struct NewsPage: PluginPage {
    static let id = "news"

    @MainActor
    func view(argument: String, host: any WatchlistHost) -> AnyView {
        AnyView(NewsView(host: host))
    }
}

struct PersonNews: PersonSection {
    @MainActor
    func view(_ context: PersonSectionContext) -> AnyView {
        AnyView(PersonNewsView(name: context.name, host: context.host))
    }
}
