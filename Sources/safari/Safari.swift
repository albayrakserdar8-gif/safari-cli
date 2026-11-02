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

/// What the caller believes about a tab position. Safari checks it in the same Apple Event
/// that performs the action, so a stale position is refused instead of hitting another tab.
struct Expect {
    /// Tab count of the window; negative skips the check.
    var count: Int
    /// URL of the tab; nil skips the check (used while a navigation is in flight).
    var url: String?
}

/// The page script produced no value: syntax error, page not ready, or a dialog is open.
struct ScriptEmpty: Error {}

/// Apple Events bridge. One script is compiled once; handlers are invoked with
/// parameters, so nothing is re-compiled or string-escaped per call.
final class Safari {
    private static let stale = "!"
    private static let anyURL = "*"

    private static let source = """
    on chk(w, t, n, u)
    	tell application "Safari"
    		if n is not less than 0 and (count of tabs of window id w) is not n then return false
    		if u is "*" then return true
    		set cu to ""
    		try
    			set cu to URL of tab t of window id w
    			if cu is missing value then set cu to ""
    		end try
    		considering case
    			return cu is u
    		end considering
    	end tell
    end chk

    on taburl(w, t)
    	set cu to ""
    	try
    		tell application "Safari" to set cu to URL of tab t of window id w
    		if cu is missing value then set cu to ""
    	end try
    	return cu
    end taburl

    on runjs(w, t, n, u, code)
    	if not chk(w, t, n, u) then return "!"
    	set r to ""
    	try
    		with timeout of 20 seconds
    			tell application "Safari" to set r to (do JavaScript code in tab t of window id w)
    		end timeout
    	on error m number en
    		if en is not -2753 and en is not -2763 then error m number en
    	end try
    	set rt to ""
    	try
    		set rt to r as text
    	end try
    	return taburl(w, t) & (character id 9) & rt
    end runjs

    on listtabs()
    	set out to ""
    	set s to character id 9
    	tell application "Safari"
    		repeat with w in (every window)
    			try
    				set wid to id of w
    				set ci to index of current tab of w
    				repeat with t in (every tab of w)
    					set i to index of t
    					set u to ""
    					try
    						set u to URL of t
    						if u is missing value then set u to ""
    					end try
    					set c to "0"
    					if i is ci then set c to "1"
    					set out to out & wid & ":" & i & s & c & s & (name of t) & s & u & linefeed
    				end repeat
    			end try
    		end repeat
    	end tell
    	return out
    end listtabs

    on seturl(w, t, n, u, target)
    	if not chk(w, t, n, u) then return "!"
    	tell application "Safari" to set URL of tab t of window id w to target
    	return ""
    end seturl

    on newtab(w, u)
    	tell application "Safari"
    		tell window id w
    			if u is "" then
    				set nt to make new tab
    			else
    				set nt to make new tab with properties {URL:u}
    			end if
    			return index of nt
    		end tell
    	end tell
    end newtab

    on newdoc(u)
    	tell application "Safari"
    		if u is "" then
    			make new document
    		else
    			make new document with properties {URL:u}
    		end if
    		return id of window 1
    	end tell
    end newdoc

    on closetab(w, t, n, u)
    	if not chk(w, t, n, u) then return "!"
    	tell application "Safari" to close tab t of window id w
    	return ""
    end closetab

    on selecttab(w, t, n, u)
    	if not chk(w, t, n, u) then return "!"
    	tell application "Safari" to tell window id w to set current tab to tab t
    	return ""
    end selecttab

    on raisetab(w, t, n, u)
    	if not chk(w, t, n, u) then return "!"
    	tell application "Safari"
    		tell window id w to set current tab to tab t
    		set index of window id w to 1
    		activate
    	end tell
    	return ""
    end raisetab

    on frontapp()
    	return (path to frontmost application as text)
    end frontapp

    on activateapp(p)
    	tell application p to activate
    	return ""
    end activateapp
    """

    /// The window or tab index no longer exists.
    private struct Gone: Error {}

    private let script: NSAppleScript

