import AppKit
import CoreGraphics
import Foundation

/// What `Tools` needs from Safari. Two implementations: the extension (preferred, no Apple
/// Events permission) and Apple Events (`Safari`, the fallback). Both check `Expect` in the
/// same step that acts, so a stale position never hits another tab.
protocol Browser: AnyObject {
    func listTabs() throws -> [TabInfo]
    func js(_ tab: TabRef, _ code: String, _ e: Expect) throws -> (url: String, result: String)?
    func setURL(_ tab: TabRef, _ url: String, _ e: Expect) throws -> Bool
    func close(_ tab: TabRef, _ e: Expect) throws -> Bool
    func select(_ tab: TabRef, _ e: Expect) throws -> Bool
    func raise(_ tab: TabRef, _ e: Expect) throws -> Bool
    func newTab(in wid: Int?, url: String) throws -> (ref: TabRef, xid: Int?)
    /// HTTP status of the tab's last top-level load, 0 when unknown.
    func status(_ tab: TabRef) -> Int
    /// Window server id of the window, for screen capture and real input.
    func cgWindow(_ wid: Int) -> Int?
    /// JPEG of the window's visible tab, when the backend can take one itself.
    func capture(_ wid: Int) -> Data?
    var isExtension: Bool { get }
}

extension Safari: Browser {
    func newTab(in wid: Int?, url: String) throws -> (ref: TabRef, xid: Int?) { (try openTab(in: wid, url: url), nil) }
    func status(_ tab: TabRef) -> Int { 0 }
    func cgWindow(_ wid: Int) -> Int? { wid }
    func capture(_ wid: Int) -> Data? { nil }
    var isExtension: Bool { false }
}

/// Safari through the extension's background page.
final class ExtBrowser: Browser {
    private let bridge: Bridge
    init(_ bridge: Bridge) { self.bridge = bridge }

    /// Child frame that `js` runs in; 0 is the top document. Set only around one call.
    var frame = 0

    /// Child frames of the tab (iframes), in document order.
    func frames(_ tab: TabRef, _ e: Expect) throws -> [(id: Int, url: String)] {
        let r = try bridge.call("frames", at(tab, e))
        return (r["ok"] as? [[String: Any]] ?? []).compactMap { f in (f["id"] as? Int).map { ($0, f["url"] as? String ?? "") } }
    }

    var isExtension: Bool { true }

    private func at(_ tab: TabRef, _ e: Expect) -> [String: Any] {
        ["w": tab.wid, "i": tab.idx, "n": e.count, "u": e.url ?? "*"]
    }

    func listTabs() throws -> [TabInfo] {
        let r = try bridge.call("tabs")
        return (r["ok"] as? [[String: Any]] ?? []).compactMap { t in
            guard let w = t["w"] as? Int, let i = t["i"] as? Int else { return nil }
            return TabInfo(ref: TabRef(w, i), current: t["cur"] as? Bool ?? false, title: t["title"] as? String ?? "", url: t["url"] as? String ?? "", xid: t["id"] as? Int)
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

    func capture(_ wid: Int) -> Data? {
        guard let r = try? bridge.call("shot", ["w": wid], timeout: 8), let url = r["ok"] as? String,
              let comma = url.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(url[url.index(after: comma)...]))
    }
}
