import AVKit
import SwiftUI

/// A plain picture: no system controls (live TV has nothing to scrub, and they would
/// swallow our swipes). Picture in Picture hangs off its layer, see PadSession.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PadPlayerView: UIViewRepresentable {
    let player: AVPlayer
    /// Fill the screen (crop) instead of fitting the whole picture.
    var fill = false
    let session: PadSession

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.backgroundColor = .black
        v.playerLayer.player = player
        v.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        session.attach(layer: v.playerLayer)
        return v
    }

    func updateUIView(_ v: PlayerLayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
        let gravity: AVLayerVideoGravity = fill ? .resizeAspectFill : .resizeAspect
        if v.playerLayer.videoGravity != gravity { v.playerLayer.videoGravity = gravity }
    }
}

/// The system's AirPlay picker, tinted like the rest of the controls.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor(Brand.paper)
        v.activeTintColor = UIColor(Brand.signal)
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}
