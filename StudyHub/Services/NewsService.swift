import Foundation

struct NewsArticle: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let source: String
    let link: URL
    let published: Date?
}

/// Finance topics, each pulled from Google News' free RSS search (last 24 hours).
enum NewsTopic: String, CaseIterable, Identifiable {
    case top = "Top"
    case markets = "Markets"
    case economy = "Economy"
    case corporate = "Corporate"
    case investing = "Investing"

    var id: String { rawValue }

    var query: String {
        switch self {
        case .top: return "finance"
        case .markets: return "stock market OR Wall Street OR Nasdaq"
        case .economy: return "economy OR Federal Reserve OR inflation"
        case .corporate: return "earnings OR merger OR IPO"
        case .investing: return "investing OR personal finance"
        }
    }

    var icon: String {
        switch self {
        case .top: return "star.fill"
        case .markets: return "chart.line.uptrend.xyaxis"
        case .economy: return "building.columns.fill"
        case .corporate: return "briefcase.fill"
        case .investing: return "dollarsign.circle.fill"
        }
    }

    var feedURL: URL {
        var c = URLComponents(string: "https://news.google.com/rss/search")!
        c.queryItems = [
            URLQueryItem(name: "q", value: query + " when:1d"),
            URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "gl", value: "US"),
            URLQueryItem(name: "ceid", value: "US:en"),
        ]
        return c.url!
    }
}

enum NewsService {
    static func fetch(_ topic: NewsTopic) async throws -> [NewsArticle] {
        var request = URLRequest(url: topic.feedURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: request)
        let parsed = RSSParser().parse(data)
        var seen = Set<String>()
        let unique = parsed.filter { seen.insert($0.title.lowercased()).inserted }
        return unique.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
    }
}

/// Reads the RSS feed Google News returns.
final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [NewsArticle] = []
    private var inItem = false
    private var text = ""
    private var title = ""
    private var link = ""
    private var pubDate = ""
    private var source = ""
    private var guid = ""

    func parse(_ data: Data) -> [NewsArticle] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "item" {
            inItem = true
            title = ""; link = ""; pubDate = ""; source = ""; guid = ""
        }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        guard inItem else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title": title = value
        case "link": link = value
        case "pubDate": pubDate = value
        case "source": source = value
        case "guid": guid = value
        case "item":
            inItem = false
            if let url = URL(string: link), !title.isEmpty {
                var headline = title
                let suffix = " - " + source
                if !source.isEmpty, headline.hasSuffix(suffix) {
                    headline = String(headline.dropLast(suffix.count))
                }
                items.append(NewsArticle(id: guid.isEmpty ? link : guid, title: headline,
                                         source: source, link: url, published: Self.date(pubDate)))
            }
        default: break
        }
        text = ""
    }

    private static func date(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: s)
    }
}
