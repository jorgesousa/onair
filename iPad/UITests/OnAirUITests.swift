import XCTest

/// Drives the iPad app against the fake provider (python3 scripts/fake-provider.py, port 18765).
/// The playlist is passed in launch arguments, so each test starts from the same state.
class OnAirUITestCase: XCTestCase {
    var app: XCUIApplication!

    /// An M3U playlist on the fake provider, as the app stores it (JSON → hex data).
    static let playlistArgs: [String] = {
        let id = "6F1C2D3E-0000-4000-8000-000000000001"
        let json = #"[{"id":"\#(id)","name":"Fake","source":{"m3u":{"location":"http://127.0.0.1:18765/get.php?username=t&password=t"}}}]"#
        let hex = Data(json.utf8).map { String(format: "%02x", $0) }.joined()
        return ["-playlists", "<\(hex)>", "-selected", id]
    }()

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = Self.playlistArgs
        XCUIDevice.shared.orientation = .portrait
    }

    var root: XCUIElement { app.otherElements["root"].firstMatch }
    var rail: XCUIElement { app.otherElements["rail"].firstMatch }
    var window: XCUIElement { app }
    var picture: XCUIElement { app.otherElements["picture"].firstMatch }
    var card: XCUIElement { app.otherElements["card"].firstMatch }

    /// The controls hide 3 s after a tap; a slow simulator can take that long between two
    /// steps. Wake them and press, again if they had already gone, until `done` holds.
    func press(_ id: String, until done: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<3 {
            let b = app.buttons[id]
            if !b.exists { picture.tap() }
            if b.waitForExistence(timeout: 2) { b.tap() }
            if done() { return }
            sleep(1)
            if done() { return }
        }
        XCTFail("pressing \(id) didn't take", file: file, line: line)
    }

    /// The controls, shown (a tap wakes them only if they're not already up; a second tap hides them).
    func control(_ id: String) -> XCUIElement {
        let b = app.buttons[id]
        if !b.exists { picture.tap() }
        _ = b.waitForExistence(timeout: 2)
        return b
    }

    /// The search field; under the picture it opens from the 🔍 button first.
    func openSearch() -> XCUIElement {
        let f = app.textFields["search"]
        if !f.exists { app.buttons["Search channels"].tap() }
        XCTAssertTrue(f.waitForExistence(timeout: 2))
        return f
    }

    func waitForCard(_ number: String, timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line) {
        let p = NSPredicate(format: "value == %@", number)
        let ok = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: card)], timeout: timeout) == .completed
        XCTAssertTrue(ok, "card is \(String(describing: card.value)), wanted \(number)", file: file, line: line)
    }

    func waitForMode(_ mode: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let p = NSPredicate(format: "value == %@", mode)
        let ok = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: root)], timeout: timeout) == .completed
        XCTAssertTrue(ok, "layout is \(String(describing: root.value)), wanted \(mode)", file: file, line: line)
    }

    var stage: XCUIElement { app.otherElements["stage"].firstMatch }

    func waitForStage(_ value: String, timeout: TimeInterval = 25, file: StaticString = #filePath, line: UInt = #line) {
        let p = NSPredicate(format: "value == %@", value)
        let ok = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: stage)], timeout: timeout) == .completed
        XCTAssertTrue(ok, "stage is \(String(describing: stage.value)), wanted \(value)", file: file, line: line)
    }

    func play(_ name: String) {
        let row = app.buttons["channel-\(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no row \(name)")
        row.tap()
    }

    func screenshot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
}

final class PlayerTests: OnAirUITestCase {
    func testPickingAChannelPlaysIt() {
        app.launch()
        play("Test One")
        waitForStage("playing")
        screenshot("playing")
    }

    func testLeavingWithoutPictureInPictureFreesTheConnection() {
        app.launchArguments += ["-autoPictureInPicture", "NO"]
        app.launch()
        play("Test One")
        waitForStage("playing")
        XCUIDevice.shared.press(.home)
        sleep(4)
        app.activate()
        waitForStage("resume", timeout: 5)
        screenshot("resume")
        app.buttons["resume"].tap()
        waitForStage("playing")
    }

