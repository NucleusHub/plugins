import Foundation
import WatchlistPluginKit

/// Why an article is in For you.
enum NewsReason: Hashable, Sendable {
    case following(String)
    case person(String)
    case watchlist(String)
    case movieDNA(String)
}

/// The names For you looks for in articles, strongest reason first.
struct NewsInterests: Sendable {
    struct Term: Hashable, Sendable {
        let text: String
        let reason: NewsReason
        /// Single words only count capitalised, so "Dune" matches but "dune buggies" doesn't.
        let caseSensitive: Bool
    }

    var terms: [Term] = []

    init(dna: PluginMovieDNA, library: [PluginLibraryTitle]) {
        var seen = Set<String>()
        func add(_ text: String, _ reason: NewsReason) {
            let name = text.trimmingCharacters(in: .whitespaces)
            guard Self.matchable(name), seen.insert(name.lowercased()).inserted else { return }
            terms.append(Term(text: name, reason: reason, caseSensitive: !name.contains(" ")))
        }
        // Follows only show while MovieDNA is on; that's where they're kept.
        for p in dna.people where p.followed { add(p.name, .following(p.name)) }
        for t in library where !t.isCompleted { add(t.title, .watchlist(t.title)) }
        for t in dna.titles where t.strength >= 40 { add(t.name, .movieDNA(t.name)) }
        for p in dna.people where !p.followed && p.strength >= 40 { add(p.name, .person(p.name)) }
        for t in library where t.isCompleted { add(t.title, .watchlist(t.title)) }
    }

    init(terms: [Term]) { self.terms = terms }

    /// Names too short or too common to mean the title when they turn up in a sentence.
    static func matchable(_ name: String) -> Bool {
        let words = name.split(separator: " ")
        if words.count >= 2 { return name.count >= 5 }
        return name.count >= 4 && !common.contains(name.lowercased())
    }

    private static let common: Set = ["home", "love", "life", "time", "news", "film", "show", "away", "free", "this", "that",
                                      "with", "they", "them", "here", "there", "what", "when", "will", "nope", "next", "more"]

    /// The best reason this article is for the person, or nil.
    func reason(for article: Article) -> NewsReason? {
        let text = article.title + " " + article.summary
        return terms.first { Self.contains(text, $0.text, caseSensitive: $0.caseSensitive) }?.reason
    }

    /// A whole-word match, ignoring accents ("Timothée" finds "Timothee").
    static func contains(_ text: String, _ name: String, caseSensitive: Bool) -> Bool {
        var options: String.CompareOptions = [.diacriticInsensitive]
        if !caseSensitive { options.insert(.caseInsensitive) }
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: name, options: options, range: searchRange) {
            let before = found.lowerBound == text.startIndex ? nil : text[text.index(before: found.lowerBound)]
            let after = found.upperBound == text.endIndex ? nil : text[found.upperBound]
            if !(before?.isLetter ?? false || before?.isNumber ?? false), !(after?.isLetter ?? false || after?.isNumber ?? false) {
                return true
            }
            searchRange = found.upperBound..<text.endIndex
        }
        return false
    }
}
