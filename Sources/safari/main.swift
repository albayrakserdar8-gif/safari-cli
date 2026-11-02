import Foundation

let argv = Array(CommandLine.arguments.dropFirst())

// `safari --grab <json>` is the screenshot helper the daemon spawns for one capture.
if argv.count == 2, argv[0] == "--grab" {
    exit(Capture.helperMain(argv[1]))
}

// The daemon keeps tab ids and the extension connection between commands. Requests are
// handled in order on the main thread, whose run loop must stay free when idle: the first
// Apple Event registers the process with the window server, which then expects it to take
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
    let (tool, args, out) = try CLI.parse(argv)
    if tool == "help" {
        print(args["text"] as? String ?? CLI.help)
        exit(0)
    }
    exit(Client.run(tool, args, out: out))
} catch let u as Usage {
    FileHandle.standardError.write(Data(("safari: " + u.msg + "\n").utf8))
    exit(2)
}
