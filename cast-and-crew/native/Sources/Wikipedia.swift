import Foundation

/// Finds a person's Wikipedia article through the Wikidata id TMDb gives, in the phone's language when there is one.
enum Wikipedia {
    nonisolated(unsafe) private static var cache: [String: URL] = [:]
    private static let lock = NSLock()

    static func article(wikidataID: String, languages: [String] = preferredLanguages) async -> URL? {
        let id = wikidataID.filter { $0.isLetter || $0.isNumber }
        guard !id.isEmpty else { return nil }
        if let hit = lock.withLock({ cache[id] }) { return hit }
        guard let url = URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(id).json"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let found = article(in: data, id: id, languages: languages) else { return nil }
        lock.withLock { cache[id] = found }
        return found
    }

    static func article(in data: Data, id: String, languages: [String]) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entities = json["entities"] as? [String: Any],
              let entity = (entities[id] ?? entities.values.first) as? [String: Any],
              let sitelinks = entity["sitelinks"] as? [String: Any] else { return nil }
        for language in languages {
            if let link = sitelinks["\(language)wiki"] as? [String: Any] {
                if let url = (link["url"] as? String).flatMap(URL.init(string:)) { return url }
                if let title = link["title"] as? String,
                   let escaped = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                    return URL(string: "https://\(language).wikipedia.org/wiki/\(escaped)")
                }
            }
        }
        return nil
    }

    /// The phone's languages, then English.
    static var preferredLanguages: [String] {
        var out = Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        out.append("en")
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }
}
