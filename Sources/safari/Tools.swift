import AppKit
import Foundation
import UniformTypeIdentifiers

struct ToolError: Error {
    let msg: String
    init(_ msg: String) { self.msg = msg }
}

enum Content {
    case text(String)
    case image(Data)
}

func jsonString(_ value: Any) -> String {
    let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
}

final class Tools {
    static let names: Set = ["tabs", "navigate", "read", "table", "act", "js", "screenshot", "logs", "locator", "highlight", "route", "storage", "cookies", "record"]

    /// A tab we know about. `id` is ours and stable; `pos` is where Safari has it now.
    private struct Tab {
        let id: Int
        var pos: TabRef
        var url: String
        var title: String
        var visible: Bool
        /// Stamped into the page's agent once we have worked in the tab.
        var handle: String?
        /// Safari's tab id when the extension is in use; matched before anything else.
        var xid: Int? = nil
        /// In a private window (reported by the extension, or opened by us as one).
        var priv = false
    }

    private lazy var apple = Safari()
    private let bridge = Bridge()
    private lazy var ext = ExtBrowser(bridge)
    private var usingExt: Bool?
    private var extGeneration = 0

    /// Safari through the extension when it is connected, else through Apple Events.
    private var safari: Browser {
        let e = bridge.ready()
        let g = e ? bridge.generation : extGeneration
        if let u = usingExt, u != e || (e && g != extGeneration) { switched(toExtension: e) }
        usingExt = e
        extGeneration = g
        return e ? ext : apple
    }

    /// Window ids and positions differ between the two backends. Carry over the tabs whose
    /// URL is unique on both sides; the rest get new ids at the next sync.
    private func switched(toExtension e: Bool) {
        log(e ? "using the Safari extension" : "extension not connected; using Apple Events")
        frameIDs = [:]  // frame ids mean different things in the two backends
        focusFrame = [:]
        let list = (try? (e ? ext : apple as Browser).listTabs()) ?? []
        var fresh: [Int: Tab] = [:]
        for t in tabs.values where tabs.values.filter({ $0.url == t.url }).count == 1 {
            let hits = list.filter { $0.url == t.url }
            guard hits.count == 1 else { continue }
            var n = t
            n.pos = hits[0].ref
            n.visible = hits[0].current
            n.xid = hits[0].xid
            n.priv = n.priv || hits[0].priv
            fresh[t.id] = n
        }
        tabs = fresh
        counts = [:]
    }

    /// One line for `safari status`; does not touch Safari.
    func status() -> String {
        let ext = bridge.ready() ? "extension connected (port \(bridge.port))"
            : bridge.port == 0 ? "extension bridge off (ports 47391-47399 busy); Apple Events"
            : "extension not connected (port \(bridge.port)); Apple Events"
        return "daemon pid \(getpid()) · \(ext) · \(tabs.count) tabs tracked"
    }

