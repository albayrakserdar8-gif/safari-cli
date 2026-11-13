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

        print("selftest: \(total) checks, \(failed) failed")
        return failed == 0 ? 0 : 1
    }
}
