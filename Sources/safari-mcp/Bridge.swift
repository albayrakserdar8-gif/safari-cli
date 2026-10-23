import CryptoKit
import Foundation
import Network

/// Local WebSocket the Safari extension connects to. The extension's background page tries
/// every port in `ports`, so each server process (one per Claude Code session) takes the
/// first free one. Both sides prove they know the token in `~/.config/safari-mcp/token`
/// before any command runs, so neither a web page nor another local listener can take part.
final class Bridge {
    static let ports: ClosedRange<UInt16> = 47391...47399

    private let q = DispatchQueue(label: "bridge")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private let started = Date()
    private let token: Data

    // Guarded by `q`.
    private var conn: NWConnection?
    private var authed = false
    private var nonce = ""
    private var seq = 0
    private var pending: [Int: (DispatchSemaphore, Box)] = [:]

    private final class Box { var value: [String: Any]? }

    init() {
        token = Bridge.loadToken()
        for p in Bridge.ports where listen(on: p) { port = p; break }
        if port == 0 { log("no free port in \(Bridge.ports); extension bridge disabled") }
    }

    var connected: Bool { q.sync { authed && conn != nil } }

    /// True once the extension is connected. Shortly after start it waits a little, since the
    /// extension retries every 2 s and the first tool call usually comes right away.
    func ready() -> Bool {
        if connected { return true }
        guard port != 0 else { return false }
        let left = 3.0 - Date().timeIntervalSince(started)
        guard left > 0 else { return false }
        let end = Date().addingTimeInterval(left)
        while Date() < end {
            usleep(50_000)
            if connected { return true }
        }
        return false
    }

    /// Sends one command and waits for its reply. Throws `BridgeDown` when not connected
    /// or the connection drops, so the caller can fall back to Apple Events.
    func call(_ op: String, _ args: [String: Any] = [:], timeout: Double = 20) throws -> [String: Any] {
        let sem = DispatchSemaphore(value: 0)
        let box = Box()
        let id: Int = try q.sync {
            guard authed, let c = conn else { throw BridgeDown() }
            seq += 1
            pending[seq] = (sem, box)
            var m = args
            m["id"] = seq
            m["op"] = op
            send(c, m)
            return seq
        }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            q.sync { _ = pending.removeValue(forKey: id) }
            throw ToolError("Safari did not answer in time; the page may be showing a dialog.")
        }
        guard let r = box.value else { throw BridgeDown() }
        if let e = r["err"] as? String { throw ToolError(e) }
        return r
    }

    // MARK: listener

    private func listen(on port: UInt16) -> Bool {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = false
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.maximumMessageSize = 64 << 20
        ws.setClientRequestHandler(q) { _, headers in
            // Only a Safari extension page may connect; web pages send their own origin.
            let origin = headers.first { $0.name.lowercased() == "origin" }?.value ?? ""
            return NWProtocolWebSocket.Response(status: origin.hasPrefix("safari-web-extension://") ? .accept : .reject, subprotocol: nil)
        }
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        guard let l = try? NWListener(using: params) else { return false }
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        l.stateUpdateHandler = { st in
            switch st {
            case .ready: ok = true; sem.signal()
            case .failed, .cancelled: sem.signal()
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: q)
        _ = sem.wait(timeout: .now() + 1)
        if !ok { l.cancel(); return false }
        l.stateUpdateHandler = nil
        listener = l
        return true
    }

    private func accept(_ c: NWConnection) {
        // A new extension connection replaces the old one (Safari restarted, page reloaded).
        c.stateUpdateHandler = { [weak self] st in
            switch st {
            case .failed, .cancelled: self?.drop(c)
            default: break
            }
        }
        c.start(queue: q)
        let n = Bridge.random(16)
        receive(c, nonce: n, authed: false)
        send(c, ["hello": 1, "n": n])
    }

    private func drop(_ c: NWConnection) {
        guard conn === c else { return }
        conn = nil
        authed = false
        for (_, (sem, _)) in pending { sem.signal() }
        pending.removeAll()
        log("extension disconnected")
    }

    private func receive(_ c: NWConnection, nonce: String, authed ok: Bool) {
        c.receiveMessage { [weak self] data, _, _, err in
            guard let self else { return }
            if err != nil { self.drop(c); c.cancel(); return }
            var ok = ok
            if let data, let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                if !ok {
                    // Handshake: the extension signs our nonce; we sign its nonce back.
                    guard let auth = m["auth"] as? String, auth == self.hmac("ext:" + nonce),
                          let theirs = m["n"] as? String else {
                        log("extension failed authentication; check ~/.config/safari-mcp/token")
                        c.cancel()
                        return
                    }
                    ok = true
                    if let old = self.conn, old !== c { old.cancel() }
                    self.conn = c
                    self.authed = true
                    self.send(c, ["auth": self.hmac("srv:" + theirs)])
                    log("extension connected on port \(self.port)")
                } else if let id = m["id"] as? Int, let (sem, box) = self.pending.removeValue(forKey: id) {
                    box.value = m
                    sem.signal()
                }
            }
            self.receive(c, nonce: nonce, authed: ok)
        }
    }

    private func send(_ c: NWConnection, _ m: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: m) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        c.send(content: data, contentContext: NWConnection.ContentContext(identifier: "m", metadata: [meta]), isComplete: true, completion: .idempotent)
    }

    // MARK: token

    private func hmac(_ s: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(s.utf8), using: SymmetricKey(data: token))
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    static var tokenURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/safari-mcp/token")
    }

    /// The shared secret, created on first use. Hex text so the extension can read it as a string.
    private static func loadToken() -> Data {
        let url = tokenURL
        if let s = try? String(contentsOf: url, encoding: .utf8), s.trimmingCharacters(in: .whitespacesAndNewlines).count >= 32 {
            return Data(s.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        }
        let s = random(32)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        FileManager.default.createFile(atPath: url.path, contents: Data(s.utf8), attributes: [.posixPermissions: 0o600])
        return Data(s.utf8)
    }

    private static func random(_ n: Int) -> String {
        (0..<n).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}

struct BridgeDown: Error {}

func log(_ s: String) {
    FileHandle.standardError.write(Data(("safari-mcp: " + s + "\n").utf8))
}
