import SafariServices

/// Answers the extension's one native request: the shared token the safari-mcp server
/// keeps in ~/.config/safari-mcp/token. Both sides sign each other's nonce with it.
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        // Inside the sandbox NSHomeDirectory() is the container; the passwd entry is the real home.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let raw = try? String(contentsOfFile: home + "/.config/safari-mcp/token", encoding: .utf8)
        let token = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["token": token]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
