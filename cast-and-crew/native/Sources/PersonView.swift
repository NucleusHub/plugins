import NucleusUI
import SwiftUI
import WatchlistPluginKit

/// A person's page: who they are, Follow, Wikipedia, what they're known for and everything they worked on.
struct PersonView: View {
    let personID: Int
    let host: any WatchlistHost
    @Environment(\.openURL) private var openURL
    @State private var person: PluginPerson?
    @State private var filmography: Filmography?
    @State private var failed = false
    @State private var wikipedia: URL?
    @State private var bioExpanded = false
    @State private var expandedGroups: Set<String> = []

    private static let groupLimit = 12

    var body: some View {
        NucleusPage {
            if let person, let filmography {
                content(person, filmography)
            } else if failed {
                NucleusEmptyState("person.crop.circle.badge.exclamationmark", title: "Couldn't load this person",
                                  message: "Check your connection and TMDb key.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 120)
            }
        }
        .task(id: personID) { await load() }
    }

    @ViewBuilder
    private func content(_ person: PluginPerson, _ film: Filmography) -> some View {
        VStack(spacing: 12) {
            PersonPhoto(url: person.photoURL, name: person.name)
                .frame(width: 150, height: 150)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            Text(verbatim: person.name)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .multilineTextAlignment(.center)
                .foregroundStyle(Nucleus.primaryText)
            if !film.occupations.isEmpty {
                Text(film.occupations.map { String(localized: String.LocalizationValue($0)) }.joined(separator: " · "))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Nucleus.accent)
            }
            if let life = lifeLine(person) {
                Text(verbatim: life)
                    .font(.system(size: 14))
                    .foregroundStyle(Nucleus.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)

        HStack(spacing: 10) {
            followButton(person)
            if let wikipedia {
                Button { openURL(wikipedia) } label: {
                    Label("Wikipedia", systemImage: "book.closed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Nucleus.primaryText)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Capsule().fill(Nucleus.well))
                }
                .buttonStyle(NucleusPressStyle(scale: 0.96))
            }
        }
        .padding(.bottom, 24)

        if !person.biography.isEmpty {
            NucleusSection("Biography") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: person.biography)
                        .font(.system(size: 15))
                        .foregroundStyle(Nucleus.primaryText)
                        .lineLimit(bioExpanded ? nil : 6)
                    if person.biography.count > 380 {
                        Button(bioExpanded ? "Show less" : "Read more") { withAnimation { bioExpanded.toggle() } }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Nucleus.accent)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        if !film.knownFor.isEmpty {
            NucleusSection("Known for") {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(film.knownFor) { entry in
                            Button { host.open(.title(entry.kind, entry.titleID)) } label: { KnownForCard(entry: entry, inLibrary: host.inLibrary(entry.kind, tmdbID: entry.titleID)) }
                                .buttonStyle(NucleusPressStyle(scale: 0.96))
                        }
                    }
                    .padding(14)
                }
            }
        }

        host.personSections(personID: person.id, name: person.name)

        ForEach(film.groups) { group in
            let expanded = expandedGroups.contains(group.id)
            NucleusSection(LocalizedStringKey(group.id)) {
                ForEach(expanded ? group.entries : Array(group.entries.prefix(Self.groupLimit))) { entry in
                    Button { host.open(.title(entry.kind, entry.titleID)) } label: {
                        FilmographyRow(entry: entry, inLibrary: host.inLibrary(entry.kind, tmdbID: entry.titleID))
                    }
                    .buttonStyle(NucleusRowButtonStyle())
                }
                if group.entries.count > Self.groupLimit {
                    Button {
                        withAnimation { if expanded { expandedGroups.remove(group.id) } else { expandedGroups.insert(group.id) } }
                    } label: {
                        NucleusRow(expanded ? "Show fewer" : "Show all \(group.entries.count)")
                    }
                    .buttonStyle(NucleusRowButtonStyle())
                }
            }
        }
    }

    private func followButton(_ person: PluginPerson) -> some View {
        let following = host.isFollowing(person.id)
        return Button {
            Haptics.tap()
            withAnimation(NucleusMotion.quick) {
                host.setFollowing(!following, personID: person.id, name: person.name, photoURL: person.photoURL)
            }
        } label: {
            Label(following ? "Following" : "Follow", systemImage: following ? "checkmark" : "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(following ? Nucleus.primaryText : .white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Capsule().fill(following ? AnyShapeStyle(Nucleus.well) : AnyShapeStyle(Nucleus.primaryGradient)))
        }
        .buttonStyle(NucleusPressStyle(scale: 0.96))
        .accessibilityHint("Following someone shapes your MovieDNA.")
    }

    /// "Born 18 December 1963 in Shawnee, Oklahoma" or "1930 – 2020".
    private func lifeLine(_ person: PluginPerson) -> String? {
        func date(_ s: String?) -> String? {
            guard let s, let d = PluginPersonCredit.dateFormat.date(from: s) else { return nil }
            return d.formatted(date: .long, time: .omitted)
        }
        let born = date(person.birthday), died = date(person.deathday)
        var parts: [String] = []
        if let born, let died {
            parts.append("\(born) – \(died)")
        } else if let born {
            parts.append(String(localized: "Born \(born)"))
        }
        if let place = person.birthplace { parts.append(place) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func load() async {
        do {
            let person = try await host.person(personID)
            filmography = Filmography(person)
            self.person = person
            if let wikidata = person.wikidataID { wikipedia = await Wikipedia.article(wikidataID: wikidata) }
        } catch {
            failed = true
        }
    }
}

struct KnownForCard: View {
    let entry: Filmography.Entry
    let inLibrary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TitlePoster(url: entry.posterURL, cornerRadius: 12)
                .frame(width: 110, height: 165)
                .overlay(alignment: .topTrailing) { if inLibrary { LibraryBadge().padding(6) } }
            Text(verbatim: entry.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Nucleus.primaryText)
                .lineLimit(2)
            if let year = entry.year {
                Text(verbatim: year).font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText)
            }
        }
        .frame(width: 110, alignment: .leading)
    }
}

struct FilmographyRow: View {
    let entry: Filmography.Entry
    let inLibrary: Bool

    var body: some View {
        HStack(spacing: 12) {
            TitlePoster(url: entry.posterURL, cornerRadius: 6).frame(width: 40, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.title)
                    .font(.system(size: 16))
                    .foregroundStyle(Nucleus.primaryText)
                    .lineLimit(1)
                Text(verbatim: [entry.year, entry.roles.isEmpty ? nil : entry.roles.joined(separator: ", ")].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundStyle(Nucleus.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if inLibrary { LibraryBadge() }
            Chevron()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
