import Foundation

/// Reads an XMLTV guide and keeps, per channel id, the programmes from now to the next few hours.
/// One download for the whole list, instead of one request per channel.
enum XMLTV {
    static func parse(_ data: Data, from: Date = .now, hours: Double = 12) -> [String: [Programme]] {
        let d = Delegate(window: from...from.addingTimeInterval(hours * 3600))
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.out.mapValues { $0.sorted { $0.start < $1.start } }
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let window: ClosedRange<Date>
        var out: [String: [Programme]] = [:]
        private var channel: String?, start: Date?, stop: Date?
        private var title = "", inTitle = false, gotTitle = false

        init(window: ClosedRange<Date>) { self.window = window }

        private static let fmt: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMddHHmmss Z"
            return f
        }()
        private static func date(_ s: String?) -> Date? {
            guard let s else { return nil }
            let t = s.trimmingCharacters(in: .whitespaces)
            return fmt.date(from: t) ?? fmt.date(from: String(t.prefix(14)) + " +0000")
        }

        func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?,
                    attributes a: [String: String]) {
            if e == "programme" {
                channel = a["channel"]?.lowercased(); start = Self.date(a["start"]); stop = Self.date(a["stop"])
                title = ""; gotTitle = false
            } else if e == "title", channel != nil, !gotTitle {
                inTitle = true
            }
        }

        func parser(_ p: XMLParser, foundCharacters s: String) { if inTitle { title += s } }

        func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            if e == "title", inTitle { inTitle = false; gotTitle = true }
            guard e == "programme" else { return }
            defer { channel = nil }
            guard let channel, let start, let stop, stop > window.lowerBound, start < window.upperBound else { return }
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            out[channel, default: []].append(Programme(title: t.isEmpty ? "Untitled" : t, start: start, end: stop))
        }
    }
}
