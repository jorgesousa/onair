import SwiftUI

@main
struct OnAirPadApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            PadRoot()
                .environment(store)
                .tint(Brand.signal)
                .preferredColorScheme(.dark)
        }
    }
}
