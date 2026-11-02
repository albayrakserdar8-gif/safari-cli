import Foundation

struct Usage: Error {
    let msg: String
}

/// argv → one `Tools` call. The only place the command syntax is defined.
enum CLI {
    /// Short help per verb; `safari help` prints them all.
    static let verbs: [(name: String, usage: String)] = [
        ("tabs", "tabs                          list tabs (* = visible)"),
        ("open", "open [URL] [--private] [--window] [--id-only] [--delay S]   new background tab → its id"),
        ("go", "[T] go URL|back|forward|reload [--delay S]  load and wait (S: seconds since the site's last load, e.g. 8-14)"),
        ("read", "[T] read [-q Q] [--all] [--full] [--diff] [--ref R] [--sel CSS] [--max N] [--offset K] [-o FILE]"),
        ("text", "[T] text [-q Q] [--diff] [--ref R] [--sel CSS] [--max N] [--offset K] [-o FILE]   page as markdown"),
        ("links", "[T] links [-q Q] [--ref R] [--sel CSS] [--max N] [--offset K] [-o FILE]"),
        ("table", "[T] table [--sel CSS|--ref R] [--rows CSS] [--json] [--max N] [--offset K] [-o FILE]   rows as TSV"),
        ("crawl", "T crawl [--next TEXT] [--pages N (5)] [--delay S] [--sel CSS|--rows CSS] [--json] [-o FILE]   from this page on: table, next page, repeat"),
        ("click", "[T] click R [--right] [--answer accept|dismiss|TEXT] [--os]   (dblclick, hover alike)"),
        ("dblclick", "[T] dblclick R [--os]"),
        ("hover", "[T] hover R [--os]"),
        ("drag", "[T] drag R --to R2           drag and drop"),
        ("fill", "[T] fill R TEXT | fill R=V R2=V2 …  (true/false for checkboxes) [--os]"),
        ("check", "[T] check R | uncheck R      set a checkbox or radio (safe to repeat)"),
        ("uncheck", "[T] uncheck R"),
        ("type", "[T] type R TEXT [--os]       append"),
        ("select", "[T] select R OPTION | select R TEXT   (option of a <select>; text in a field or editor)"),
        ("key", "[T] key KEY [R] [--os]        Enter, Escape, cmd+a, shift+Tab…"),
        ("scroll", "[T] scroll [DY] [R] [--os]"),
        ("wait", "[T] wait TEXT | --ref R | --sel CSS | --load  [--gone] [--timeout S]"),
        ("upload", "[T] upload R FILE…"),
        ("dialog", "[T] dialog accept|dismiss|TEXT"),
        ("js", "[T] js CODE|- [R] [--max N] [-o FILE]   async function body; bare expression ok; R is `el`"),
        ("shot", "[T] shot [R|--sel CSS|--full] [--region x,y,w,h] [--width N] [-o FILE]   JPEG → path; --full: whole page"),
        ("logs", "[T] logs [--net] [--errors|--warn] [--new] [-p PAT] [--id nN] [--limit N] [--clear]"),
        ("locator", "[T] locator R                 a CSS selector for R that lasts across page loads (--sel)"),
        ("highlight", "[T] highlight R [--for S (5; 0 = until --hide)] | highlight --hide   box around R in the user's view"),
        ("route", "[T] route PATTERN [--status N] [--body TEXT|@FILE] [--type CT] [--block] | route --list   mock fetch/XHR"),
        ("unroute", "[T] unroute [PATTERN]         remove one route, or all"),
        ("storage", "[T] storage [local|session] [KEY [VALUE]] [--delete KEY] [--clear]   list, get or set web storage"),
        ("drop", "[T] drop R FILE… [--text T]   drop files (or text) onto a drop zone"),
        ("record", "T record | T record --stop     record what the user does in the tab; --stop prints it as commands"),
        ("show", "T show                        make the tab visible"),
        ("close", "T close | close --agents   (--agents: every agent tab not on screen)"),
        ("resize", "[T] resize W H               viewport size, in a window of agent tabs only (open --window)"),
        ("downloads", "downloads [--wait] [--timeout S]   recent downloads; --wait until one finishes"),
        ("rate", "rate [SITE [S|off]]          pace page loads per site (S: seconds, e.g. 10 or 8-14)"),
        ("status", "status                       daemon and extension state"),
        ("stop", "stop                         stop the daemon"),
    ]

    static var help: String {
        """
        safari: drive the user's Safari. T = tab id (t3), R = ref from read (e12, f1e5).
        Elements can also be given as --sel CSS or --xy X,Y. Without T: the last tab used.
        --max N caps output (read/text/links/table 6000, js 4000; 0 = all); -o FILE writes it all.
        Notes such as "… N more chars" go to stderr.

        """ + verbs.filter { !["dblclick", "hover", "uncheck"].contains($0.name) }.map { "  safari " + $0.usage }.joined(separator: "\n")
    }

