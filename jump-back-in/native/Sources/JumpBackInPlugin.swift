import NucleusPlugins
import SwiftUI
import WatchlistPluginKit

/// Jump back in: the last few titles you watched, at the top of the Watchlist.
public struct JumpBackInPlugin: Plugin {
    public let manifest: PluginManifest

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: "jump-back-in", name: "Jump back in", version: "1.0.0", target: ["watchlist"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .homeSections, id: "jump-back-in", JumpBackInSection() as any HomeSection)
    }
}

struct JumpBackInSection: HomeSection {
    var id: String { "jump-back-in" }

    /// Unfinished titles with a page to go back to, most recently watched first.
    static func pick(_ titles: [PluginTitle], limit: Int = 3) -> [PluginTitle] {
        titles
            .filter { !$0.isCompleted && $0.resumeHost != nil && $0.lastWatchedAt != nil }
            .sorted { ($0.lastWatchedAt ?? .distantPast) > ($1.lastWatchedAt ?? .distantPast) }
            .prefix(limit).map { $0 }
    }

    @MainActor
    func view(_ context: HomeSectionContext) -> AnyView {
        AnyView(JumpBackInView(titles: Self.pick(context.titles), canResume: context.canResume, resume: context.resume,
                       resetActions: context.resetActions, perform: context.perform))
    }
}
