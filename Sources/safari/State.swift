import Foundation

/// `safari T state save|load FILE`: the site's cookies, localStorage and sessionStorage as one
/// JSON file. Runs in the client over existing tools (`cookies`, `js`, `navigate`).
enum State {
    private static let readJS = """
        var f=function(st){var o={};for(var i=0;i<st.length;i++){var k=st.key(i);if(k.indexOf('__smcp_')!==0)o[k]=st.getItem(k)}return o};
        return JSON.stringify({origin:location.origin,url:location.href,local:f(localStorage),session:f(sessionStorage)})
        """

    static func run(_ args: [String: Any]) -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        guard let path = args["file"] as? String else { return fail("safari: state needs a file") }
        var base: [String: Any] = [:]
        if let t = args["tab"] { base["tab"] = t }
        func call(_ tool: String, _ a: [String: Any]) throws -> (data: String, notes: [String]) {
            let r = try Client.send(tool, base.merging(a) { $1 })
            let s = Client.split(r["text"] as? String ?? "")
            guard r["ok"] as? Bool == true else { throw Client.Failure(msg: s.data) }
            return s
        }
        func json(_ s: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(s.utf8)) }
        do {
            guard let page = json(try call("js", ["code": readJS, "max_chars": 0]).data) as? [String: Any],
                  let origin = page["origin"] as? String, origin.hasPrefix("http") else {
                return fail("safari: state needs an http(s) page in the tab")
            }
            if args["act"] as? String == "save" {
                let c = try call("cookies", ["act": "dump"])
                let cookies = json(c.data) as? [Any] ?? []
                let file: [String: Any] = ["origin": origin, "url": page["url"] ?? "", "saved": ISO8601DateFormatter().string(from: Date()),
                                           "cookies": cookies, "local": page["local"] ?? [:], "session": page["session"] ?? [:]]
                let d = try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                // Session tokens: readable by the user only.
                guard FileManager.default.createFile(atPath: path, contents: d, attributes: [.posixPermissions: 0o600]) else {
                    return fail("safari: cannot write \(path)")
                }
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
                Out.data("saved \(cookies.count) cookies, \((page["local"] as? [String: Any])?.count ?? 0) local, \((page["session"] as? [String: Any])?.count ?? 0) session keys of \(origin) → \(path)")
                c.notes.forEach(Out.note)
                return 0
            }
            guard let d = FileManager.default.contents(atPath: path), let file = json(String(decoding: d, as: UTF8.self)) as? [String: Any] else {
                return fail("safari: cannot read \(path) as a state file")
            }
            let want = file["origin"] as? String ?? ""
            guard want == origin else { return fail("safari: \(path) is for \(want); open it in this tab first (the tab is on \(origin))") }
            let cookies = file["cookies"] as? [Any] ?? []
            let c = try call("cookies", ["act": "load", "list": cookies])
            let local = file["local"] as? [String: Any] ?? [:], session = file["session"] as? [String: Any] ?? [:]
            let put = "var w=function(st,o){for(var k in o)st.setItem(k,o[k])};w(localStorage,\(jsonString(local)));w(sessionStorage,\(jsonString(session)));return 'ok'"
            _ = try call("js", ["code": put])
            let r = try call("navigate", ["url": "reload"])
            Out.data("loaded \(c.data.split(separator: " ").dropFirst().first ?? "0") of \(cookies.count) cookies, \(local.count) local, \(session.count) session keys; reloaded: \(r.data.split(separator: "\n").first ?? "")")
            c.notes.forEach(Out.note)
            return 0
        } catch let f as Client.Failure {
            return fail(f.msg.hasPrefix("safari") ? f.msg : "safari: " + f.msg)
        } catch {
            return fail("safari: \(error)")
        }
    }

    private static func fail(_ msg: String) -> Int32 { Out.fail(msg) }
}
