import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum Capture {
    /// Screen bounds and owner pid of a window, from the window server.
    static func window(_ wid: Int) -> (bounds: CGRect, pid: pid_t)? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(wid)) as? [[String: Any]],
              let w = list.first,
              let b = w[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: b),
              let pid = w[kCGWindowOwnerPID as String] as? Int else { return nil }
        return (rect, pid_t(pid))
    }

    /// False when the window is on another Space, in a hidden app or minimized: macOS does
    /// not render it then, so it cannot be captured.
    static func onScreen(_ wid: Int) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(wid)) as? [[String: Any]]
        return list?.first?[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = attr(el, kAXPositionAttribute), let s = attr(el, kAXSizeAttribute) else { return nil }
        var pt = CGPoint.zero
        var sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    /// Exact on-screen rect of the page viewport, via Accessibility. Nil without that permission.
    private static func axViewport(pid: pid_t, bounds: CGRect) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        guard let wins = attr(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        guard let win = wins.first(where: { w in
            guard let f = frame(w) else { return false }
            return abs(f.minX - bounds.minX) < 2 && abs(f.minY - bounds.minY) < 2 && abs(f.width - bounds.width) < 2
        }) else { return nil }

        var queue: [(el: AXUIElement, parent: AXUIElement?, depth: Int)] = [(win, nil, 0)]
        var head = 0
        while head < queue.count && head < 1500 {
            let (el, parent, depth) = queue[head]
            head += 1
            if attr(el, kAXRoleAttribute) as? String == "AXWebArea" {
                // The web area spans the whole document; its scroll area is the visible part.
                if let parent, attr(parent, kAXRoleAttribute) as? String == "AXScrollArea", let f = frame(parent) { return f }
                return frame(el)
            }
            if depth < 16, let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
                for k in kids { queue.append((k, el, depth + 1)) }
            }
        }
        return nil
    }

    /// The JavaScript dialog (alert, confirm, prompt) shown in the window's visible tab, found via
    /// Accessibility. With `answer` ("accept", "dismiss", or text for a prompt) it is also answered.
    /// Returns the dialog's message, or nil when there is none or permission is missing.
    static func dialog(wid: Int, answer: String?) -> String? {
        guard AXIsProcessTrusted(), let (bounds, pid) = window(wid) else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 2)
        // While a dialog is up Safari can report an empty window list; the focused window still works.
        var wins = attr(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if let f = attr(app, kAXFocusedWindowAttribute) { wins.append(f as! AXUIElement) }
        guard let win = wins.first(where: { w in
            guard let f = frame(w) else { return false }
            return abs(f.minX - bounds.minX) < 2 && abs(f.minY - bounds.minY) < 2 && abs(f.width - bounds.width) < 2
        }) else { return nil }
        var queue = [(win, 0)], head = 0
        var found: AXUIElement?
        while head < queue.count && head < 400 {
            let (el, depth) = queue[head]
            head += 1
            if attr(el, kAXSubroleAttribute) as? String == "AXDialog" { found = el; break }
            if depth < 5, attr(el, kAXRoleAttribute) as? String != "AXWebArea", let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
                for k in kids { queue.append((k, depth + 1)) }
            }
        }
        guard let dlg = found else { return nil }
        let msg = attr(dlg, kAXValueAttribute) as? String ?? ""
        guard let answer else { return msg }
        let kids = attr(dlg, kAXChildrenAttribute) as? [AXUIElement] ?? []
        let buttons = kids.filter { attr($0, kAXRoleAttribute) as? String == "AXButton" }
        if answer != "accept" && answer != "dismiss",
           let field = kids.first(where: { attr($0, kAXRoleAttribute) as? String == "AXTextField" }) {
            AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, answer as CFString)
        }
        // Safari lists Cancel before OK; an alert has only one button.
        guard let button = answer == "dismiss" ? buttons.first : buttons.last else { return nil }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
        return msg
    }

    /// Viewport rect in screen points. Falls back to assuming all browser chrome is on the
    /// top and left, with no page zoom, when Accessibility is not granted.
    static func viewport(wid: Int, iw: Double, ih: Double) throws -> (rect: CGRect, bounds: CGRect) {
        guard let (bounds, pid) = window(wid) else { throw ToolError("Safari window not found; run tabs.") }
        if let r = axViewport(pid: pid, bounds: bounds) { return (r, bounds) }
        let w = min(iw, Double(bounds.width)), h = min(ih, Double(bounds.height))
        return (CGRect(x: Double(bounds.maxX) - w, y: Double(bounds.maxY) - h, width: w, height: h), bounds)
    }

    /// State shared with ScreenCaptureKit's callbacks. It also keeps the filter and
    /// configuration alive until the capture finishes: with locals, an optimized build
    /// releases them early and the completion handler never fires.
    private final class Grab: @unchecked Sendable {
        private let lock = NSLock()
        private var image: CGImage?
        private var failure = "timed out"
        private var done = false
        var keep: [AnyObject] = []

        func finish(_ image: CGImage?, _ failure: String?) {
            lock.lock()
            self.image = image
            if let failure { self.failure = failure }
            done = true
            lock.unlock()
        }

        var result: (done: Bool, image: CGImage?, failure: String) {
            lock.lock()
            defer { lock.unlock() }
            return (done, image, failure)
        }
    }

    /// Captures in a child process and returns the JPEG. ScreenCaptureKit sometimes never
    /// calls back (for example when the window leaves the screen mid-capture), and a hung
    /// request blocks every later capture from the same process. A child can be killed.
    static func jpeg(wid: Int, bounds: CGRect, crop: CGRect, maxWidth: Int) throws -> (data: Data, width: Int, height: Int) {
        guard let exe = Bundle.main.executableURL else { throw ToolError("Cannot locate the server binary for the screenshot helper.") }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("smcp-\(getpid())-\(wid).jpg")
        defer { try? FileManager.default.removeItem(at: out) }
        func arr(_ r: CGRect) -> [Double] { [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)] }
        let spec: [String: Any] = ["wid": wid, "bounds": arr(bounds), "crop": arr(crop), "maxWidth": maxWidth, "out": out.path]
        let p = Process()
        let pipe = Pipe()
        p.executableURL = exe
        p.arguments = ["--grab", jsonString(spec)]
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        let start = Date()
        while p.isRunning && Date().timeIntervalSince(start) < 6 { usleep(20_000) }
        if p.isRunning {
            kill(p.processIdentifier, SIGKILL)
            throw ToolError("The screenshot timed out, most likely because the Safari window left the screen during capture. Try again.")
        }
        let msg = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dims = msg.split(separator: " ").compactMap { Int($0) }
        guard p.terminationStatus == 0, dims.count == 2, let data = try? Data(contentsOf: out) else {
            throw ToolError(msg.isEmpty ? "The screenshot helper failed." : msg)
        }
        return (data, dims[0], dims[1])
    }

    /// Entry point of the helper process: prints "width height" on success, or the error.
    static func helperMain(_ json: String) -> Int32 {
        func rect(_ v: Any?) -> CGRect? {
            guard let a = v as? [NSNumber], a.count == 4 else { return nil }
            return CGRect(x: a[0].doubleValue, y: a[1].doubleValue, width: a[2].doubleValue, height: a[3].doubleValue)
        }
        guard let spec = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let wid = spec["wid"] as? Int, let bounds = rect(spec["bounds"]), let crop = rect(spec["crop"]),
              let maxWidth = spec["maxWidth"] as? Int, let out = spec["out"] as? String else {
            print("bad helper arguments")
            return 2
        }
        do {
            let r = try render(wid: wid, bounds: bounds, crop: crop, maxWidth: maxWidth)
            try r.data.write(to: URL(fileURLWithPath: out))
            print(r.width, r.height)
            return 0
        } catch let e as ToolError {
            print(e.msg)
            return 1
        } catch {
            print("\(error)")
            return 1
        }
    }

    /// Window image via ScreenCaptureKit, which also works for windows behind others.
    private static func grab(_ wid: Int) throws -> CGImage {
        _ = CGMainDisplayID()  // a command-line process must touch the window server first
        let g = Grab()
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, err in
            guard let w = content?.windows.first(where: { Int($0.windowID) == wid }) else {
                g.finish(nil, err?.localizedDescription ?? "window not found")
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: w)
            let cfg = SCStreamConfiguration()
            cfg.width = Int(w.frame.width * CGFloat(filter.pointPixelScale))
            cfg.height = Int(w.frame.height * CGFloat(filter.pointPixelScale))
            cfg.showsCursor = false
            cfg.ignoreShadowsSingleWindow = true
            g.keep = [w, filter, cfg]
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { img, err in
                g.finish(img, err?.localizedDescription)
            }
        }
        let start = Date()
        while !g.result.done && Date().timeIntervalSince(start) < 5 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let r = g.result
        guard let image = r.image else {
            throw ToolError("Could not capture the window (\(r.failure)). Screenshots need Screen Recording permission for the app running this server (System Settings > Privacy & Security), and the window must not be minimized.")
        }
        return image
    }

    /// Captures the window, crops to `crop` given in
    /// screen points, downsizes to `maxWidth` pixels and returns a JPEG.
    private static func render(wid: Int, bounds: CGRect, crop: CGRect, maxWidth: Int) throws -> (data: Data, width: Int, height: Int) {
        let full = try grab(wid)
        let s = CGFloat(full.width) / bounds.width
        let px = CGRect(x: (crop.minX - bounds.minX) * s, y: (crop.minY - bounds.minY) * s, width: crop.width * s, height: crop.height * s)
            .integral.intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
        guard !px.isEmpty, let cut = full.cropping(to: px) else { throw ToolError("Region is outside the viewport.") }

        let w = min(maxWidth, cut.width, Int(crop.width.rounded()))
        let h = max(1, Int((Double(cut.height) * Double(w) / Double(cut.width)).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ToolError("Could not scale the screenshot.")
        }
        ctx.interpolationQuality = .high
        ctx.draw(cut, in: CGRect(x: 0, y: 0, width: w, height: h))
        let out = NSMutableData()
        guard let small = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ToolError("Could not encode the screenshot.")
        }
        CGImageDestinationAddImage(dest, small, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return (out as Data, w, h)
    }
}
