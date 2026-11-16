import Foundation
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

@Suite struct PauseCountingTests {
    @Test func onlyADeliberatePauseCountsTowardsLettingGo() {
        #expect(ConnectionPolicy.pausedFor(after: 4, status: .paused) == 5)
        #expect(ConnectionPolicy.pausedFor(after: 4, status: .waitingToPlayAtSpecifiedRate) == 0)
        #expect(ConnectionPolicy.pausedFor(after: 4, status: .playing) == 0)
    }
}

@Suite struct SameChannelTests {
    @Test func movingToTheChannelAlreadyOnIsNoMove() {
        #expect(Zap.move(from: "a", in: ["a"], by: 1) == nil)
        #expect(Zap.move(from: "a", in: ["a", "b"], by: 1) == "b")
        #expect(Zap.move(from: nil, in: ["a"], by: 1) == "a")
    }
}

@Suite struct FailureTests {
    @Test func providerRefusalsAreRefused() {
        #expect(PlaybackFailure.of(NSError(domain: NSURLErrorDomain, code: 403)) == .refused)
        let nested = NSError(domain: "AVFoundationErrorDomain", code: -11800,
                             userInfo: [NSUnderlyingErrorKey: NSError(domain: "CoreMediaErrorDomain", code: -12660)])
        #expect(PlaybackFailure.of(nested) == .refused)
    }

    @Test func formatsTheDeviceCannotDecodeAreUnsupported() {
        let e = NSError(domain: "AVFoundationErrorDomain", code: -11800,
                        userInfo: [NSUnderlyingErrorKey: NSError(domain: "CoreMediaErrorDomain", code: -12863)])
        #expect(PlaybackFailure.of(e) == .unsupported)
    }

    @Test func everythingElseIsWorthRetrying() {
        #expect(PlaybackFailure.of(NSError(domain: NSURLErrorDomain, code: -1009)) == .other)
        #expect(PlaybackFailure.of(nil) == .other)
    }

    @Test func afterARefusalTheAppWaitsTwoMinutesBeforeTryingByItself() {
        let t0 = Date(timeIntervalSince1970: 1000)
        #expect(Retry.holdAfterRefusal == 120)
        #expect(Retry.remaining(until: t0.addingTimeInterval(120), at: t0) == 120)
        #expect(Retry.remaining(until: t0, at: t0.addingTimeInterval(5)) == 0)
        #expect(Retry.remaining(until: nil, at: t0) == 0)
    }
}

@Suite struct FullScreenTurnTests {
    @Test func theButtonHoldsTheTurnUntilThePhoneIsHeldThatWay() {
        #expect(FullScreenTurn.release(lockedTo: .landscape, held: .portrait) == false)
        #expect(FullScreenTurn.release(lockedTo: .landscape, held: nil) == false)
        #expect(FullScreenTurn.release(lockedTo: .landscape, held: .landscape) == true)
        #expect(FullScreenTurn.release(lockedTo: .portrait, held: .portrait) == true)
        #expect(FullScreenTurn.release(lockedTo: nil, held: .landscape) == false)
    }

    @Test func onlyAPhoneTurnsForFullScreen() {
        #expect(FullScreenTurn.target(phone: true, wide: false) == .landscape)
        #expect(FullScreenTurn.target(phone: true, wide: true) == .portrait)
        #expect(FullScreenTurn.target(phone: false, wide: false) == nil)
    }
}

@Suite struct OffAirTests {
    @Test func aChannelThatNeverShowsAnythingIsOffAirAfterThreeTriesAndTwentySeconds() {
        #expect(OffAir.giveUp(failures: 3, seconds: 20, everPlayed: false, refused: false))
        #expect(!OffAir.giveUp(failures: 2, seconds: 60, everPlayed: false, refused: false))
        // Dispatcharr's brief "busy" after a channel change is not "off air".
        #expect(!OffAir.giveUp(failures: 5, seconds: 12, everPlayed: false, refused: false))
    }

    @Test func aChannelThatPlayedOrWasRefusedIsNotOffAir() {
        #expect(!OffAir.giveUp(failures: 9, seconds: 90, everPlayed: true, refused: false))
        #expect(!OffAir.giveUp(failures: 9, seconds: 90, everPlayed: false, refused: true))
    }
}

@Suite struct BusyTests {
    @Test func dispatcharrsBusyAndNotReadyAnswersAreBusy() {
        let busy = NSError(domain: NSURLErrorDomain, code: -1008,
                           userInfo: [NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -16849)])
        let notReady = NSError(domain: NSURLErrorDomain, code: -1008,
                               userInfo: [NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -16847)])
        #expect(PlaybackFailure.of(busy) == .busy)
        #expect(PlaybackFailure.of(notReady) == .busy)
        let missing = NSError(domain: NSURLErrorDomain, code: -1100)
        #expect(PlaybackFailure.of(missing) == .other)
    }

    @Test func whileBusyOffAirWaitsLonger() {
        #expect(!OffAir.giveUp(failures: 8, seconds: 30, everPlayed: false, refused: false, busy: true))
        #expect(OffAir.giveUp(failures: 8, seconds: 45, everPlayed: false, refused: false, busy: true))
    }
}
