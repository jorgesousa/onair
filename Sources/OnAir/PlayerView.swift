import SwiftUI
import AVKit

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    /// False hides AVKit's controls. In Watch mode they follow the channel card: they come with the mouse
    /// and go after 3 s idle. (AVKit's own full screen kept them on screen for live streams.)
    var controls = true
    /// Picture in Picture started (true) or ended (false).
    var onPictureInPicture: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = controls ? .floating : .none
        // One full screen only: the window's (⏎, the green button), which is Watch mode.
        v.showsFullScreenToggleButton = false
        v.allowsPictureInPicturePlayback = true
        v.pictureInPictureDelegate = context.coordinator
        context.coordinator.changed = onPictureInPicture
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
        let style: AVPlayerViewControlsStyle = controls ? .floating : .none
        if v.controlsStyle != style { v.controlsStyle = style }
        context.coordinator.changed = onPictureInPicture
    }

    final class Coordinator: NSObject, AVPlayerViewPictureInPictureDelegate {
        var changed: (Bool) -> Void = { _ in }
        func playerViewWillStartPicture(inPicture playerView: AVPlayerView) { changed(true) }
        func playerViewDidStopPicture(inPicture playerView: AVPlayerView) { changed(false) }
        func playerView(_ playerView: AVPlayerView,
                        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            completionHandler(true)
        }
    }
}
