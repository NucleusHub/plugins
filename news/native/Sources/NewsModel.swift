import Foundation
import Observation

/// Every source's latest articles, newest first, fetched straight from the sites. Kept for the session.
@MainActor
@Observable
final class NewsModel {
    static let shared = NewsModel()
    static let maxAge: TimeInterval = 20 * 60

    private(set) var articles: [Article] = []
    private(set) var loading = false
    /// Sources that didn't answer the last time, so the page can say so.
    private(set) var failedSources: [String] = []
    @ObservationIgnored private var loadedAt: Date?

    /// Articles open in the default browser unless the person picks the app's own; kept on this device.
    var openInApp = UserDefaults.standard.bool(forKey: "news.openInApp") {
        didSet { UserDefaults.standard.set(openInApp, forKey: "news.openInApp") }
    }

    func refresh(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < Self.maxAge, !articles.isEmpty { return }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let results = await withTaskGroup(of: (String, [Article]?).self) { group in
            for source in NewsSource.all {
                group.addTask { (source.name, await Self.fetch(source)) }
            }
            var out: [(String, [Article]?)] = []
            for await result in group { out.append(result) }
            return out
        }
        let merged = Self.merge(results.flatMap { $0.1 ?? [] })
        failedSources = results.filter { $0.1 == nil }.map(\.0).sorted()
        if !merged.isEmpty || articles.isEmpty { articles = merged }
        loadedAt = Date()
    }

    /// Newest first, one per link, and one per headline when outlets syndicate the same story.
    nonisolated static func merge(_ articles: [Article]) -> [Article] {
        var links = Set<String>()
        var headlines = Set<String>()
        return articles.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.filter {
            let headline = $0.title.lowercased().filter { $0.isLetter || $0.isNumber }
            return links.insert($0.id).inserted && headlines.insert(headline).inserted
        }
    }

    nonisolated private static func fetch(_ source: NewsSource) async -> [Article]? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-sampleNews") { return SampleNews.articles(source.name) }
        #endif
        var request = URLRequest(url: source.feed, timeoutInterval: 15)
        request.setValue("Watchlist (iOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { return nil }
        return RSSParser.parse(data, source: source.name)
    }
}

#if DEBUG
/// Headlines for screenshots without the network (`-sampleNews`).
enum SampleNews {
    static func articles(_ source: String) -> [Article] {
        let headlines = [
            "Denis Villeneuve Sets Next Film After ‘Dune: Part Three’",
            "Box Office: ‘Oppenheimer’ Re-Release Crosses $10 Million",
            "‘Severance’ Season 3 Starts Shooting in New York",
            "Cannes Lineup Announced: Twelve Debuts in Competition",
            "The Bear Wins Big at the Emmys Again",
            "Streaming Ratings: What Everyone Watched Last Week",
        ]
        return headlines.enumerated().map { i, title in
            Article(title: title, link: URL(string: "https://example.com/\(source.hashValue)/\(i)")!,
                    date: Date().addingTimeInterval(-Double(i * 5400 + source.count * 300)), source: source, summary: "")
        }
    }
}
#endif
