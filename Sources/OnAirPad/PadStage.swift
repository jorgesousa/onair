import SwiftUI

/// The picture and what sits on it while tuning or in trouble. Same pieces as the Mac stage.
struct PadStage: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(PadSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduce
    var fill = false
    /// A pick from the side list in landscape: the stream is already starting, but the
    /// "tuning in" card waits for the list to start leaving (about 0.12 s).
    var holdTuning = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            // Always in the tree, so rotating or switching layouts never rebuilds the picture.
            PadPlayerView(player: playback.player, fill: fill, session: session)
                .opacity(playback.isTuning || playback.current == nil ? 0 : 1)
                .animation(reduce ? Motion.fade : Motion.fade.delay(0.12), value: playback.isTuning)
            if let c = playback.current {
                if session.pipActive {
                    InPictureInPictureView(channel: c).transition(.opacity)
                }
                TuningOverlay(channel: c, tuning: playback.isTuning && !holdTuning)
                if playback.soundOnly, !playback.isTuning {
                    SoundOnlyCard()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                if playback.offAir {
                    OffAirView(channel: c).transition(.opacity)
                } else if playback.cantPlay {
                    CantPlayView(channel: c).transition(.opacity)
                } else if let f = playback.failed {
                    StageNotice(text: f, until: playback.holdUntil)
                        .frame(maxWidth: .infinity)
                    .padding(24)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .clipped()
        .animation(Motion.if(reduce, Motion.fade), value: playback.isTuning)
        .animation(Motion.if(reduce, Motion.fade), value: playback.offAir)
        .animation(Motion.if(reduce, Motion.fade), value: playback.cantPlay)
        .animation(Motion.if(reduce, Motion.enter), value: playback.failed)
        .animation(Motion.if(reduce, Motion.enter), value: playback.soundOnly)
        .animation(Motion.if(reduce, Motion.fade), value: session.pipActive)
    }
}

/// Nothing playing, but the last channel is a tap away (after the iPad let go of the connection).
struct ResumeCard: View {
    let channel: Channel
    let resume: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Tag(text: "Paused to free your connection", color: Brand.dim)
            Button(action: resume) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill").font(.system(size: 18, weight: .bold))
                    Text("RESUME \(channel.displayName.uppercased())").font(Brand.display(20)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .foregroundStyle(Brand.ink)
                .padding(.horizontal, 28).frame(minHeight: 60)
                .background(Brand.paper, in: .capsule)
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("resume")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
