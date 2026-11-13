import Foundation

let argv = Array(CommandLine.arguments.dropFirst())

// `safari --grab <json>` is the screenshot helper the daemon spawns for one capture.
if argv.count == 2, argv[0] == "--grab" {
    exit(Capture.helperMain(argv[1]))
}

// The daemon keeps tab ids and the extension connection between commands. Requests are
// handled in order on the main thread, whose run loop must stay free when idle: the first
// window-server call (capture, Accessibility) registers the process, which then expects it to take
// events and otherwise reports it as "Not Responding" after the next app switch.
if argv == ["--daemon"] {
    Daemon.main()
}

do {
    // `safari --parse …` prints what a command maps to without running it (tests).
    if argv.first == "--parse" {
        let (tool, args, out) = try CLI.parse(Array(argv.dropFirst()))
        let d = try JSONSerialization.data(withJSONObject: ["tool": tool, "args": args, "out": out ?? NSNull()], options: [.sortedKeys, .withoutEscapingSlashes])
        print(String(decoding: d, as: UTF8.self))
        exit(0)
    }
    // `safari --selftest` checks the pure functions without Safari or the daemon (tests).
    if argv == ["--selftest"] {
        exit(SelfTest.run())
    }
    // `safari --reserve URL [lo hi]` asks for a pacing slot without sleeping or navigating (tests).
    if argv.first == "--reserve", argv.count >= 2 {
        var a: [String: Any] = ["url": argv[1]]
        if argv.count == 4, let lo = Double(argv[2]), let hi = Double(argv[3]) { a["delay"] = [lo, hi] }
        let r = try Client.send("reserve", a)
        print(String(format: "%.1f", r["wait"] as? Double ?? 0))
        exit(0)
    }
    // `safari --ext OP [JSON]` sends one raw op to the extension (debugging the bridge).
    if argv.first == "--ext", argv.count >= 2 {
        var a: [String: Any] = ["op": argv[1]]
        if argv.count > 2, let d = argv[2].data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] { a["args"] = o }
        let r = try Client.send("ext", a)
        print(r["text"] as? String ?? "")
        exit(r["ok"] as? Bool == true ? 0 : 1)
    }
    let (tool, args, out) = try CLI.parse(argv)
    if tool == "help" {
        print(args["text"] as? String ?? CLI.help)
        exit(0)
    }
    if tool == "downloads" { exit(Downloads.run(args)) }
    if tool == "pdf" { exit(Pdf.run(args, out: out)) }
    if tool == "state" { exit(State.run(args)) }
    if tool == "crawl" { exit(Crawl.run(args, out: out)) }
    exit(Client.run(tool, args, out: out))
} catch let u as Usage {
    FileHandle.standardError.write(Data(("safari: " + u.msg + "\n").utf8))
    exit(2)
} catch let f as Client.Failure {
    FileHandle.standardError.write(Data((f.msg + "\n").utf8))
    exit(1)
}
