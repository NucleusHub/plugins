import NucleusPlugins
import SwiftUI
import WatchlistPluginKit

/// Cast & Crew: who's in a title and who made it, and a page for each of them.
public struct CastAndCrewPlugin: Plugin {
    public let manifest: PluginManifest

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: "cast-and-crew", name: "Cast & Crew", version: "1.0.0", target: ["watchlist"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .itemSections, id: "cast-and-crew", CastAndCrewSection() as any ItemSection)
        registrar.contribute(to: .pages, id: PluginPageID.person, PersonPage() as any PluginPage)
        registrar.contribute(to: .pages, id: CreditsPage.id, CreditsPage() as any PluginPage)
    }
}

struct CastAndCrewSection: ItemSection {
    var id: String { "cast-and-crew" }

    @MainActor
    func view(_ context: ItemSectionContext) -> AnyView {
        AnyView(CastAndCrewView(kind: context.kind, tmdbID: context.tmdbID, title: context.title, host: context.host,
                                canNavigate: context.canNavigate, given: context.credits))
    }
}

struct PersonPage: PluginPage {
    @MainActor
    func view(argument: String, host: any WatchlistHost) -> AnyView {
        AnyView(PersonView(personID: Int(argument) ?? 0, host: host))
    }
}

/// Everyone in a title's credits; the argument is `movie:603` or `show:1399` plus a tab and the title.
struct CreditsPage: PluginPage {
    static let id = "credits"

    static func argument(kind: MediaKind, tmdbID: Int, title: String) -> String {
        "\(kind.rawValue):\(tmdbID):\(title)"
    }

    @MainActor
    func view(argument: String, host: any WatchlistHost) -> AnyView {
        let parts = argument.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2, let kind = MediaKind(rawValue: parts[0]), let id = Int(parts[1]) else { return AnyView(EmptyView()) }
        return AnyView(AllCreditsView(kind: kind, tmdbID: id, title: parts.count > 2 ? parts[2] : "", host: host))
    }
}
