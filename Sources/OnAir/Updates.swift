import Foundation
import Observation

/// Asks GitHub, at most once a day, which ONAIR release is the latest. That one request is the
/// only one ONAIR makes that doesn't go to your provider; it carries no data about you, and
/// "Check for updates automatically" in About turns it off.
@MainActor @Observable
final class UpdateChecker {
    struct Release: Equatable {
        let version: String
        let page: URL
    }

    static let repo = "jorgesousa/onair"
    static let repoPage = URL(string: "https://github.com/\(repo)")!
    static let issuesPage = repoPage.appendingPathComponent("issues")
    static let suggestListPage = URL(string: "https://github.com/\(repo)/issues/new?title=Free%20list%3A%20&labels=free-list&body=Name%3A%0ALink%3A%0AWhat%20it%20has%3A%0AWhy%20it%27s%20free%20and%20legal%3A")!

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    var available: Release?
    var checking = false
    var lastResult: String?

    var automatic: Bool {
        didSet { UserDefaults.standard.set(automatic, forKey: "checkForUpdates") }
    }

    init() {
        automatic = UserDefaults.standard.object(forKey: "checkForUpdates") as? Bool ?? true
    }

    func checkIfDue() async {
        guard automatic else { return }
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard last.timeIntervalSinceNow < -24 * 3600 else { return }
        await check()
    }

    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("OnAir/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                lastResult = "No releases published yet."
                return
            }
            struct GH: Decodable { let tag_name: String; let html_url: URL }
            let gh = try JSONDecoder().decode(GH.self, from: data)
            let latest = gh.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            UserDefaults.standard.set(Date.now, forKey: "lastUpdateCheck")
            if Self.isNewer(latest, than: currentVersion) {
                available = Release(version: latest, page: gh.html_url)
                lastResult = nil
            } else {
                available = nil
                lastResult = "You're on the latest version."
            }
        } catch {
            lastResult = "Couldn't reach GitHub."
        }
    }

    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
