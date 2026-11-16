import Foundation
import Network
import SwiftUI
import os

/// The screens at home finding each other (Bonjour, `_onair._tcp`) and passing the channel
/// around for `Follow`. Each message is one short TCP exchange: a JSON line in, and for an
/// `ask`, a JSON line back with what's on. Runs only while this screen is on Home.
@MainActor
final class HomeLink {
    static let service = "_onair._tcp"
    nonisolated private static let log = Logger(subsystem: "com.sousalab.onair", category: "home")
    let me: String
    /// What this screen put on (or adopted) last, and when.
    private(set) var current: (key: String, at: Date)?
    /// Another screen's change. Main actor.
    var onMessage: ((Follow.Message) -> Void)?
    var peerCount: Int { peers.count }
    /// The other screens' Bonjour names.
    var peerNames: [String] {
        peers.compactMap { if case .service(let name, _, _, _) = $0 { return name } else { return nil } }
    }
    var isActive: Bool { listener != nil }

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var peers: [NWEndpoint] = []

    init(me: String = UUID().uuidString) { self.me = me }

    func start() {
        guard listener == nil else { return }
        Self.log.notice("home: start \(self.me, privacy: .public)")
        if let l = try? NWListener(using: .tcp) {
            l.service = NWListener.Service(name: me, type: Self.service)
            l.stateUpdateHandler = { state in Self.log.notice("home: listener \(String(describing: state), privacy: .public)") }
            l.newConnectionHandler = { [weak self] c in
                MainActor.assumeIsolated { self?.serve(c) }
            }
            l.start(queue: .main)
            listener = l
        }
        let b = NWBrowser(for: .bonjour(type: Self.service, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.peers = results.compactMap { r in
                    if case .service(let name, _, _, _) = r.endpoint, name == self.me { return nil }
                    return r.endpoint
                }
            }
        }
        b.stateUpdateHandler = { state in Self.log.notice("home: browser \(String(describing: state), privacy: .public)") }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        if listener != nil { Self.log.notice("home: stop") }
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        peers = []
    }

    /// This screen changed channel: tell the others. The same channel again is not news
    /// (that's also how an adopted change doesn't echo back).
    func announce(_ key: String, at: Date = .now) {
        guard current?.key != key else { return }
        current = (key, at)
        Self.log.notice("home: announce \(key, privacy: .public) to \(self.peers.count) screens")
        guard isActive, let data = try? Follow.encode(.init(from: me, key: key, at: at)) else { return }
        for p in peers { send(data, to: p, expectReply: false) { _ in } }
    }

    /// Adopted another screen's change: remember it, so announcing it back is a no-op.
    func remember(_ m: Follow.Message) { current = (m.key, m.at) }

    /// Calls `pick` with each change from another screen that this one should follow.
    func follow(_ pick: @escaping (String) -> Void) {
        onMessage = { [weak self] m in
            guard let self, Follow.adopt(m, me: self.me, shared: self.isActive,
                                         current: self.current?.key, lastChange: self.current?.at) else { return }
            self.remember(m)
            pick(m.key)
        }
    }

    /// Joining Home: what are the others watching? The newest answer, if any. Bonjour takes a
    /// moment to find everyone, so a screen that has just started gives it `settle` seconds.
    func ask(settle: Double = 0) async -> Follow.Message? {
        if settle > 0 { try? await Task.sleep(for: .seconds(settle)) }
        guard isActive, !peers.isEmpty,
              let data = try? Follow.encode(.init(from: me, key: "", at: .now, ask: true)) else { return nil }
        var answers: [Follow.Message] = []
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            var left = peers.count
            for p in peers {
                send(data, to: p, expectReply: true) { reply in
                    if let reply { answers.append(reply) }
                    left -= 1
                    if left == 0 { done.resume() }
                }
            }
        }
        return answers.filter { !$0.key.isEmpty }.max { $0.at < $1.at }
    }

    // MARK: Wire

    private func serve(_ c: NWConnection) {
        c.start(queue: .main)
        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                guard let self, let data, let m = try? Follow.decode(data) else { c.cancel(); return }
                if m.ask {
                    let now = self.current.map { Follow.Message(from: self.me, key: $0.key, at: $0.at) }
                    let reply = (try? Follow.encode(now ?? .init(from: self.me, key: "", at: .distantPast))) ?? Data()
                    c.send(content: reply, completion: .contentProcessed { _ in c.cancel() })
                } else {
                    c.cancel()
                    self.onMessage?(m)
                }
            }
        }
    }

    private func send(_ data: Data, to endpoint: NWEndpoint, expectReply: Bool,
                      done: @escaping (Follow.Message?) -> Void) {
        let c = NWConnection(to: endpoint, using: .tcp)
        var finished = false
        let finish: (Follow.Message?) -> Void = { m in
            guard !finished else { return }
            finished = true; c.cancel(); done(m)
        }
        c.stateUpdateHandler = { state in
            MainActor.assumeIsolated {
                switch state {
                case .ready:
                    c.send(content: data, completion: .contentProcessed { _ in
                        guard expectReply else { MainActor.assumeIsolated { finish(nil) }; return }
                        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { reply, _, _, _ in
                            MainActor.assumeIsolated { finish(reply.flatMap { try? Follow.decode($0) }) }
                        }
                    })
                case .failed, .cancelled: finish(nil)
                default: break
                }
            }
        }
        c.start(queue: .main)
        // A screen that has gone to sleep doesn't hold anyone up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { finish(nil) } }
    }
}

/// Home on any screen: switch the link on while a Dispatcharr playlist is chosen, tell the
/// others when this screen changes channel, follow theirs, and on joining start whatever
/// is already on. `pick` is how this app tunes a channel from the list.
struct FollowsHome: ViewModifier {
    @Environment(Store.self) private var store
    let playback: PlaybackController
    let pick: (Channel) -> Void
    @State private var link = HomeLink()

    private var shared: Bool { Follow.isShared(store.selectedPlaylist) }

    func body(content: Content) -> some View {
        content
            .onChange(of: store.selectedPlaylistID, initial: true) { _, _ in
                if shared { link.start() } else { link.stop() }
            }
            .onChange(of: playback.current?.id) { _, _ in
                if shared, let c = playback.current { link.announce(Follow.key(c)) }
            }
            .onChange(of: store.isLoading) { _, loading in
                guard !loading, shared, playback.current == nil else { return }
                Task { @MainActor in
                    guard let m = await link.ask(settle: 1.5), playback.current == nil,
                          let c = store.items.first(where: { Follow.key($0) == m.key }) else { return }
                    link.remember(m)
                    pick(c)
                }
            }
            .task {
                link.follow { key in
                    if let c = store.items.first(where: { Follow.key($0) == key }) { pick(c) }
                }
            }
    }
}

extension View {
    func followsHome(playback: PlaybackController, pick: @escaping (Channel) -> Void) -> some View {
        modifier(FollowsHome(playback: playback, pick: pick))
    }
}