    private static let valued: [String: String] = [
        "-q": "query", "--query": "query", "--ref": "ref", "--sel": "selector", "--max": "max_chars",
        "--offset": "offset", "--xy": "xy", "--to": "to", "--answer": "answer", "--text": "text", "--timeout": "timeout",
        "--region": "region", "--width": "max_width", "-p": "pattern", "--pattern": "pattern",
        "--id": "id", "--limit": "limit", "-o": "out", "--rows": "rows", "--next": "next", "--pages": "pages",
        "--delay": "delay", "--for": "secs", "--status": "status", "--body": "body", "--type": "ctype", "--delete": "del",
    ]
    private static let flags: [String: String] = [
        "--all": "all", "--full": "full", "--diff": "diff", "--os": "os", "--gone": "gone",
        "--private": "private", "--net": "net", "--errors": "errors", "--warn": "warn",
        "--new": "new", "--clear": "clear", "--right": "right", "--id-only": "idonly", "--wait": "wait",
        "--json": "json", "--load": "load", "--window": "window", "--agents": "agents", "--hide": "hide", "--block": "block", "--list": "list", "--stop": "stop",
    ]
    /// Options each verb takes.
    private static let allowed: [String: Set<String>] = {
        let page: Set = ["query", "ref", "selector", "max_chars", "offset", "diff"]
        let el: Set = ["ref", "selector", "xy", "os"]
        return [
            "tabs": [], "open": ["private", "window", "idonly", "delay"], "downloads": ["wait", "timeout"], "status": [], "stop": [], "show": [], "close": ["agents"], "resize": [], "route": ["status", "body", "ctype", "block", "list"], "unroute": [], "storage": ["del", "clear", "max_chars"], "drop": ["ref", "selector", "xy", "text"], "record": ["stop"], "locator": ["ref", "selector", "xy"], "highlight": ["ref", "selector", "xy", "secs", "hide"], "go": ["delay"],
            "read": page.union(["all", "full", "out"]), "text": page.union(["out"]), "links": page.union(["out"]),
            "table": ["ref", "selector", "rows", "json", "max_chars", "offset", "out"],
            "crawl": ["selector", "rows", "json", "next", "pages", "delay", "out"], "rate": [],
            "click": el.union(["answer", "right"]), "drag": ["ref", "selector", "xy", "to"], "dblclick": el.union(["answer"]), "hover": el,
            "fill": el, "check": ["ref", "selector", "xy"], "uncheck": ["ref", "selector", "xy"], "type": el, "select": el, "key": el, "scroll": el,
            "wait": ["ref", "selector", "gone", "timeout", "load"], "upload": el.subtracting(["os"]), "dialog": [],
            "js": ["ref", "selector", "xy", "max_chars", "out"], "shot": ["ref", "selector", "region", "max_width", "out", "full"],
            "logs": ["net", "errors", "warn", "new", "pattern", "id", "limit", "clear"],
        ]
    }()
    private static let global: Set = ["tabs", "open", "status", "stop", "help", "downloads", "rate"]