    func testLeavingWithPictureInPictureKeepsPlaying() {
        app.launch()
        play("Test One")
        waitForStage("playing")
        XCUIDevice.shared.press(.home)
        sleep(5)
        app.activate()
        waitForStage("playing", timeout: 10)
    }
}

/// The small window, as Springboard shows it after leaving the app.
extension OnAirUITestCase {
    var pipWindow: XCUIElement {
        XCUIApplication(bundleIdentifier: "com.apple.springboard").windows["Picture in Picture"]
    }
    /// A tap shows the window's controls, or hides them if they were already up: tap until it's there.
    func pipButton(_ name: String) -> XCUIElement {
        let b = pipWindow.buttons[name]
        for _ in 0..<3 where !b.waitForExistence(timeout: 1.5) { pipWindow.tap() }
        return b
    }
}

final class PictureInPictureTests: OnAirUITestCase {
    func testClosingTheSmallWindowFreesTheConnection() {
        app.launch()
        play("Test One")
        waitForStage("playing")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(pipWindow.waitForExistence(timeout: 5))
        let close = pipButton("Close Picture in Picture")
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        sleep(3)
        app.activate()
        waitForStage("resume", timeout: 5)
    }

    func testPausedInTheSmallWindowFreesTheConnectionAfterTenSeconds() {
        app.launch()
        play("Test One")
        waitForStage("playing")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(pipWindow.waitForExistence(timeout: 5))
        let pause = pipButton("Pause")
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        pause.tap()
        sleep(13)
        app.activate()
        waitForStage("resume", timeout: 5)
    }

    func testLiveTVHasNoSkipButtons() {
        app.launch()
        play("Test One")
        waitForStage("playing")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(pipWindow.waitForExistence(timeout: 5))
        XCTAssertTrue(pipButton("Pause").waitForExistence(timeout: 3))
        XCTAssertFalse(pipWindow.buttons["Skip forward 10 seconds"].exists)
        app.activate()
    }
}

final class LayoutTests: OnAirUITestCase {
    func testLandscapeShowsTheListBesideTheStage() {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["channel-Test One"].waitForExistence(timeout: 15))
        waitForMode("rail")
        screenshot("landscape-rail")
        let row = app.buttons["channel-Test One"].frame
        XCTAssertLessThan(row.maxX, 420)
        XCTAssertGreaterThan(stage.frame.minX, 350)
    }

    func testPortraitListFillsTheScreen() {
        app.launch()
        XCTAssertTrue(app.buttons["channel-Test One"].waitForExistence(timeout: 15))
        XCTAssertEqual(rail.frame.width, window.frame.width, accuracy: 1)
        screenshot("portrait-rail")
    }

    func testRowsAreBigEnoughForAFingertip() {
        app.launch()
        let row = app.buttons["channel-Test One"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(row.frame.height, 54)
    }

    func testSearchNarrowsTheListAndSaysWhenNothingMatches() {
        app.launch()
        XCTAssertTrue(app.buttons["channel-Test One"].waitForExistence(timeout: 15))
        let search = app.textFields["search"]
        search.tap()
        search.typeText("two")
        XCTAssertTrue(app.buttons["channel-Test Two"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["channel-Test One"].exists)
        app.buttons["Clear search"].tap()
        search.tap()
        search.typeText("zzz")
        XCTAssertTrue(app.staticTexts["NO MATCH"].waitForExistence(timeout: 3) || app.staticTexts["No match"].exists)
    }

    func testPickingInLandscapeFillsTheScreen() {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        play("Test One")
        waitForMode("watch")
        waitForStage("playing")
        XCTAssertEqual(stage.frame.width, window.frame.width, accuracy: 1)
        XCTAssertEqual(stage.frame.height, window.frame.height, accuracy: 1)
        screenshot("watch")
    }

    func testRotatingWhilePlayingStacksWithoutRestarting() {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        play("Test One")
        waitForStage("playing")
        XCUIDevice.shared.orientation = .portrait
        waitForMode("stacked")
        XCTAssertEqual(stage.frame.width, window.frame.width, accuracy: 1)
        XCTAssertEqual(stage.frame.height, window.frame.width * 9 / 16, accuracy: 2)
        for _ in 0..<8 { XCTAssertEqual(stage.value as? String, "playing"); usleep(250_000) }
        screenshot("stacked")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForMode("watch")
        XCTAssertEqual(stage.value as? String, "playing")
    }

    func testExpandInPortraitAndBack() {
        app.launch()
        play("Test One")
        waitForMode("stacked")
        waitForStage("playing")
        press("expand") { root.value as? String == "watch" }
        press("collapse") { root.value as? String == "stacked" }
    }

    func testLeftEdgeBringsTheListOverThePicture() {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        play("Test One")
        waitForMode("watch")
        waitForStage("playing")
        XCTAssertLessThan(rail.frame.maxX, 2)
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.003, dy: 0.5))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(1)
        XCTAssertGreaterThan(rail.frame.minX, -2)
        screenshot("peek")
        play("Test Two")
        sleep(1)
        XCTAssertLessThan(rail.frame.maxX, 2)
        waitForStage("playing")
    }
}

