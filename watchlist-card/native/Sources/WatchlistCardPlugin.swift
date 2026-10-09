import Foundation
import NotesPluginKit
import NucleusPlugins
import NucleusUI
import SwiftUI

/// Watchlist card: a movie, show or season from Watchlist on a note, as a poster card.
public struct WatchlistCardPlugin: Plugin, PluginActivation {
    public let manifest: PluginManifest

    static let scopes = ["read:watchlist/library"]

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: WatchCardLogic.pluginID, name: "Watchlist card", version: "1.0.0", target: ["notes"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .insertActions, id: "watchlist-title", WatchlistInsertAction() as any InsertAction)
        registrar.contribute(to: .noteSections, id: "watchlist", WatchlistNoteSection() as any NoteSection)
        registrar.contribute(to: .noteDetails, id: "watchlist", WatchlistNoteDetail() as any NoteDetail)
    }

    @MainActor
    public func activate(host: any NotesHost) async -> Bool {
        do {
            try await host.crossApp.ensureScopes(Self.scopes)
            return true
        } catch CrossAppError.notSignedIn {
            host.show(String(localized: "Sign in with Nucleus ID to connect Watchlist."), icon: "person.crop.circle.badge.exclamationmark")
        } catch CrossAppError.scopeDenied {
            host.show(String(localized: "Watchlist wasn't connected."), icon: "xmark.circle.fill")
        } catch {
            host.show(String(localized: "Couldn't connect Watchlist. Try again."), icon: "wifi.exclamationmark")
        }
        return false
    }
}

/// "Watchlist title" in the insert menu: pick one, and it lands in the body and gets a card.
struct WatchlistInsertAction: InsertAction {
    var title: LocalizedStringResource { "Watchlist title" }
    var icon: String { "film" }

    @MainActor
    func sheet(_ context: InsertContext) -> AnyView? {
        let cards = WatchCardLogic.cards(context.note.pluginData[WatchCardLogic.pluginID])
        return AnyView(
            WatchlistPicker(host: context.host, attached: Set(cards.map(\.itemId)), onPick: { card in
                switch WatchCardLogic.add(card, to: WatchCardLogic.cards(context.note.pluginData[WatchCardLogic.pluginID])) {
                case .added(let all):
                    context.host.setPluginData(noteID: context.note.id, pluginID: WatchCardLogic.pluginID, value: WatchCardLogic.json(all))
                    context.insert([WatchCardLogic.embedBlock(for: card)])
                case .alreadyThere:
                    context.host.show(String(localized: "“\(card.label)” is already in this note."), icon: "film")
                case .full:
                    context.host.show(String(localized: "A note holds up to \(WatchCardLogic.maxCards) titles."), icon: "film")
                }
                context.dismiss()
            }, onCancel: { context.dismiss() })
        )
    }
}

struct WatchlistNoteSection: NoteSection {
    @MainActor
    func view(_ context: NoteSectionContext) -> AnyView {
        AnyView(WatchlistCardSection(value: context.pluginData(for: WatchCardLogic.pluginID), noteBody: context.body,
                                     store: WatchlistCardStore(host: context.host)))
    }
}

struct WatchlistNoteDetail: NoteDetail {
    func chip(for note: PluginNote) -> NoteChip? { WatchCardLogic.chip(cards(note)) }
    func shareLine(for note: PluginNote) -> String? { WatchCardLogic.shareText(cards(note)) }
    func searchText(for note: PluginNote) -> String? { WatchCardLogic.searchText(cards(note)) }

    private func cards(_ note: PluginNote) -> [WatchCard] { WatchCardLogic.cards(note.pluginData[WatchCardLogic.pluginID]) }
}
