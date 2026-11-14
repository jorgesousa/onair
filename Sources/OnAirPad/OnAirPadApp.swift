import SwiftUI

@main
struct OnAirPadApp: App {
    @State private var store = Store()
    @State private var playback: PlaybackController
    @State private var session: PadSession

    init() {
        let p = PlaybackController()
        _playback = State(initialValue: p)
        _session = State(initialValue: PadSession(playback: p))
    }

    var body: some Scene {
        WindowGroup {
            PadRoot()
                .environment(store)
                .environment(playback)
                .environment(session)
                .tint(Brand.signal)
                .preferredColorScheme(.dark)
        }
    }
}
