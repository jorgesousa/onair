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
    }

    var stage: XCUIElement { app.descendants(matching: .any)["stage"] }

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
