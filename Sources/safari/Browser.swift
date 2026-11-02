import AppKit
import CoreGraphics
import Foundation

/// Position of a tab right now. Positions shift when tabs open, close or move, so every
/// call that touches a tab also states what it expects to find there (see `Expect`).
struct TabRef: Equatable {
    var wid: Int
    var idx: Int

    init(_ wid: Int, _ idx: Int) {
        self.wid = wid
        self.idx = idx
    }
}

struct TabInfo {
    let ref: TabRef
    let current: Bool
    let title: String
    let url: String
    /// Safari's own tab id, only known through the extension. It never changes while the tab is open.
    var xid: Int? = nil
    /// In a private window; only known through the extension.
    var priv = false
}

/// What the caller believes about a tab position. The extension checks it in the same step
/// that performs the action, so a stale position is refused instead of hitting another tab.
struct Expect {
    /// Tab count of the window; negative skips the check.
    var count: Int
    /// URL of the tab; nil skips the check (used while a navigation is in flight).
    var url: String?
}

/// The page script produced no value: syntax error, page not ready, or a dialog is open.
struct ScriptEmpty: Error {}

/// Safari through the Safari CLI Bridge extension's background page. Every tab-targeted op
/// carries an `Expect` that the extension checks in the same step that acts, so a stale
/// position is refused instead of hitting another tab.
final class ExtBrowser {
    private let bridge: Bridge
    init(_ bridge: Bridge) { self.bridge = bridge }

    /// Child frame that `js` runs in; 0 is the top document. Set only around one call.
    var frame = 0

    /// Child frames of the tab (iframes), in document order.
    func frames(_ tab: TabRef, _ e: Expect) throws -> [(id: Int, url: String)] {
        let r = try bridge.call("frames", at(tab, e))
        return (r["ok"] as? [[String: Any]] ?? []).compactMap { f in (f["id"] as? Int).map { ($0, f["url"] as? String ?? "") } }
    }

    private func at(_ tab: TabRef, _ e: Expect) -> [String: Any] {
        ["w": tab.wid, "i": tab.idx, "n": e.count, "u": e.url ?? "*"]
    }

    func listTabs() throws -> [TabInfo] {
        let r = try bridge.call("tabs")
        return (r["ok"] as? [[String: Any]] ?? []).compactMap { t in
            guard let w = t["w"] as? Int, let i = t["i"] as? Int else { return nil }
            return TabInfo(ref: TabRef(w, i), current: t["cur"] as? Bool ?? false, title: t["title"] as? String ?? "", url: t["url"] as? String ?? "", xid: t["id"] as? Int, priv: t["p"] != nil)
        }
    }

    func js(_ tab: TabRef, _ code: String, _ e: Expect) throws -> (url: String, result: String)? {
        var a = at(tab, e)
        a["code"] = code
        if frame != 0 { a["frame"] = frame }
        let r = try bridge.call("run", a)
        if r["stale"] != nil { return nil }
        return (r["url"] as? String ?? "", r["ok"] as? String ?? "")
    }

    private func tabOp(_ op: String, _ tab: TabRef, _ e: Expect, _ extra: [String: Any] = [:]) throws -> Bool {
        let r = try bridge.call(op, at(tab, e).merging(extra) { $1 })
        return r["stale"] == nil
    }

    func setURL(_ tab: TabRef, _ url: String, _ e: Expect) throws -> Bool { try tabOp("seturl", tab, e, ["url": url]) }
    func close(_ tab: TabRef, _ e: Expect) throws -> Bool { try tabOp("close", tab, e) }
    func select(_ tab: TabRef, _ e: Expect) throws -> Bool { try tabOp("select", tab, e) }

    func raise(_ tab: TabRef, _ e: Expect) throws -> Bool {
        guard try tabOp("raise", tab, e) else { return false }
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first?.activate()
        return true
    }

    func newTab(in wid: Int?, url: String) throws -> (ref: TabRef, xid: Int?) {
        var a: [String: Any] = ["url": url]
        if let wid { a["w"] = wid }
        let r = try bridge.call("newtab", a)
        guard let w = r["w"] as? Int, let i = r["i"] as? Int else { throw ToolError("Could not open a Safari tab.") }
        return (TabRef(w, i), r["tab"] as? Int)
    }

    func newPrivateWindow(url: String) -> (ref: TabRef, xid: Int?)? {
        guard let r = try? bridge.call("newpriv", ["url": url]), let w = r["w"] as? Int else { return nil }
        return (TabRef(w, 1), r["tab"] as? Int)
    }

    /// Every request the tab made since its page started loading, as log lines.
    func requests(_ tab: TabRef) -> [String]? {
        (try? bridge.call("reqs", ["w": tab.wid, "i": tab.idx], timeout: 3))?["ok"] as? [String]
    }

    func status(_ tab: TabRef) -> Int {
        ((try? bridge.call("status", ["w": tab.wid, "i": tab.idx], timeout: 3))?["ok"] as? Int) ?? 0
    }

    /// Matches the extension's window to a window server window by its frame. Window
    /// bounds are readable without Screen Recording permission (titles are not).
    func cgWindow(_ wid: Int) -> Int? {
        guard let r = try? bridge.call("win", ["w": wid], timeout: 3),
              let x = r["x"] as? Double, let y = r["y"] as? Double, let w = r["width"] as? Double, let h = r["height"] as? Double,
              let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let safari = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").map { Int($0.processIdentifier) })
        let match = list.first { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, safari.contains(pid),
                  info[kCGWindowLayer as String] as? Int == 0,
                  let b = info[kCGWindowBounds as String] as? NSDictionary, let rect = CGRect(dictionaryRepresentation: b) else { return false }
            return abs(rect.minX - x) < 2 && abs(rect.minY - y) < 2 && abs(rect.width - w) < 2 && abs(rect.height - h) < 2
        }
        return match?[kCGWindowNumber as String] as? Int
    }

    /// Replaces the tab's network rules (`safari route`). False: the tab moved (re-sync and retry).
    func rules(_ tab: TabRef, _ e: Expect, _ list: [[String: Any]]) throws -> Bool {
        do {
            return try bridge.call("rules", at(tab, e).merging(["rules": list]) { $1 })["stale"] == nil
        } catch let e as ToolError where e.msg.hasPrefix("unknown op") {
            throw ToolError("The Safari CLI Bridge extension is out of date; rebuild it with Extension/build.sh.")
        }
    }

    /// The extension's `cookies` op on the tab's site; the reply has `ok`, `stale` (tab moved) or `no` (no cookie API).
    func cookies(_ tab: TabRef, _ e: Expect, _ m: [String: Any]) throws -> [String: Any] {
        do {
            return try bridge.call("cookies", at(tab, e).merging(m) { $1 })
        } catch let e as ToolError where e.msg.hasPrefix("unknown op") {
            return ["no": 1]
        }
    }

    func resize(_ wid: Int, width: Int, height: Int) throws -> Bool {
        do {
            _ = try bridge.call("resize", ["w": wid, "width": width, "height": height])
            return true
        } catch let e as ToolError where e.msg.hasPrefix("unknown op") {
            return false
        }
    }

    func capture(_ wid: Int) -> Data? {
        guard let r = try? bridge.call("shot", ["w": wid], timeout: 8), let url = r["ok"] as? String,
              let comma = url.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(url[url.index(after: comma)...]))
    }
}
