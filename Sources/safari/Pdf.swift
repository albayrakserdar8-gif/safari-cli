import AppKit
import WebKit

/// `safari T pdf [-o FILE]`: a snapshot of the page's current DOM, rendered by WebKit here in
/// the client with JavaScript off and printed to a paged PDF. Safari stays in the background
/// and the shared daemon only serves one `js` call.
enum Pdf {
    /// The page as static HTML: form state written into attributes, canvases as images,
    /// CSSOM-only styles (CSS-in-JS) as text, lazy images resolved, scripts and handlers removed.
    private static let snapshotJS = """
        var D=document,d=D.documentElement.cloneNode(true),q=function(r,s){return[].slice.call(r.querySelectorAll(s))};
        var fs=q(D,'input,textarea,select'),fd=q(d,'input,textarea,select');
        fs.forEach(function(e,i){var c=fd[i];if(!c)return;
          if(e.tagName==='TEXTAREA')c.textContent=e.value;
          else if(e.tagName==='SELECT')[].forEach.call(c.options,function(o,j){if(e.options[j]&&e.options[j].selected)o.setAttribute('selected','');else o.removeAttribute('selected')});
          else if(/^(checkbox|radio)$/i.test(e.type)){if(e.checked)c.setAttribute('checked','');else c.removeAttribute('checked')}
          else if(!/^(password|file)$/i.test(e.type))c.setAttribute('value',e.value)});
        var is=q(D,'img'),id=q(d,'img');is.forEach(function(e,i){var c=id[i];if(!c)return;if(e.currentSrc)c.setAttribute('src',e.currentSrc);c.removeAttribute('srcset');c.removeAttribute('loading')});
        q(d,'picture source').forEach(function(e){e.remove()});
        var ss=q(D,'style'),sd=q(d,'style');ss.forEach(function(e,i){try{var r=e.sheet&&e.sheet.cssRules;if(r&&sd[i]&&!e.textContent.trim())sd[i].textContent=[].map.call(r,function(x){return x.cssText}).join('\\n')}catch(x){}});
        try{var ad=(D.adoptedStyleSheets||[]).map(function(s){return[].map.call(s.cssRules,function(x){return x.cssText}).join('\\n')}).join('\\n');if(ad){var st=D.createElement('style');st.textContent=ad;(d.querySelector('head')||d).appendChild(st)}}catch(x){}
        var cs=q(D,'canvas'),cd=q(d,'canvas');cs.forEach(function(e,i){var c=cd[i];if(!c)return;try{var im=D.createElement('img');im.src=e.toDataURL();var r=e.getBoundingClientRect();im.style.width=r.width+'px';im.style.height=r.height+'px';im.className=e.className;c.replaceWith(im)}catch(x){}});
        q(d,'script,noscript,base,[data-smcp-hl],link[rel=preload],link[rel=modulepreload]').forEach(function(e){e.remove()});
        q(d,'*').forEach(function(e){[].slice.call(e.attributes).forEach(function(a){if(/^on/i.test(a.name))e.removeAttribute(a.name)})});
        var h=d.querySelector('head');if(h){var b=D.createElement('base');b.href=D.baseURI;h.insertBefore(b,h.firstChild)}
        return JSON.stringify({u:location.href,t:D.title,h:'<!DOCTYPE html>'+d.outerHTML})
        """

    static func run(_ args: [String: Any], out: String?) -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        var a: [String: Any] = ["code": snapshotJS, "max_chars": 0]
        if let t = args["tab"] { a["tab"] = t }
        let snap: [String: Any]
        do {
            let r = try Client.send("js", a)
            let data = Client.split(r["text"] as? String ?? "").data
            guard r["ok"] as? Bool == true else { return fail(data.hasPrefix("safari") ? data : "safari: " + data) }
            guard let s = (try? JSONSerialization.jsonObject(with: Data(data.utf8))) as? [String: Any] else {
                return fail("safari: could not read the page")
            }
            snap = s
        } catch let f as Client.Failure {
            return fail(f.msg)
        } catch {
            return fail("safari: \(error)")
        }
        let html = snap["h"] as? String ?? ""
        let base = URL(string: snap["u"] as? String ?? "")
        guard base?.scheme?.hasPrefix("http") == true else { return fail("safari: pdf needs an http(s) page") }

