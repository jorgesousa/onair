import Foundation

enum M3UParser {
    static func parse(_ text: String, base: URL?) -> [Channel] {
        var channels: [Channel] = []
        var name: String?
        var group = ""
        var logo: URL?
        var epgID: String?
        var headers: [String: String] = [:]

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXTINF") {
                name = title(of: line)
                if name?.isEmpty ?? true { name = attribute("tvg-name", in: line) }
                group = attribute("group-title", in: line) ?? ""
                logo = attribute("tvg-logo", in: line).flatMap(URL.init(string:))
                epgID = attribute("tvg-id", in: line)
                headers = [:]
                if let ua = attribute("http-user-agent", in: line) { headers["User-Agent"] = ua }
                if let ref = attribute("http-referrer", in: line) { headers["Referer"] = ref }
            } else if line.hasPrefix("#EXTVLCOPT:") {
                // VLC-style per-stream options: some streams only answer to a given browser or page.
                let opt = line.dropFirst(11)
                if let v = value(of: "http-user-agent=", in: opt) { headers["User-Agent"] = v }
                if let v = value(of: "http-referrer=", in: opt) { headers["Referer"] = v }
            } else if line.hasPrefix("#EXTGRP:") {
                group = String(line.dropFirst(8))
            } else if !line.hasPrefix("#") {
                guard let url = URL(string: line, relativeTo: base)?.absoluteURL else { continue }
                channels.append(Channel(name: name ?? url.lastPathComponent,
                                        group: group.isEmpty ? "Uncategorised" : group,
                                        logo: logo, url: url, epgID: epgID,
                                        headers: headers.isEmpty ? nil : headers))
                name = nil; group = ""; logo = nil; epgID = nil; headers = [:]
            }
        }
        return channels
    }

    /// The title is what follows the first comma outside quoted attribute values.
    /// (Attribute values such as a user agent can contain commas themselves.)
    private static func title(of line: String) -> String? {
        var inQuotes = false
        for i in line.indices {
            let ch = line[i]
            if ch == "\"" { inQuotes.toggle() }
            else if ch == ",", !inQuotes {
                return String(line[line.index(after: i)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func value(of key: String, in s: Substring) -> String? {
        guard s.hasPrefix(key) else { return nil }
        let v = String(s.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    private static func attribute(_ key: String, in line: String) -> String? {
        guard let r = line.range(of: " " + key + "=\"") ?? line.range(of: key + "=\"") else { return nil }
        let rest = line[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let v = String(rest[..<end])
        return v.isEmpty ? nil : v
    }
}
