import Darwin
import Foundation

/// Sends one command to the daemon, starting it when needed, and prints the result.
enum Client {
    struct Failure: Error { let msg: String }

    static func run(_ tool: String, _ args: [String: Any], out: String? = nil) -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        var args = args
        let idOnly = args.removeValue(forKey: "idonly") != nil
        do {
            let (waited, site) = try pace(tool, &args)
            var r = try send(tool, args)
            if waited >= 0.5, r["ok"] as? Bool == true, let t = r["text"] as? String {
                // On the first line, which is the one describing the page.
                let note = " (waited \(String(format: "%.1f", waited)) s: pacing \(site))"
                if let nl = t.firstIndex(of: "\n") { r["text"] = t[..<nl] + note + t[nl...] } else { r["text"] = t + note }
            }
            return show(r, tab: args["tab"] as? String, out: out, idOnly: idOnly)
        } catch let f as Failure {
            return fail(f.msg)
        } catch {
            return fail("safari: \(error)")
        }
    }

    /// Before a navigation (go, open URL): ask the daemon for the site's next slot and sleep
    /// until it, here rather than in the shared daemon. Returns the seconds waited and the site.
    static func pace(_ tool: String, _ args: inout [String: Any]) throws -> (Double, String) {
        let delay = args.removeValue(forKey: "delay"), fallback = args.removeValue(forKey: "fallback")
        let nav = tool == "navigate" || (tool == "tabs" && args["action"] as? String == "new" && args["url"] != nil)
        guard nav else { return (0, "") }
        var ra: [String: Any] = ["url": args["url"] ?? ""]
        if let t = args["tab"] { ra["tab"] = t }
        if let delay { ra["delay"] = delay }
        if let fallback { ra["fallback"] = fallback }
        let r = try send("reserve", ra)
        guard let w = r["wait"] as? Double, w > 0 else { return (0, "") }
        let site = r["site"] as? String ?? ""
        if w > 20 { FileHandle.standardError.write(Data("safari: waiting \(Int(w.rounded())) s for the next slot on \(site)\n".utf8)) }
        Thread.sleep(forTimeInterval: w)
        return (w, site)
    }

    /// One request to the daemon, starting it when needed. Returns the reply (`ok`, `text`, …).
    static func send(_ tool: String, _ args: [String: Any]) throws -> [String: Any] {
        var data = Data(jsonString(["v": buildID(), "tool": tool, "args": args]).utf8)
        data.append(0x0A)
        let canStart = tool != "stop"
        let deadline = Date().addingTimeInterval(10)
        var started = Date.distantPast

        while true {
            if let fd = connectDaemon() {
                defer { close(fd) }
                guard writeAll(fd: fd, data) else { continue }
                guard let line = readLine(fd: fd),
                      let r = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
                    throw Failure(msg: "safari: the daemon exited before answering; see \(Paths.log)")
                }
                if r["restart"] as? Bool == true {
                    // That daemon is from another build and is exiting; nothing ran there.
                    guard Date() < deadline else { throw Failure(msg: "safari: the daemon did not restart; see \(Paths.log)") }
                    usleep(100_000)
                    continue
                }
                return r
            }
            if !canStart { return ["ok": true, "text": "no daemon running"] }
            if Date() > deadline { throw Failure(msg: "safari: could not start the daemon; see \(Paths.log)") }
            // A daemon that is still exiting holds the lock; try again shortly.
            if Date().timeIntervalSince(started) > 0.5 {
                startDaemon()
                started = Date()
            }
            usleep(50_000)
        }
    }

    /// Splits a result into data and notes: lines starting with \u{1E} (continuation hints,
    /// row counts) go to stderr, so piping or `-o` keeps the data clean.
    static func split(_ text: String) -> (data: String, notes: [String]) {
        guard text.contains("\u{1E}") else { return (text, []) }
        var data: [Substring] = [], notes: [String] = []
        for l in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if l.hasPrefix("\u{1E}") { notes.append(String(l.dropFirst())) } else { data.append(l) }
        }
        return (data.joined(separator: "\n"), notes)
    }

    private static func connectDaemon() -> Int32? {
        guard var addr = unixAddress(Paths.sock) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        if withSockaddr(&addr, { connect(fd, $0, $1) }) == 0 { return fd }
        close(fd)
        return nil
    }

    /// The daemon is a child of this shell, not a launchd job, so macOS attributes it to the
    /// same app (the terminal) and the existing Automation/Accessibility grants apply.
    private static func startDaemon() {
        Paths.ensureDir()
        guard let exe = Bundle.main.executablePath else { return }
        var fa: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fa)
        defer { posix_spawn_file_actions_destroy(&fa) }
        // Never inherit the caller's stdout: the shell running this command would wait for it.
        posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fa, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fa, 2, Paths.log, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        var at: posix_spawnattr_t? = nil
        posix_spawnattr_init(&at)
        defer { posix_spawnattr_destroy(&at) }
        posix_spawnattr_setflags(&at, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(exe), strdup("--daemon"), nil]
        defer { argv.forEach { free($0) } }
        var pid = pid_t()
        if posix_spawn(&pid, exe, &fa, &at, argv, environ) != 0 {
            fputs("safari: could not start the daemon: \(String(cString: strerror(errno)))\n", stderr)
        }
    }

    private static func show(_ r: [String: Any], tab: String?, out: String?, idOnly: Bool = false) -> Int32 {
        var text = r["text"] as? String ?? ""
        let images = r["img"] as? [String] ?? []
        if !images.isEmpty {
            var paths: [String] = []
            for (i, b64) in images.enumerated() {
                guard let d = Data(base64Encoded: b64) else { continue }
                let url = imagePath(out, tab: tab, index: i, count: images.count)
                do {
                    try d.write(to: url)
                    paths.append(url.path)
                } catch {
                    return fail("safari: cannot write \(url.path): \(error.localizedDescription)")
                }
            }
            text = paths.joined(separator: " ") + (text.isEmpty ? "" : " " + text)
        }
        guard r["ok"] as? Bool == true else { return fail(split(text).data) }
        let (data, notes) = split(text)
        text = data
        defer { for n in notes { FileHandle.standardError.write(Data((n + "\n").utf8)) } }
        // `-o FILE` for text results: the whole result into the file, one line here.
        if images.isEmpty, let out {
            let path = (out as NSString).expandingTildeInPath
            do { try Data((text.hasSuffix("\n") ? text : text + "\n").utf8).write(to: URL(fileURLWithPath: path)) } catch {
                return fail("safari: cannot write \(path): \(error.localizedDescription)")
            }
            print("wrote \(text.unicodeScalars.count) chars → \(path)")
            return 0
        }
        // `open --id-only`: just the new tab id, for scripts.
        if idOnly, let m = text.firstMatch(of: #/t\d+/#) { text = String(m.output) }
        if !text.isEmpty { print(text) }
        return 0
    }

    private static func imagePath(_ out: String?, tab: String?, index: Int, count: Int) -> URL {
        if let out {
            let u = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
            return count == 1 ? u : u.deletingPathExtension().appendingPathExtension("\(index + 1).jpg")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("safari-cli")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ms = Int(Date().timeIntervalSince1970 * 1000) % 100_000_000
        return dir.appendingPathComponent("shot-\(tab ?? "t")-\(ms)\(count > 1 ? "-\(index + 1)" : "").jpg")
    }

    private static func fail(_ msg: String) -> Int32 {
        FileHandle.standardError.write(Data((msg.hasSuffix("\n") ? msg : msg + "\n").utf8))
        return 1
    }
}