        let path: URL
        if let out {
            path = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
        } else {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("safari-cli")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ms = Int(Date().timeIntervalSince1970 * 1000) % 100_000_000
            path = dir.appendingPathComponent("page-\(args["tab"] as? String ?? "t")-\(ms).pdf")
        }
        try? FileManager.default.removeItem(at: path)

        let r = Renderer(html: html, base: base, to: path)
        if let err = r.run() { return fail("safari: " + err) }
        let pages = CGPDFDocument(path as CFURL)?.numberOfPages ?? 0
        guard pages > 0 else { return fail("safari: the PDF came out empty") }
        Out.data("\(path.path) (\(pages) page\(pages == 1 ? "" : "s")\(r.single ? ", one long page" : ""))")
        return 0
    }

    private static func fail(_ msg: String) -> Int32 { Out.fail(msg) }

    /// Loads the snapshot in an off-screen WKWebView and prints it to `to`.
    private final class Renderer: NSObject, WKNavigationDelegate {
        let html: String, base: URL?, to: URL
        var done = false, error: String?, single = false
        private var window: NSWindow!
        private var web: WKWebView!

        init(html: String, base: URL?, to: URL) {
            self.html = html
            self.base = base
            self.to = to
        }

        func run() -> String? {
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            let info = NSPrintInfo()
            let width = info.paperSize.width - info.leftMargin - info.rightMargin
            let conf = WKWebViewConfiguration()
            conf.defaultWebpagePreferences.allowsContentJavaScript = false
            conf.websiteDataStore = .nonPersistent()
            web = WKWebView(frame: NSRect(x: 0, y: 0, width: max(width, 500), height: 1000), configuration: conf)
            web.navigationDelegate = self
            window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: web.frame.width, height: 1000),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = web
            web.loadHTMLString(html, baseURL: base)
            spin(until: { self.done }, timeout: 20)
            if !done { return "the page did not finish loading in 20 s" }
            if let error { return error }
            // Lazy images and fonts: a moment more.
            spin(until: { false }, timeout: 0.6)

            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = to
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            info.isHorizontallyCentered = false
            info.isVerticallyCentered = false
            let op = web.printOperation(with: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            op.view?.frame = web.bounds
            var printed = false
            onPrinted = { printed = true }
            op.runModal(for: window, delegate: self, didRun: #selector(printDone(_:success:context:)), contextInfo: nil)
            spin(until: { printed && FileManager.default.fileExists(atPath: self.to.path) }, timeout: 20)
            if CGPDFDocument(to as CFURL)?.numberOfPages ?? 0 > 0 { return nil }

            // Fallback: one long page.
            var data: Data?
            var failed: String?
            web.createPDF(configuration: WKPDFConfiguration()) { r in
                switch r {
                case .success(let d): data = d
                case .failure(let e): failed = e.localizedDescription
                }
            }
            spin(until: { data != nil || failed != nil }, timeout: 20)
            guard let data else { return failed ?? "printing timed out" }
            do { try data.write(to: to) } catch { return "cannot write \(to.path): \(error.localizedDescription)" }
            single = true
            return nil
        }

        private var onPrinted: (() -> Void)?
        @objc func printDone(_ op: NSPrintOperation, success: Bool, context: UnsafeMutableRawPointer?) { onPrinted?() }

        private func spin(until ok: () -> Bool, timeout: Double) {
            let end = Date().addingTimeInterval(timeout)
            while !ok(), Date() < end {
                if let e = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.05), inMode: .default, dequeue: true) { NSApp.sendEvent(e) }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done = true }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError e: Error) { error = e.localizedDescription; done = true }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError e: Error) { error = e.localizedDescription; done = true }
    }
}
