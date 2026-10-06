import Foundation

/// A news site and its RSS feed.
struct NewsSource: Hashable, Sendable {
    let id: String
    let name: String
    let feed: URL

    /// Free trade and film press with full RSS feeds.
    static let all: [NewsSource] = [
        NewsSource(id: "variety", name: "Variety", feed: URL(string: "https://variety.com/feed/")!),
        NewsSource(id: "deadline", name: "Deadline", feed: URL(string: "https://deadline.com/feed/")!),
        NewsSource(id: "thr", name: "The Hollywood Reporter", feed: URL(string: "https://www.hollywoodreporter.com/feed/")!),
        NewsSource(id: "indiewire", name: "IndieWire", feed: URL(string: "https://www.indiewire.com/feed/")!),
        NewsSource(id: "slashfilm", name: "/Film", feed: URL(string: "https://www.slashfilm.com/feed/")!),
    ]
}

struct Article: Identifiable, Hashable, Sendable {
    let title: String
    let link: URL
    let date: Date?
    let source: String
    /// The summary without its HTML, for matching.
    let summary: String

    var id: String { link.absoluteString }
}

/// Reads an RSS 2.0 feed's items: title, link, date and description.
final class RSSParser: NSObject, XMLParserDelegate {
    private let source: String
    private var articles: [Article] = []
    private var current: [String: String]?
    private var text = ""

    init(source: String) { self.source = source }

    static func parse(_ data: Data, source: String) -> [Article] {
        let parser = XMLParser(data: data)
        let delegate = RSSParser(source: source)
        parser.delegate = delegate
        parser.parse()
        return delegate.articles
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "item" { current = [:] }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(decoding: block, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard current != nil else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title", "link", "pubDate", "description": if current?[name] == nil { current?[name] = value }
        case "item":
            if let item = current, let title = item["title"].map(Self.plain), !title.isEmpty,
               let link = item["link"].flatMap(URL.init(string:)), link.scheme?.hasPrefix("http") == true {
                articles.append(Article(title: title, link: link, date: item["pubDate"].flatMap(Self.date), source: source,
                                        summary: Self.plain(item["description"] ?? "")))
            }
            current = nil
        default: break
        }
        text = ""
    }

    /// Text without tags, and with the common entities decoded.
    static func plain(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, char) in ["&amp;": "&", "&quot;": "\"", "&#039;": "'", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">",
                               "&nbsp;": " ", "&#8217;": "’", "&#8216;": "‘", "&#8220;": "“", "&#8221;": "”", "&#8211;": "–", "&#8212;": "—",
                               "&#8230;": "…", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”"] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    private static let formats: [DateFormatter] = ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    /// RSS dates (RFC 822), as feeds actually write them.
    static func date(_ string: String) -> Date? {
        for f in formats { if let d = f.date(from: string) { return d } }
        return nil
    }
}
