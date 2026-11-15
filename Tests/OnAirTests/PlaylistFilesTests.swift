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

    #expect(kept.hasPrefix(store.path))
    #expect(kept.hasSuffix(".m3u"))
    let text = try String(contentsOfFile: kept, encoding: .utf8)
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
