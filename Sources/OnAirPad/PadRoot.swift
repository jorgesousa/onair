import SwiftUI

/// Placeholder until the real screens land: proves the core runs on iPad.
struct PadRoot: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            Wordmark(size: 40)
            Text("\(store.channels.count) channels").font(Brand.mono(18)).foregroundStyle(Brand.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.ink)
        .task { await store.loadIfNeeded() }
    }
}
