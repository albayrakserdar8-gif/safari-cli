import ApplicationServices
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

    private static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "enter": 36, "return": 36, "tab": 48, "space": 49, " ": 49, "backspace": 51, "escape": 53, "esc": 53,
        "delete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "arrowleft": 123, "arrowright": 124, "arrowdown": 125, "arrowup": 126,
        "left": 123, "right": 124, "down": 125, "up": 126, "del": 117, "pgup": 116, "pgdn": 121,
    ]

    private static func press(_ code: CGKeyCode, _ flags: CGEventFlags) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: tap)
            usleep(10_000)
        }
        // Let the app handle the key before more input arrives.
        usleep(40_000)
    }

    /// `combo` is like "Enter", "cmd+a", "shift+Tab".
    static func key(_ combo: String) throws {
        var parts = combo.split(separator: "+").map { $0.lowercased() }
        guard let name = parts.popLast() else { throw ToolError("key required") }
        var flags: CGEventFlags = []
        for p in parts {
            switch p {
            case "cmd", "meta": flags.insert(.maskCommand)
            case "ctrl": flags.insert(.maskControl)
            case "alt", "option": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default: throw ToolError("unknown modifier \(p)")
            }
        }
        if let code = codes[name] {
            press(code, flags)
        } else if name.count == 1 && flags.isEmpty {
            type(name)
        } else {
            throw ToolError("unknown key \(combo)")
        }
    }
}