    init() {
        script = NSAppleScript(source: Safari.source)!
        var err: NSDictionary?
        script.compileAndReturnError(&err)
        if let err { FileHandle.standardError.write("safari: script compile failed: \(err)\n".data(using: .utf8)!) }
    }

    private func fcc(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

    private func run(_ handler: String, _ args: [Any] = []) throws -> String {
        let params = NSAppleEventDescriptor.list()
        for (i, a) in args.enumerated() {
            let d: NSAppleEventDescriptor
            if let n = a as? Int { d = NSAppleEventDescriptor(int32: Int32(n)) } else { d = NSAppleEventDescriptor(string: "\(a)") }
            params.insert(d, at: i + 1)
        }
        let ev = NSAppleEventDescriptor(
            eventClass: fcc("ascr"), eventID: fcc("psbr"), targetDescriptor: nil, returnID: -1, transactionID: 0)
        ev.setDescriptor(NSAppleEventDescriptor(string: handler), forKeyword: fcc("snam"))
        ev.setDescriptor(params, forKeyword: fcc("----"))

        var err: NSDictionary?
        let res = script.executeAppleEvent(ev, error: &err)
        if let err {
            let msg = err[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
            if msg.contains("Allow JavaScript from Apple Events") {
                throw ToolError("Safari blocks scripting. Enable Safari > Settings > Developer > 'Allow JavaScript from Apple Events', then retry.")
            }
            let num = err[NSAppleScript.errorNumber] as? Int ?? 0
            if num == -1719 || num == -1728 { throw Gone() }
            if num == -1712 { throw ToolError("Safari did not answer in time; the page may be showing a dialog.") }
            throw ToolError(msg)
        }
        return res.stringValue ?? ""
    }

    /// Runs a tab-targeted handler. Returns nil when the position was stale.
    private func guarded(_ handler: String, _ tab: TabRef, _ e: Expect, _ extra: [Any] = []) throws -> String? {
        do {
            let r = try run(handler, [tab.wid, tab.idx, e.count, e.url ?? Safari.anyURL] + extra)
            return r == Safari.stale ? nil : r
        } catch is Gone {
            return nil
        }
    }

    /// Runs JavaScript in the tab. Returns the tab's URL afterwards and the script result,
    /// or nil when the position was stale (nothing ran).
    func js(_ tab: TabRef, _ code: String, _ e: Expect) throws -> (url: String, result: String)? {
        guard let r = try guarded("runjs", tab, e, [code]) else { return nil }
        let f = r.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        return (String(f[0]), f.count > 1 ? String(f[1]) : "")
    }

    func listTabs() throws -> [TabInfo] {
        var tabs: [TabInfo] = []
        for line in try run("listtabs").split(separator: "\n") {
            let f = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard f.count == 4 else { continue }
            let p = f[0].split(separator: ":")
            guard p.count == 2, let w = Int(p[0]), let i = Int(p[1]) else { continue }
            tabs.append(TabInfo(ref: TabRef(w, i), current: f[1] == "1", title: String(f[2]), url: String(f[3])))
        }
        return tabs
    }

    func setURL(_ tab: TabRef, _ url: String, _ e: Expect) throws -> Bool { try guarded("seturl", tab, e, [url]) != nil }
    func close(_ tab: TabRef, _ e: Expect) throws -> Bool { try guarded("closetab", tab, e) != nil }
    func select(_ tab: TabRef, _ e: Expect) throws -> Bool { try guarded("selecttab", tab, e) != nil }
    func raise(_ tab: TabRef, _ e: Expect) throws -> Bool { try guarded("raisetab", tab, e) != nil }

    func openTab(in wid: Int?, url: String) throws -> TabRef {
        if let wid, let idx = Int((try? run("newtab", [wid, url])) ?? "") { return TabRef(wid, idx) }
        guard let w = Int(try run("newdoc", [url])) else { throw ToolError("Could not open a Safari window.") }
        return TabRef(w, 1)
    }

    func frontApp() -> String? { try? run("frontapp") }
    func activate(app: String) { _ = try? run("activateapp", [app]) }
}
