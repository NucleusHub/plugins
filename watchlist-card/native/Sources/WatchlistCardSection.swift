import NotesPluginKit
import NucleusUI
import Observation
import SwiftUI
import UIKit

/// Loads Watchlist's library for one note's cards and writes what changed into the note's `pluginData`.
@MainActor
@Observable
final class WatchlistCardStore {
    private(set) var loading = false
    /// Why the last refresh failed; nil after one that worked.
    private(set) var failure: CrossAppError?
    /// When the library last loaded on this device.
    private(set) var fetchedAt: Date?

    @ObservationIgnored let host: any NotesHost
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private let defaults: UserDefaults
    private static let fetchedKey = "watchlist-card.fetchedAt"

    init(host: any NotesHost, now: @escaping () -> Date = Date.init, defaults: UserDefaults = .standard) {
        self.host = host
        self.now = now
        self.defaults = defaults
        let saved = defaults.double(forKey: Self.fetchedKey)
        fetchedAt = saved > 0 ? Date(timeIntervalSince1970: saved) : nil
    }

    #if DEBUG
    /// Previews show the offline footer without a failing network.
    func pretendOffline(since date: Date?) {
        failure = .network
        fetchedAt = date
    }
    #endif

    func refresh(_ value: Binding<JSONValue?>) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let library = LibraryTitle.library(try await host.crossApp.view(app: WatchCardLogic.app, name: WatchCardLogic.view))
            update(value) { WatchCardLogic.refreshed($0, with: library) }
            failure = nil
            fetchedAt = now()
            defaults.set(now().timeIntervalSince1970, forKey: Self.fetchedKey)
        } catch let error as CrossAppError {
            failure = error
        } catch {
            failure = .network
        }
    }

    func remove(_ card: WatchCard, value: Binding<JSONValue?>, body: Binding<NoteBody>) {
        update(value) { WatchCardLogic.remove(card.id, from: $0) }
        let trimmed = WatchCardLogic.removingEmbeds(card.id, from: body.wrappedValue)
        if trimmed != body.wrappedValue { body.wrappedValue = trimmed }
    }

    func adopt(_ body: NoteBody, _ value: Binding<JSONValue?>) {
        update(value) { WatchCardLogic.adopt(body, into: $0) }
    }

    func open(_ card: WatchCard) {
        guard let url = WatchCardLogic.url(itemId: card.itemId), UIApplication.shared.canOpenURL(url) else {
            host.show(String(localized: "Install Watchlist to open it."), icon: "arrow.down.app")
            return
        }
        Haptics.tap()
        UIApplication.shared.open(url)
    }

    /// Writes only a real change, so the note isn't edited by an idle refresh.
    private func update(_ value: Binding<JSONValue?>, _ change: ([WatchCard]) -> [WatchCard]) {
        let old = WatchCardLogic.cards(value.wrappedValue)
        let new = change(old)
        if new != old { value.wrappedValue = WatchCardLogic.json(new) }
    }
}

/// The note's "Watchlist" section: a poster card per attached title.
struct WatchlistCardSection: View {
    @Binding var value: JSONValue?
    @Binding var noteBody: NoteBody
    @State private var store: WatchlistCardStore

    init(value: Binding<JSONValue?>, noteBody: Binding<NoteBody>, store: WatchlistCardStore) {
        _value = value
        _noteBody = noteBody
        _store = State(initialValue: store)
    }

    var body: some View {
        let cards = WatchCardLogic.cards(value)
        Group {
            if !cards.isEmpty {
                NucleusSection("Watchlist", footer: footer) {
                    ForEach(cards) { card in
                        WatchCardRow(card: card, open: { store.open(card) }, remove: {
                            withAnimation(NucleusMotion.quick) { store.remove(card, value: $value, body: $noteBody) }
                        })
                    }
                }
                .task { await store.refresh($value) }
            }
        }
        .onAppear { store.adopt(noteBody, $value) }
        .onChange(of: noteBody) { _, body in store.adopt(body, $value) }
    }

    /// "Updated 3 hr. ago" once a refresh failed, so offline cards say how old they are.
    private var footer: Text? {
        guard store.failure != nil else { return nil }
        guard let at = store.fetchedAt else { return Text("Offline") }
        return Text("Updated \(at.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))")
    }
}

/// One title: poster, name, kind, status pill and season progress; tap opens it in Watchlist.
struct WatchCardRow: View {
    let card: WatchCard
    let open: () -> Void
    let remove: () -> Void

    private var statusColor: Color? { WatchCardLogic.statusHex(card.status).map { Color(hex: $0) } }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 14) {
                    Poster(url: card.poster, title: card.title, type: card.type, cornerRadius: 10)
                        .frame(width: 76)
                        .saturation(card.broken == true ? 0 : 1)
                        .opacity(card.broken == true ? 0.6 : 1)
                        .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(NucleusPressStyle(scale: 0.98))
            .accessibilityHint("Opens it in Watchlist")

            Menu {
                Button(action: open) { Label("Open in Watchlist", systemImage: "arrow.up.forward.app") }
                Button(role: .destructive, action: remove) { Label("Remove from note", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Nucleus.glyph)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Nucleus.well))
            }
            .accessibilityLabel("More")
        }
        .padding(14)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: card.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(verbatim: WatchCardLogic.subtitle(card))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Nucleus.secondaryText)
            }
            if card.broken == true {
                Label("Removed from Watchlist", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Nucleus.danger)
            } else if let title = WatchCardLogic.statusTitle(card.status), let statusColor {
                StatusPill(title: title, color: statusColor)
            }
            if card.broken != true, let label = WatchCardLogic.progressLabel(card), let fraction = WatchCardLogic.progress(card) {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        Capsule().fill(Nucleus.well)
                            .overlay(alignment: .leading) {
                                Capsule().fill(statusColor ?? Nucleus.accent)
                                    .frame(width: max(fraction > 0 ? 6 : 0, geo.size.width * fraction))
                            }
                    }
                    .frame(height: 5)
                    Text(verbatim: label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Nucleus.secondaryText)
                        .monospacedDigit()
                }
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Watchlist's status as a tinted capsule with a dot.
struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(verbatim: title)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}
