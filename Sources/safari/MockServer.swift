import Foundation
import Network

/// Plain HTTP on 127.0.0.1 that answers mocked requests for `safari route`, at an unguessable
/// path per route (`/m/<id>`, anything after it is ignored), so pages cannot use routes they
/// were not given. The routed tab's own fetch/XHR are pointed here by main.js; `--global`
/// routes reach it through the extension's network rules. It never fetches anything itself.
final class MockServer {
    static let ports: ClosedRange<UInt16> = 47401...47409

    struct Mock {
        var status = 200
        var headers: [(String, String)] = []
        var body = Data()
        var delay = 0.0
    }

    private let q = DispatchQueue(label: "mock")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var mocks: [String: Mock] = [:]  // guarded by q

    /// Starts on the first free port; false when every port is taken.
    func start() -> Bool {
        if port != 0 { return true }
        for p in MockServer.ports where listen(on: p) { port = p; return true }
        log("no free port in \(MockServer.ports); route mocks disabled")
        return false
    }

    /// Registers a route and returns its base URL (`…/m/<id>`).
    func add(_ m: Mock) -> String {
        let id = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        q.sync { mocks[id] = m }
        return "http://127.0.0.1:\(port)/m/\(id)"
    }

    var base: String { "http://127.0.0.1:\(port)" }

    func remove(url: String) {
        guard let id = url.split(separator: "/").last.map(String.init) else { return }
        q.sync { _ = mocks.removeValue(forKey: id) }
    }

    private func listen(on port: UInt16) -> Bool {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = false
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
        c.start(queue: q)
        q.asyncAfter(deadline: .now() + 10) { if c.state != .cancelled { c.cancel() } }
        read(c, Data())
    }

    /// Reads until the end of the request head; the body (if any) is ignored.
    private func read(_ c: NWConnection, _ buf: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buf
            if let data { buf.append(data) }
            if let r = buf.range(of: Data("\r\n\r\n".utf8)) {
                self.answer(c, String(decoding: buf[..<r.lowerBound], as: UTF8.self))
            } else if err != nil || done || buf.count > 65536 {
                c.cancel()
            } else {
                self.read(c, buf)
            }
        }
    }

    private func answer(_ c: NWConnection, _ head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        let method = parts.first.map(String.init) ?? ""
        let path = parts.count > 1 ? String(parts[1]) : ""
        var h: [String: String] = [:]
        for l in lines.dropFirst() {
            guard let i = l.firstIndex(of: ":") else { continue }
            h[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        // /m/<id>, optionally followed by anything (main.js appends the original URL).
        let segs = path.split(separator: "/", maxSplits: 3, omittingEmptySubsequences: false)
        guard segs.count >= 3, segs[1] == "m", let m = mocks[String(segs[2].prefix { $0 != "?" })] else {
            return send(c, method, h, 404, [("Content-Type", "text/plain")], Data("no such route\n".utf8))
        }
        if method == "OPTIONS" {
            return send(c, method, h, 204, [("Access-Control-Allow-Methods", h["access-control-request-method"] ?? "*"),
                                            ("Access-Control-Allow-Headers", h["access-control-request-headers"] ?? "*"),
                                            ("Access-Control-Max-Age", "600")], Data())
        }
        let go = { self.send(c, method, h, m.status, m.headers, m.body) }
        if m.delay > 0 { q.asyncAfter(deadline: .now() + m.delay, execute: go) } else { go() }
    }

    private func send(_ c: NWConnection, _ method: String, _ h: [String: String], _ status: Int, _ headers: [(String, String)], _ body: Data) {
        // CORS: a redirected or rewritten request now goes to another origin, so allow the page's.
        var cors: [(String, String)] = [("Cache-Control", "no-store"), ("Timing-Allow-Origin", "*"), ("Cross-Origin-Resource-Policy", "cross-origin")]
        if let o = h["origin"] {
            cors += [("Access-Control-Allow-Origin", o), ("Access-Control-Allow-Credentials", "true"), ("Access-Control-Expose-Headers", "*"), ("Vary", "Origin")]
        } else {
            cors.append(("Access-Control-Allow-Origin", "*"))
        }
        let noBody = [101, 204, 205, 304].contains(status) || method == "HEAD"
        var out = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status).capitalized)\r\n"
        let names = Set(headers.map { $0.0.lowercased() })
        for (k, v) in cors where !names.contains(k.lowercased()) { out += "\(k): \(v)\r\n" }
        for (k, v) in headers { out += "\(k): \(v)\r\n" }
        out += "Content-Length: \(noBody && method != "HEAD" ? 0 : body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(out.utf8)
        if !noBody { data.append(body) }
        c.send(content: data, completion: .contentProcessed { _ in c.cancel() })
    }
}
