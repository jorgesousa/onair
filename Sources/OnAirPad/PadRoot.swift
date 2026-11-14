import SwiftUI

/// Temporary screen for the player work (Task 5): a picture and a plain list.
/// Replaced by the rail and stage in the next tasks.
struct PadRoot: View {
    @Environment(Store.self) private var store
    @Environment(PlaybackController.self) private var playback
    @Environment(PadSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    private var stageState: String {
        if playback.current == nil { return playback.lastStopped == nil ? "idle" : "resume" }
        if let f = playback.failed { return "failed: \(f)" }
        return playback.isTuning ? "tuning" : "playing"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PadPlayerView(player: playback.player, session: session)
                if playback.current == nil, let last = playback.lastStopped {
                    Button("Resume \(last.displayName)") { session.play(last) }
                        .font(Brand.display(18)).foregroundStyle(Brand.ink)
                        .padding(.horizontal, 22).padding(.vertical, 14)
                        .background(Brand.paper, in: .capsule)
                        .accessibilityIdentifier("resume")
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stage")
            .accessibilityValue(stageState)
            HStack {
                Button("Picture in Picture") { session.togglePictureInPicture() }
                    .disabled(!session.pipAvailable)
                AirPlayButton().frame(width: 44, height: 44)
            }
            .padding()
            List(store.channels) { c in
                Button(c.displayName) { session.play(c) }
                    .accessibilityIdentifier("channel-\(c.displayName)")
            }
        }
        .background(Brand.ink)
        .task { await store.loadIfNeeded() }
        .onChange(of: scenePhase, initial: true) { _, p in session.update(phase: p) }
        .onChange(of: playback.current) { _, _ in session.refreshIdleTimer() }
    }
}
