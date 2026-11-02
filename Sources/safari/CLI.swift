import Foundation

struct Usage: Error {
    let msg: String
}

/// argv → one `Tools` call. The only place the command syntax is defined.
enum CLI {
    /// Short help per verb; `safari help` prints them all.
    static let verbs: [(name: String, usage: String)] = [
        ("tabs", "tabs                          list tabs (* = visible)"),
        ("open", "open [URL] [--private] [--id-only]   new background tab → its id"),
        ("go", "[T] go URL|back|forward|reload  load and wait"),
        ("read", "[T] read [-q Q] [--all] [--full] [--diff] [--ref R] [--sel CSS] [--max N] [--offset K]"),
        ("text", "[T] text [-q Q] [--diff] [--ref R] [--sel CSS] [--max N] [--offset K]   page as markdown"),
        ("links", "[T] links [-q Q] [--ref R] [--sel CSS] [--max N] [--offset K]"),
        ("click", "[T] click R [--right] [--answer accept|dismiss|TEXT] [--os]   (dblclick, hover alike)"),
        ("dblclick", "[T] dblclick R [--os]"),
        ("hover", "[T] hover R [--os]"),
        ("drag", "[T] drag R --to R2           drag and drop"),
        ("fill", "[T] fill R TEXT | fill R=V R2=V2 …  (true/false for checkboxes) [--os]"),
        ("type", "[T] type R TEXT [--os]       append"),
        ("select", "[T] select R OPTION | select R TEXT   (option of a <select>; text in a field or editor)"),
        ("key", "[T] key KEY [R] [--os]        Enter, Escape, cmd+a, shift+Tab…"),
        ("scroll", "[T] scroll [DY] [R] [--os]"),
        ("wait", "[T] wait TEXT | --ref R | --sel CSS  [--gone] [--timeout S]"),
        ("upload", "[T] upload R FILE…"),
        ("dialog", "[T] dialog accept|dismiss|TEXT"),
        ("js", "[T] js CODE|- [--max N]     async function body; bare expression ok"),
        ("shot", "[T] shot [R|--sel CSS] [--region x,y,w,h] [--width N] [-o FILE]   JPEG → path"),
        ("logs", "[T] logs [--net] [--errors|--warn] [--new] [-p PAT] [--id nN] [--limit N] [--clear]"),
        ("show", "T show                        make the tab visible"),
        ("close", "T close"),
        ("downloads", "downloads [--wait] [--timeout S]   recent downloads; --wait until one finishes"),
        ("status", "status                       daemon and extension state"),
        ("stop", "stop                         stop the daemon"),
    ]

    static var help: String {
        """
        safari: drive the user's Safari. T = tab id (t3), R = ref from read (e12, f1e5).
        Elements can also be given as --sel CSS or --xy X,Y. Without T: the last tab used.

        """ + verbs.filter { !["dblclick", "hover"].contains($0.name) }.map { "  safari " + $0.usage }.joined(separator: "\n")
    }

    private static let valued: [String: String] = [
        "-q": "query", "--query": "query", "--ref": "ref", "--sel": "selector", "--max": "max_chars",
        "--offset": "offset", "--xy": "xy", "--to": "to", "--answer": "answer", "--timeout": "timeout",
        "--region": "region", "--width": "max_width", "-p": "pattern", "--pattern": "pattern",
        "--id": "id", "--limit": "limit", "-o": "out",
    ]
    private static let flags: [String: String] = [
        "--all": "all", "--full": "full", "--diff": "diff", "--os": "os", "--gone": "gone",
        "--private": "private", "--net": "net", "--errors": "errors", "--warn": "warn",
        "--new": "new", "--clear": "clear", "--right": "right", "--id-only": "idonly", "--wait": "wait",
    ]
    /// Options each verb takes.
    private static let allowed: [String: Set<String>] = {
        let page: Set = ["query", "ref", "selector", "max_chars", "offset", "diff"]
        let el: Set = ["ref", "selector", "xy", "os"]
        return [
            "tabs": [], "open": ["private", "idonly"], "downloads": ["wait", "timeout"], "status": [], "stop": [], "show": [], "close": [], "go": [],
            "read": page.union(["all", "full"]), "text": page, "links": page,
            "click": el.union(["answer", "right"]), "drag": ["ref", "selector", "xy", "to"], "dblclick": el.union(["answer"]), "hover": el,
            "fill": el, "type": el, "select": el, "key": el, "scroll": el,
            "wait": ["ref", "selector", "gone", "timeout"], "upload": el.subtracting(["os"]), "dialog": [],
            "js": ["max_chars"], "shot": ["ref", "selector", "region", "max_width", "out"],
            "logs": ["net", "errors", "warn", "new", "pattern", "id", "limit", "clear"],
        ]
    }()
    private static let global: Set = ["tabs", "open", "status", "stop", "help", "downloads"]

