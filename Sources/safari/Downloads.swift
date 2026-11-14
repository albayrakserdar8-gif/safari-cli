import Foundation

/// `safari downloads`: Safari's recent downloads. Runs in the client (it needs no Safari), so a
/// `--wait` never holds up the daemon other agents share. The source is Safari's download list
/// (~/Library/Safari/Downloads.plist: URL, path, progress, errors); when that cannot be read,
/// recent files in the download folder.
enum Downloads {
    private struct Item {
        let url: String
        let path: String
        let added: Date
        let finished: Bool
        let failed: Int?
        let got: Int
        let total: Int

        var host: String { URLComponents(string: url)?.host ?? url }
        var done: Bool { finished || failed != nil }

        var line: String {
            if let e = failed { return "failed  \(url)" + (e == -999 ? "  (cancelled)" : "  (error \(e))") }
            if finished {
                let size = ByteCountFormatter.string(fromByteCount: Int64(got), countStyle: .file)
                var dir: ObjCBool = false
                let gone = !FileManager.default.fileExists(atPath: path, isDirectory: &dir)
                return "\(path)  \(size)  \(ago(added)) ago" + (dir.boolValue ? "  (a folder: Safari unpacked the archive; the size is the archive's)" : gone ? "  (moved or deleted since)" : "")
            }
            if got == 0 && -added.timeIntervalSinceNow > 3 {
                return "waiting  \(url)  (not started: Safari may be asking the user to allow downloads from \(host))"
            }
            let pct = total > 0 ? " \(got * 100 / total)%" : ""
            return "downloading\(pct)  \(path.isEmpty ? url : path)"
        }
    }

    private static func ago(_ d: Date) -> String {
        let s = Int(-d.timeIntervalSinceNow)
        return s < 120 ? "\(s) s" : "\(s / 60) min"
    }

    /// Downloads added in the last `within` seconds, newest first; nil when the list is unreadable.
    private static func fromSafari(within: TimeInterval) -> [Item]? {
        let p = NSHomeDirectory() + "/Library/Safari/Downloads.plist"
        guard let d = FileManager.default.contents(atPath: p),
              let pl = (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any],
              let hist = pl["DownloadHistory"] as? [[String: Any]] else { return nil }
        let now = Date()
        return hist.compactMap { e -> Item? in
            guard let added = e["DownloadEntryDateAddedKey"] as? Date, now.timeIntervalSince(added) <= within else { return nil }
            // While downloading, the file sits in a `.download` bundle; PostPath is where it ended up
            // (a folder when Safari unpacked an archive).
            var path = e["DownloadEntryPostPath"] as? String ?? e["DownloadEntryPath"] as? String ?? ""
            if let r = path.range(of: ".download/", options: .backwards), e["DownloadEntryDateFinishedKey"] != nil {
                path = String(path[..<r.lowerBound])
            }
            return Item(url: e["DownloadEntryURL"] as? String ?? "",
                        path: path,
                        added: added,
                        finished: e["DownloadEntryDateFinishedKey"] != nil && e["DownloadEntryErrorCodeDictionaryKey"] == nil,
                        failed: e["DownloadEntryErrorCodeDictionaryKey"] as? Int,
                        got: e["DownloadEntryProgressBytesSoFar"] as? Int ?? 0,
                        total: e["DownloadEntryProgressTotalToLoad"] as? Int ?? 0)
        }.sorted { $0.added > $1.added }
    }

    /// Safari's download folder setting, else ~/Downloads.
    private static var folder: String {
        if let p = CFPreferencesCopyAppValue("DownloadsPath" as CFString, "com.apple.Safari" as CFString) as? String, !p.isEmpty {
            return (p as NSString).expandingTildeInPath
        }
        return NSHomeDirectory() + "/Downloads"
    }

    /// Fallback: files that appeared in the download folder; `.download` bundles are in progress.
    private static func fromFolder(within: TimeInterval) -> [Item] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .addedToDirectoryDateKey, .fileSizeKey, .isDirectoryKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let now = Date()
        return urls.compactMap { u -> Item? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            let date = [v.contentModificationDate, v.addedToDirectoryDate].compactMap { $0 }.max() ?? .distantPast
            let partial = u.pathExtension == "download"
            if v.isDirectory == true && !partial { return nil }
            guard now.timeIntervalSince(date) <= within else { return nil }
            return Item(url: "", path: partial ? u.deletingPathExtension().path : u.path, added: date, finished: !partial, failed: nil, got: v.fileSize ?? 0, total: 0)
        }.sorted { $0.added > $1.added }
    }

    private static func items(within: TimeInterval) -> [Item] {
        fromSafari(within: within) ?? fromFolder(within: within)
    }

    /// Exit status: 0; 1 when --wait ends on a failed download or nothing finished in time.
    static func run(_ a: [String: Any]) -> Int32 {
        guard a["wait"] as? Bool == true else {
            let found = items(within: 600)
            Out.data(found.isEmpty ? "(no downloads in the last 10 minutes)" : found.map(\.line).joined(separator: "\n"))
            return 0
        }
        // Waits for the downloads started in the last 2 minutes to end.
        let deadline = Date().addingTimeInterval(min(a["timeout"] as? Double ?? 30, 120))
        while true {
            let found = items(within: 120)
            if !found.isEmpty && found.allSatisfy(\.done) {
                Out.data(found.map(\.line).joined(separator: "\n"))
                return found.first?.failed == nil ? 0 : 1
            }
            if Date() > deadline {
                let msg = found.isEmpty ? "no download started in the last 2 minutes" : found.map(\.line).joined(separator: "\n")
                return Out.fail(msg, kind: "timeout")
            }
            usleep(500_000)
        }
    }
}
