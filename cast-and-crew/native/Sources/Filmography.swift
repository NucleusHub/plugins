import Foundation
import WatchlistPluginKit

/// A person's work sorted the way their page shows it: what they do, what they're known for, and every title by role.
struct Filmography {
    struct Entry: Identifiable, Hashable {
        let titleID: Int
        let kind: MediaKind
        let title: String
        let date: String?
        let posterURL: URL?
        /// Every role or job on this title, in the order TMDb lists them.
        let roles: [String]
        let voteCount: Int

        var id: String { "\(kind.rawValue)-\(titleID)" }
        var year: String? { date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } }
    }

    struct Group: Identifiable, Hashable {
        /// The department, or `appearances` for playing themselves.
        let id: String
        let entries: [Entry]
    }

    static let appearances = "Appearances"

    let occupations: [String]
    let knownFor: [Entry]
    let groups: [Group]

    init(_ person: PluginPerson) {
        let credits = person.credits.filter { !$0.title.isEmpty }
        var byGroup: [String: [PluginPersonCredit]] = [:]
        for credit in credits {
            let group = credit.department == "Acting" && Self.isSelf(credit.role) ? Self.appearances : credit.department
            byGroup[group, default: []].append(credit)
        }
        // Their main department first, then by how much they did; appearances always last.
        let order = byGroup.keys.sorted { a, b in
            if (a == Self.appearances) != (b == Self.appearances) { return b == Self.appearances }
            if (a == person.knownFor) != (b == person.knownFor) { return a == person.knownFor }
            let ca = byGroup[a]?.count ?? 0, cb = byGroup[b]?.count ?? 0
            return ca != cb ? ca > cb : a < b
        }
        groups = order.map { Group(id: $0, entries: Self.merge(byGroup[$0] ?? [])) }
        occupations = Self.occupations(person, credits: credits)
        // Well-known titles from what they're known for, not talk-show visits.
        let main = credits.filter { $0.department == (person.knownFor ?? $0.department) && !Self.isSelf($0.role) }
        knownFor = Array(Self.merge(main.isEmpty ? credits : main).sorted { $0.voteCount > $1.voteCount }.prefix(10))
    }

    /// One entry per title, newest first; titles without a date (announced) on top.
    static func merge(_ credits: [PluginPersonCredit]) -> [Entry] {
        var order: [String] = []
        var merged: [String: Entry] = [:]
        for c in credits {
            let key = "\(c.kind.rawValue)-\(c.titleID)"
            if let prev = merged[key] {
                let roles = c.role.isEmpty || prev.roles.contains(c.role) ? prev.roles : prev.roles + [c.role]
                merged[key] = Entry(titleID: prev.titleID, kind: prev.kind, title: prev.title, date: prev.date ?? c.date,
                                    posterURL: prev.posterURL ?? c.posterURL, roles: roles, voteCount: max(prev.voteCount, c.voteCount))
            } else {
                order.append(key)
                merged[key] = Entry(titleID: c.titleID, kind: c.kind, title: c.title, date: c.date, posterURL: c.posterURL,
                                    roles: c.role.isEmpty ? [] : [c.role], voteCount: c.voteCount)
            }
        }
        return order.compactMap { merged[$0] }.sorted { ($0.date ?? "9999") > ($1.date ?? "9999") }
    }

    /// What they are, most defining first: "Actor", "Director", "Producer"...
    static func occupations(_ person: PluginPerson, credits: [PluginPersonCredit]) -> [String] {
        var counts: [String: Int] = [:]
        for c in credits where !(c.department == "Acting" && isSelf(c.role)) {
            guard let name = occupation(department: c.department, job: c.role) else { continue }
            counts[name, default: 0] += 1
        }
        let main = person.knownFor.flatMap { occupation(department: $0, job: "") }
        let ranked = counts.keys.sorted { a, b in
            if (a == main) != (b == main) { return a == main }
            return counts[a]! != counts[b]! ? counts[a]! > counts[b]! : a < b
        }
        // A one-off job isn't an occupation, unless it's all they did.
        let solid = ranked.filter { $0 == main || counts[$0]! >= 2 }
        return Array((solid.isEmpty ? ranked : solid).prefix(4))
    }

    static func occupation(department: String, job: String) -> String? {
        switch department {
        case "Acting": "Actor"
        case "Directing": job.isEmpty || job == "Director" ? "Director" : nil
        case "Writing": job == "Creator" ? "Creator" : "Writer"
        case "Production": job.contains("Casting") ? nil : "Producer"
        case "Sound": job.contains("Composer") || job == "Music" || job.isEmpty ? "Composer" : nil
        case "Camera": job == "Director of Photography" || job.isEmpty ? "Cinematographer" : nil
        case "Editing": job == "Editor" || job.isEmpty ? "Editor" : nil
        case "Creator": "Creator"
        default: nil
        }
    }

    /// Talk shows, award shows and documentaries list people as themselves.
    static func isSelf(_ role: String) -> Bool {
        let r = role.lowercased()
        return r == "self" || r.hasPrefix("self ") || r.hasPrefix("self -") || r.hasPrefix("himself") || r.hasPrefix("herself")
            || r.hasPrefix("themselves") || r.contains("(uncredited) self")
    }
}
