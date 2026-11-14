import AVKit
import SwiftUI
import os

/// Everything about watching on an iPad that the Mac doesn't have: the audio session,
/// Picture in Picture, keeping the screen awake, and giving the provider's one
/// connection back when nobody can see the picture (ConnectionPolicy).
@MainActor @Observable
final class PadSession: NSObject {
    let playback: PlaybackController
    private(set) var pipActive = false
    private(set) var pipPossible = false

    @ObservationIgnored private var pip: AVPictureInPictureController?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    @ObservationIgnored private var phase: ScenePhaseLike = .active
    @ObservationIgnored private var pausedFor: TimeInterval = 0
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let log = Logger(subsystem: "com.sousalab.onair", category: "session")

    /// "Picture in Picture when you leave" (on by default).
    static let autoPiPKey = "autoPictureInPicture"
    /// `bool(forKey:)`, not `as? Bool`: a value from launch arguments or a plist arrives as "NO"/"YES".
    private var autoPiP: Bool {
        UserDefaults.standard.register(defaults: [Self.autoPiPKey: true])
        return UserDefaults.standard.bool(forKey: Self.autoPiPKey)
    }

    init(playback: PlaybackController) {
        self.playback = playback
        super.init()
        configureAudio()
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let ended = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue
            guard ended else { return }
            MainActor.assumeIsolated { self?.interruptionEnded() }
        })
    }

    /// Sound with the silent switch on, and on in the background / Picture in Picture.
    func configureAudio() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    @ObservationIgnored private weak var layer: AVPlayerLayer?

    /// With "Picture in Picture when you leave" on, the controller exists from the start and
    /// takes over when you leave. Off, it is only made when you tap the button: iOS starts
    /// Picture in Picture on leaving for any controller it finds, whatever the flag says.
    func attach(layer: AVPlayerLayer) {
        self.layer = layer
        if autoPiP { makePictureInPicture() }
    }

    private func makePictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported(), let layer, pip?.playerLayer !== layer,
              let c = AVPictureInPictureController(playerLayer: layer) else { return }
        c.canStartPictureInPictureAutomaticallyFromInline = autoPiP
        c.requiresLinearPlayback = true      // live TV: no ±10 s skip buttons
        c.delegate = self
        possibleObservation = c.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] c, _ in
            let possible = c.isPictureInPicturePossible
            Task { @MainActor in self?.pipPossible = possible }
        }
        pip = c
    }

    /// The button is offered whenever the iPad can do Picture in Picture and something plays.
    var pipAvailable: Bool { AVPictureInPictureController.isPictureInPictureSupported() && playback.current != nil }

    func togglePictureInPicture() {
        if pip == nil { makePictureInPicture() }
        guard let pip else { return }
        if pip.isPictureInPictureActive { pip.stopPictureInPicture(); return }
        // A fresh controller needs a moment before it reports it can start.
        if pip.isPictureInPicturePossible { pip.startPictureInPicture(); return }
        Task { @MainActor in
            for _ in 0..<20 where !pip.isPictureInPicturePossible { try? await Task.sleep(for: .milliseconds(100)) }
            pip.startPictureInPicture()
        }
    }

    /// Picking a channel: the audio session goes live with the first one.
    func play(_ c: Channel) {
        try? AVAudioSession.sharedInstance().setActive(true)
        pip?.canStartPictureInPictureAutomaticallyFromInline = autoPiP
        playback.play(c)
        refreshIdleTimer()
    }

    func update(phase newPhase: ScenePhase) {
        switch newPhase {
        case .active: phase = .active
        case .inactive: phase = .inactive
        default: phase = .background
        }
        log.info("phase \(String(describing: self.phase)) pip \(self.pipActive) auto \(self.autoPiP)")
        refreshIdleTimer()
        ticker?.invalidate(); ticker = nil
        pausedFor = 0
        // Judged a second later, not at once: leaving with Picture in Picture reports the
        // background slightly before Picture in Picture says it has started.
        if phase == .background {
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
    }

    /// The screen stays on while a channel plays in front of you, never otherwise.
    func refreshIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = phase == .active && playback.current != nil
    }

    private func tick() {
        guard playback.current != nil else { ticker?.invalidate(); ticker = nil; return }
        pausedFor = playback.player.timeControlStatus == .playing ? 0 : pausedFor + 1
        if !ConnectionPolicy.keep(phase: phase, pip: pipActive, pausedFor: pausedFor) {
            log.info("release: nobody can see the picture (pip \(self.pipActive), paused \(self.pausedFor)s)")
            playback.release()
            refreshIdleTimer()
        }
    }

    private func interruptionEnded() {
        guard playback.current != nil else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        playback.reconnectNow(reason: "interruption")
    }
}

extension PadSession: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.pipActive = true }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.pipActive = false }
    }
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}
