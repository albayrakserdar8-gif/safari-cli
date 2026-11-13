import Darwin
import Foundation

/// Where the daemon keeps its socket, lock and log. `SAFARI_CLI_HOME` overrides it (tests).
enum Paths {
    static let dir = ProcessInfo.processInfo.environment["SAFARI_CLI_HOME"] ?? NSHomeDirectory() + "/.config/safari-cli"
    static var sock: String { dir + "/sock" }
    static var lock: String { dir + "/daemon.lock" }
    static var log: String { dir + "/daemon.log" }

    static func ensureDir() {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
}

/// Identifies this build. A daemon started from another build answers `restart`, so a
/// rebuild takes effect on the next command.
func buildID() -> String {
    let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
    var st = stat()
    guard stat(path, &st) == 0 else { return path }
    return "\(path):\(st.st_size):\(st.st_mtimespec.tv_sec).\(st.st_mtimespec.tv_nsec)"
}

// MARK: unix socket helpers

func unixAddress(_ path: String) -> sockaddr_un? {
    var a = sockaddr_un()
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: a.sun_path) else { return nil }
    a.sun_family = sa_family_t(AF_UNIX)
    a.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &a.sun_path) { buf in
        for (i, b) in bytes.enumerated() { buf[i] = b }
        buf[bytes.count] = 0
    }
    return a
}

func withSockaddr<T>(_ a: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
    withUnsafePointer(to: &a) { p in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}

/// Reads up to the first newline (or EOF). Returns nil when nothing arrived.
func readLine(fd: Int32, limit: Int = 64 << 20) -> Data? {
    var out = Data()
    var buf = [UInt8](repeating: 0, count: 65536)
    while out.count < limit {
        let n = read(fd, &buf, buf.count)
        if n < 0 && errno == EINTR { continue }
        if n <= 0 { break }
        if let nl = buf[0..<n].firstIndex(of: 0x0A) {
            out.append(contentsOf: buf[0..<nl])
            return out
        }
        out.append(contentsOf: buf[0..<n])
    }
    return out.isEmpty ? nil : out
}

@discardableResult
func writeAll(fd: Int32, _ data: Data) -> Bool {
    data.withUnsafeBytes { raw -> Bool in
        guard var p = raw.baseAddress else { return true }
        var left = raw.count
        while left > 0 {
            let n = write(fd, p, left)
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return false }
            p += n
            left -= n
        }
        return true
    }
}

// MARK: daemon

/// Owns `Tools` (tab ids, the extension bridge) between commands. Requests are handled one at
/// a time on the main queue; the main run loop must stay free when idle (see main.swift).
final class Daemon {
    static let idleLimit: TimeInterval = 30 * 60
    /// Tabs opened with `open` and unused this long are closed (SAFARI_CLI_REAP, in seconds, for tests).
    static let reapLimit: TimeInterval = Double(ProcessInfo.processInfo.environment["SAFARI_CLI_REAP"] ?? "") ?? 30 * 60

    private let tools = Tools()
    private let build = buildID()
    private var exiting = false
    private var idle: Timer?
    private var reaper: Timer?