    static func isRef(_ s: String) -> Bool { s.wholeMatch(of: #/(f\d+)?e\d+/#) != nil }
    static func isTab(_ s: String) -> Bool { s.wholeMatch(of: #/t\d+/#) != nil }

    /// Returns the tool and its arguments; `help` comes back as tool "help" with the text.
    static func parse(_ argv: [String]) throws -> (tool: String, args: [String: Any], out: String?) {
        var rest = argv
        var tab: String?
        if let f = rest.first, isTab(f) { tab = f; rest.removeFirst() }
        guard let verb = rest.first else { throw Usage(msg: tab == nil ? help : "missing verb after \(tab!)\n\n" + help) }
        rest.removeFirst()
        // SAFARI_TAB=t5 makes t5 the tab for commands that name none (one per agent).
        if tab == nil, !global.contains(verb), !["help", "-h", "--help"].contains(verb), !(verb == "close" && rest.contains("--agents")),
           let e = ProcessInfo.processInfo.environment["SAFARI_TAB"], !e.isEmpty {
            guard isTab(e) else { throw Usage(msg: "SAFARI_TAB must be a tab id like t3, not \(e)") }
            tab = e
        }

        if ["help", "-h", "--help"].contains(verb) {
            if let v = rest.first, let u = verbs.first(where: { $0.name == v }) { return ("help", ["text": "safari " + u.usage], nil) }
            return ("help", ["text": help], nil)
        }
        guard let keys = allowed[verb] else { throw Usage(msg: "unknown verb \(verb); `safari help` lists them") }
        let usage = "usage: safari " + (verbs.first { $0.name == verb }?.usage ?? verb)
        func bad(_ m: String) -> Usage { Usage(msg: m + "\n" + usage) }
        if tab != nil, global.contains(verb) { throw bad("\(verb) takes no tab id") }
        if tab == nil, verb == "crawl" || verb == "record" || (verb == "close" && !rest.contains("--agents")) { throw bad("\(verb) needs a tab id") }
        if tab != nil, verb == "close", rest.contains("--agents") { throw bad("close --agents takes no tab id") }

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
        /// Seconds between page loads: "10" or "8-14".
        func delay() throws {
            guard let v = o["delay"] else { return }
            guard let r = Rate.Rule(v) else { throw bad("--delay is seconds, e.g. 10 or 8-14") }
            args["delay"] = [r.lo, r.hi]
        }
        /// -o FILE gets the whole result unless --max says otherwise.
        func outAll() { if o["out"] != nil, o["max_chars"] == nil { args["max_chars"] = 0 } }

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
            if f.contains("window") { args["window"] = true }
            if f.contains("idonly") { args["idonly"] = true }
            try delay()
            return ("tabs", args, nil)
        case "show", "close":
            try noMore()
            args["action"] = verb == "show" ? "select" : f.contains("agents") ? "closeagents" : "close"
            return ("tabs", args, nil)
        case "route":
            if f.contains("list") {
                try noMore()
                if !o.isEmpty || f.count > 1 { throw bad("--list takes nothing else") }
                args["action"] = "list"
                return ("route", args, nil)
            }
            args["pattern"] = try one("a URL pattern (glob like '*/api/*', a substring, or re:REGEX)")
            args["action"] = "add"
            if f.contains("block") {
                if o["status"] != nil || o["body"] != nil || o["ctype"] != nil { throw bad("--block takes no --status, --body or --type") }
                args["block"] = true
            }
            if let v = o["status"] {
                guard let n = Int(v), (200...599).contains(n) else { throw bad("--status must be an HTTP status, 200-599") }
                args["status"] = n
            }
            if var b = o["body"] {
                if b.hasPrefix("@") {
                    let path = (String(b.dropFirst()) as NSString).expandingTildeInPath
                    guard let d = FileManager.default.contents(atPath: path), let t = String(data: d, encoding: .utf8) else { throw bad("cannot read \(b.dropFirst()) as text") }
                    b = t
                }
                guard b.utf8.count <= 1_000_000 else { throw bad("--body is limited to 1 MB") }
                args["body"] = b
            }
            if let t = o["ctype"] { args["ctype"] = t }
            if let p = args["pattern"] as? String, p.hasPrefix("re:"), (try? NSRegularExpression(pattern: String(p.dropFirst(3)))) == nil { throw bad("bad regular expression after re:") }
            return ("route", args, nil)
        case "storage":
            if let p = pos.first, p == "local" || p == "session" { args["area"] = p; pos.removeFirst() }
            if f.contains("clear") || o["del"] != nil {
                try noMore()
                if f.contains("clear") && o["del"] != nil { throw bad("give --delete KEY or --clear, not both") }
                if f.contains("clear") { args["clear"] = true } else { args["del"] = o["del"] }
                return ("storage", args, nil)
            }
            guard pos.count <= 2 else { throw bad("storage takes a key and a value (quote values with spaces)") }
            if let k = pos.first { args["key"] = k }
            if pos.count == 2 { args["value"] = pos[1] }
            try int("max_chars")
            return ("storage", args, nil)
        case "drop":
            try target(required: true)
            if let t = o["text"] { args["dtext"] = t }
            guard !pos.isEmpty || args["dtext"] != nil else { throw bad("drop needs file paths or --text") }
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            if !pos.isEmpty { args["text"] = pos.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, relativeTo: cwd).standardizedFileURL.path }.joined(separator: ",") }
            args["action"] = "drop"
            return ("act", args, nil)
        case "record":
            try noMore()
            if f.contains("stop") { args["stop"] = true }
            return ("record", args, nil)
        case "unroute":
            guard pos.count <= 1 else { throw bad("unroute takes one pattern, or none for all") }
            if let p = pos.first { args["pattern"] = p }
            args["action"] = "remove"
            return ("route", args, nil)
        case "locator":
            try target(required: true)
            try noMore()
            return ("locator", args, nil)
        case "highlight":
            if f.contains("hide") {
                try noMore()
                if o["ref"] != nil || o["selector"] != nil || o["xy"] != nil || o["secs"] != nil { throw bad("--hide takes nothing else") }
                args["hide"] = true
                return ("highlight", args, nil)
            }
            try target(required: true)
            try noMore()
            if let v = o["secs"] {
                guard let n = Double(v), n >= 0, n <= 600 else { throw bad("--for is seconds, 0-600") }
                args["secs"] = n
            }
            return ("highlight", args, nil)
        case "resize":
            guard pos.count == 2, let w = Int(pos[0]), let h = Int(pos[1]), (200...8000).contains(w), (200...8000).contains(h) else {
                throw bad("resize needs the viewport width and height in px (200-8000), e.g. resize 390 844")
            }
            args["action"] = "resize"
            args["width"] = w
            args["height"] = h
            return ("tabs", args, nil)
        case "go":
            args["url"] = try one("a URL, back, forward or reload")
            try delay()
            return ("navigate", args, nil)
        case "read", "text", "links":
            try noMore()
            args["mode"] = verb == "read" ? (f.contains("all") ? "all" : "interactive") : verb
            for k in ["query", "ref", "selector"] { if let v = o[k] { args[k] = v } }
            for k in ["full", "diff"] where f.contains(k) { args[k] = true }
            try int("max_chars")
            try int("offset")
            outAll()
            return ("read", args, o["out"])
        case "table":
            try noMore()
            for k in ["ref", "selector", "rows"] { if let v = o[k] { args[k] = v } }
            if args["ref"] != nil, args["selector"] != nil { throw bad("give --ref or --sel, not both") }
            if f.contains("json") { args["json"] = true }
            try int("max_chars")
            try int("offset")
            outAll()
            return ("table", args, o["out"])
        case "crawl":
            try noMore()
            for k in ["selector", "rows", "next"] { if let v = o[k] { args[k] = v } }
            if f.contains("json") { args["json"] = true }
            try int("pages")
            if let p = args["pages"] as? Int, p < 1 || p > 100 { throw bad("--pages must be 1-100") }
            try delay()
            return ("crawl", args, o["out"])
        case "rate":
            guard pos.count <= 2 else { throw bad("rate takes a site and seconds") }
            if let s = pos.first { args["site"] = s }
            if pos.count == 2 {
                guard pos[1] == "off" || Rate.Rule(pos[1]) != nil else { throw bad("give seconds, e.g. 10 or 8-14, or off") }
                args["range"] = pos[1]
            }
            return ("rate", args, nil)
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
        case "check", "uncheck":
            try target(required: true)
            try noMore()
            args["action"] = "check"
            args["text"] = verb == "check" ? "true" : "false"
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
            if f.contains("load") {
                if args["text"] != nil || args["ref"] != nil || args["selector"] != nil || f.contains("gone") { throw bad("--load waits for the page alone") }
                args["load"] = true
            } else if args["text"] == nil, args["ref"] == nil, args["selector"] == nil { throw bad("wait needs text, --ref, --sel or --load") }
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
            // An element after the code (a ref, --sel or --xy) is `el` in the code.
            if pos.count >= 2, let last = pos.last, isRef(last) { args["ref"] = last; pos.removeLast() }
            if let r = o["ref"] { args["ref"] = r }
            if let s = o["selector"] { args["selector"] = s }
            if [args["ref"], args["selector"], o["xy"]].compactMap({ $0 }).count > 1 { throw bad("give one element: a ref, --sel or --xy") }
            if let xy = o["xy"] {
                let v = try nums(xy, 2, "--xy")
                args["x"] = v[0]
                args["y"] = v[1]
            }
            if let r = args["ref"] as? String, r.hasPrefix("f") { throw bad("js runs in the top frame; a ref inside a frame cannot be `el`") }
            var code = pos.joined(separator: " ")
            if pos.isEmpty || pos == ["-"] {
                code = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            }
            guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw bad("js needs code (or - to read it from stdin)") }
            args["code"] = code
            try int("max_chars")
            outAll()
            return ("js", args, o["out"])
        case "shot":
            if let p = pos.first, isRef(p) { args["ref"] = p; pos.removeFirst() }
            if let r = o["ref"] { args["ref"] = r }
            if let r = args["ref"] as? String, r.hasPrefix("f") { throw bad("shot cannot crop to a ref inside a frame; crop to the frame with --sel iframe, or use --region") }
            if let s = o["selector"] { args["selector"] = s }
            try noMore()
            if let r = o["region"] { args["region"] = try nums(r, 4, "--region") }
            if f.contains("full") {
                if args["ref"] != nil || args["selector"] != nil || args["region"] != nil { throw bad("--full takes the whole page; no element or --region") }
                args["full"] = true
            }
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