final class TouchTests: OnAirUITestCase {
    func startWatching() {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        play("Test One")
        waitForMode("watch")
        waitForStage("playing")
    }

    func testSwipeUpGoesToTheNextChannelAndTheCardSaysSoAtOnce() {
        startWatching()
        picture.swipeUp()
        waitForCard("002", timeout: 2)
        XCTAssertGreaterThan(card.frame.minY, app.frame.height / 2, "card must sit low, clear of the score")
        XCTAssertLessThan(card.frame.minX, 120)
        screenshot("card")
        waitForStage("playing")
        picture.swipeDown()
        waitForCard("001", timeout: 2)
    }

    func testFiveQuickSwipesLandOnOneChannel() {
        startWatching()
        for _ in 0..<5 { picture.swipeUp() }
        waitForCard("006", timeout: 2)
        waitForStage("playing")
        sleep(4)   // the card has gone; wake it with a tap and check where we are
        picture.tap()
        waitForCard("006", timeout: 2)
    }

    /// The "last" button and the two-finger tap run the same code (backToLast). XCTest can't
    /// synthesise a two-finger tap on this simulator, so the button stands in for it.
    func testBackToTheLastChannelFlipsBetweenTwo() {
        startWatching()
        picture.swipeUp()
        waitForCard("002")
        waitForStage("playing")
        let last = control("last")
        XCTAssertTrue(last.exists)
        XCTAssertTrue(last.label.contains("Test One"), last.label)
        last.tap()
        waitForCard("001")
        waitForStage("playing")
        // The controls may hide between finding the button and reading it: look again if so.
        var label = ""
        for _ in 0..<3 where !label.contains("Test Two") {
            let b = control("last")
            if b.exists { label = b.label }
        }
        XCTAssertTrue(label.contains("Test Two"), label)
    }

    /// Portrait full screen: XCTest misplaces taps near the edges in landscape.
    func testTapShowsBigControlsAndTheListButtonOpensTheList() {
        app.launch()
        play("Test One")
        waitForMode("stacked")
        waitForStage("playing")
        press("expand") { root.value as? String == "watch" }
        var width: CGFloat = 0
        for _ in 0..<3 where width == 0 {
            let b = control("list")
            if b.exists { width = b.frame.width }
        }
        XCTAssertGreaterThanOrEqual(width, 54)
        press("list") { rail.frame.minX > -2 }
        screenshot("list-over-picture")
    }
}

final class PlaylistTests: OnAirUITestCase {
    /// No playlists at all, as on a first launch.
    static let emptyArgs = ["-playlists", "<5b5d>"]

    func fill(_ label: String, _ text: String) {
        let f = app.descendants(matching: .any)["field-\(label)"].firstMatch
        XCTAssertTrue(f.waitForExistence(timeout: 3), "no field \(label)")
        f.tap(); f.typeText(text)
    }