    static func isRef(_ s: String) -> Bool { s.wholeMatch(of: #/(f\d+)?e\d+/#) != nil }
    static func isTab(_ s: String) -> Bool { s.wholeMatch(of: #/t\d+/#) != nil }

    /// Returns the tool and its arguments; `help` comes back as tool "help" with the text.
    static func parse(_ argv: [String]) throws -> (tool: String, args: [String: Any], out: String?) {
        var rest = argv
        var tab: String?
        if let f = rest.first, isTab(f) { tab = f; rest.removeFirst() }
        guard let verb = rest.first else { throw Usage(msg: tab == nil ? help : "missing verb after \(tab!)\n\n" + help) }
        rest.removeFirst()

        if ["help", "-h", "--help"].contains(verb) {
            if let v = rest.first, let u = verbs.first(where: { $0.name == v }) { return ("help", ["text": "safari " + u.usage], nil) }
            return ("help", ["text": help], nil)
        }
        guard let keys = allowed[verb] else { throw Usage(msg: "unknown verb \(verb); `safari help` lists them") }
        let usage = "usage: safari " + (verbs.first { $0.name == verb }?.usage ?? verb)
        func bad(_ m: String) -> Usage { Usage(msg: m + "\n" + usage) }
        if tab != nil, global.contains(verb) { throw bad("\(verb) takes no tab id") }
        if tab == nil, verb == "close" { throw bad("close needs a tab id") }

        // Options anywhere; "--" ends them; negative numbers are values (scroll -400).
        var pos: [String] = []
        var o: [String: String] = [:]
        var f = Set<String>()
        var i = 0
        var done = false
        while i < rest.count {
            var a = rest[i]
            i += 1
            if done || !a.hasPrefix("-") || a == "-" || Double(a) != nil { pos.append(a); continue }
            if a == "--" { done = true; continue }
            var inline: String?
            if a.hasPrefix("--"), let eq = a.firstIndex(of: "=") {
                inline = String(a[a.index(after: eq)...])
                a = String(a[..<eq])
            }
            if let k = valued[a] {
                guard keys.contains(k) else { throw bad("\(verb) does not take \(a)") }
                if let inline { o[k] = inline; continue }
                guard i < rest.count else { throw bad("\(a) needs a value") }
                o[k] = rest[i]
                i += 1
            } else if let k = flags[a], inline == nil {
                guard keys.contains(k) else { throw bad("\(verb) does not take \(a)") }
                f.insert(k)
            } else {
                throw bad("unknown option \(a)")
            }
        }

        var args: [String: Any] = [:]
        if let tab { args["tab"] = tab }
        func int(_ k: String) throws {
            guard let v = o[k] else { return }
            guard let n = Int(v) else { throw bad("\(k) must be a whole number") }
            args[k] = n
        }
        func nums(_ s: String, _ n: Int, _ what: String) throws -> [Double] {
            let v = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard v.count == n else { throw bad("\(what) must be \(n) comma-separated numbers") }
            return v
        }
        /// Element: a leading positional ref, --ref, --sel or --xy.
        func target(required: Bool) throws {
            if let p = pos.first, isRef(p) { args["ref"] = p; pos.removeFirst() }
            if let r = o["ref"] { args["ref"] = r }
            if let s = o["selector"] { args["selector"] = s }
            if [args["ref"], args["selector"], o["xy"]].compactMap({ $0 }).count > 1 { throw bad("give one element: a ref, --sel or --xy") }
            if let xy = o["xy"] {
                let v = try nums(xy, 2, "--xy")
                args["x"] = v[0]
                args["y"] = v[1]
            }
            if required, args["ref"] == nil, args["selector"] == nil, args["x"] == nil {
                throw bad("\(verb) needs an element: a ref (e12), --sel CSS or --xy X,Y")
            }
        }
        func noMore() throws { if !pos.isEmpty { throw bad("unexpected \(pos.joined(separator: " "))") } }
        func one(_ what: String) throws -> String {
            guard pos.count == 1 else { throw bad(pos.isEmpty ? "\(verb) needs \(what)" : "unexpected \(pos.dropFirst().joined(separator: " ")) (quote text with spaces)") }
            return pos.removeFirst()
        }
        if f.contains("os") { args["os"] = true }

        switch verb {
        case "tabs", "status", "stop":
            try noMore()
            return (verb, args, nil)
        case "downloads":
            try noMore()
            if f.contains("wait") { args["wait"] = true }
            if let t = o["timeout"] {
                guard let s = Double(t) else { throw bad("--timeout is in seconds") }
                args["timeout"] = s
            }
            return (verb, args, nil)
        case "open":
            guard pos.count <= 1 else { throw bad("open takes one URL") }
            args["action"] = "new"
            if let u = pos.first { args["url"] = u }
            if f.contains("private") { args["private"] = true }
            if f.contains("idonly") { args["idonly"] = true }
            return ("tabs", args, nil)
        case "show", "close":
            try noMore()
            args["action"] = verb == "show" ? "select" : "close"
            return ("tabs", args, nil)
        case "go":
            args["url"] = try one("a URL, back, forward or reload")
            return ("navigate", args, nil)
        case "read", "text", "links":
            try noMore()
            args["mode"] = verb == "read" ? (f.contains("all") ? "all" : "interactive") : verb
            for k in ["query", "ref", "selector"] { if let v = o[k] { args[k] = v } }
            for k in ["full", "diff"] where f.contains(k) { args[k] = true }
            try int("max_chars")
            try int("offset")
            return ("read", args, nil)
        case "click", "dblclick", "hover":
            try target(required: true)
            try noMore()
            args["action"] = f.contains("right") ? "rclick" : verb
            if let a = o["answer"] { args["text"] = a }
            return ("act", args, nil)
        case "drag":
            try target(required: true)
            try noMore()
            guard let to = o["to"], isRef(to) else { throw bad("drag needs --to and a ref (e12) to drop on") }
            args["to"] = to
            args["action"] = "drag"
            return ("act", args, nil)
        case "fill" where !pos.isEmpty && pos.allSatisfy({ s in s.firstIndex(of: "=").map { isRef(String(s[..<$0])) } ?? false }):
            var fields: [String: String] = [:]
            for p in pos {
                let eq = p.firstIndex(of: "=")!
                fields[String(p[..<eq])] = String(p[p.index(after: eq)...])
            }
            args["action"] = "fill"
            args["fields"] = fields
            return ("act", args, nil)
        case "fill", "type", "select":
            try target(required: true)
            args["text"] = try one(verb == "select" ? "an option or text" : "the text")
            args["action"] = verb
            return ("act", args, nil)
        case "key":
            guard !pos.isEmpty else { throw bad("key needs a key name") }
            args["key"] = pos.removeFirst()
            try target(required: false)
            try noMore()
            args["action"] = "key"
            return ("act", args, nil)
        case "scroll":
            if let p = pos.first, let dy = Double(p) { args["dy"] = dy; pos.removeFirst() }
            try target(required: false)
            if args["dy"] == nil, let p = pos.first, let dy = Double(p) { args["dy"] = dy; pos.removeFirst() }
            try noMore()
            args["action"] = "scroll"
            return ("act", args, nil)
        case "wait":
            if let r = o["ref"] { args["ref"] = r }
            if let s = o["selector"] { args["selector"] = s }
            if !pos.isEmpty { args["text"] = try one("text") }
            if args["text"] == nil, args["ref"] == nil, args["selector"] == nil { throw bad("wait needs text, --ref or --sel") }
            if f.contains("gone") { args["gone"] = true }
            if let t = o["timeout"] {
                guard let s = Double(t) else { throw bad("--timeout is in seconds") }
                args["timeout"] = s
            }
            args["action"] = "wait"
            return ("act", args, nil)
        case "upload":
            try target(required: true)
            guard !pos.isEmpty else { throw bad("upload needs file paths") }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            args["text"] = pos.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, relativeTo: cwd).standardizedFileURL.path }.joined(separator: ",")
            args["action"] = "upload"
            return ("act", args, nil)
        case "dialog":
            args["text"] = try one("accept, dismiss or a prompt reply")
            args["action"] = "dialog"
            return ("act", args, nil)
        case "js":
            var code = pos.joined(separator: " ")
            if pos.isEmpty || pos == ["-"] {
                code = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            }
            guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw bad("js needs code (or - to read it from stdin)") }
            args["code"] = code
            try int("max_chars")
            return ("js", args, nil)
        case "shot":
            if let p = pos.first, isRef(p) { args["ref"] = p; pos.removeFirst() }
            if let r = o["ref"] { args["ref"] = r }
            if let r = args["ref"] as? String, r.hasPrefix("f") { throw bad("shot cannot crop to a ref inside a frame; crop to the frame with --sel iframe, or use --region") }
            if let s = o["selector"] { args["selector"] = s }
            try noMore()
            if let r = o["region"] { args["region"] = try nums(r, 4, "--region") }
            try int("max_width")
            return ("screenshot", args, o["out"])
        case "logs":
            try noMore()
            if f.contains("net") || o["id"] != nil { args["kind"] = "network" }
            if f.contains("errors") { args["level"] = "error" } else if f.contains("warn") { args["level"] = "warn" }
            for k in ["new", "clear"] where f.contains(k) { args[k] = true }
            for k in ["pattern", "id"] { if let v = o[k] { args[k] = v } }
            try int("limit")
            return ("logs", args, nil)
        default:
            throw bad("unknown verb \(verb)")
        }
    }
}