    /// Window server id for a tab's window, for capture, real input and native dialogs.
    private func cg(_ wid: Int) -> Int { safari.cgWindow(wid) ?? -1 }
    private var tabs: [Int: Tab] = [:]
    /// Ids in Safari's order: windows front to back, tabs left to right.
    private var order: [Int] = []
    private var counts: [Int: Int] = [:]
    /// Tab ids are never reused, not even by a later daemon: an agent still holding t5 from
    /// before a restart must get "gone", not whichever tab the new daemon numbers t5.
    private var nextTab: Int = {
        let s = try? String(contentsOfFile: Paths.dir + "/next-tab", encoding: .utf8)
        return max(1, Int(s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 1)
    }() {
        didSet { try? String(nextTab).write(toFile: Paths.dir + "/next-tab", atomically: true, encoding: .utf8) }
    }
    private var synced = false
    /// Tab used when a call does not name one.
    private var current: Int?
    /// Set once the default tab went away; from then on calls must name a tab rather than
    /// fall back to whatever the user happens to be looking at.
    private var defaultLost = false
    /// Tabs opened with tabs new. Several agents can share this daemon; once more than one
    /// of these is open, "the last tab used" may be another agent's, so calls must name a tab.
    private var opened = Set<Int>()
    /// When each tab was last named by a call; `reap` closes opened tabs left unused.
    private var lastUse: [Int: Date] = [:]
    /// Tabs brought forward with `show`: the user may be looking at them, so never reaped.
    private var shown = Set<Int>()
    private let session = String(UInt32.random(in: 0...UInt32.max), radix: 36)
    private var seq = 0
    /// URL the last successful `exec` verified before it ran.
    private var verifiedURL = ""

    func call(_ name: String, _ a: [String: Any]) throws -> [Content] {
        dialogs = []
        defer { if let c = current { lastUse[c] = Date() } }
        var out: [Content]
        do {
            out = try dispatch(name, a)
        } catch let e as ToolError where e.msg.hasPrefix("Safari did not answer in time") {
            // Most likely a dialog the page agent could not intercept (shown before it was injected).
            guard let id = current else { throw e }
            blocked.insert(id)
            if let t = tabs[id], t.visible, let msg = Capture.dialog(wid: cg(t.pos.wid), answer: nil) {
                throw ToolError("The page shows a dialog: \(jsonString(clip(msg, 200))). Answer it with: safari t\(id) dialog accept (or dismiss).")
            }
            throw ToolError(e.msg + " If so, `safari t\(id) dialog accept` (or dismiss) answers it; it needs Accessibility permission and shows the tab.")
        }
        saveState()
        if !dialogs.isEmpty {
            let note = dialogs.map { "⚠ dialog " + $0 }.joined(separator: "\n")
            if let i = out.lastIndex(where: { if case .text = $0 { return true } else { return false } }), case .text(let t) = out[i] {
                out[i] = .text(t + "\n" + note)
            } else { out.append(.text(note)) }
        }
        return out
    }

    /// Dialogs the page agent answered during this call.
    private var dialogs: [String] = []
    /// Tabs whose last call timed out, probably behind a native dialog.
    private var blocked: Set<Int> = []

    private func dispatch(_ name: String, _ a: [String: Any]) throws -> [Content] {
        switch name {
        case "tabs": return [.text(try tabsTool(a))]
        case "navigate": return [.text(try navigate(a))]
        case "read": return [.text(try page("read", a, ["mode", "query", "ref", "selector", "full", "diff", "max_chars", "offset"]))]
        case "table": return [.text(try page("table", a, ["ref", "selector", "rows", "json", "max_chars", "offset"]))]
        case "act": return [.text(try act(a))]
        case "locator":
            var v = try page("locator", a, ["ref", "selector", "x", "y"])
            if let r = a["ref"] as? String, r.hasPrefix("f") { v += " (inside frame \(r.prefix { $0 != "e" }): --sel looks in the top page only)" }
            return [.text(v)]
        case "route": return [.text(try route(a))]
        case "storage": return [.text(try page("storage", a, ["area", "key", "value", "del", "clear", "max_chars"]))]
        case "cookies": return [.text(try cookies(a))]
        case "record":
            if !safari.isExtension { throw ToolError("record needs the Safari CLI Bridge extension (the recorder must start with each page).") }
            return [.text(try page("record", a, ["stop"]))]
        case "highlight": return [.text(try page("highlight", a, ["ref", "selector", "x", "y", "secs", "hide"]))]
        case "js": return [.text(try js(a))]
        case "screenshot": return try screenshot(a)
        case "logs":
            var la = a
            if a["kind"] as? String == "network", a["id"] == nil, safari.isExtension, let t = tabs[try resolve(a)], let wr = ext.requests(t.pos) {
                la["wr"] = wr
            }
            return [.text(try page("logs", la, ["kind", "level", "new", "pattern", "id", "limit", "clear", "wr"]))]
        default: throw ToolError("Unknown tool \(name)")
        }
    }

    // MARK: tab tracking

    private func nextID(_ prefix: String) -> String {
        seq += 1
        return "\(prefix)\(session)\(seq)"
    }

    private func clip(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n - 1)) + "…" : s }

    private func gone(_ id: Int) -> ToolError {
        ToolError("Tab t\(id) is gone (closed, or changed outside this session); run `safari tabs` for current ids.")
    }

    private func sameHost(_ a: String, _ b: String) -> Bool {
        guard let ha = URLComponents(string: a)?.host, let hb = URLComponents(string: b)?.host else { return false }
        return ha == hb
    }

    /// Longest common subsequence, as index pairs.
    private func lcs(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var len = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                len[i][j] = a[i] == b[j] ? len[i + 1][j + 1] + 1 : max(len[i + 1][j], len[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { pairs.append((i, j)); i += 1; j += 1 } else if len[i + 1][j] >= len[i][j + 1] { i += 1 } else { j += 1 }
        }
        return pairs
    }

    /// Re-reads Safari's tabs and carries our ids over to wherever each tab is now.
    /// Tabs keep their order unless moved, so matching the URL sequence per window finds
    /// most of them; what is left is matched by the handle in the page, or dropped.
    // A restarted daemon (idle exit, rebuild) gives tabs we worked in back the ids they had.
    // They are matched by the handle stored in the page (Safari's extension tab ids change
    // between connections), and only on the same site.
    private var restoreLoaded = false
    private var restored: [(id: Int, url: String, handle: String)] = []
    private var savedState = ""
    private var statePath: String { Paths.dir + "/tabs.json" }

    private func loadRestored() {
        guard !restoreLoaded else { return }
        restoreLoaded = true
        guard let d = FileManager.default.contents(atPath: statePath),
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
        for v in j["h"] as? [[Any]] ?? [] {
            if v.count == 3, let id = v[0] as? Int, let u = v[1] as? String, let h = v[2] as? String { restored.append((id, u, h)) }
        }
        opened.formUnion(j["o"] as? [Int] ?? [])
    }

    private func saveState() {
        let h = tabs.values.compactMap { t in t.handle.map { [t.id, t.url, $0] as [Any] } }
        let s = jsonString(["h": h, "o": opened.filter { tabs[$0] != nil }.sorted()])
        guard s != savedState else { return }
        savedState = s
        try? s.write(toFile: statePath, atomically: true, encoding: .utf8)
    }

    private func sync() throws {
        loadRestored()
        let list = try safari.listTabs()
        var result: [Int: Tab] = [:]
        var slot = [Int?](repeating: nil, count: list.count)

        func assign(_ old: Tab, _ li: Int) {
            var t = old
            t.pos = list[li].ref
            t.url = list[li].url
            t.title = list[li].title
            t.visible = list[li].current
            t.xid = list[li].xid
            t.priv = old.priv || list[li].priv
            result[t.id] = t
            slot[li] = t.id
        }

        // With the extension every tab has a fixed id: no guessing needed for those.
        var byXid: [Int: Int] = [:]
        for li in list.indices { if let x = list[li].xid { byXid[x] = li } }
        for old in tabs.values { if let x = old.xid, let li = byXid[x] { assign(old, li) } }

        var wids: [Int] = []
        for t in list where !wids.contains(t.ref.wid) { wids.append(t.ref.wid) }
        for wid in wids {
            let news = list.indices.filter { list[$0].ref.wid == wid && slot[$0] == nil }
            let olds = tabs.values.filter { $0.pos.wid == wid && result[$0.id] == nil && $0.xid == nil }.sorted { $0.pos.idx < $1.pos.idx }
            var po = 0, pn = 0
            for (oi, ni) in lcs(olds.map(\.url), news.map { list[$0].url }) + [(olds.count, news.count)] {
                let go = Array(olds[po..<oi]), gn = Array(news[pn..<ni])
                if go.count == gn.count {
                    // Same place, new URL: the tab navigated. For a tab we have worked in,
                    // only take that on trust within one site; otherwise ask the page below.
                    for k in go.indices where go[k].handle == nil || sameHost(go[k].url, list[gn[k]].url) { assign(go[k], gn[k]) }
                }
                if oi < olds.count { assign(olds[oi], news[ni]) }
                po = oi + 1
                pn = ni + 1
            }
        }

        let looseOld = tabs.values.filter { result[$0.id] == nil && $0.handle != nil && $0.xid == nil }.sorted { $0.id < $1.id }
        if !looseOld.isEmpty {
            var probed: [Int: String] = [:]
            for old in looseOld {
                for li in list.indices where slot[li] == nil {
                    if probed[li] == nil {
                        probed[li] = (try? safari.js(list[li].ref, "window.__smcp?__smcp.h||'':''", Expect(count: -1, url: nil)))?.result ?? ""
                    }
                    if probed[li] == old.handle { assign(old, li); break }
                }
            }
        }
        for li in list.indices where slot[li] == nil {
            var id = nextTab, handle: String?
            let cands = restored.indices.filter { result[restored[$0].id] == nil && sameHost(restored[$0].url, list[li].url) }
            if !cands.isEmpty, let h = (try? safari.js(list[li].ref, "window.__smcp?__smcp.h||'':''", Expect(count: -1, url: nil)))??.result,
               !h.isEmpty, let k = cands.first(where: { restored[$0].handle == h }) {
                id = restored[k].id
                handle = h
                restored.remove(at: k)
            } else {
                nextTab += 1
            }
            let t = Tab(id: id, pos: list[li].ref, url: list[li].url, title: list[li].title, visible: list[li].current, handle: handle, xid: list[li].xid, priv: list[li].priv)
            result[t.id] = t
            slot[li] = t.id
        }

        // A tab in a window we know is private is private too.
        let pw = Set(result.values.filter(\.priv).map(\.pos.wid))
        for (k, t) in result where !t.priv && pw.contains(t.pos.wid) { result[k]?.priv = true }
        tabs = result
        order = slot.compactMap { $0 }
        counts = [:]
        for t in list { counts[t.ref.wid, default: 0] += 1 }
        synced = true
        saveState()
        if let c = current, tabs[c] == nil {
            current = nil
            defaultLost = true
        }
    }

    /// Closes tabs opened with `open` that no call has named for `limit` seconds, except
    /// visible ones in the user's windows and ones brought forward with `show`. Returns "tN url" for each closed tab.
    func reap(olderThan limit: TimeInterval) -> [String] {
        guard !opened.isEmpty, (try? sync()) != nil else { return [] }
        let now = Date()
        var closed: [String] = []
        for id in opened.sorted() {
            guard let t = tabs[id] else { continue }
            // A visible tab is the user's view, unless its window holds only agent tabs (open --window).
            let ownWindow = !tabs.values.contains { $0.pos.wid == t.pos.wid && !opened.contains($0.id) }
            if (t.visible && !ownWindow) || shown.contains(id) { continue }
            // A tab restored from an earlier daemon starts its clock now (limit 0: at idle exit).
            let last = lastUse[id] ?? (limit > 0 ? now : .distantPast)
            lastUse[id] = last
            guard now.timeIntervalSince(last) >= limit else { continue }
            if (try? guardedOp(id, { try safari.close($0, $1) })) != nil {
                tabs[id] = nil
                opened.remove(id)
                closed.append("t\(id) \(t.url)")
                if current == id { current = nil; defaultLost = true }
            }
        }
        if !closed.isEmpty { try? sync(); saveState() }
        return closed
    }

    private func resolve(_ a: [String: Any]) throws -> Int {
        if let raw = a["tab"] {
            let s = "\(raw)"
            guard let id = Int(s.hasPrefix("t") ? String(s.dropFirst()) : s) else {
                throw ToolError("Bad tab id \(s); use an id from `safari tabs`, like t3.")
            }
            if tabs[id] == nil { try sync() }
            guard tabs[id] != nil else {
                // Never let later calls without a tab fall back to the user's visible tab instead.
                if current == nil { defaultLost = true }
                throw gone(id)
            }
            current = id
            defaultLost = false
            return id
        }
        opened = opened.filter { tabs[$0] != nil }
        if opened.count > 1 {
            throw ToolError("Several tabs opened here are open (\(opened.sorted().map { "t\($0)" }.joined(separator: ", "))); put the tab id first: safari t3 <verb> (or export SAFARI_TAB=t3 once).")
        }
        if let c = current {
            guard tabs[c] != nil else { throw gone(c) }
            return c
        }
        if defaultLost { throw ToolError("The default tab was closed; put a tab id first (ids from `safari tabs`).") }
        try sync()
        guard let front = order.first(where: { tabs[$0]?.visible == true }) else { throw ToolError("Safari has no open tab; use `safari open <url>`.") }
        current = front
        return front
    }

    private func expect(_ t: Tab, url: Bool = true) -> Expect {
        Expect(count: counts[t.pos.wid] ?? -1, url: url ? t.url : nil)
    }

    /// Runs `op` on the tab's position; Safari refuses if the tab is not what we expect,
    /// in which case positions are re-read and the call retried.
    private func guardedOp(_ id: Int, _ op: (TabRef, Expect) throws -> Bool) throws {
        for _ in 0..<3 {
            guard let t = tabs[id] else { throw gone(id) }
            if try op(t.pos, expect(t)) { return }
            try sync()
        }
        throw ToolError("Tab t\(id) keeps changing; run `safari tabs`.")
    }

    /// Runs JavaScript in the tab after Safari has verified it is the tab we mean.
    private func exec(_ id: Int, _ code: String) throws -> String {
        for _ in 0..<3 {
            guard let t = tabs[id] else { throw gone(id) }
            if let r = try safari.js(t.pos, code, expect(t)) {
                verifiedURL = t.url
                tabs[id]?.url = r.url
                return r.result
            }
            try sync()
        }
        throw ToolError("Tab t\(id) keeps changing; run `safari tabs`.")
    }

    /// JavaScript without the URL check, for polling while a navigation is in flight.
    private func poll(_ id: Int, _ code: String) -> (url: String, result: String)? {
        guard let t = tabs[id] else { return nil }
        if let r = try? safari.js(t.pos, code, expect(t, url: false)) {
            tabs[id]?.url = r.url
            return r
        }
        try? sync()
        return nil
    }

    /// Runs `body(handle)` inside the page with the agent present and the handle verified.
    /// `body` is JS statements that return a JSON envelope string.
    private func agent(_ id: Int, _ body: (String) -> String) throws -> [String: Any] {
        // Without the extension, a frame (aeFrame) is reached from the top document: the code
        // runs through the frame window's own Function, so it sees that frame's globals.
        func run(_ expr: String) throws -> String {
            guard aeFrame != 0 else { return try exec(id, expr) }
            let r = try exec(id, frameJS(aeFrame, "return " + expr))
            if r == Tools.noFrame { throw ToolError("This frame cannot be reached without the Safari CLI Bridge extension (cross-origin, or the page blocks scripts).") }
            return r
        }
        for _ in 0..<4 {
            let h = tabs[id]?.handle
            let r = try run("(function(){if(!window.__smcp)return '\(PageAgent.absent)';\(body(h ?? ""))})()")
            if r == PageAgent.absent {
                let nh = h ?? nextID("h")
                // With the extension, the main-world part is already in the page as main.js.
                let src = safari.isExtension ? PageAgent.source : PageAgent.mainSource + ";" + PageAgent.source
                let installed = aeFrame == 0
                    ? try exec(id, src + ";__smcp.h=\(jsonString(nh));'ok'")
                    : try exec(id, frameJS(aeFrame, src + ";__smcp.h=\(jsonString(nh));return 'ok'"))
                guard installed == "ok" else {
                    throw ToolError("Could not run script in this tab (still loading, showing a dialog, or not a web page).")
                }
                tabs[id]?.handle = nh
                continue
            }
            guard !r.isEmpty else { throw ScriptEmpty() }
            guard let env = (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any] else {
                throw ToolError("Unexpected reply from page: \(clip(r, 120))")
            }
            if let m = env["m"] as? String {
                if tabs.values.contains(where: { $0.handle == m && $0.id != id }) {
                    // This position holds another tab we know: tabs were reordered. Drop what
                    // we believed about this window and let sync find tabs by their handles.
                    guard let wid = tabs[id]?.pos.wid else { throw gone(id) }
                    for t in tabs.values where t.pos.wid == wid {
                        if t.handle == nil { tabs[t.id] = nil } else { tabs[t.id]?.url = "?" }
                    }
                    try sync()
                    guard tabs[id] != nil else { throw gone(id) }
                } else {
                    // Agent left by an earlier session: adopt it.
                    let nh = h ?? nextID("h")
                    _ = try run("(__smcp.h=\(jsonString(nh)),'ok')")
                    tabs[id]?.handle = nh
                }
                continue
            }
            if let d = env["d"] as? [String] { dialogs += d }
            if let e = env["e"] as? String { throw ToolError(e) }
            return env
        }
        throw ToolError("Tab t\(id) keeps changing; run `safari tabs`.")
    }

    private func agentCall(_ id: Int, _ op: [String: Any]) throws -> [String: Any] {
        do {
            return try agent(id) { h in
                var o = op
                o["h"] = h
                return "return __smcp.call(\(jsonString(o)))"
            }
        } catch is ScriptEmpty {
            throw ToolError("The page did not respond (still loading, showing a dialog, or not a web page).")
        }
    }

    private func pick(_ a: [String: Any], _ keys: [String]) -> [String: Any] {
        var o: [String: Any] = [:]
        for k in keys { if let v = a[k] { o[k] = v } }
        return o
    }

    private func page(_ op: String, _ a: [String: Any], _ keys: [String]) throws -> String {
        let id = try resolve(a)
        var o = pick(a, keys)
        o["op"] = op
        let frame = try frameOf(&o, id)
        var v = try inFrame(frame) { try agentCall(id, o)["v"] as? String ?? "" }
        if op == "read", frame == 0, a["ref"] == nil, a["selector"] == nil { v += frameBlocks(id, o) }
        return v
    }

    // MARK: frames (extension only)

    /// Refs like f12e5 point into child frame 12. Strips the frame from `ref` (or from the
    /// keys of `fields`) so the frame's own agent understands it, and returns the frame.
    /// Safari's frame ids are long; the model sees f1, f2… per tab instead.
    private var frameIDs: [Int: [Int]] = [:]
    /// Per tab, the frame the last targeted act went to: focus is there, so keys without a target follow it.
    private var focusFrame: [Int: Int] = [:]

    private func frameOf(_ o: inout [String: Any], _ tab: Int) throws -> Int {
        func split(_ r: String) -> (Int, String)? {
            guard let m = r.wholeMatch(of: #/f(\d+)(e\d+)/#), let f = Int(m.1) else { return nil }
            return (f, String(m.2))
        }
        var frame = 0
        if let r = o["ref"] as? String, let (f, rr) = split(r) { frame = f; o["ref"] = rr }
        if let r = o["to"] as? String, let (f, rr) = split(r) {
            guard f == frame else { throw ToolError("drag works within one frame") }
            o["to"] = rr
        }
        if let fields = o["fields"] as? [String: Any] {
            var out: [String: Any] = [:]
            var seen = Set<Int>()
            for (k, v) in fields {
                if let (f, rr) = split(k) { seen.insert(f); out[rr] = v } else { seen.insert(0); out[k] = v }
            }
            guard seen.count <= 1 else { throw ToolError("fields must all be in the same frame") }
            frame = seen.first ?? 0
            o["fields"] = out
        }
        if frame == 0 { return 0 }
        guard let list = frameIDs[tab], frame >= 1, frame <= list.count else { throw ToolError("frame f\(frame) is unknown; read again") }
        return list[frame - 1]
    }

    private func inFrame<T>(_ f: Int, _ body: () throws -> T) rethrows -> T {
        guard f != 0 else { return try body() }
        // A negative id is a frame reached from the top document (srcdoc frames with the extension).
        if safari.isExtension && f > 0 {
            ext.frame = f
            defer { ext.frame = 0 }
            return try body()
        }
        aeFrame = abs(f)
        defer { aeFrame = 0 }
        return try body()
    }

    /// Apple Events only: the frame calls go to, as its 1-based index among the top
    /// document's iframes. Only same-origin frames whose CSP allows Function can be reached.
    private var aeFrame = 0
    static let noFrame = "__smcp_noframe__"

    /// JS for the top document that runs `body` (a function body) inside frame `i`.
    private func frameJS(_ i: Int, _ body: String) -> String {
        "(function(){var F=document.querySelectorAll('iframe,frame')[\(i - 1)],W=null;try{W=F&&F.contentWindow;if(W&&!W.document)W=null}catch(e){W=null}"
            + "if(!W)return '\(Tools.noFrame)';try{return String(W.Function(\(jsonString(body)))())}catch(e){return '\(Tools.noFrame)'}})()"
    }

    /// Apple Events only: the top document's visible iframes, with whether we can script them.
    private func aeFrames(_ id: Int) -> [(id: Int, url: String, ok: Bool)] {
        let js = "JSON.stringify([].map.call(document.querySelectorAll('iframe,frame'),function(f,i){var r=f.getBoundingClientRect(),u='',ok=0;"
            + "try{u=f.contentWindow.location.href;f.contentWindow.Function('');ok=1}catch(e){u=u||f.src||''}return[i+1,u,ok,r.width>20&&r.height>20?1:0]}))"
        guard let r = try? exec(id, js), let list = (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [[Any]] else { return [] }
        return list.compactMap { x in
            guard x.count == 4, let i = x[0] as? Int, let u = x[1] as? String, (x[3] as? Int) == 1 else { return nil }
            return (i, u, (x[2] as? Int) == 1)
        }
    }

    /// The same read in each child frame, as `--- frame f12 <url>` blocks with frame refs.
    private func frameBlocks(_ id: Int, _ o: [String: Any]) -> String {
        guard let t = tabs[id] else { return "" }
        var frames: [(id: Int, url: String)]
        var unread = 0
        if safari.isExtension {
            guard let list = try? ext.frames(t.pos, expect(t)) else { return "" }
            frames = list.filter { $0.url.hasPrefix("http") || $0.url.hasPrefix("file") }
            if list.count > frames.count {
                // Safari does not let the extension script srcdoc/about:blank frames (rich-text editors
                // such as TinyMCE); reach them from the top document, as without the extension.
                frames += aeFrames(id).filter { $0.ok && $0.url.hasPrefix("about:") }.map { (-$0.id, $0.url) }
            }
        } else {
            let all = aeFrames(id)
            frames = all.filter(\.ok).map { ($0.id, $0.url) }
            unread = all.count - frames.count
        }
        var fo = o
        let fm = o["max_chars"] as? Int ?? 6000
        fo["max_chars"] = fm == 0 ? 0 : min(fm / 2, 3000)
        var out = ""
        for f in frames.prefix(8) {
            guard let body = try? inFrame(f.id, { try agentCall(id, fo)["v"] as? String }) else {
                if !f.url.hasPrefix("about:") { unread += 1 }
                continue
            }
            var list = frameIDs[id] ?? []
            if !list.contains(f.id) { list.append(f.id); frameIDs[id] = list }
            let alias = list.firstIndex(of: f.id)! + 1
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
            guard let first = lines.first, !first.isEmpty,
                  !["(nothing", "no match", "no link", "(no links", "no changes", "no text"].contains(where: { first.hasPrefix($0) }) else { continue }
            let pre = "f\(alias)"
            let fixed = lines.map { l -> String in
                if l.hasPrefix("- e") && l.split(separator: " ").dropFirst().allSatisfy({ $0.wholeMatch(of: #/e\d+/#) != nil }) {
                    return "-" + l.split(separator: " ").dropFirst().map { " " + pre + $0 }.joined()
                }
                return String(l).replacing(#/^([+~] )?(e\d+ )/#) { m in (m.1.map(String.init) ?? "") + pre + m.2 }
            }
            out += "\n--- frame \(pre) \(clip(f.url, 120))\n" + fixed.joined(separator: "\n")
        }
        if unread > 0 { out += "\n(\(unread) iframe\(unread > 1 ? "s" : "") not read: \(safari.isExtension ? "the extension could not reach them" : "cross-origin or the page blocks scripts; needs the Safari CLI Bridge extension"))" }
        return out
    }

    // MARK: loading

    private struct PageState {
        /// document.readyState, or "old" for a document marked before navigating away,
        /// or "leaving" once it has started to unload.
        let ready: String
        let url: String
        /// HTTP status of the document, 0 when unknown.
        let status: Int
        /// False when nothing on the page has changed since the last act call.
        let changed: Bool
        let title: String
        /// Safari's URL for the tab, which already shows a navigation that has not committed.
        let tabURL: String

        private func bare(_ u: String) -> String {
            var b = u.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? u
            if b.hasSuffix("/") { b.removeLast() }
            return b
        }

        /// Safari is heading somewhere else but still shows this document.
        var pending: Bool { !tabURL.isEmpty && bare(tabURL) != bare(url) && !url.hasPrefix("safari-resource:") }
    }

    /// Value of the marker put on the document we are navigating away from. Unique per
    /// navigation, so a marked document restored by back/forward does not count as old.
    private var mark = 0
    private var stateJS: String {
        "(window.__smcpOld===\(mark)?'old':window.__smcp&&__smcp.bye&&Date.now()-__smcp.bye<10000?'leaving':document.readyState)+'\\n'+location.href+'\\n'+((performance.getEntriesByType('navigation')[0]||{}).responseStatus||0)+'\\n'+(window.__smcp&&__smcp.fx===0?0:1)+'\\n'+document.title"
    }

    private func peek(_ id: Int) -> PageState? {
        guard let r = poll(id, stateJS) else { return nil }
        let f = r.result.split(separator: "\n", maxSplits: 4, omittingEmptySubsequences: false)
        guard f.count == 5 else { return nil }
        return PageState(ready: String(f[0]), url: String(f[1]), status: Int(f[2]) ?? 0, changed: f[3] != "0", title: String(f[4]), tabURL: r.url)
    }

    /// Waits for a navigation to finish. With `marked`, the old document carries a marker,
    /// so any unmarked document is the new one; otherwise a change away from `from` is.
    /// `stuck` means nothing happened: the marked document stayed and Safari was not
    /// heading anywhere.
    private func waitLoad(_ id: Int, marked: Bool, from: String?, timeout: Double, grace: Double = 1.2) -> (text: String, stuck: Bool) {
        let start = Date()
        var moved = false
        var stuck = false
        var inPage = false
        var last: PageState?
        // A loaded page is accepted only once it is still there, at the same address, a moment
        // later: some pages redirect again by script right after loading.
        var settled: String?
        while true {
            let t = Date().timeIntervalSince(start)
            guard tabs[id] != nil else { return ("lost track of the tab while it was loading; run `safari tabs`", false) }
            if let s = peek(id) {
                last = s
                if s.ready == "old" {
                    // Same document, new address: an in-page navigation (fragment, pushState).
                    if let from, s.url != from { inPage = true; break }
                    if t > grace && !s.pending { stuck = true; break }
                } else if s.ready != "leaving" {
                    if marked || s.url != from { moved = true }
                    // Accept "interactive" after a few seconds: some pages never finish loading.
                    if (s.ready == "complete" && (moved || t > grace)) || (s.ready == "interactive" && moved && t > 4) {
                        if settled == s.url || t > timeout { break }
                        settled = s.url
                        usleep(250_000)
                        continue
                    }
                    settled = nil
                }
            } else {
                moved = true
            }
            if t > timeout { break }
            usleep(t < 1 ? 60_000 : 150_000)
        }
        defer { mark += 1 }
        guard let last else { return ("(page did not respond)", false) }
        if last.ready == "old" { _ = poll(id, "delete window.__smcpOld;''") }
        tabs[id]?.title = last.title
        var note = ""
        if stuck { note = " (no navigation happened)" }
        else if last.ready == "old" && !inPage { note = " (the new page has not arrived yet)" }
        else if last.ready != "complete" && last.ready != "old" { note = " (still loading)" }
        let status = last.status != 0 ? last.status : tabs[id].map { safari.status($0.pos) } ?? 0
        if status >= 400 { note += " (HTTP \(status))" }
        return ((last.title.isEmpty ? "" : clip(last.title, 80) + " | ") + clip(last.url, 200) + note, stuck)
    }

    // MARK: tools

    /// A tab put to sleep by the Tab Sleeper extension is a data: page with the original
    /// address in its fragment (`#tabsleeper&u=…&t=…`).
    private func sleeping(_ url: String) -> (title: String, url: String)? {
        guard url.hasPrefix("data:"), let r = url.range(of: "#tabsleeper&") else { return nil }
        let q = URLComponents(string: "?" + url[r.upperBound...])?.queryItems ?? []
        guard let u = q.first(where: { $0.name == "u" })?.value, !u.isEmpty else { return nil }
        return (q.first(where: { $0.name == "t" })?.value ?? "", u)
    }

    /// Safari hides data: and other extensions' pages from our extension (blank URL and title),
    /// which is how sleeping tabs look. Ask Apple Events for those, matching windows by tab
    /// count and the URLs both sides can see. Only used for the `tabs` listing.
    private func hiddenURLs() -> [Int: String] {
        guard usingExt == true else { return [:] }
        let blank = order.filter { tabs[$0].map { $0.url.isEmpty && $0.title.isEmpty } ?? false }
        if blank.isEmpty { return [:] }
        guard let list = try? apple.listTabs() else { return [:] }
        let aeWins = Dictionary(grouping: list, by: \.ref.wid).mapValues { $0.sorted { $0.ref.idx < $1.ref.idx } }
        var out: [Int: String] = [:]
        for (wid, ids) in Dictionary(grouping: order, by: { tabs[$0]?.pos.wid ?? -1 }) where ids.contains(where: blank.contains) {
            let mine = ids.compactMap { tabs[$0] }.sorted { $0.pos.idx < $1.pos.idx }
            let hits = aeWins.values.filter { ae in
                ae.count == mine.count && zip(mine, ae).allSatisfy { $0.url.isEmpty || $0.url == $1.url }
            }
            guard hits.count == 1, wid >= 0 else { continue }
            for (t, a) in zip(mine, hits[0]) where t.url.isEmpty { out[t.id] = a.url }
        }
        return out
    }

    private func tabsTool(_ a: [String: Any]) throws -> String {
        switch a["action"] as? String ?? "list" {
        case "list":
            try sync()
            if order.isEmpty { return "(no tabs)" }
            var lines: [String] = []
            var lastWid: Int?
            let hidden = hiddenURLs()
            for id in order {
                guard let t = tabs[id] else { continue }
                if let lastWid, lastWid != t.pos.wid { lines.append("-- another window --") }
                lastWid = t.pos.wid
                let s = sleeping(hidden[id] ?? t.url)
                lines.append("t\(id)\(t.visible ? "*" : "")\(opened.contains(id) ? " (agent)" : "")\(t.priv ? " (private)" : "")\(s != nil ? " (sleeping)" : "") \(clip(s?.title ?? t.title, 60)) | \(clip(s?.url ?? t.url, 120))")
            }
            return lines.joined(separator: "\n")
        case "new":
            var url = a["url"] as? String ?? ""
            if !url.isEmpty && !url.contains(":") { url = "https://" + url }
            let priv = a["private"] as? Bool ?? false
            try sync()
            // Prefer the current tab's window, but never mix private and normal tabs in one window.
            let cands = ([current].compactMap { $0 } + order).compactMap { tabs[$0] }.filter { $0.priv == priv }
            let pos: (ref: TabRef, xid: Int?)
            if !priv, a["window"] as? Bool == true {
                pos = try safari.newTab(in: nil, url: url)
            } else if let wid = cands.first?.pos.wid {
                pos = try safari.newTab(in: wid, url: url)
            } else if priv {
                pos = try openPrivateWindow(url)
            } else {
                pos = try safari.newTab(in: nil, url: url)
            }
            try sync()
            guard let id = (tabs.values.first { pos.xid != nil && $0.xid == pos.xid } ?? tabs.values.first { $0.pos == pos.ref })?.id else { throw ToolError("Opened a tab but lost track of it; run `safari tabs`.") }
            if priv { tabs[id]?.priv = true }
            current = id
            defaultLost = false
            opened.insert(id)
            saveState()
            var loaded = ""
            if !url.isEmpty {
                let text = waitLoad(id, marked: false, from: "about:blank", timeout: 15, grace: 8).text
                // Unreachable host: Safari's error page, which no script can enter. Close the tab rather
                // than hand back an id for a page that is not there (scripts use `open --id-only`).
                let errorPage = peek(id)?.url.hasPrefix("safari-resource:") == true
                if text.hasPrefix("(page did not respond)") || errorPage {
                    if let t = tabs[id] { _ = try? safari.close(t.pos, expect(t, url: false)) }
                    opened.remove(id)
                    tabs[id] = nil
                    if current == id { current = nil }
                    saveState()
                    throw ToolError("Safari could not load \(clip(url, 120)) (unreachable host, or not a web page); closed the tab it opened.")
                }
                loaded = ": " + (try passCheck(id, text))
            }
            // Stamp the page now, so the tab keeps its id even if the daemon restarts next.
            if !url.isEmpty { _ = try? agentCall(id, ["op": "nop"]) }
            return "opened t\(id)" + loaded
        case "close":
            guard a["tab"] != nil else { throw ToolError("close needs a tab id: safari t3 close.") }
            let previous = current, wasLost = defaultLost
            let id = try resolve(a)
            try guardedOp(id) { try safari.close($0, $1) }
            tabs[id] = nil
            // Closing a tab must not change which tab is the default, except to lose it.
            current = previous == id ? nil : previous
            defaultLost = previous == id || (previous == nil && wasLost)
            try sync()
            return "closed t\(id)"
        case "select":
            let id = try resolve(a)
            try guardedOp(id) { try safari.select($0, $1) }
            shown.insert(id)
            return "selected t\(id)"
        case "closeagents":
            let closed = reap(olderThan: 0)
            let kept = opened.filter { tabs[$0] != nil }.sorted().map { "t\($0)" }
            return (closed.isEmpty ? "no agent tabs to close" : "closed " + closed.map { String($0.prefix { $0 != " " }) }.joined(separator: ", "))
                + (kept.isEmpty ? "" : "\n\u{1E}kept \(kept.joined(separator: ", ")) (on screen or shown; close them by id)")
        case "resize":
            return try resize(a)
        default:
            throw ToolError("action must be list, new, close or select.")
        }
    }

    /// Routes per tab, re-sent after a navigation to another site (sessionStorage is per site).
    private var routes: [Int: [[String: Any]]] = [:]

    private func describe(_ r: [String: Any]) -> String {
        let p = r["p"] as? String ?? ""
        if r["blk"] as? Bool == true { return "\(p) → blocked" }
        let b = r["b"] as? String ?? ""
        return "\(p) → \(r["s"] as? Int ?? 200)" + (r["t"].map { " \($0)" } ?? "") + " (\(b.utf8.count) B body)"
    }

    /// Mocked answers for the page's fetch/XHR requests (`safari route`), and with the
    /// extension a block rule for everything else the tab loads (images, scripts, styles).
    private func route(_ a: [String: Any]) throws -> String {
        let id = try resolve(a)
        func send(_ list: [[String: Any]]?) throws -> [[String: Any]] {
            var o: [String: Any] = ["op": "route"]
            if let list { o["list"] = list }
            let v = try agentCall(id, o)["v"] as? String ?? "[]"
            return (try? JSONSerialization.jsonObject(with: Data(v.utf8))) as? [[String: Any]] ?? []
        }
        var list = try send(nil)
        let action = a["action"] as? String ?? "list"
        var head: String
        switch action {
        case "add":
            let p = a["pattern"] as? String ?? ""
            var r: [String: Any] = ["p": p]
            if a["block"] as? Bool == true { r["blk"] = true } else {
                r["s"] = a["status"] as? Int ?? 200
                r["b"] = a["body"] as? String ?? ""
                if let t = a["ctype"] { r["t"] = t }
            }
            list.removeAll { $0["p"] as? String == p }
            list.append(r)
            list = try send(list)
            head = "routed " + describe(r)
        case "remove":
            if let p = a["pattern"] as? String {
                guard list.contains(where: { $0["p"] as? String == p }) else {
                    throw ToolError("no route \(p) on t\(id)" + (list.isEmpty ? "" : "; routes: " + list.compactMap { $0["p"] as? String }.joined(separator: ", ")))
                }
                list.removeAll { $0["p"] as? String == p }
                head = "removed route \(p)"
            } else {
                head = list.isEmpty ? "no routes" : "removed \(list.count) route\(list.count == 1 ? "" : "s")"
                list = []
            }
            list = try send(list)
        default:
            head = list.isEmpty ? "no routes on t\(id)" : list.map(describe).joined(separator: "\n")
        }
        routes[id] = list.isEmpty ? nil : list
        var notes: [String] = []
        if action != "list" {
            let blocked = list.filter { $0["blk"] as? Bool == true }.compactMap { $0["p"] as? String }
            if safari.isExtension, let t = tabs[id] {
                if !ext.block(t.pos, expect(t, url: false), blocked), !blocked.isEmpty {
                    notes.append("--block covers fetch/XHR only: this Safari or extension build cannot block other requests")
                }
            } else if !blocked.isEmpty {
                notes.append("--block covers fetch/XHR only without the Safari CLI Bridge extension")
            }
            if !safari.isExtension, !list.isEmpty { notes.append("without the extension, routes start once safari touches each new page; earlier requests go out") }
        }
        return head + notes.map { "\n\u{1E}" + $0 }.joined()
    }

    /// Cookies of the tab's site: through the extension (all, HttpOnly too), else `document.cookie`.
    /// `act`: list (or get with `name`), set, del, clear; dump and load serve `safari state`.
    private func cookies(_ a: [String: Any]) throws -> String {
        let id = try resolve(a)
        let act = a["act"] as? String ?? "list"
        var m: [String: Any] = ["act": act]
        for k in ["name", "value", "domain", "list"] { if let v = a[k] { m[k] = v } }
        var reply: [String: Any]?
        if safari.isExtension {
            var tries = 0
            while reply == nil {
                guard let t = tabs[id] else { throw gone(id) }
                let r = try ext.cookies(t.pos, expect(t), m)
                if r["no"] != nil { break }
                if r["stale"] == nil { reply = r; break }
                tries += 1
                if tries == 3 { throw ToolError("Tab t\(id) keeps changing; run `safari tabs`.") }
                try sync()
            }
        }
        let full = reply != nil
        if reply == nil {
            if m["domain"] != nil { throw ToolError("--domain needs the Safari CLI Bridge extension; without it only the page's own cookies are visible") }
            let v = try page("cookies", a.merging(m) { $1 }, ["act", "name", "value", "list"])
            reply = (try? JSONSerialization.jsonObject(with: Data(v.utf8))) as? [String: Any] ?? [:]
        }
        let host = URL(string: tabs[id]?.url ?? "")?.host ?? "this site"
        let partial = full ? "" : "\n\u{1E}HttpOnly cookies are not visible here (no Safari CLI Bridge extension, or a private window it cannot reach)"
        if act == "load" { return "set \(reply?["ok"] as? Int ?? 0) cookies" + partial }
        let list = reply?["ok"] as? [[String: Any]] ?? []
        if act == "dump" {
            let d = try JSONSerialization.data(withJSONObject: list, options: [.sortedKeys, .withoutEscapingSlashes])
            return String(decoding: d, as: UTF8.self) + partial
        }
        let name = a["name"] as? String
        func line(_ c: [String: Any]) -> String {
            var v = c["value"] as? String ?? ""
            if v.count > 120 { v = v.prefix(119) + "…" }
            var s = "\(c["name"] as? String ?? "") = \(v)"
            if let d = c["domain"] as? String { s += "  \(d)\(c["path"] as? String ?? "/")" }
            if c["httpOnly"] as? Bool == true { s += " httpOnly" }
            if c["secure"] as? Bool == true { s += " secure" }
            if let e = c["exp"] as? Double {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                s += " until " + f.string(from: Date(timeIntervalSince1970: e))
            } else if c["domain"] != nil { s += " session" }
            return s
        }
        switch act {
        case "set":
            guard let c = list.first else { throw ToolError("Safari did not set cookie \(name ?? "")") }
            return "set " + line(c)
        case "del", "clear":
            if list.isEmpty, let name { throw ToolError("no cookie \(name) on \(host)" + partial.replacingOccurrences(of: "\n\u{1E}", with: "; ")) }
            return (act == "del" ? "deleted \(name ?? "")" : "cleared \(list.count) cookie\(list.count == 1 ? "" : "s") of \(host)") + partial
        default:
            if let name {
                guard let c = list.first else { throw ToolError("no cookie \(name) on \(host)" + partial.replacingOccurrences(of: "\n\u{1E}", with: "; ")) }
                let v = c["value"] as? String ?? ""
                let max = a["max_chars"] as? Int ?? 6000
                return max > 0 && v.count > max ? String(v.prefix(max)) + "\n\u{1E}… \(v.count - max) more chars (--max 0 for all)" : v
            }
            if list.isEmpty { return "(no cookies on \(host))" + partial }
            return list.map(line).joined(separator: "\n") + "\n\u{1E}\(list.count) cookie\(list.count == 1 ? "" : "s") on \(a["domain"] as? String ?? host)" + partial
        }
    }

    /// After a load in tab `id`: routes live in the site's sessionStorage, so a new site needs them again.
    private func reapplyRoutes(_ id: Int) {
        guard let list = routes[id], !list.isEmpty else { return }
        _ = try? agentCall(id, ["op": "route", "list": list])
    }

    /// Sets the viewport of the tab's window to W x H. Only in a window that holds nothing but
    /// tabs opened with `open`, so the user's own windows never change size.
    private func resize(_ a: [String: Any]) throws -> String {
        guard let w = a["width"] as? Int, let h = a["height"] as? Int else { throw ToolError("width and height required") }
        let id = try resolve(a)
        try sync()
        guard let t = tabs[id] else { throw gone(id) }
        let others = tabs.values.filter { $0.pos.wid == t.pos.wid && !opened.contains($0.id) }
        if !others.isEmpty {
            throw ToolError("t\(id) shares a window with tabs that are not yours; open one with `safari open URL --window` and resize that.")
        }
        func size() throws -> [Int] {
            let v = try exec(id, "[outerWidth,outerHeight,innerWidth,innerHeight].join(',')").split(separator: ",").compactMap { Int($0) }
            guard v.count == 4 else { throw ToolError("Could not read the window size (page not responding).") }
            return v
        }
        // The window frame includes the toolbar: aim the outer size at viewport + chrome, twice
        // because the chrome can change with the width (a toolbar that wraps).
        // Safari re-lays out its toolbar a moment after a resize, so measure until it settles.
        func settled() throws -> [Int] {
            var v = try size()
            for _ in 0..<6 {
                usleep(150_000)
                let n = try size()
                if n == v { break }
                v = n
            }
            return v
        }
        var v = try size()
        for _ in 0..<3 {
            if v[2] == w && v[3] == h { break }
            guard try safari.resize(t.pos.wid, width: w + v[0] - v[2], height: h + v[1] - v[3]) else {
                throw ToolError("The Safari CLI Bridge extension is out of date and cannot resize; rebuild it with Extension/build.sh.")
            }
            usleep(200_000)
            v = try settled()
        }
        let note = v[2] == w && v[3] == h ? "" : " (asked \(w)x\(h); the screen or Safari's minimum size limits it)"
        return "t\(id) viewport \(v[2])x\(v[3])" + note
    }

    /// A new private window: through the extension if Safari lets it, else File > New Private
    /// Window via Accessibility, then the window that was not there before.
    private func openPrivateWindow(_ url: String) throws -> (ref: TabRef, xid: Int?) {
        if let r = safari.newPrivateWindow(url: url) { return r }
        let before = Set(try safari.listTabs().map(\.ref.wid))
        guard Capture.newPrivateWindow() else {
            throw ToolError("Opening a private window needs Accessibility permission for the app running safari (your terminal) (System Settings > Privacy & Security > Accessibility).")
        }
        for _ in 0..<30 {
            usleep(100_000)
            if let t = try safari.listTabs().first(where: { !before.contains($0.ref.wid) }) {
                if !url.isEmpty { _ = try safari.setURL(t.ref, url, Expect(count: -1, url: nil)) }
                return (t.ref, t.xid)
            }
        }
        throw ToolError(safari.isExtension
            ? "Safari opened a private window, but the extension cannot see it: in Safari > Settings > Extensions, turn on Allow in Private Browsing for Safari CLI Bridge."
            : "Safari did not open a private window.")
    }

    private func navigate(_ a: [String: Any]) throws -> String {
        guard var url = a["url"] as? String, !url.isEmpty else { throw ToolError("url required") }
        let id = try resolve(a)
        // Mark the current document so the wait below cannot mistake it for the new one.
        mark += 1
        let from: String
        do {
            from = try exec(id, "window.__smcpOld=\(mark);location.href")
        } catch let e as ToolError {
            // A blank tab (about:blank, a new tab) is out of the extension's reach; just load.
            let cur = tabs[id]?.url ?? ""
            guard cur.isEmpty || cur.hasPrefix("about:") || cur.hasPrefix("favorites:"), !["back", "forward", "reload"].contains(url) else { throw e }
            from = cur
        }
        switch url {
        case "back", "forward":
            // A history of one entry has nowhere to go; say so at once instead of waiting.
            if try exec(id, "history.length<=1?(delete window.__smcpOld,'no'):(history.\(url)(),'')") == "no" {
                return "no \(url) history; still on " + (tabs[id]?.url ?? "")
            }
        case "reload": _ = try exec(id, "location.reload();''")
        default:
            if !url.contains(":") { url = "https://" + url }
            try guardedOp(id) { try safari.setURL($0, url, $1) }
        }
        usleep(100_000)
        let (text, _) = waitLoad(id, marked: true, from: url == "reload" ? nil : from, timeout: 15, grace: 1.5)
        if let r = routes[id], !r.isEmpty, let to = tabs[id]?.url, !sameHost(to, from) { reapplyRoutes(id) }
        if !["back", "forward", "reload"].contains(url), let s = peek(id), s.url.hasPrefix("safari-resource:") {
            throw ToolError("Safari could not open \(clip(url, 120)) (\(clip(s.title, 60))); the tab now shows Safari's error page.")
        }
        // Nothing answered: usually Safari's error page (unreachable host), which no script can enter.
        if text.hasPrefix("(page did not respond)") {
            try? sync()
            let t = tabs[id]
            throw ToolError("Safari could not load \(clip(url, 120)): the page did not respond" + (t.map { "; the tab shows \(jsonString(clip($0.title, 60))) | \(clip($0.url, 120))" } ?? ""))
        }
        return try passCheck(id, text)
    }

    // MARK: bot checks and pacing

    /// Per-site pacing for navigations; the client sleeps on the slots it hands out.
    let rate = Rate()

    /// The kind of bot check the page shows ("cloudflare", "captcha"…), "" for none, "~" while loading.
    /// A captcha on a normal page (a login form) does not count: it needs a check-like title,
    /// an HTTP error, or a page with almost nothing else on it.
    private let botJS = #"(function(){if(document.readyState!=='complete')return'~';var d=document,t=(d.title||'').trim(),st=(performance.getEntriesByType('navigation')[0]||{}).responseStatus||0,"#
        + #"n=d.querySelectorAll('a[href],button,input:not([type=hidden]),select,textarea').length,k='',"#
        + #"tm=/^(just a moment|bir dakika|attention required|checking your browser|access denied|please wait|one more step|are you a (robot|human)|security check|güvenlik doğrulamas)/i.test(t);"#
        + #"if(d.querySelector('#challenge-form,#challenge-running,#cf-challenge-running,#cf-please-wait,script[src*="/cdn-cgi/challenge-platform"]'))k='cloudflare';"#
        + #"else if(d.querySelector('#px-captcha'))k='perimeterx';"#
        + #"else if(d.querySelector('iframe[src*="hcaptcha.com"],iframe[src*="recaptcha"],iframe[src*="challenges.cloudflare.com"],.g-recaptcha,.h-captcha,.cf-turnstile'))k='captcha';"#
        + #"else if(tm)k='bot check';return k&&(tm||st>=400||n<6)?k:''})()"#

    private func host(_ id: Int) -> String { URL(string: tabs[id]?.url ?? "")?.host ?? "" }

    /// After a load: a bot-check page that passes by itself is waited out (the result then
    /// describes the real page); one that does not is an error naming the tab, so `&&` chains stop.
    /// Either way the site is paced more slowly for the rest of the session.
    private func passCheck(_ id: Int, _ text: String) throws -> String {
        var text = text
        let h = host(id)
        if text.contains("(HTTP 429)") || text.contains("(HTTP 503)") { text += rate.backoff(host: h) }
        guard let k = poll(id, botJS)?.result, !k.isEmpty, k != "~" else { return text }
        let what = ["cloudflare": "Cloudflare check", "perimeterx": "PerimeterX check"][k] ?? k
        let limit: Double = k == "cloudflare" || k == "bot check" ? 20 : 10
        let start = Date()
        var clear = 0
        while Date().timeIntervalSince(start) < limit {
            usleep(400_000)
            guard tabs[id] != nil else { throw gone(id) }
            let r = poll(id, botJS)?.result
            clear = r == "" ? clear + 1 : 0
            if clear >= 2, let s = peek(id) {
                tabs[id]?.title = s.title
                tabs[id]?.url = s.url
                let st = s.status >= 400 ? " (HTTP \(s.status))" : ""
                // Backoff counts from now, after the wait.
                return (s.title.isEmpty ? "" : clip(s.title, 80) + " | ") + clip(s.url, 200) + st + " (passed a \(what))" + rate.backoff(host: h)
            }
        }
        throw ToolError("t\(id): \(what) on \(h) did not clear in \(Int(limit)) s\(rate.backoff(host: h)). Show it to the user (safari t\(id) show), ask them to solve it, then: safari t\(id) wait --load")
    }

    /// Answers the client before a navigation: how long to wait for this site's next slot.
    func reserve(_ a: [String: Any]) -> [String: Any] {
        var u = a["url"] as? String ?? ""
        if ["", "back", "forward", "reload"].contains(u) {
            guard a["tab"] != nil || current != nil, let id = try? resolve(a) else { return ["wait": 0] }
            u = tabs[id]?.url ?? ""
        } else if !u.contains(":") { u = "https://" + u }
        guard let h = URL(string: u)?.host else { return ["wait": 0] }
        func rule(_ k: String) -> Rate.Rule? { (a[k] as? [Double]).flatMap { $0.count == 2 ? Rate.Rule(lo: $0[0], hi: $0[1]) : nil } }
        guard let r = rate.reserve(host: h, override: rule("delay"), fallback: rule("fallback")) else { return ["wait": 0] }
        return ["wait": r.wait, "site": r.key]
    }

    /// Reports a navigation the action caused, so the model need not look.
    private func settle(_ id: Int, _ result: String, href: String, tabURL: String, wasReady: Bool, twice: Bool) -> String {
        var changed = true
        for wait: useconds_t in twice ? [120_000, 250_000] : [120_000] {
            usleep(wait)
            guard let s = peek(id) else { return result + " → " + waitLoad(id, marked: false, from: href, timeout: 10).text }
            if s.url != href || s.ready == "leaving" || (wasReady && s.ready != "complete") {
                return result + " → " + waitLoad(id, marked: false, from: href, timeout: 10).text
            }
            if s.tabURL != tabURL {
                // Safari has the new address but still shows the old document: mark it and wait.
                mark += 1
                _ = poll(id, "if(location.href===\(jsonString(href)))window.__smcpOld=\(mark);''")
                let (text, stuck) = waitLoad(id, marked: true, from: href, timeout: 10, grace: 1.5)
                return stuck ? result : result + " → " + text
            }
            changed = s.changed
        }
        // Synthetic events are ignored by some pages; tell the model when nothing reacted.
        return twice && !changed ? result + " (no change on the page yet)" : result
    }

    private func act(_ a: [String: Any]) throws -> String {
        guard let action = a["action"] as? String else { throw ToolError("action required") }
        let id = try resolve(a)
        if action == "wait" { return try waitFor(id, a) }
        if action == "dialog", let r = try nativeDialog(id, a["text"] as? String ?? "accept") { return r }
        var result: String
        var env: [String: Any]
        var frame = 0
        if action == "upload" || action == "drop" {
            var o = pick(a, ["ref", "selector", "x", "y"])
            o["op"] = "act"
            o["action"] = action
            if let t = a["text"] as? String, !t.isEmpty { o["files"] = try files(t) }
            if let t = a["dtext"] as? String { o["text"] = t }
            env = try agentCall(id, o)
            result = env["v"] as? String ?? "ok"
        } else if a["os"] as? Bool == true {
            (result, env) = try osAct(id, action, a)
        } else {
            var o = pick(a, ["action", "ref", "x", "y", "text", "key", "dy", "fields", "selector", "to", "to_sel"])
            o["op"] = "act"
            frame = try frameOf(&o, id)
            let targeted = o["ref"] != nil || o["selector"] != nil || o["x"] != nil || o["fields"] != nil
            if targeted { focusFrame[id] = frame }
            if !targeted, action == "key" || action == "type", let f = focusFrame[id], f != 0,
               let e = try? inFrame(f, { try agentCall(id, o) }) {
                frame = f
                env = e
            } else {
                env = try inFrame(frame) { try agentCall(id, o) }
            }
            result = env["v"] as? String ?? "ok"
            if frame != 0, let alias = frameIDs[id]?.firstIndex(of: frame).map({ "f\($0 + 1)" }) {
                // Report frame refs as the model knows them, and judge page changes by the top document.
                result = result.replacing(#/\be(\d+)\b/#) { alias + "e" + $0.1 }
                env["u"] = tabs[id]?.url ?? ""
                env["u0"] = env["u"]
                env["r"] = "complete"
            }
        }
        if ["scroll", "dialog"].contains(action) { return result }
        let twice = ["click", "dblclick", "rclick", "drag", "key", "hover"].contains(action)
        // The address from before the action, so a pushState route change shows up as one.
        var out = settle(id, result, href: env["u0"] as? String ?? env["u"] as? String ?? "", tabURL: verifiedURL,
                         wasReady: env["r"] as? String == "complete", twice: twice)
        guard !out.contains(" → "), a["os"] as? Bool != true else { return out }
        // Pages often react a moment later (a timer, an animation): give them up to 1.2 s more.
        let noChange = " (no change on the page yet)"
        if frame == 0, out.hasSuffix(noChange) {
            let t0 = Date()
            while Date().timeIntervalSince(t0) < 1.2 {
                usleep(150_000)
                if peek(id)?.changed == true { out = String(out.dropLast(noChange.count)); break }
            }
        }
        // The page may still be waiting for its own requests (adding to a cart, an address lookup):
        // let them finish, so what they change is part of this result.
        let start = Date()
        var waited = false
        while Date().timeIntervalSince(start) < 2,
              let n = try? inFrame(frame, { try agentCall(id, ["op": "pend"])["v"] as? Int }), n > 0 {
            usleep(150_000)
            waited = true
        }
        if waited { usleep(150_000) }
        // Same page, changed in place: the new lines (a form result, a message), other fields that
        // changed (an address lookup, a reset) and failed requests, so the model need not read again.
        var extra = ""
        var changed = false
        if let d = try? inFrame(frame, { try agentCall(id, ["op": "delta"])["v"] as? [String: Any] }) {
            if twice, let t = d["t"] as? String, !t.isEmpty { extra += " · new text: " + t; changed = true }
            if var c = d["c"] as? String, !c.isEmpty {
                if frame != 0, let alias = frameIDs[id]?.firstIndex(of: frame).map({ "f\($0 + 1)" }) {
                    c = c.replacing(#/\be(\d+)\b/#) { alias + "e" + $0.1 }
                }
                extra += " · also changed: " + c
                changed = true
            }
            if let f = d["f"] as? String, !f.isEmpty { extra += " · failed: " + f }
        }
        // A dialog in a frame reaches the top document by postMessage, after the frame call returned.
        if frame != 0 { _ = try? agentCall(id, ["op": "nop"]) }
        // settle judges the top document right after the action; later or in-frame changes count too.
        if changed && out.hasSuffix(" (no change on the page yet)") {
            return String(out.dropLast(" (no change on the page yet)".count)) + extra
        }
        return out + extra
    }

    /// Answers a dialog Safari shows natively, via Accessibility. Only tried when the tab's last
    /// call timed out or the visible tab shows one; otherwise act dialog sets the agent's answer.
    private func nativeDialog(_ id: Int, _ answer: String) throws -> String? {
        guard Input.trusted(prompt: false), let t = tabs[id] else {
            if blocked.contains(id) { throw ToolError("Answering this dialog needs Accessibility permission for the app running safari (your terminal) (System Settings > Privacy & Security > Accessibility), or answer it in Safari.") }
            return nil
        }
        if t.visible {
            if let msg = Capture.dialog(wid: cg(t.pos.wid), answer: answer) {
                blocked.remove(id)
                return "answered dialog \(jsonString(clip(msg, 120))) (\(answer))"
            }
            return nil
        }
        guard blocked.contains(id) else { return nil }
        // Safari only shows a background tab's dialog once the tab is selected.
        let back = tabs.values.first { $0.pos.wid == t.pos.wid && $0.visible }
        try guardedOp(id) { try safari.select($0, $1) }
        usleep(400_000)
        let msg = Capture.dialog(wid: cg(t.pos.wid), answer: answer)
        if let back { try? guardedOp(back.id) { try safari.select($0, $1) } }
        try? sync()
        blocked.remove(id)
        guard let msg else { return "no dialog found in t\(id)" }
        return "answered dialog \(jsonString(clip(msg, 120))) (\(answer))" + (back.map { "; t\($0.id) is visible again" } ?? "")
    }

    /// Polls the page until the text, ref or selector appears (or with gone, disappears).
    /// Keeps going across navigations, so it also works for "wait for the next page".
    private func waitFor(_ id: Int, _ a: [String: Any]) throws -> String {
        if a["load"] as? Bool == true {
            // The page has finished loading and is not a bot check (after the user solved one).
            let limit = min(max(a["timeout"] as? Double ?? 15, 0.5), 30)
            let (text, _) = waitLoad(id, marked: false, from: nil, timeout: limit, grace: 0)
            return try passCheck(id, text)
        }
        var o = pick(a, ["ref", "selector", "text"])
        guard !o.isEmpty else { throw ToolError("wait needs text, ref or selector") }
        o["op"] = "has"
        let frame = try frameOf(&o, id)
        let gone = a["gone"] as? Bool == true
        var limit = a["timeout"] as? Double ?? 10
        if limit > 100 { limit /= 1000 }  // given in milliseconds
        limit = min(max(limit, 0.5), 30)
        let what = (a["text"] as? String).map { "text " + jsonString($0) } ?? (a["ref"] as? String ?? (a["selector"] as? String).map { "selector " + $0 } ?? "")
        let start = Date()
        var first = true
        while true {
            if let env = try? inFrame(frame, { try agentCall(id, o) }), let v = env["v"] as? Bool, v != gone {
                if first && !gone { return "\(what) already present (it may be from before; wait for something new)" }
                return "\(what) \(gone ? "gone" : "present") after \(String(format: "%.1f", Date().timeIntervalSince(start)))s"
            }
            first = false
            if Date().timeIntervalSince(start) > limit {
                throw ToolError("timed out after \(String(format: "%g", limit))s waiting for \(what) to \(gone ? "disappear" : "appear")")
            }
            usleep(150_000)
        }
    }

    /// Files for an upload, base64-encoded for the page agent.
    private func files(_ list: String) throws -> [[String: String]] {
        let paths = list.split(separator: ",").map { NSString(string: $0.trimmingCharacters(in: .whitespaces)).expandingTildeInPath }
        guard !paths.isEmpty else { throw ToolError("upload needs the file path(s)") }
        var total = 0
        return try paths.map { p in
            guard let data = FileManager.default.contents(atPath: p) else { throw ToolError("cannot read \(p)") }
            total += data.count
            guard total <= 10_000_000 else { throw ToolError("upload is limited to 10 MB in total") }
            let ext = (p as NSString).pathExtension
            let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            return ["n": (p as NSString).lastPathComponent, "t": mime, "b": data.base64EncodedString()]
        }
    }

    private func osAct(_ id: Int, _ action: String, _ a: [String: Any]) throws -> (String, [String: Any]) {
        guard Input.trusted(prompt: true) else {
            throw ToolError("Real input needs Accessibility permission for the app running safari (your terminal) (System Settings > Privacy & Security > Accessibility). Grant it and retry, or drop --os.")
        }
        // Real input goes to whatever is on screen, so the tab is shown first. The user's
        // visible tab and front app are put back afterwards.
        try sync()
        guard let w = tabs[id]?.pos.wid else { throw gone(id) }
        let back = tabs.values.first { $0.pos.wid == w && $0.visible && $0.id != id }
        let front = NSWorkspace.shared.frontmostApplication
        try guardedOp(id) { try safari.raise($0, $1) }
        defer {
            if let back { try? guardedOp(back.id) { try safari.select($0, $1) } }
            if let front, front.bundleIdentifier != "com.apple.Safari" { front.activate() }
        }
        let wid = cg(w)
        var tries = 0
        while !Capture.onScreen(wid) && tries < 20 { usleep(100_000); tries += 1 }
        usleep(250_000)

        // Measure only now: a background tab can lay out differently from the shown one.
        var o = pick(a, ["ref", "x", "y", "selector"])
        o["op"] = "geom"
        let env = try agentCall(id, o)
        let verified = verifiedURL
        let g = env["v"] as? [String: Any] ?? [:]
        let iw = g["iw"] as? Double ?? 0, ih = g["ih"] as? Double ?? 0
        if let cover = g["cover"] as? String, ["click", "dblclick", "rclick", "type", "fill"].contains(action) {
            throw ToolError("\(g["d"] as? String ?? "target") is covered by \(cover) at its centre; not clicking. Close what covers it, or use --xy.")
        }
        let view = try Capture.viewport(wid: wid, iw: iw, ih: ih).rect
        let z = iw > 0 ? Double(view.width) / iw : 1
        var point: CGPoint?
        if let x = g["x"] as? Double, let y = g["y"] as? Double {
            point = CGPoint(x: Double(view.minX) + x * z, y: Double(view.minY) + y * z)
        }
        func needPoint() throws -> CGPoint {
            guard let point else { throw ToolError("pass a ref or --xy x,y") }
            return point
        }
        let text = a["text"] as? String ?? ""

        switch action {
        case "click": Input.click(try needPoint())
        case "rclick": Input.click(try needPoint(), right: true)
        case "dblclick": Input.click(try needPoint(), count: 2)
        case "hover": Input.move(try needPoint())
        case "type", "fill":
            // A click would drop the caret or selection already in the focused field.
            if let point, action == "fill" || g["fo"] == nil { Input.click(point); usleep(200_000) }
            if action == "fill" { try Input.key("cmd+a") }
            Input.type(text)
        case "key":
            guard let k = a["key"] as? String else { throw ToolError("key required") }
            if let point, g["fo"] == nil { Input.click(point); usleep(200_000) }
            try Input.key(k)
        case "scroll":
            let dy = (a["dy"] as? Double).map { Int($0) } ?? Int(ih * 0.8)
            Input.scroll(at: point ?? CGPoint(x: view.midX, y: view.midY), dy: dy)
        default:
            throw ToolError("\(action) has no os mode; drop --os.")
        }
        verifiedURL = verified
        usleep(150_000)  // let the event land before the user's tab comes back
        let what = (g["d"] as? String).map { " on " + $0 } ?? ""
        return ("real \(action)\(what)", env)
    }

    /// Whether the code has a `return` of its own, outside strings, comments and nested
    /// functions or blocks: `xs.map(x => { return x })` is still a bare expression.
    static func topLevelReturn(_ code: String) -> Bool {
        let c = Array(code.unicodeScalars)
        var i = 0, depth = 0
        func word(at j: Int) -> Bool {
            let w = Array("return".unicodeScalars)
            guard j + w.count <= c.count, Array(c[j..<j + w.count]) == w else { return false }
            func ident(_ u: Unicode.Scalar) -> Bool { u == "_" || u == "$" || u == "." || CharacterSet.alphanumerics.contains(u) }
            if j > 0, ident(c[j - 1]) { return false }
            if j + w.count < c.count, ident(c[j + w.count]), c[j + w.count] != "." { return false }
            return true
        }
        while i < c.count {
            let ch = c[i]
            switch ch {
            case "\"", "'", "`":
                i += 1
                while i < c.count, c[i] != ch { if c[i] == "\\" { i += 1 }; i += 1 }
            case "/" where i + 1 < c.count && c[i + 1] == "/":
                while i < c.count, c[i] != "\n" { i += 1 }
            case "/" where i + 1 < c.count && c[i + 1] == "*":
                i += 2
                while i + 1 < c.count, !(c[i] == "*" && c[i + 1] == "/") { i += 1 }
                i += 1
            case "{", "(", "[": depth += 1
            case "}", ")", "]": depth = max(0, depth - 1)
            case "r" where depth == 0 && word(at: i): return true
            default: break
            }
            i += 1
        }
        return false
    }

    private func js(_ a: [String: Any]) throws -> String {
        guard var code = a["code"] as? String else { throw ToolError("code required") }
        let id = try resolve(a)
        let slot = nextID("s")
        var prelude = ""
        if a["ref"] != nil || a["selector"] != nil || a["x"] != nil {
            // Mark the element in the DOM, which both the page's world and the extension's see.
            var o = pick(a, ["ref", "selector", "x", "y"])
            o["op"] = "mark"
            o["slot"] = slot
            let env = try agentCall(id, o)
            if let e = env["e"] as? String { throw ToolError(e) }
            prelude = "var el=document.querySelector('[data-smcp-el=\"\(slot)\"]');if(!el)throw new Error('the element is gone');el.removeAttribute('data-smcp-el');\n"
        }
        var href = ""
        func start(_ src: String) throws {
            href = try agent(id) { h in
                "if(__smcp.h!==\(jsonString(h)))return JSON.stringify({m:__smcp.h||''});var S=__smcp.slot('\(slot)');var u=location.href;(async function(){\(src)\n})().then(S.done,S.fail);return JSON.stringify({v:1,u:u})"
            }["u"] as? String ?? ""
        }
        // A bare expression is the common case; fall back to statements if it does not parse.
        while let last = code.last, last == ";" || last.isWhitespace { code.removeLast() }
        let hasReturn = Tools.topLevelReturn(code)
        var note = ""
        var inMain = false
        if safari.isExtension {
            // The extension's own scripts cannot see page globals; run in the page via main.js.
            func startMain(_ src: String) throws -> String {
                let env = try agent(id) { h in
                    "if(__smcp.h!==\(jsonString(h)))return JSON.stringify({m:__smcp.h||''});var u=location.href;return JSON.stringify({v:__smcp.mrun('\(slot)',\(jsonString(src))),u:u})"
                }
                href = env["u"] as? String ?? ""
                return env["v"] as? String ?? ""
            }
            var v = try startMain(prelude + (hasReturn ? code : "return (\n\(code)\n)"))
            if v.hasPrefix("syntax") && !hasReturn { v = try startMain(prelude + code) }
            if v.hasPrefix("syntax") { throw ToolError("SyntaxError: " + v.dropFirst(8)) }
            if v == "ok" { inMain = true } else {
                note = v == "csp" ? " (page CSP blocks eval: ran in the extension's context, page globals not visible)"
                    : " (page loaded before the extension: ran in the extension's context, page globals not visible; reload the page)"
            }
        }
        if !inMain { do {
            try start(prelude + (hasReturn ? code : "return (\n\(code)\n)"))
        } catch is ScriptEmpty {
            do {
                try start(prelude + code)
            } catch is ScriptEmpty {
                let why = poll(id, "(function(){try{new Function(\(jsonString(code)))}catch(e){return e instanceof SyntaxError?String(e):''}return ''})()")?.result ?? ""
                throw ToolError(why.isEmpty ? "The script did not run (page still loading, showing a dialog, or not a web page)." : why)
            }
        } }

        let before = verifiedURL
        let started = Date()
        var delay: useconds_t = 10_000
        while Date().timeIntervalSince(started) < 15 {
            usleep(delay)
            delay = min(delay * 2, 250_000)
            guard let r = poll(id, "window.__smcp?__smcp.take('\(slot)'):'{\"x\":1}'"),
                  let env = (try? JSONSerialization.jsonObject(with: Data(r.result.utf8))) as? [String: Any] else { continue }
            if env["p"] != nil { continue }
            tabs[id]?.url = r.url
            if env["x"] != nil { return "(page navigated before the script returned) " + waitLoad(id, marked: false, from: nil, timeout: 10).text }
            if let e = env["e"] as? String { throw ToolError(clip(e, 600)) }
            var v = env["v"] as? String ?? "undefined"
            // A string result prints as itself, not as a JSON literal, so shell tools can use it.
            if v.hasPrefix("\""), let d = v.data(using: .utf8), let str = try? JSONSerialization.jsonObject(with: d, options: .fragmentsAllowed) as? String { v = str }
            // Notes start with \u{1E}: the client prints those lines to stderr, so the data stays clean.
            let max = a["max_chars"] as? Int ?? 4000
            var out = max > 0 && v.count > max ? String(v.prefix(max)) + "\n\u{1E}… \(v.count - max) more chars (--max 0 for all, or -o FILE)" : v
            if !note.isEmpty { out += "\n\u{1E}" + note.trimmingCharacters(in: .whitespaces) }
            // The script sent the tab somewhere else: wait, so the next call sees the new page.
            var navigated = r.url != before
            if !navigated, code.range(of: #"location|history\.|\.submit\(|\.click\(|\.open\("#, options: .regularExpression) != nil {
                usleep(120_000)
                if let s = peek(id) { navigated = s.tabURL != before || s.url != href || s.ready != "complete" } else { navigated = true }
            }
            if navigated { out += " → " + waitLoad(id, marked: false, from: href, timeout: 10, grace: 6).text }
            return out
        }
        throw ToolError("js still running after 15 s; result discarded (the code may keep running in the page)")
    }

    private func screenshot(_ a: [String: Any]) throws -> [Content] {
        let id = try resolve(a)
        // Only the visible tab of a window can be captured.
        try sync()
        guard let tab = tabs[id] else { throw gone(id) }
        var back: Tab?
        if !tab.visible {
            back = tabs.values.first { $0.pos.wid == tab.pos.wid && $0.visible }
            try guardedOp(id) { try safari.select($0, $1) }
            usleep(350_000)
        }
        // Put the user's visible tab back once the capture is done.
        defer { if let back { try? guardedOp(back.id) { try safari.select($0, $1) } } }
        var o = pick(a, ["ref", "selector"])
        o["op"] = "geom"
        let g = try agentCall(id, o)["v"] as? [String: Any] ?? [:]
        guard let w = tabs[id]?.pos.wid else { throw gone(id) }
        let iw = g["iw"] as? Double ?? 0, ih = g["ih"] as? Double ?? 0
        var region = g["r"] as? [Double]
        if region == nil, let r = a["region"] as? [NSNumber] { region = r.map(\.doubleValue) }
        let maxWidth = a["max_width"] as? Int ?? 1024
        if a["full"] as? Bool == true { return try fullShot(id, w, iw: iw, ih: ih, maxWidth: maxWidth) }

        // The extension captures the visible tab itself: no Screen Recording permission needed.
        if let jpeg = safari.capture(w), let shot = Capture.recode(jpeg, viewport: CGSize(width: iw, height: ih), region: region, maxWidth: maxWidth) {
            return [.image(shot.data), .text(shotNote(shot.width, shot.height, k: shot.k, region: region))]
        }

        let wid = cg(w)
        let (view, bounds) = try Capture.viewport(wid: wid, iw: iw, ih: ih)
        let z = iw > 0 ? Double(view.width) / iw : 1

        var crop = view
        var origin = (x: 0.0, y: 0.0)
        if let r = region, r.count == 4 {
            crop = CGRect(x: Double(view.minX) + r[0] * z, y: Double(view.minY) + r[1] * z, width: r[2] * z, height: r[3] * z).intersection(view)
            origin = (r[0], r[1])
        }
        let shot: (data: Data, width: Int, height: Int)
        var raised = false
        if Capture.onScreen(wid) {
            shot = try Capture.jpeg(wid: wid, bounds: bounds, crop: crop, maxWidth: maxWidth)
        } else {
            // macOS only renders windows on the active Space. Show Safari for a moment, then
            // go back and let the Space switch finish so the next capture is not mid-animation.
            let front = NSWorkspace.shared.frontmostApplication
            try guardedOp(id) { try safari.raise($0, $1) }
            defer {
                if let front, front.bundleIdentifier != "com.apple.Safari" {
                    front.activate()
                    usleep(700_000)
                }
            }
            var tries = 0
            while !Capture.onScreen(wid) && tries < 20 { usleep(100_000); tries += 1 }
            usleep(250_000)
            shot = try Capture.jpeg(wid: wid, bounds: bounds, crop: crop, maxWidth: maxWidth)
            raised = true
        }

        // Tell the model how image pixels map to the viewport px that act expects.
        let k = Double(crop.width) / z / Double(shot.width)
        var note = shotNote(shot.width, shot.height, k: k, region: origin.x != 0 || origin.y != 0 ? [origin.x, origin.y] : nil)
        if raised { note += "; Safari was brought forward briefly to capture" }
        return [.image(shot.data), .text(note)]
    }

    /// The whole page: scroll one viewport at a time, capture each, and stack them. Fixed and
    /// sticky elements (headers, cookie bars) are hidden after the first screen so they show once.
    private func fullShot(_ id: Int, _ w: Int, iw: Double, ih: Double, maxWidth: Int) throws -> [Content] {
        let info = try exec(id, "var d=document.scrollingElement||document.documentElement;[scrollX,scrollY,d.scrollHeight].join(',')").split(separator: ",").compactMap { Double($0) }
        guard info.count == 3, iw > 0, ih > 0 else { throw ToolError("Could not measure the page.") }
        let (x0, y0) = (info[0], info[1])
        let limit = min(16000, ih * 12)
        let total = min(info[2], limit)
        var raised = false
        let front = NSWorkspace.shared.frontmostApplication
        defer {
            _ = try? exec(id, "(window.__smcpHid||[]).forEach(function(e){e[0].style.setProperty('visibility',e[1],e[2])});delete window.__smcpHid;scrollTo(\(x0),\(y0));''")
            if raised, let front, front.bundleIdentifier != "com.apple.Safari" { front.activate() }
        }
        func grab() throws -> CGImage {
            var data = safari.capture(w)
            if data == nil {
                let wid = cg(w)
                if !Capture.onScreen(wid) {
                    try guardedOp(id) { try safari.raise($0, $1) }
                    raised = true
                    var tries = 0
                    while !Capture.onScreen(wid) && tries < 20 { usleep(100_000); tries += 1 }
                    usleep(250_000)
                }
                let (view, bounds) = try Capture.viewport(wid: wid, iw: iw, ih: ih)
                data = try Capture.jpeg(wid: wid, bounds: bounds, crop: view, maxWidth: 10000).data
            }
            guard let d = data, let src = CGImageSourceCreateWithData(d as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                throw ToolError("The screenshot failed.")
            }
            return img
        }
        var slices: [(img: CGImage, y: Double)] = []
        var y = 0.0
        while true {
            let at = Double(try exec(id, "scrollTo(0,\(min(y, max(0, total - ih))));scrollY")) ?? y
            usleep(slices.isEmpty ? 250_000 : 400_000)  // paint, lazy images; Safari also limits captures per second
            slices.append((try grab(), at))
            if slices.count == 1 {
                _ = try exec(id, "var H=window.__smcpHid=[];document.querySelectorAll('body *').forEach(function(e){var p=getComputedStyle(e).position;if(p==='fixed'||p==='sticky'){H.push([e,e.style.getPropertyValue('visibility'),e.style.getPropertyPriority('visibility')]);e.style.setProperty('visibility','hidden','important')}});''")
            }
            if at + ih >= total - 1 || slices.count >= 12 { break }
            y = at + ih
        }
        let s = Double(slices[0].img.width) / iw
        let height = min(total, (slices.last!.y) + ih)
        let pw = slices[0].img.width, ph = Int((height * s).rounded())
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw ToolError("Image too large.") }
        // CoreGraphics puts y = 0 at the bottom. Later slices overwrite the overlap of earlier ones.
        for sl in slices {
            let top = sl.y * s
            ctx.draw(sl.img, in: CGRect(x: 0, y: Double(ph) - top - Double(sl.img.height), width: Double(sl.img.width), height: Double(sl.img.height)))
        }
        guard let img = ctx.makeImage() else { throw ToolError("Could not build the image.") }
        let data = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { throw ToolError("Could not encode the image.") }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(dst), let shot = Capture.recode(data as Data, viewport: CGSize(width: iw, height: height), region: nil, maxWidth: maxWidth) else {
            throw ToolError("Could not encode the image.")
        }
        var note = shotNote(shot.width, shot.height, k: shot.k, region: nil)
        if info[2] > height + 1 {
            note += "; top \(Int(height)) of \(Int(info[2])) px (\(slices.count) screens, the limit)\n\u{1E}page cut: for the rest, scroll and shot, or `text`"
        } else {
            note += "; whole page, \(slices.count) screens"
        }
        if raised { note += "; Safari was brought forward briefly to capture" }
        return [.image(shot.data), .text(note)]
    }

    /// Tells the model how image pixels map to the viewport px that act expects.
    private func shotNote(_ w: Int, _ h: Int, k: Double, region: [Double]?) -> String {
        var note = "\(w)x\(h)"
        let ox = region?.first ?? 0, oy = region.map { $0.count > 1 ? $0[1] : 0 } ?? 0
        if abs(k - 1) > 0.01 || ox != 0 || oy != 0 {
            note += "; viewport px = image px × \(String(format: "%.2f", k))"
            if ox != 0 || oy != 0 { note += " + (\(Int(ox)),\(Int(oy)))" }
        }
        return note
    }
}
