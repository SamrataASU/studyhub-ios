import Foundation

enum CanvasError: LocalizedError {
    case badLink, notACalendar, server(Int)

    var errorDescription: String? {
        switch self {
        case .badLink: return "That doesn't look like a valid link."
        case .notACalendar: return "That link didn't return a calendar. Copy the “Calendar Feed” link from Canvas."
        case .server(let code): return "Canvas answered with error \(code). Try again later."
        }
    }
}

/// Downloads the ASU Canvas calendar feed (assignments, exams, course events).
enum CanvasService {
    static var cacheURL: URL { AppPaths.support.appendingPathComponent("canvas-cache.ics") }

    static func normalizedURL(_ raw: String) -> URL? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("webcal://") { t = "https://" + t.dropFirst("webcal://".count) }
        guard let url = URL(string: t), url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }

    static func download(feed: String) async throws -> String {
        guard let url = normalizedURL(feed) else { throw CanvasError.badLink }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CanvasError.server(http.statusCode)
        }
        let text = String(decoding: data, as: UTF8.self)
        guard text.contains("BEGIN:VCALENDAR") else { throw CanvasError.notACalendar }
        return text
    }

    static func items(fromICS text: String) -> [StudyItem] {
        ICSParser.parse(text).compactMap { ev -> StudyItem? in
            guard let start = ev.start else { return nil }
            let (title, course) = splitCourse(ev.summary ?? "Untitled")
            let link = ev.url.flatMap { URL(string: $0) }
            let kind = ItemKind.classify(title: title, url: link, fromCanvas: true)
            let notes = ev.description.flatMap { $0.isEmpty ? nil : $0 }
            return StudyItem(
                id: "canvas-" + (ev.uid ?? "\(title)-\(Int(start.timeIntervalSince1970))"),
                title: title,
                course: course,
                start: start,
                end: ev.end,
                isAllDay: ev.isAllDay,
                kind: kind,
                source: .canvas,
                url: link,
                notes: notes,
                location: ev.location,
                tint: kind.color,
                eventIdentifier: nil
            )
        }
    }

    /// Canvas titles look like "Homework 5 [FIN 525 Fall 2026]". Split off the course.
    static func splitCourse(_ summary: String) -> (String, String?) {
        guard let r = summary.range(of: #"\s*\[([^\]]+)\]\s*$"#, options: .regularExpression) else {
            return (summary, nil)
        }
        let inner = summary[r].trimmingCharacters(in: CharacterSet(charactersIn: "[] \t"))
        let title = String(summary[..<r.lowerBound])
        return (title.isEmpty ? summary : title, inner.isEmpty ? nil : inner)
    }
}
