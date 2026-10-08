import NucleusPlugins
import NucleusUI
import SwiftUI
import TodoPluginKit

/// Watchlist link: a Watchlist title on a task, marked watched when the task gets done.
public struct WatchlistLinkPlugin: Plugin, PluginActivation {
    public let manifest: PluginManifest

    static let scopes = ["read:watchlist/library", "send:watchlist/markWatched", "send:watchlist/unmarkWatched"]

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: LinkSync.pluginID, name: "Watchlist link", version: "1.0.0", target: ["todo"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .editorSections, id: "watchlist", WatchlistEditorSection() as any TaskEditorSection)
        registrar.contribute(to: .taskDetails, id: "watchlist", WatchlistDetail() as any TaskDetail)
        registrar.contribute(to: .appEvents, id: "watchlist", WatchlistEvents() as any AppEvents)
    }

    @MainActor
    public func activate(host: any TodoHost) async -> Bool {
        do {
            try await host.crossApp.ensureScopes(Self.scopes)
            return true
        } catch CrossAppError.notSignedIn {
            host.show(String(localized: "Sign in with Nucleus ID to link Watchlist."), icon: "person.crop.circle.badge.exclamationmark")
        } catch CrossAppError.scopeDenied {
            host.show(String(localized: "Watchlist wasn't connected."), icon: "xmark.circle.fill")
        } catch {
            host.show(String(localized: "Couldn't connect Watchlist. Try again."), icon: "wifi.exclamationmark")
        }
        return false
    }
}

struct WatchlistEditorSection: TaskEditorSection {
    @MainActor
    func view(_ context: TaskEditorContext) -> AnyView {
        AnyView(WatchlistSection(value: context.pluginData(for: LinkSync.pluginID), title: context.title, host: context.host))
    }
}

struct WatchlistDetail: TaskDetail {
    func chip(for task: PluginTask) -> TaskChip? {
        link(task).map { link in
            // A title like "Watch Severance S2 E5–8" already says what; the chip adds only the episodes.
            let named = task.title.localizedCaseInsensitiveContains(link.title)
            return TaskChip(icon: icon(link), text: named ? (link.range ?? String(localized: "Watchlist")) : link.label)
        }
    }

    func shareLine(for task: PluginTask) -> String? { link(task).map { "🎬 \($0.label)" } }
    func searchText(for task: PluginTask) -> String? { link(task)?.title }

    private func icon(_ link: WatchLink) -> String {
        if link.broken != nil { return "exclamationmark.triangle" }
        if link.mark?.status == .applied { return "checkmark.circle" }
        return link.type == "movie" ? "film" : "tv"
    }

    private func link(_ task: PluginTask) -> WatchLink? { WatchLink(task.pluginData[LinkSync.pluginID]) }
}

struct WatchlistEvents: AppEvents {
    @MainActor func tasksChanged(host: any TodoHost) { LinkSync.shared.reconcile(host) }
}
