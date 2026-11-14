import Foundation

/// `safari --selftest`: checks the pure functions, with no Safari, daemon, network or files.
/// Hooked into Tests/smoke.sh so a wrong expectation fails without a browser.
enum SelfTest {
    static func run() -> Int32 {
        var total = 0, failed = 0

        func eq<T: Equatable>(_ name: String, _ got: T, _ want: T) {
            total += 1
            guard got == want else {
                failed += 1
                print("FAIL \(name): got \(got), want \(want)")
                return
            }
        }
        /// What a command line parses to; nil (and a failure) when it throws.
        func parse(_ name: String, _ argv: [String]) -> (tool: String, args: [String: Any], out: String?)? {
            total += 1
            do { return try CLI.parse(argv) } catch {
                failed += 1
                print("FAIL \(name): got \(error), want a parse")
                return nil
            }
        }
        /// A command line that must be rejected with Usage.
        func usage(_ name: String, _ argv: [String]) {
            total += 1
            do {
                let (tool, args, _) = try CLI.parse(argv)
                failed += 1
                print("FAIL \(name): got tool \(tool) \(args), want Usage")
            } catch is Usage {
            } catch {
                failed += 1
                print("FAIL \(name): got \(error), want Usage")
            }
        }

        // Tools.topLevelReturn: a return of the expression's own, not one in a block or a word.
        eq("return 1", Tools.topLevelReturn("return 1"), true)
        eq("var a=1; return a", Tools.topLevelReturn("var a=1; return a"), true)
        eq("if(x){y()} return z", Tools.topLevelReturn("if(x){y()} return z"), true)
        eq("1+1", Tools.topLevelReturn("1+1"), false)
        eq("document.title", Tools.topLevelReturn("document.title"), false)
        eq("return in a block", Tools.topLevelReturn("xs.map(x => { return x })"), false)
        eq("return in a string", Tools.topLevelReturn("\"return\""), false)
        eq("return in a line comment", Tools.topLevelReturn("// return\n1"), false)
        eq("return in a block comment", Tools.topLevelReturn("/* return */ 2"), false)
        eq("a.return", Tools.topLevelReturn("a.return"), false)
        eq("returned", Tools.topLevelReturn("returned"), false)
        eq("myreturn", Tools.topLevelReturn("myreturn"), false)

        // Tools.ruleRegex: re: passes through, a glob is anchored, plain text is escaped.
        eq("re: passes the regex", Tools.ruleRegex("re:^a.*b$"), "^a.*b$")
        eq("a.b without a star", Tools.ruleRegex("a.b"), "a\\.b")
        eq("*/api/* is anchored", Tools.ruleRegex("*/api/*"), "^.*\\/api\\/.*$")

        // Tools.origin: scheme, host and port only.
        eq("origin of a page URL", Tools.origin("https://example.com/a?b"), "https://example.com")
        eq("origin keeps the port", Tools.origin("http://127.0.0.1:8765/x"), "http://127.0.0.1:8765")
        eq("origin of nil", Tools.origin(nil), String?.none)
        eq("origin of about:blank", Tools.origin("about:blank"), String?.none)

        // Tools.marker: the mock's id, the last path segment of its URL.
        eq("mock marker", Tools.marker(["url": "http://127.0.0.1:47401/m/abc123"]), "__smcp_m=abc123")

        // Client.split: \u{1E} lines are notes, the rest is the data.
        let plain = Client.split("a\nb")
        eq("split keeps text", plain.data, "a\nb")
        eq("split finds no notes", plain.notes, [])
        let noted = Client.split("a\n\u{1E}note one\nb\n\u{1E}note two")
        eq("split drops the notes from data", noted.data, "a\nb")
        eq("split returns the notes", noted.notes, ["note one", "note two"])

        // Rate.Rule: "10", "8-14", "2.5-4"; nil otherwise.
        eq("rule 10 lo", Rate.Rule("10")?.lo, Optional(10.0))
        eq("rule 10 hi", Rate.Rule("10")?.hi, Optional(10.0))
        eq("rule 8-14 lo", Rate.Rule("8-14")?.lo, Optional(8.0))
        eq("rule 8-14 hi", Rate.Rule("8-14")?.hi, Optional(14.0))
        eq("rule 2.5-4 lo", Rate.Rule("2.5-4")?.lo, Optional(2.5))
        eq("rule 2.5-4 hi", Rate.Rule("2.5-4")?.hi, Optional(4.0))
        eq("rule 10 text", Rate.Rule("10")?.text, Optional("10 s"))
        eq("rule 8-14 text", Rate.Rule("8-14")?.text, Optional("8-14 s"))
        for s in ["soon", "14-8", "-5", "1-2-3", "601", ""] {
            eq("rule \(s.isEmpty ? "\"\"" : s) is nil", Rate.Rule(s) == nil, true)
        }

        // Rate holds (after a block page): per site and its subdomains, until they expire or reset.
        let rate = Rate(persist: false)
        eq("not held", rate.heldFor(host: "cimri.com") == nil, true)
        eq("hold key", rate.hold(host: "www.cimri.com", for: 900), "cimri.com")
        eq("held site", rate.heldFor(host: "cimri.com")?.key, Optional("cimri.com"))
        eq("held subdomain", rate.heldFor(host: "m.cimri.com")?.key, Optional("cimri.com"))
        eq("held for 15 min", (rate.heldFor(host: "cimri.com")?.secs ?? 0) > 890, true)
        eq("other site not held", rate.heldFor(host: "example.com") == nil, true)
        eq("rate list shows the hold", (try? rate.command([:])) ?? "", "cimri.com held 15 min")
        eq("reset ends the hold", rate.reset("cimri.com"), true)
        eq("not held after reset", rate.heldFor(host: "cimri.com") == nil, true)
        eq("reset again finds nothing", rate.reset("cimri.com"), false)
        rate.hold(host: "x.org", for: -1)
        eq("an expired hold is gone", rate.heldFor(host: "x.org") == nil, true)
        _ = try? rate.command(["site": "y.org", "range": "5"])
        rate.hold(host: "y.org", for: 60)
        eq("rate SITE reset keeps the saved rule", (try? rate.command(["site": "y.org", "range": "reset"])) ?? "", "y.org: hold and temporary slowdown ended; keeps 5 s between pages")
        eq("…and the rule stays", (try? rate.command(["site": "y.org"])) ?? "", "y.org 5 s")

        // Tools.withScheme: http for this machine, https for the rest, a scheme kept.
        for (u, w) in [("cimri.com/arama?q=a:b", "https://cimri.com/arama?q=a:b"), ("example.com", "https://example.com"),
                       ("localhost:8765/x", "http://localhost:8765/x"), ("localhost", "http://localhost"), ("127.0.0.1:8765/a", "http://127.0.0.1:8765/a"),
                       ("[::1]:3000/", "http://[::1]:3000/"), ("http://a.b/c", "http://a.b/c"), ("HTTPS://A.b", "HTTPS://A.b"),
                       ("about:blank", "about:blank"), ("data:text/html,x", "data:text/html,x"), ("javascript:void(0)", "javascript:void(0)"),
                       ("blob:https://a.b/1", "blob:https://a.b/1"), ("localhost.example.com", "https://localhost.example.com")] {
            eq("withScheme \(u)", Tools.withScheme(u), w)
        }
        // Tools.isLoopback: no 2-4 s pace floor for a server on this machine.
        for (u, w) in [("http://localhost:8765/", true), ("http://127.0.0.1:8765/", true), ("http://127.1.2.3/", true), ("http://[::1]:3000/", true),
                       ("https://example.com/", false), ("https://localhost.example.com/", false), ("https://127.example.com/", false)] {
            eq("isLoopback \(u)", Tools.isLoopback(URL(string: u)?.host ?? ""), w)
        }

        // Rate.site: lowercase, without a leading www.
        eq("site strips www", Rate.site("WWW.Example.com"), "example.com")
        eq("site keeps a subdomain", Rate.site("sub.example.com"), "sub.example.com")

        // CLI.isRef / CLI.isTab: e12 and f1e5 are refs, t3 a tab.
        for r in ["e12", "f1e5"] { eq("isRef \(r)", CLI.isRef(r), true) }
        for r in ["e", "12", "t3", "e12x", "fe5"] { eq("isRef \(r)", CLI.isRef(r), false) }
        eq("isTab t3", CLI.isTab("t3"), true)
        for t in ["t", "3", "e3"] { eq("isTab \(t)", CLI.isTab(t), false) }

        // CLI.parse: negative numbers are values, "--" ends options, --max=N is inline.
        if let a = parse("scroll -400", ["t5", "scroll", "-400"])?.args {
            eq("scroll -400 has dy", a["dy"] as? Double, Optional(-400.0))
        }
        if let a = parse("read --max=300", ["t5", "read", "--max=300"])?.args {
            eq("read --max=300", a["max_chars"] as? Int, Optional(300))
        }
        usage("click -- -weird is no ref", ["t5", "click", "--", "-weird"])
        usage("unknown verb", ["frob"])

        // --json: any verb, anywhere before "--"; after it, it is text.
        if let a = parse("read --json", ["t5", "read", "--json"])?.args { eq("read --json", a["json"] as? Bool, Optional(true)) }
        if let a = parse("--json first", ["--json", "t5", "click", "e3"])?.args {
            eq("--json first: still a click", a["action"] as? String, Optional("click"))
            eq("--json first", a["json"] as? Bool, Optional(true))
        }
        if let a = parse("fill -- --json", ["t5", "fill", "e4", "--", "--json"])?.args {
            eq("fill -- --json is the text", a["text"] as? String, Optional("--json"))
            eq("fill -- --json is no flag", a["json"] == nil, true)
        }
        eq("wantsJSON stops at --", CLI.wantsJSON(["t5", "type", "--", "--json"]), false)

        // Out.envelope: fixed key order, no empty notes, nav only when true, nested rows.
        eq("envelope order", Out.envelope(["notes": ["n"], "text": "x", "tab": "t5", "ok": true, "url": "https://a.b/", "title": "A", "nav": true]),
           #"{"ok":true,"tab":"t5","url":"https://a.b/","title":"A","nav":true,"text":"x","notes":["n"]}"#)
        eq("envelope drops empty notes and nav false", Out.envelope(["ok": true, "text": "", "notes": [String](), "nav": false]), #"{"ok":true,"text":""}"#)
        eq("envelope rows", Out.envelope(["ok": true, "rows": [["a": "1"]], "pages": 2]), #"{"ok":true,"rows":[{"a":"1"}],"pages":2}"#)
        eq("envelope error", Out.envelope(["error": "Tab t9 is gone", "ok": false, "kind": "gone", "tab": "t9"]),
           #"{"ok":false,"kind":"gone","error":"Tab t9 is gone","tab":"t9"}"#)

        print("selftest: \(total) checks, \(failed) failed")
        return failed == 0 ? 0 : 1
    }
}