    static func main() -> Never {
        Paths.ensureDir()
        signal(SIGPIPE, SIG_IGN)
        // Keep the log small: it only holds the last runs' messages.
        if let size = try? FileManager.default.attributesOfItem(atPath: Paths.log)[.size] as? Int, size > 1 << 20 {
            ftruncate(2, 0)
        }
        // One daemon at a time; a second one started in a race just leaves.
        let lock = open(Paths.lock, O_RDWR | O_CREAT, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { exit(0) }

        unlink(Paths.sock)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard var addr = unixAddress(Paths.sock) else {
            log("socket path too long (max 103 bytes): \(Paths.sock)")
            exit(1)
        }
        guard fd >= 0, withSockaddr(&addr, { bind(fd, $0, $1) }) == 0, listen(fd, 32) == 0 else {
            log("cannot listen on \(Paths.sock): \(String(cString: strerror(errno)))")
            exit(1)
        }
        chmod(Paths.sock, 0o600)
        log("daemon \(getpid()) started")

        let d = Daemon()
        Thread.detachNewThread { d.acceptLoop(fd) }
        DispatchQueue.main.async {
            d.touch()
            d.reaper = Timer.scheduledTimer(withTimeInterval: min(300, max(5, Daemon.reapLimit / 2)), repeats: true) { [weak d] _ in d?.reap(Daemon.reapLimit) }
        }
        RunLoop.main.run()
        exit(0)
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let c = accept(fd, nil, nil)
            if c < 0 { usleep(10_000); continue }
            var uid = uid_t(), gid = gid_t()
            guard getpeereid(c, &uid, &gid) == 0, uid == getuid() else { close(c); continue }
            var one: Int32 = 1
            setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var tv = timeval(tv_sec: 30, tv_usec: 0)
            setsockopt(c, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            Thread.detachNewThread { self.serve(c) }
        }
    }

    private func serve(_ c: Int32) {
        guard let line = readLine(fd: c),
              let msg = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            close(c)
            return
        }
        // The request is handled on the main queue, in arrival order. The reply is written back
        // on this thread: a client that stops reading (Ctrl-Z) then blocks only its own thread,
        // not the main queue that every other client waits on.
        let done = DispatchSemaphore(value: 0)
        var reply = Data()
        DispatchQueue.main.async {
            autoreleasepool {
                reply = (try? JSONSerialization.data(withJSONObject: self.handle(msg), options: [.withoutEscapingSlashes])) ?? Data()
                reply.append(0x0A)
                done.signal()
            }
        }
        done.wait()
        writeAll(fd: c, reply)
        close(c)
    }

    private func handle(_ m: [String: Any]) -> [String: Any] {
        touch()
        let tool = m["tool"] as? String ?? ""
        if tool == "stop" {
            quit()
            return ["ok": true, "text": "stopped daemon \(getpid())"]
        }
        // Another build is asking: nothing runs here, the client starts a fresh daemon.
        if exiting || m["v"] as? String != build {
            quit()
            return ["restart": true]
        }
        if tool == "status" { return ["ok": true, "text": tools.status()] }
        let args = m["args"] as? [String: Any] ?? [:]
        // Pacing: the client asks for a slot before navigating and sleeps itself.
        if tool == "reserve" { return tools.reserve(args).merging(["ok": true]) { a, _ in a } }
        if tool == "rate" {
            do { return ["ok": true, "text": try tools.rate.command(args)] } catch let e as ToolError { return ["ok": false, "text": e.msg] } catch { return ["ok": false, "text": "\(error)"] }
        }
        if tool == "ext" {
            do { return ["ok": true, "text": try tools.rawExt(args["op"] as? String ?? "", args["args"] as? [String: Any] ?? [:])] } catch let e as ToolError { return ["ok": false, "text": e.msg] } catch { return ["ok": false, "text": "\(error)"] }
        }
        guard Tools.names.contains(tool) else { return ["ok": false, "text": "unknown tool \(tool)"] }
        do {
            var text: [String] = []
            var images: [String] = []
            for c in try tools.call(tool, args) {
                switch c {
                case .text(let t): text.append(t)
                case .image(let d): images.append(d.base64EncodedString())
                }
            }
            return ["ok": true, "text": text.joined(separator: "\n"), "img": images]
        } catch let e as ToolError {
            return ["ok": false, "text": e.msg]
        } catch {
            return ["ok": false, "text": "\(error)"]
        }
    }

    /// Stops taking new connections at once and exits after the replies already queued.
    private func quit() {
        guard !exiting else { return }
        exiting = true
        unlink(Paths.sock)
        log("daemon \(getpid()) exiting")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
    }

    private func touch() {
        idle?.invalidate()
        idle = Timer.scheduledTimer(withTimeInterval: Daemon.idleLimit, repeats: false) { [weak self] _ in
            // Nothing has used the daemon for idleLimit, so every agent tab is idle that long.
            self?.reap(0)
            self?.quit()
        }
    }

    private func reap(_ limit: TimeInterval) {
        guard !exiting else { return }
        for t in tools.reap(olderThan: limit) { log("closed unused agent tab \(t)") }
    }
}
