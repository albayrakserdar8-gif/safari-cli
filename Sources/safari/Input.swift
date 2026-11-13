import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Real mouse and keyboard events. Only used when a tool call asks for `os: true`.
enum Input {
    private static let src = CGEventSource(stateID: .hidSystemState)
    private static let tap = CGEventTapLocation.cghidEventTap

    static func trusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func move(_ p: CGPoint) {
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: tap)
        usleep(30_000)
    }

    /// Clicks at `p`, then puts the pointer back where the user had it.
    static func click(_ p: CGPoint, count: Int = 1, right: Bool = false) {
        let home = CGEvent(source: nil)?.location
        move(p)
        for c in 1...count {
            for type in right ? [CGEventType.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp] {
                let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: right ? .right : .left)
                e?.setIntegerValueField(.mouseEventClickState, value: Int64(c))
                e?.post(tap: tap)
                usleep(15_000)
            }
        }
        if let home { CGWarpMouseCursorPosition(home) }
    }

    static func scroll(at p: CGPoint, dy: Int) {
        move(p)
        CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 1, wheel1: Int32(-dy), wheel2: 0, wheel3: 0)?.post(tap: tap)
    }

    static func type(_ text: String) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.offset > 0 { press(36, []) }
            let units = Array(line.element.utf16)
            var i = 0
            while i < units.count {
                let chunk = Array(units[i..<min(i + 20, units.count)])
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                    e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                    // Without this, a modifier from a key combo just before (cmd+a) still applies.
                    e?.flags = []
                    e?.post(tap: tap)
                    usleep(4_000)
                }
                usleep(8_000)
                i += 20
            }
        }
    }

    /// Keys that are not characters. Their virtual key codes are the same on every layout.
    private static let named: [String: CGKeyCode] = [
        "enter": 36, "return": 36, "tab": 48, "space": 49, " ": 49, "backspace": 51, "escape": 53, "esc": 53,
        "delete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "arrowleft": 123, "arrowright": 124, "arrowdown": 125, "arrowup": 126,
        "left": 123, "right": 124, "down": 125, "up": 126, "del": 117, "pgup": 116, "pgdn": 121,
    ]

    private static func press(_ code: CGKeyCode, _ flags: CGEventFlags, text: String? = nil) {
        let units = text.map { Array($0.utf16) }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            if let units { e?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units) }
            e?.post(tap: tap)
            usleep(10_000)
        }
        // Let the app handle the key before more input arrives.
        usleep(40_000)
    }

    /// `combo` is like "Enter", "cmd+a", "shift+Tab", "ctrl+.". A character is found on the
    /// user's current keyboard layout, so `cmd+i` presses the key that makes `i` on Turkish Q too.
    static func key(_ combo: String) throws {
        var parts = combo.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // "cmd++" splits into ["cmd", "", ""]: the key is "+".
        if parts.count >= 2, parts.last == "", parts[parts.count - 2] == "" { parts.removeLast(2); parts.append("+") }
        guard let last = parts.popLast(), !last.isEmpty else { throw ToolError("key required") }
        var flags: CGEventFlags = []
        for p in parts {
            switch p.lowercased() {
            case "cmd", "meta": flags.insert(.maskCommand)
            case "ctrl": flags.insert(.maskControl)
            case "alt", "option": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default: throw ToolError("unknown modifier \(p)")
            }
        }
        if let code = named[last.lowercased()] {
            press(code, flags)
            return
        }
        guard last.count == 1 else { throw ToolError("unknown key \(combo)") }
        let map = KeyLayout.current()
        if flags.isEmpty {
            // The real key, so the page's keydown sees its `code`/`keyCode` (a `j` shortcut
            // checking `KeyJ`); the character is attached so the text is exact either way.
            if let hit = map?.find(last, command: false) {
                press(hit.code, hit.flags, text: last)
            } else {
                type(last)
            }
            return
        }
        // A shortcut names the key in lower case: cmd+A is cmd+a, as in menus.
        let name = last.lowercased()
        let hit = map?.find(name, command: flags.contains(.maskCommand)) ?? KeyLayout.us[name].map { KeyLayout.Hit(code: $0, flags: []) }
        guard let hit else { throw ToolError("unknown key \(combo) (no key makes \(name) on this keyboard layout)") }
        // No text here: the system turns key + modifiers into the character the shortcut matches.
        press(hit.code, flags.union(hit.flags))
    }
}

/// Reverse map of a keyboard layout: which virtual key (and shift/option) makes a character.
enum KeyLayout {
    struct Hit {
        let code: CGKeyCode
        let flags: CGEventFlags
    }

    struct Map {
        let id: String
        /// Characters typed without command.
        let plain: [String: Hit]
        /// Characters with command held: some layouts (Dvorak - QWERTY ⌘) switch while it is down,
        /// and macOS matches command shortcuts on this character.
        let command: [String: Hit]

        func find(_ c: String, command cmd: Bool) -> Hit? {
            cmd ? (command[c] ?? plain[c]) : plain[c]
        }
    }

    /// ANSI US positions, used only when no layout data can be read at all.
    static let us: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
    ]

    private static var cache: [String: Map] = [:]
    private static let lock = NSLock()

    /// The layout in use now (it can change between calls in the daemon). Input methods without
    /// layout data (some CJK ones) fall back to the ASCII-capable layout they type through; nil
    /// means the caller uses `us`.
    static func current() -> Map? {
        for copy in [TISCopyCurrentKeyboardLayoutInputSource, TISCopyCurrentASCIICapableKeyboardLayoutInputSource] {
            if let s = copy()?.takeRetainedValue(), let m = map(for: s) { return m }
        }
        return nil
    }

    static func map(for source: TISInputSource) -> Map? {
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
              let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        lock.lock()
        defer { lock.unlock() }
        if let m = cache[id] { return m }
        let data = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let m = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            Map(id: id, plain: build(layout, command: false), command: build(layout, command: true))
        }
        cache[id] = m
        return m
    }

    /// Keypad keys come last so digits and `. + - * /` map to the main block, as a person types them
    /// (`/` is shift+7 on Turkish Q, not keypad /).
    private static let keypad: Set<CGKeyCode> = [65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]

    private static func build(_ layout: UnsafePointer<UCKeyboardLayout>, command: Bool) -> [String: Hit] {
        let main = (0..<128).map { CGKeyCode($0) }.filter { !keypad.contains($0) }
        let states: [(UInt32, CGEventFlags)] = [
            (0, []), (UInt32(shiftKey), .maskShift), (UInt32(optionKey), .maskAlternate),
            (UInt32(shiftKey | optionKey), [.maskShift, .maskAlternate]),
        ]
        let kbd = UInt32(LMGetKbdType())
        var out: [String: Hit] = [:]
        // Main block before keypad; within each, fewest modifiers win: a character on its own key
        // beats the same one behind shift or option.
        for group in [main, keypad.sorted()] {
            for (mods, flags) in states {
                let state = ((mods | (command ? UInt32(cmdKey) : 0)) >> 8) & 0xFF
                for code in group {
                    var dead: UInt32 = 0
                    var len = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let err = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), state, kbd, 0, &dead, chars.count, &len, &chars)
                    // A dead key only starts a composition; pressing it alone types nothing.
                    guard err == noErr, dead == 0, len > 0 else { continue }
                    let s = String(utf16CodeUnits: chars, count: len)
                    guard s.count == 1, let u = s.unicodeScalars.first, u.value >= 0x20, u.value != 0x7F else { continue }
                    if out[s] == nil { out[s] = Hit(code: code, flags: flags) }
                }
            }
        }
        return out
    }
}
