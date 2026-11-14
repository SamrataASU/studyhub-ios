import Foundation

/// One event read from a calendar feed (.ics file).
struct ICSEvent {
    var uid: String?
    var summary: String?
    var description: String?
    var url: String?
    var location: String?
    var start: Date?
    var end: Date?
    var isAllDay = false
}

/// A small reader for the iCalendar format that Canvas uses for its calendar feed.
enum ICSParser {
    static func parse(_ text: String) -> [ICSEvent] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Long lines are "folded" onto the next line starting with a space; join them back.
        var lines: [String] = []
        for raw in normalized.components(separatedBy: "\n") {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += String(raw.dropFirst())
            } else if !raw.isEmpty {
                lines.append(raw)
            }
        }

        var events: [ICSEvent] = []
        var current: ICSEvent?
        var nested = 0

        for line in lines {
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" { current = ICSEvent(); nested = 0; continue }
            if upper == "END:VEVENT" {
                if let c = current { events.append(c) }
                current = nil
                continue
            }
            guard current != nil else { continue }
            if upper.hasPrefix("BEGIN:") { nested += 1; continue }   // e.g. alarms inside an event
            if upper.hasPrefix("END:") { nested = max(0, nested - 1); continue }
            if nested > 0 { continue }

            guard let colon = line.firstIndex(of: ":") else { continue }
            let head = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let parts = head.split(separator: ";").map(String.init)
            guard let name = parts.first?.uppercased() else { continue }

            var params: [String: String] = [:]
            for p in parts.dropFirst() {
                let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 {
                    params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }

            switch name {
            case "UID": current?.uid = value
            case "SUMMARY": current?.summary = unescape(value)
            case "DESCRIPTION": current?.description = unescape(value)
            case "URL": current?.url = value.trimmingCharacters(in: .whitespaces)
            case "LOCATION": current?.location = unescape(value)
            case "DTSTART":
                let (date, allDay) = parseDate(value, params: params)
                current?.start = date
                current?.isAllDay = allDay
            case "DTEND":
                current?.end = parseDate(value, params: params).0
            default: break
            }
        }
        return events
    }

    static func parseDate(_ raw: String, params: [String: String]) -> (Date?, Bool) {
        let value = raw.trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")

        if params["VALUE"]?.uppercased() == "DATE" || value.count == 8 {
            f.timeZone = .current
            f.dateFormat = "yyyyMMdd"
            return (f.date(from: String(value.prefix(8))), true)
        }
        if value.hasSuffix("Z") {
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else {
            f.timeZone = params["TZID"].flatMap { TimeZone(identifier: $0) } ?? .current
            f.dateFormat = "yyyyMMdd'T'HHmmss"
        }
        return (f.date(from: value), false)
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            if c == "\\", let n = it.next() {
                switch n {
                case "n", "N": out.append("\n")
                default: out.append(n)
                }
            } else {
                out.append(c)
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
