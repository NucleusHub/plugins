import NucleusUI
import SwiftUI
import WatchlistPluginKit

/// Everyone in a title's credits: the cast in billing order, the crew by department.
struct AllCreditsView: View {
    enum Tab: Hashable { case cast, crew }

    let kind: MediaKind
    let tmdbID: Int
    let title: String
    let host: any WatchlistHost
    @State private var credits: PluginCredits?
    @State private var tab: Tab = .cast

    var body: some View {
        NucleusPage(title.isEmpty ? "Cast & crew" : LocalizedStringKey(title)) {
            if let credits {
                NucleusSegmented(selection: $tab, items: [(Tab.cast, "Cast"), (Tab.crew, "Crew")], fill: true)
                    .padding(.bottom, 8)
                switch tab {
                case .cast:
                    NucleusSection {
                        ForEach(credits.cast) { row($0) }
                    }
                case .crew:
                    ForEach(Self.departments(credits.crew), id: \.name) { department in
                        NucleusSection(LocalizedStringKey(department.name)) {
                            ForEach(department.people) { row($0) }
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 120)
            }
        }
        .task(id: tmdbID) { credits = try? await host.credits(kind, tmdbID: tmdbID) }
    }

    private func row(_ credit: PluginCredit) -> some View {
        Button { host.open(.person(credit.personID)) } label: {
            HStack(spacing: 12) {
                PersonPhoto(url: credit.photoURL, name: credit.name).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: credit.name).font(.system(size: 16)).foregroundStyle(Nucleus.primaryText).lineLimit(1)
                    if !credit.role.isEmpty {
                        Text(verbatim: credit.role).font(.system(size: 13)).foregroundStyle(Nucleus.secondaryText).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Chevron()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(NucleusRowButtonStyle())
    }

    /// Departments in the order TMDb's ranking first brings them up.
    static func departments(_ crew: [PluginCredit]) -> [(name: String, people: [PluginCredit])] {
        var order: [String] = []
        var groups: [String: [PluginCredit]] = [:]
        for c in crew {
            let name = c.department.isEmpty ? "Crew" : c.department
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(c)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}
