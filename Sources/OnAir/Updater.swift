import Foundation
import AppKit
import Observation

/// Installs a new version from inside the app, the way the user would by hand:
/// Homebrew installs run `brew update` and `brew upgrade onair`, source builds run
/// `git pull` and the build script. Then ONAIR quits and the new version opens.
/// When Homebrew belongs to another account, its password is needed, so the same
/// steps open in Terminal instead.
@MainActor @Observable
final class Updater {
    enum Install: Equatable {
        case homebrew(prefix: URL, owner: String?)   // owner set when it isn't this account
        case source(clone: URL)
        case unknown
    }
    enum Phase: Equatable { case idle, running, done, failed(String) }

    static let install: Install = detect()
    var phase: Phase = .idle
    var log = ""

    nonisolated static func detect() -> Install {
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let path = bundle.path
        if let r = path.range(of: "/Cellar/onair/") {
            let prefix = URL(fileURLWithPath: String(path[..<r.lowerBound]))
            let brew = prefix.appendingPathComponent("bin/brew").path
            let owner = (try? FileManager.default.attributesOfItem(atPath: brew)[.ownerAccountName]) as? String
            return .homebrew(prefix: prefix, owner: owner == NSUserName() ? nil : owner)
        }
        // A build in <clone>/build/OnAir.app
        let clone = bundle.deletingLastPathComponent().deletingLastPathComponent()
        if FileManager.default.isExecutableFile(atPath: clone.appendingPathComponent("scripts/build-app.sh").path) {
            return .source(clone: clone)
        }
        return .unknown
    }

    /// What pressing Update will do, said before it happens.
    static var plan: String {
        switch install {
        case .homebrew(_, nil):
            "ONAIR runs “brew update” and “brew upgrade onair” for you. Homebrew builds the new version on your Mac, which takes a minute or two, then ONAIR restarts."
        case .homebrew(_, let owner?):
            "Homebrew belongs to “\(owner)”, so Terminal opens and runs the update as that account: you'll be asked for its password. Then ONAIR restarts."
        case .source(let clone):
            "ONAIR pulls the new version into \(clone.path), rebuilds it and restarts."
        case .unknown:
            "This copy wasn't installed with Homebrew. Install it with Homebrew to update in one click."
        }
    }

    static var canUpdate: Bool { install != .unknown }

    private var script: String? {
        switch Self.install {
        case .homebrew(let prefix, let owner):
            // Call the real brew script, not a link to it: brew finds its own files from where it runs.
            let brew = q(prefix.appendingPathComponent("bin/brew").resolvingSymlinksInPath().path)
            let run = owner.map { "sudo -u \(q($0)) " } ?? ""
            return "\(run)\(brew) update && \(run)\(brew) upgrade onair"
        case .source(let clone):
            return "cd \(q(clone.path)) && git pull --ff-only && scripts/build-app.sh"
        case .unknown:
            return nil
        }
    }

    private var relaunchTarget: String {
        switch Self.install {
        case .homebrew(let prefix, _): prefix.appendingPathComponent("opt/onair/OnAir.app").path
        default: Bundle.main.bundlePath
        }
    }

    func start() {
        guard let script, phase != .running else { return }
        if case .homebrew(_, _?) = Self.install { openInTerminal(script); return }
        phase = .running; log = ""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", script]
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_ENV_HINTS"] = "1"; env["HOMEBREW_NO_INSTALL_CLEANUP"] = nil
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            guard !s.isEmpty else { return }
            Task { @MainActor in self?.log += s }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let ok = proc.terminationStatus == 0
            Task { @MainActor in
                guard let self else { return }
                if ok { self.phase = .done; self.relaunch() }
                else { self.phase = .failed("The update stopped with an error. You can run it in Terminal instead.") }
            }
        }
        do { try p.run() } catch { phase = .failed(error.localizedDescription) }
    }

    /// The same steps in Terminal, where a password can be typed and every line is visible.
    func openInTerminal() { if let script { openInTerminal(script) } }

    private func openInTerminal(_ script: String) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("update-onair.command")
        let body = """
        #!/bin/zsh
        # Updates ONAIR and opens the new version. Written by ONAIR for Terminal to run.
        set -e
        echo "Updating ONAIR…"
        \(script)
        pkill -x OnAir || true
        sleep 1
        open \(q(relaunchTarget))
        echo "Done. You can close this window."
        """
        do {
            try body.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            NSWorkspace.shared.open(file)
        } catch { phase = .failed(error.localizedDescription) }
    }

    /// Quit, and have a helper open the new copy once this process is really gone
    /// (opening the same app while it still runs would only bring the old one forward).
    private func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; sleep 0.5; open \(q(relaunchTarget))"]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSApp.windows.forEach { w in w.sheets.forEach { w.endSheet($0) } }
            NSApp.terminate(nil)
            // A sheet or window can veto a polite quit; the update is installed, so leave anyway.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) }
        }
    }

    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
