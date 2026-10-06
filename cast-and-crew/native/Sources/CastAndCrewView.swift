import NucleusUI
import SwiftUI
import WatchlistPluginKit

/// The people behind a title, key crew first, as a strip on its page. Tapping one opens their page.
struct CastAndCrewView: View {
    let kind: MediaKind
    let tmdbID: Int?
    let title: String
    let host: any WatchlistHost
    var canNavigate = true
    /// Entered by hand; shown as they are instead of asking TMDb.
    var given: PluginCredits?
    @State private var fetched: PluginCredits?

    /// The jobs that say who made it; the rest of the crew waits for "See all".
    private static let keyJobs: Set = ["Director", "Creator", "Screenplay", "Writer", "Novel", "Original Music Composer", "Composer"]

    var body: some View {
        Group {
            if let credits = given ?? fetched, !credits.cast.isEmpty || !credits.crew.isEmpty {
                let people = Self.strip(credits, allCrew: given != nil)
                NucleusSection("Cast & crew") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(people) { credit in
                                // Someone typed in by hand has no TMDb page to open.
                                if canNavigate, credit.personID > 0 {
                                    Button { host.open(.person(credit.personID)) } label: { PersonBubble(credit: credit) }
                                        .buttonStyle(NucleusPressStyle(scale: 0.95))
                                } else {
                                    PersonBubble(credit: credit)
                                }
                            }
                        }
                        .padding(14)
                    }
                    if canNavigate, given == nil, let tmdbID {
                        Button { host.open(.page(id: CreditsPage.id, argument: CreditsPage.argument(kind: kind, tmdbID: tmdbID, title: title))) } label: {
                            NucleusRow("See all cast & crew") { Chevron() }
                        }
                        .buttonStyle(NucleusRowButtonStyle())
                    }
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: tmdbID) {
            guard given == nil, let tmdbID else { return }
            fetched = try? await host.credits(kind, tmdbID: tmdbID)
        }
    }

    /// Key crew, one bubble per person with their jobs joined, then the top-billed cast.
    /// Hand-entered credits are short and chosen on purpose, so all their crew shows.
    static func strip(_ credits: PluginCredits, allCrew: Bool = false) -> [PluginCredit] {
        var crew: [PluginCredit] = []
        for c in credits.crew where allCrew || keyJobs.contains(c.role) {
            if let i = crew.firstIndex(where: { $0.personID == c.personID && (c.personID > 0 || $0.name == c.name) }) {
                let prev = crew[i]
                crew[i] = PluginCredit(personID: prev.personID, name: prev.name, role: "\(prev.role), \(c.role)", department: prev.department, photoURL: prev.photoURL)
            } else {
                crew.append(c)
            }
        }
        return Array(crew.prefix(allCrew ? 20 : 4)) + Array(credits.cast.prefix(20))
    }
}

/// A round photo with a name and role under it.
struct PersonBubble: View {
    let credit: PluginCredit
    var size: CGFloat = 76

    var body: some View {
        VStack(spacing: 6) {
            PersonPhoto(url: credit.photoURL, name: credit.name)
                .frame(width: size, height: size)
            Text(verbatim: credit.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Nucleus.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if !credit.role.isEmpty {
                Text(verbatim: credit.role)
                    .font(.system(size: 12))
                    .foregroundStyle(Nucleus.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: size + 14)
    }
}

/// A circular photo, with initials when TMDb has no picture.
struct PersonPhoto: View {
    let url: URL?
    let name: String

    var body: some View {
        Circle()
            .fill(Nucleus.well)
            .overlay {
                if let url {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { initials }
                } else {
                    initials
                }
            }
            .clipShape(Circle())
    }

    private var initials: some View {
        Text(verbatim: name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Nucleus.secondaryText)
    }
}
