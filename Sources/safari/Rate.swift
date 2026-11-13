import Foundation

/// Per-site pacing for navigations (`safari rate`, `go --delay`). The daemon only hands out
/// time slots; the client sleeps until its slot, so the shared daemon never blocks and two
/// agents crawling one site queue behind each other.
final class Rate {
    struct Rule {
        var lo: Double
        var hi: Double
        var text: String { lo == hi ? "\(fmt(lo)) s" : "\(fmt(lo))-\(fmt(hi)) s" }
        private func fmt(_ d: Double) -> String { String(format: "%g", d) }

        /// "8-14", "10", "2.5-4"; nil when it does not parse.
        init?(_ s: String) {
            let p = s.split(separator: "-", omittingEmptySubsequences: false).map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard (1...2).contains(p.count), let a = p.first ?? nil, let b = p.last ?? nil, a >= 0, b >= a, b <= 600 else { return nil }
            lo = a
            hi = b
        }
        init(lo: Double, hi: Double) { self.lo = lo; self.hi = max(lo, hi) }
    }

    /// Rules the user set; saved in rate.json.
    private var rules: [String: Rule] = [:]
    /// Rules made by backoff for sites without one; this daemon only.
    private var session: [String: Rule] = [:]
    /// Backoff factor per site after bot checks and 429/503 answers; this daemon only.
    private var boost: [String: Double] = [:]
    /// When each site's next navigation may start.
    private var next: [String: Date] = [:]
    private let file = Paths.dir + "/rate.json"

    init() {
        guard let d = FileManager.default.contents(atPath: file),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: String] else { return }
        for (k, v) in o { if let r = Rule(v) { rules[k] = r } }
    }

    private func save() {
        let o = rules.mapValues { $0.lo == $0.hi ? String(format: "%g", $0.lo) : String(format: "%g-%g", $0.lo, $0.hi) }
        if let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) {
            try? d.write(to: URL(fileURLWithPath: file), options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file)
        }
    }

    /// "WWW.Example.com" → "example.com".
    static func site(_ host: String) -> String {
        var h = host.lowercased()
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }

    /// The rule key covering a host: the host itself or the longest parent domain with a rule.
    private func key(_ host: String) -> String {
        let h = Rate.site(host)
        let keys = Set(rules.keys).union(session.keys)
        return keys.filter { h == $0 || h.hasSuffix("." + $0) }.max { $0.count < $1.count } ?? h
    }

    private func rule(_ k: String) -> Rule? { rules[k] ?? session[k] }

    /// Reserves the site's next slot. `override` (go --delay) beats the saved rule; `fallback`
    /// (crawl's default) applies only when there is none. Nil when the site is not paced.
    func reserve(host: String, override: Rule?, fallback: Rule?) -> (wait: Double, key: String)? {
        let k = key(host)
        guard let r = override ?? rule(k) ?? fallback else { return nil }
        let f = boost[k] ?? 1
        let now = Date()
        let start = max(now, next[k] ?? now)
        next[k] = start.addingTimeInterval(Double.random(in: r.lo...r.hi) * f)
        return (start.timeIntervalSince(now), k)
    }

    /// The site showed a bot check or answered 429/503: double its pace for this session
    /// (a site without a rule gets 4-8 s). Returns a note for the result line.
    func backoff(host: String) -> String {
        guard !host.isEmpty else { return "" }
        let k = key(host)
        if rule(k) == nil {
            session[k] = Rule(lo: 4, hi: 8)
        } else {
            let r = rule(k)!
            boost[k] = min((boost[k] ?? 1) * 2, max(1, 60 / max(r.hi, 0.1)))
        }
        let r = rule(k)!, f = boost[k] ?? 1
        next[k] = max(next[k] ?? Date(), Date().addingTimeInterval(r.lo * f))
        return " (pacing \(k): " + Rule(lo: r.lo * f, hi: r.hi * f).text + " between pages)"
    }

    /// `safari rate [SITE [RANGE|off]]`.
    func command(_ a: [String: Any]) throws -> String {
        guard let site = (a["site"] as? String).map({ Rate.site($0.contains("://") ? URL(string: $0)?.host ?? $0 : $0) }) else { return list() }
        guard let v = a["range"] as? String else {
            return rule(key(site)).map { "\(key(site)) \(pacing(key(site), $0))" } ?? "\(site) not paced"
        }
        if v == "off" || v == "0" {
            let had = rules.removeValue(forKey: site) != nil || session.removeValue(forKey: site) != nil
            boost[site] = nil
            next[site] = nil
            save()
            return had ? "\(site) no longer paced" : "\(site) was not paced"
        }
        guard let r = Rule(v) else { throw ToolError("give seconds between pages, e.g. 10 or 8-14, or off") }
        rules[site] = r
        session[site] = nil
        boost[site] = nil
        save()
        return "\(site) \(r.text) between pages"
    }

    private func pacing(_ k: String, _ r: Rule) -> String {
        let f = boost[k] ?? 1
        if rules[k] == nil { return Rule(lo: r.lo * f, hi: r.hi * f).text + " (temporary, after bot checks)" }
        return r.text + (f > 1 ? ", now " + Rule(lo: r.lo * f, hi: r.hi * f).text + " after bot checks" : "")
    }

    private func list() -> String {
        let all = Set(rules.keys).union(session.keys).sorted()
        if all.isEmpty { return "(no sites paced; safari rate SITE 8-14)" }
        return all.map { "\($0) \(pacing($0, rule($0)!))" }.joined(separator: "\n")
    }
}
