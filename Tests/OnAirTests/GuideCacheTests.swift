import Foundation
import Testing
@testable import OnAir

@Test func theSavedGuideKeepsOnlyTheNextDay() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let p = { (start: Double, end: Double) in Programme(title: "x", start: now.addingTimeInterval(start * 3600), end: now.addingTimeInterval(end * 3600)) }
    let guide = ["a": [p(-5, -3), p(-2, 0.5), p(0.5, 2), p(30, 31)]]
    let kept = GuideCache.trimmed(guide, around: now)
    #expect(kept["a"]?.count == 2)          // the one on now and the one after; not old, not in 30 h
}

@Test func aSavedGuideComesBackTheSame() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let now = Date()
    let guide = ["a": [Programme(title: "News", start: now, end: now.addingTimeInterval(1800))]]
    try GuideCache.save(guide, key: "acc", in: dir)
    let back = GuideCache.load(key: "acc", in: dir)
    #expect(back?["a"]?.first?.title == "News")
    #expect(GuideCache.load(key: "other", in: dir) == nil)
}
