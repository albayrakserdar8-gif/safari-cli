import Foundation

/// `safari T crawl`: table → next page → table…, merged into one TSV (or JSON array).
/// The loop runs here in the client, so every page load goes through the site's pacing slot
/// and the shared daemon is never held for the whole crawl.
enum Crawl {
    /// The next page's URL: rel=next, else a visible link or button named like "Next"/"Sonraki"
    /// (or exactly the --next text). Empty when there is none.
    private static func nextJS(_ q: String?) -> String {
        """
        var q=\(jsonString(q ?? "")).toLowerCase(),d=document;
        function nm(e){return((e.innerText||'')+'').trim().toLowerCase()||(e.getAttribute('aria-label')||e.title||'').trim().toLowerCase()}
        function ok(e){return e.getClientRects().length>0&&(e.href||e.getAttribute('data-href'))&&!/disabled/.test(e.className+'')&&e.getAttribute('aria-disabled')!=='true'}
        var all=[].filter.call(d.querySelectorAll('a[href]'),ok),a=null;
        if(q){a=all.find(function(e){return nm(e)===q})||all.find(function(e){return nm(e).indexOf(q)===0})||all.find(function(e){return nm(e).indexOf(q)>=0})}
        else{a=d.querySelector('a[rel~=next][href],link[rel~=next][href]');
          if(!a)a=all.find(function(e){return/^(next|next page|sonraki|sonraki sayfa|ileri|weiter|suivant|siguiente|›|»|>)$/.test(nm(e))})}
        return a?(a.href||''):''
        """
    }

    static func run(_ args: [String: Any], out: String?) -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        guard let tab = args["tab"] as? String else { return fail("safari: crawl needs a tab id") }
        let pages = args["pages"] as? Int ?? 5
        let json = args["json"] as? Bool == true
        var tableArgs: [String: Any] = ["tab": tab, "max_chars": 0]
        for k in ["selector", "rows", "json"] { if let v = args[k] { tableArgs[k] = v } }

        var header: [String]?
        var rows: [[String]] = []
        var objs: [[String: Any]] = []
        var seen = Set<String>()
        var visited = Set<String>()
        var status: Int32 = 0

        func note(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

        do {
            // A page that adds no new rows (a "Next" link back to the same content) does not count;
            // two of them in a row end the crawl.
            var p = 0, loads = 0, empty = 0
            while p < pages && loads < pages + 3 {
                loads += 1
                let r = try Client.send("table", tableArgs)
                guard r["ok"] as? Bool == true else {
                    note("safari: page \(p + 1): " + Client.split(r["text"] as? String ?? "").data)
                    status = 1
                    break
                }
                let data = Client.split(r["text"] as? String ?? "").data
                var added = 0, total = 0
                if json {
                    let list = (try? JSONSerialization.jsonObject(with: Data(data.utf8))) as? [[String: Any]] ?? []
                    total = list.count
                    for o in list {
                        let k = (o["id"] as? String).map { "id:" + $0 } ?? jsonString(o)
                        if seen.insert(k).inserted { objs.append(o); added += 1 }
                    }
                } else {
                    let lines = data.split(separator: "\n", omittingEmptySubsequences: false).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
                    guard let h = lines.first else { break }
                    if header == nil { header = h } else if header! != h { note("safari: page \(p + 1) has other columns: \(h.joined(separator: ", "))") }
                    let idCol = h.lastIndex(of: "id")
                    for l in lines.dropFirst() where !(l.count == 1 && l[0].isEmpty) {
                        total += 1
                        let k = idCol.flatMap { $0 < l.count && !l[$0].isEmpty ? "id:" + l[$0] : nil } ?? l.joined(separator: "\t")
                        if seen.insert(k).inserted { rows.append(l); added += 1 }
                    }
                }
                if added == 0 && loads > 1 {
                    empty += 1
                    note("same rows again (\(total), 0 new); not counted")
                    if empty >= 2 { note("no new rows; done"); break }
                } else {
                    empty = 0
                    p += 1
                    note("page \(p)/\(pages) · \(total) rows, \(added) new")
                }
                if p == pages { break }

                let nx = try Client.send("js", ["tab": tab, "code": "return (function(){" + nextJS(args["next"] as? String) + "})()"])
                // Some sites escape their hrefs twice (`&amp;amp;`), which leaves `&amp;` in the URL.
                let next = (nx["ok"] as? Bool == true ? Client.split(nx["text"] as? String ?? "").data : "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "&amp;", with: "&")
                guard next.hasPrefix("http") else { note("no next page; done"); break }
                guard visited.insert(next).inserted else { note("next page already visited; done"); break }

                var go: [String: Any] = ["tab": tab, "url": next, "fallback": [3.0, 6.0]]
                if let d = args["delay"] { go["delay"] = d }
                let (waited, _) = try Client.pace("navigate", &go)
                let g = try Client.send("navigate", go)
                guard g["ok"] as? Bool == true else {
                    note("safari: " + Client.split(g["text"] as? String ?? "").data)
                    status = 1
                    break
                }
                let line = Client.split(g["text"] as? String ?? "").data
                note("→ " + line + (waited >= 0.5 ? " (waited \(String(format: "%.1f", waited)) s)" : ""))
            }
        } catch let f as Client.Failure {
            note(f.msg)
            status = 1
        } catch {
            note("safari: \(error)")
            status = 1
        }

        let text: String
        if json {
            text = jsonString(objs)
        } else {
            text = ([header ?? []] + rows).map { $0.joined(separator: "\t") }.joined(separator: "\n")
        }
        let count = json ? objs.count : rows.count
        if let out {
            let path = (out as NSString).expandingTildeInPath
            do { try Data((text + "\n").utf8).write(to: URL(fileURLWithPath: path)) } catch {
                return fail("safari: cannot write \(path): \(error.localizedDescription)")
            }
            print("wrote \(count) rows → \(path)")
        } else if count > 0 || header != nil {
            print(text)
        }
        return status
    }

    private static func fail(_ msg: String) -> Int32 {
        FileHandle.standardError.write(Data((msg + "\n").utf8))
        return 1
    }
}