    func testAddingAnXtreamAccountThenRemovingIt() {
        app.launchArguments = Self.emptyArgs
        app.launch()
        app.buttons["Add playlist"].firstMatch.tap()
        app.buttons["XTREAM CODES"].tap()
        fill("Name", "Kitchen")
        fill("Server", "http://127.0.0.1:18765")
        fill("Username", "t")
        fill("Password", "fake-secret-42")
        screenshot("add-xtream")
        app.buttons["ADD"].tap()
        play("Test Two")
        waitForStage("playing")

        // Still there after a relaunch, with no help from launch arguments.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["channel-Test Two"].waitForExistence(timeout: 15))

        app.buttons["playlist-menu"].firstMatch.tap()
        let remove = app.buttons["Remove “Kitchen”"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.tap()
        XCTAssertTrue(app.staticTexts["NOTHING TO TUNE"].waitForExistence(timeout: 3) || app.staticTexts["Nothing to tune"].exists)
        app.terminate()
        app.launch()
        XCTAssertFalse(app.buttons["channel-Test Two"].waitForExistence(timeout: 5))
    }

    func testAboutShowsTheVersionAndNoUpdater() {
        app.launch()
        XCTAssertTrue(app.buttons["channel-Test One"].waitForExistence(timeout: 15))
        app.buttons["playlist-menu"].firstMatch.tap()
        app.buttons["About ONAIR"].tap()
        XCTAssertTrue(app.staticTexts["version"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["version"].label.hasPrefix("v0."))
        XCTAssertFalse(app.buttons["Update"].exists)
        screenshot("about")
        app.buttons["about-done"].tap()
    }
}

final class ReviewFixTests: OnAirUITestCase {
    /// One channel in the list: a swipe has nowhere to go and must not re-tune (that would
    /// reopen the provider's only connection).
    func testSwipeOnAOneChannelListLeavesThePictureAlone() {
        app.launch()
        play("Test Two")
        waitForMode("stacked")
        waitForStage("playing")
        let search = openSearch()
        search.tap(); search.typeText("two")
        XCTAssertTrue(app.buttons["channel-Test Two"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["channel-Test One"].exists)
        picture.swipeUp()
        for _ in 0..<12 { XCTAssertEqual(stage.value as? String, "playing"); usleep(250_000) }
    }

    /// Digits typed into search are search text, not channel numbers.
    func testTypingDigitsInSearchDoesNotChangeChannel() {
        app.launch()
        play("Test One")
        waitForMode("stacked")
        waitForStage("playing")
        let search = openSearch()
        search.tap(); search.typeText("3")
        sleep(2)
        XCTAssertEqual(search.value as? String, "3")
        XCTAssertTrue(app.staticTexts["TEST ONE"].exists, "the now bar should still say Test One")
        XCTAssertEqual(stage.value as? String, "playing")
    }
}

/// Diagnosis only: plays the first channel of a real playlist passed in ONAIR_PROBE_ARGS
/// (hex JSON of [Playlist], via TEST_RUNNER_ONAIR_PROBE_ARGS) and logs the stage for a minute.
/// Skipped in normal runs; nothing about the playlist is written to the repo.
final class LiveProbe: OnAirUITestCase {
    func testProbeFirstChannel() throws {
        guard let hex = ProcessInfo.processInfo.environment["ONAIR_PROBE_ARGS"] else { throw XCTSkip("diagnosis only") }
        let id = ProcessInfo.processInfo.environment["ONAIR_PROBE_SELECTED"] ?? ""
        app.launchArguments = ["-playlists", "<\(hex)>", "-selected", id]
        app.launch()
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 60), "list didn't load")
        first.tap()
        var last = ""
        let start = Date()
        while Date().timeIntervalSince(start) < 60 {
            let v = (stage.value as? String) ?? "?"
            if v != last { print(String(format: "PROBE %5.1fs %@", Date().timeIntervalSince(start), v)); last = v }
            usleep(500_000)
        }
        screenshot("probe")
    }
}
