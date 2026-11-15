import Foundation

/// M3U files picked from disk. The Mac keeps the file's path. The iPad can't read a picked
/// file again later (it's outside the app's sandbox), so it keeps its own copy.
enum PlaylistFiles {
    static var appDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Playlists", isDirectory: true)
    }

    /// Copies the file into `directory` under a fresh name and returns the copy's path.
    static func copyIntoApp(_ url: URL, directory: URL = appDirectory) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "m3u" : url.pathExtension
        let target = directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: url, to: target)
        return target.path
    }

    /// What to store for a picked file on this platform.
    static func location(forPicked url: URL) -> String {
        #if os(iOS)
        return (try? copyIntoApp(url)) ?? url.path
        #else
        return url.path
        #endif
    }
}
