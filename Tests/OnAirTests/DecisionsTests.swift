import CoreGraphics
import Testing
@testable import OnAir

@Suite struct ZapTests {
    let abc = ["a", "b", "c"]
    @Test func stepsForwardAndBackWithWrap() {
        #expect(Zap.step(from: "b", in: abc, by: 1) == "c")
        #expect(Zap.step(from: "c", in: abc, by: 1) == "a")
        #expect(Zap.step(from: "a", in: abc, by: -1) == "c")
    }
    @Test func unknownCurrentStartsAtTheEnds() {
        #expect(Zap.step(from: nil, in: abc, by: 1) == "a")
        #expect(Zap.step(from: nil, in: abc, by: -1) == "c")
        #expect(Zap.step(from: "zzz", in: abc, by: 1) == "a")
    }
    @Test func emptyAndSingleLists() {
        #expect(Zap.step(from: nil, in: [], by: 1) == nil)
        #expect(Zap.step(from: "a", in: ["a"], by: 1) == "a")
    }
    @Test func typedNumbersCommitLikeARemote() {
        #expect(Zap.shouldCommit(typed: "1", count: 100) == false)
        #expect(Zap.shouldCommit(typed: "12", count: 200) == false)
        #expect(Zap.shouldCommit(typed: "12", count: 100) == true)
        #expect(Zap.shouldCommit(typed: "123", count: 999) == true)
        #expect(Zap.shouldCommit(typed: "5", count: 40) == true)
        #expect(Zap.shouldCommit(typed: "4", count: 40) == false)
    }
    @Test func typedNumberPicksTheChannel() {
        #expect(Zap.channel(forTyped: "2", in: ["a", "b"]) == "b")
        #expect(Zap.channel(forTyped: "0", in: ["a", "b"]) == nil)
        #expect(Zap.channel(forTyped: "3", in: ["a", "b"]) == nil)
        #expect(Zap.channel(forTyped: "", in: ["a", "b"]) == nil)
    }
}

@Suite struct PadLayoutTests {
    @Test func layoutFollowsTheWindowShape() {
        #expect(PadLayout.mode(size: CGSize(width: 1366, height: 1024), playing: false, expanded: false) == .rail)
        #expect(PadLayout.mode(size: CGSize(width: 1366, height: 1024), playing: true, expanded: false) == .watch)
        #expect(PadLayout.mode(size: CGSize(width: 1024, height: 1366), playing: true, expanded: false) == .stacked)
        #expect(PadLayout.mode(size: CGSize(width: 1024, height: 1366), playing: true, expanded: true) == .watch)
        #expect(PadLayout.mode(size: CGSize(width: 500, height: 800), playing: true, expanded: false) == .stacked)
    }
}

@Suite struct ConnectionPolicyTests {
    @Test func keepsTheSlotOnlyWhileThereIsAPicture() {
        #expect(ConnectionPolicy.keep(phase: .active, pip: false, pausedFor: 0) == true)
        #expect(ConnectionPolicy.keep(phase: .inactive, pip: false, pausedFor: 0) == true)
        #expect(ConnectionPolicy.keep(phase: .background, pip: false, pausedFor: 0) == false)
        #expect(ConnectionPolicy.keep(phase: .background, pip: true, pausedFor: 0) == true)
        #expect(ConnectionPolicy.keep(phase: .background, pip: true, pausedFor: 9) == true)
        #expect(ConnectionPolicy.keep(phase: .background, pip: true, pausedFor: 10) == false)
    }
}

@Suite struct SwipeTests {
    @Test func swipeUpIsNextChannelByDistanceOrFlick() {
        #expect(Swipe.step(travel: -61, velocity: 0) == 1)
        #expect(Swipe.step(travel: -30, velocity: -600) == 1)
    }
    @Test func swipeDownIsPreviousChannel() {
        #expect(Swipe.step(travel: 61, velocity: 0) == -1)
        #expect(Swipe.step(travel: 30, velocity: 600) == -1)
    }
    @Test func smallSlowDragsDoNothing() {
        #expect(Swipe.step(travel: -30, velocity: -100) == 0)
        #expect(Swipe.step(travel: 0, velocity: 0) == 0)
    }
    @Test func pictureFollowsTheFingerThenResists() {
        #expect(Swipe.rubberBand(50) == 50)
        #expect(Swipe.rubberBand(-50) == -50)
        let far = Swipe.rubberBand(300)
        #expect(far > 80 && far < 130)
        #expect(Swipe.rubberBand(-300) == -far)
    }
}
