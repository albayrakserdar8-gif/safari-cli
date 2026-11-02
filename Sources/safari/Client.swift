import Darwin
import Foundation

/// Sends one command to the daemon, starting it when needed, and prints the result.
enum Client {
    static func run(_ tool: String, _ args: [String: Any], out: String? = nil) -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        var args = args
        let idOnly = args.removeValue(forKey: "idonly") != nil
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
                    return fail("safari: the daemon exited before answering; see \(Paths.log)")
                }
                if r["restart"] as? Bool == true {
                    // That daemon is from another build and is exiting; nothing ran there.
                    guard Date() < deadline else { return fail("safari: the daemon did not restart; see \(Paths.log)") }
                    usleep(100_000)
                    continue
                }
                return show(r, tab: args["tab"] as? String, out: out, idOnly: idOnly)
            }
            if !canStart { print("no daemon running"); return 0 }
            if Date() > deadline { return fail("safari: could not start the daemon; see \(Paths.log)") }
            // A daemon that is still exiting holds the lock; try again shortly.
            if Date().timeIntervalSince(started) > 0.5 {
                startDaemon()
                started = Date()
            }
            usleep(50_000)
        }
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
        guard r["ok"] as? Bool == true else { return fail(text) }
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
