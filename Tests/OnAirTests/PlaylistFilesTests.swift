import Foundation
import Testing
@testable import OnAir

@Test func importedPlaylistFileSurvivesTheOriginalBeingDeleted() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let original = tmp.appendingPathComponent("my list.m3u")
    try "#EXTM3U\n#EXTINF:-1,One\nhttp://x/1.ts\n".write(to: original, atomically: true, encoding: .utf8)
    let store = tmp.appendingPathComponent("Playlists")

    let kept = try PlaylistFiles.copyIntoApp(original, directory: store)
    try FileManager.default.removeItem(at: original)

    let url = try #require(PlaylistFiles.url(for: kept, directory: store))
    #expect(url.path.hasPrefix(store.path))
    #expect(kept.hasSuffix(".m3u"))
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(M3UParser.parse(text, base: nil).first?.name == "One")
}

@Test func twoImportsOfTheSameNameDoNotOverwriteEachOther() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let f = tmp.appendingPathComponent("list.m3u")
    try "a".write(to: f, atomically: true, encoding: .utf8)
    let a = try PlaylistFiles.copyIntoApp(f, directory: tmp.appendingPathComponent("P"))
    let b = try PlaylistFiles.copyIntoApp(f, directory: tmp.appendingPathComponent("P"))
    #expect(a != b)
}

@Test func importedFilesAreFoundAgainAfterTheAppMoves() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let f = tmp.appendingPathComponent("a.m3u")
    try "x".write(to: f, atomically: true, encoding: .utf8)
    let first = tmp.appendingPathComponent("Old/Playlists")
    let kept = try PlaylistFiles.copyIntoApp(f, directory: first)
    #expect(!kept.hasPrefix("/"), "store a name, not a container path")
    // The app's container moved (reinstall): same name, new place.
    let moved = tmp.appendingPathComponent("New/Playlists")
    try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: first.appendingPathComponent(String(kept.split(separator: ":").last!)),
                                     to: moved.appendingPathComponent(String(kept.split(separator: ":").last!)))
    let url = PlaylistFiles.url(for: kept, directory: moved)
    #expect(url != nil)
    #expect(FileManager.default.fileExists(atPath: url!.path))
    #expect(PlaylistFiles.url(for: "/Users/x/list.m3u")?.path == "/Users/x/list.m3u")
    #expect(PlaylistFiles.url(for: "http://h/list.m3u")?.absoluteString == "http://h/list.m3u")
}
