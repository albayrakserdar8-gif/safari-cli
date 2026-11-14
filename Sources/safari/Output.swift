import Darwin

/// Everything the client prints goes through here: data to stdout, flushed at once, notes and
/// errors to stderr. When both go to the same pipe or file (a script runner that merges them),
/// notes are held until the data is out and marked `note: `, so they never land inside the data.
/// With `--json` (`json`) nothing is printed until `end`, which writes one JSON object to stdout
/// (`envelope`) and nothing to stderr.
enum Out {
    static let merged: Bool = {
        var o = stat(), e = stat()
        guard fstat(1, &o) == 0, fstat(2, &e) == 0 else { return false }
        return o.st_dev == e.st_dev && o.st_ino == e.st_ino && isatty(2) == 0
    }()
    /// `--json`: set before the command line is parsed, so usage errors are JSON too.
    static var json = false
    /// Envelope fields besides ok/error/text/notes (tab, url, title, nav, rows, pages, file, chars,
    /// files), set by whoever has them. Only used with `json`.
    static var fields: [String: Any] = [:]
    private static var held: [String] = []
    private static var text: [String] = []
    private static var failure: (msg: String, kind: String, tab: String?)?

    /// A piece of the result, ended with a newline.
    static func data(_ s: String) {
        if json { text.append(s.hasSuffix("\n") ? String(s.dropLast()) : s); return }
        fputs(s.hasSuffix("\n") ? s : s + "\n", stdout)
        fflush(stdout)
    }

    /// A note about the result (continuation hint, row count, progress): stderr at once, or after
    /// the data when the streams are merged.
    static func note(_ s: String) {
        if merged || json { held.append(s) } else { err(s) }
    }

    /// A message for whoever watches stderr, not part of the result (with `json`, a note).
    static func err(_ s: String) {
        if json { held.append(s.hasSuffix("\n") ? String(s.dropLast()) : s); return }
        fputs(s.hasSuffix("\n") ? s : s + "\n", stderr)
    }

    /// The command failed: the message on stderr. `kind` and `tab` say what failed where, for
    /// callers that read a structured reply. Returns `code` (1 unless given) for the exit status.
    @discardableResult
    static func fail(_ msg: String, code: Int32 = 1, kind: String = "error", tab: String? = nil) -> Int32 {
        if json { failure = (msg, kind, tab) } else { err(msg) }
        return code
    }

    /// Ends the command: notes held back go out after the data, then the process exits.
    static func end(_ code: Int32) -> Never {
        if json {
            var f = fields
            if let x = failure ?? (code != 0 ? (held.last ?? "failed", "error", nil) : nil) {
                f["ok"] = false
                f["kind"] = x.kind
                f["error"] = x.msg
                if let t = x.tab { f["tab"] = t }
            } else {
                f["ok"] = true
            }
            if f["text"] == nil, !text.isEmpty { f["text"] = text.joined(separator: "\n") }
            f["notes"] = held
            fputs(envelope(f) + "\n", stdout)
            fflush(stdout)
            exit(code)
        }
        fflush(stdout)
        for n in held { err("note: " + n) }
        held = []
        exit(code)
    }

    /// The `--json` object, keys in a fixed order: ok, kind, error, tab, url, title, nav, text, rows,
    /// pages, file, chars, files, notes, then any others sorted. `nav` only when true, `notes` only
    /// when there are some.
    static func envelope(_ f: [String: Any]) -> String {
        let order = ["ok", "kind", "error", "tab", "url", "title", "nav", "text", "rows", "pages", "file", "chars", "files", "notes"]
        var parts: [String] = []
        for k in order + f.keys.filter({ !order.contains($0) }).sorted() {
            guard let v = f[k] else { continue }
            if k == "nav", v as? Bool != true { continue }
            if k == "notes", (v as? [String])?.isEmpty ?? true { continue }
            parts.append(jsonString(k) + ":" + jsonString(v))
        }
        return "{" + parts.joined(separator: ",") + "}"
    }
}
