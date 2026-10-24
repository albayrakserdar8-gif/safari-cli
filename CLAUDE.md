# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`safari-mcp`: a local stdio MCP server that lets Claude Code drive the user's real Safari. One Swift binary, no dependencies, no daemon. It talks to Safari through the optional Safari MCP Bridge extension (`Extension/`) when that is connected, else through Apple Events. It is an independent project; do not copy code from Anthropic's Claude in Chrome extension, do not use its OAuth token or bridge, and keep "Claude" out of the product name.

The README is written in Turkish and is the user-facing reference for setup, permissions and known limits.

## Commands

```bash
swift build -c release          # the binary Claude Code runs: .build/release/safari-mcp
Tests/smoke.sh                  # protocol test, needs no Safari permission
Tests/smoke.sh .build/debug/safari-mcp
Extension/build.sh              # regenerate main.js, build, sign and install the Safari extension (needs Xcode)
(cd Tests && python3 -m http.server 8765 --bind 127.0.0.1)   # serve the test pages
```

The server is a SwiftPM package with no XCTest target; `Tests/smoke.sh` is the only automated test and covers the JSON-RPC layer only. Xcode is installed, but it is only needed for the extension. `Tests/fixture.html` (form, dialogs, delayed element, table, fetch, and an iframe loading `Tests/frame.html`) is for manual checks with `tabs new`. Open it as `http://127.0.0.1:8765/fixture.html`: the extension cannot reach `file://` pages, so a `file://` URL only tests the Apple Events path.

The page script is a JS string inside Swift. Syntax-check it after editing:

```bash
awk '/static let source = #"""/{f=1;next} /^    """#/{f=0} f' Sources/safari-mcp/PageAgent.swift > /tmp/agent.js && node --check /tmp/agent.js
```

Drive a tool by hand by piping JSON-RPC lines into the binary:

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"tabs","arguments":{}}}' | .build/release/safari-mcp
```

The server is registered at user scope (`claude mcp add --scope user safari -- <path>/.build/release/safari-mcp`). A running Claude Code session keeps the binary it started with: `mcp__safari__*` tools in the current session do not reflect a rebuild. Test a new build by piping into it, not through those tools.

The page agent is injected once per document and never replaced, so a page that already carries `window.__smcp` keeps the old agent after a rebuild. Reload the page (or open a new tab) before judging a change to `PageAgent.swift`.

Refs (`e12`) are assigned in scan order and differ between page loads; never hard-code one in a test sequence, take it from a `read` in the same session.

Real-page behaviour can only be tested against the user's live Safari. Open your own tab with `tabs new`, work only there, and close it afterwards; the user is browsing in the same window.

## Architecture

Two backends behind `protocol Browser` (`Browser.swift`): `ExtBrowser` (the extension, via `Bridge.swift`) and `Safari` (Apple Events). `Tools.safari` picks the extension whenever it is connected. Both take the same `TabRef` + `Expect` and check them in the same step that acts, so everything above them (tab tracking, waits, the page agent) is shared.

Request path: `main.swift` (stdin read on a side thread, requests handled in order on the main thread, whose run loop must stay free when idle or macOS reports the process as "Not Responding") → `MCP.swift` (`Server`: JSON-RPC, lifecycle, tool errors as `isError`) → `Tools.swift` (the 8 tools and all tab/navigation logic) → `Browser.swift` (`ExtBrowser` over `Bridge.swift` to the extension, or `Safari.swift` with Apple Events) → `PageAgent.swift` (JS that runs inside the page).

### Safari bridge (`Safari.swift`)

One AppleScript source is compiled once; handlers are invoked by name with parameters via a subroutine Apple Event, so nothing is string-escaped or recompiled per call. `Safari` is created lazily because loading the AppleScript runtime costs about 25 MB.

Every tab-targeted handler takes an `Expect` (window tab count and tab URL) and checks it inside Safari, in the same Apple Event, before acting. A mismatch returns `"!"` and nothing runs. This is what stops a stale position from hitting another tab; do not add a tab-targeted handler without it.

### Tab identity (`Tools.swift`)

Safari only addresses tabs by `window id` + index, which shifts when tabs open, close or move. The server gives the model stable ids (`t3`) and maps them to positions:

- `sync()` re-lists tabs and carries ids over by aligning the old and new URL sequence per window (LCS). Unmatched tabs we have worked in are found by a handle stored in the page agent (`__smcp.h`); otherwise they are dropped and the model gets a "gone" error.
- `exec` runs checked JS (count + URL), `poll` runs it with the URL check off for use while a navigation is in flight, and both keep the tracked URL fresh. `guardedOp` is the same retry-after-`sync` loop for non-JS operations.
- A same-position URL change is trusted only within one host for tabs carrying a handle. This strictness is deliberate: losing an id costs the model one `tabs` call, adopting the wrong tab acts on the user's page.
- The default tab is the last one used. Once it is closed, `defaultLost` makes calls without `tab` fail instead of falling back to the user's visible tab. Subagents share one server, so once more than one tab from `tabs new` (`opened`) is open, calls without `tab` fail too.

### Navigation waits

`waitLoad` decides when a page change is done; a loaded page is accepted only if it is still at the same address about 250 ms later (script redirects). Signals, in order of reliability:

- a marker (`window.__smcpOld = <mark>`) set on the document being left; `mark` is bumped after every wait so a marked page restored from the back-forward cache is not taken for the old one;
- Safari's tab URL versus `location.href`: they differ while a navigation is pending but not committed (`PageState.pending`);
- a `beforeunload` flag in the agent ("leaving").

`navigate` marks then waits; `act` and `js` call `settle`/a short check afterwards and append `→ title | url` when the page or its address changed. When changing this code, the failure to avoid is a result that describes the previous page.

### Page agent (`PageAgent.swift`)

Injected once per document (`window.__smcp`), then each call is one small Apple Event or extension message. It owns: the element scan behind `read` (modes `interactive`/`all`, `query` search), the markdown walker `md` behind `text` (with BM25 `rank` for `text`+`query`) and `links`, the ref map (`e12` → `WeakRef`), synthetic input for `act`, console/fetch/XHR hooks for `logs`, and result slots for async `js`.

- Every `__smcp.call` carries the tab's handle and is a no-op on mismatch.
- `do JavaScript` does not await promises, so `js` starts the code, stores the result in a slot and polls `__smcp.take`.
- User code for `js` is embedded as an async function body, never `eval`'d (page CSP would block it).
- The main-world part (`mainSource`: console/fetch/XHR hooks, dialog answers, the `js` runner) is separate from `source`. With Apple Events both are injected together; with the extension `mainSource` is `main.js` (MAIN world, `document_start`, all frames) and the agent runs in the isolated world, reaching it with `mcall` over `__smcp_q`/`__smcp_r` DOM events. Dialog answering is armed only once the agent touches the page (and its frames, via postMessage); a sessionStorage flag keeps it armed across same-site navigations, so the user's own browsing keeps native dialogs.
- Clicks are dispatched to the innermost element under the target's centre (including through open shadow roots), as a real click would be.
- Safari's window is usually not key while the server works, so `focus()` moves focus without firing `focus`/`blur`. `foc()` sends those events itself (only when `!document.hasFocus()`); forms that commit on blur (Angular) depend on it.
- The call envelope carries `u0`, the address before the call; `act` settles against it, so a `history.pushState` route change is reported as `→ title | url`. After a click or key with no navigation, `act` asks the agent for `delta`: up to 3 new visible text lines (`· new text:`) and the fetch/XHR requests answered 4xx/5xx since the action (`· failed:`, from `M.fails` over the `M.net` counter; no-response `ERR` lines are left out, they are mostly aborted beacons).
- Dispatched key events do not perform the browser's default action. `keydef` does it for editing keys in fields and contenteditable when the page did not cancel the keydown (select all, delete, caret moves, characters, Enter in multi-line fields), and the result shows the value. A key without a target goes to the frame of the last targeted act (`focusFrame`).
- `read` ends with notes for what it left out: `(+N controls off-screen …)`, and `(N iframes not read …)` for frames neither backend could script.
- Refs are per element (WeakMap), so an element keeps its ref across reads of one document. `diff` relies on this: `S.last` keeps the previous body per mode/root/query and lines are matched by ref, else by text.
- `text` output ends each returned chunk with the URLs of the `[n]` links in that chunk; same-page fragment links get no number.
- `mainSource` replaces `alert`/`confirm`/`prompt`; while the page is armed, alert is acknowledged and confirm/prompt are dismissed unless `act dialog` set the answer (`M.dp`, via `M.policy`). Answered dialogs travel in the call envelope (`d`) and `Tools.call` appends them as `⚠ dialog` lines; dialogs in child frames are posted to the top frame and marked `(frame)`. Dialogs the override does not catch (Apple Events mode before injection or in an iframe; extension mode during the first load of a site the agent has not touched) are native: Apple Events time out after 20 s (`-1712`), the tab is put in `blocked`, and `act dialog` answers through Accessibility (`Capture.dialog`), selecting a background tab first because Safari only shows a dialog in the visible tab. While a native dialog is up, Safari's AX window list can be empty; use the focused window.
- Network lines carry ids (`n4`); text/JSON bodies of the last 50 fetch/XHR responses are kept for `logs id`.

### Extension bridge (`Bridge.swift`, `Extension/`)

- `Bridge` listens on a localhost WebSocket (Network.framework) on the first free port in 47391–47399; one per server process. The extension's persistent MV2 background page (`Extension/Safari MCP Bridge/Safari MCP Bridge Extension/Resources/background.js`) tries every port every 2 s.
- Handshake: both sides sign each other's nonce with HMAC-SHA256 of the token in `~/.config/safari-mcp/token` (created by the server, mode 0600). The extension gets the token from its native handler (`SafariWebExtensionHandler.swift`, sandboxed with a read-only exception for `~/.config/safari-mcp/`). Only `safari-web-extension://` origins may connect.
- Safari can run two copies of the extension for a while after an update, each with its own tab and window ids. All authenticated connections are kept, requests go to the oldest, and `generation` changes when that one drops, so `Tools` re-matches its tabs (same path as switching backends).
- Ops mirror the Apple Events handlers (`tabs`, `run`, `seturl`, `close`, `select`, `raise`, `newtab`) plus `status` and `reqs` (webRequest), `frames` (webNavigation), `win` and `shot` (captureVisibleTab). Reply fields must not be named `id`: that is the request id.
- In extension mode tabs carry `xid` (Safari's tab id) and `sync` matches by it before the URL alignment.
- `read` appends `--- frame fN <url>` blocks for child frames (`frameBlocks`). Frame refs are `fNeM`; `frameOf` strips them and `inFrame` routes the call: through `ext.frame` with the extension, or through `aeFrame` with Apple Events, where `agent()` wraps its code in `frameJS` to run in the frame window's own `Function` (same-origin frames whose CSP allows it; others return `Tools.noFrame`). Safari does not let the extension script srcdoc/about:blank frames (it lists srcdoc with an empty URL), so with the extension those come from `aeFrames` too, stored as negative frame ids that `inFrame` routes through `aeFrame`. `frameIDs` is reset when the backend switches.
- `main.js` is generated from `PageAgent.mainSource` by `Extension/gen.sh`; never edit it directly. `Extension/build.sh` regenerates it, builds with automatic signing for the team in the project, and installs to `~/Applications`. `--schedule` adds a weekly launchd job (`com.sadopc.safari-mcp.resign`) because free-account signatures expire.
- Safari does not let extensions into `file://` pages; serve test pages over HTTP (`python3 -m http.server` in `Tests/`).
- Test the Apple Events fallback without disabling the extension by holding ports 47391–47399 with plain sockets: the server then logs that the bridge is disabled.

### Screenshots (`Capture.swift`)

Capture uses ScreenCaptureKit in a child process: the server re-executes itself as `safari-mcp --grab <json>` and kills it after 6 s. A capture that never calls back blocks all later captures from processes of the same executable, so it must stay out of the long-lived server. macOS does not render windows on an inactive Space; when the window is not on screen, `screenshot` raises Safari briefly and then reactivates the previous app.

`Input.swift` sends real mouse/keyboard events via CGEvent for `os: true`. It needs Accessibility permission, raises Safari (`osAct` measures only after raising, refuses when `geom` reports the target covered, and puts the user's visible tab and front app back), and maps viewport coordinates to the screen through the page's scroll area found with the Accessibility API. Typed events must clear modifier flags, or a preceding key combo (cmd+a) leaks into them.

## Skill

`Skill/safari-browser/SKILL.md` is the usage guide Claude Code loads for browser tasks (installed by symlink into `~/.claude/skills/`). Keep it in step with tool behaviour: when a tool's arguments, defaults or result notes change, update the skill too.

## Repository

Hosted at `github.com/sadopc/safari-mcp` (public), default branch `main`. `README.md` is user-facing and in Turkish; keep its "Sınırlar" (limits) and "Sınanma durumu" (what was tested) sections honest when behaviour changes.

## Design constraints

- Token cost is a primary goal. Tool descriptions and schemas are sent every session (about 875 tokens total; `Tests/smoke.sh` prints the size and fails above 3600 chars). Tool results are terse single lines, `read` is capped by `max_chars` with an `offset` continuation, and screenshots are opt-in JPEGs. Keep additions equally short.
- The server has no dependencies and uses no Xcode-only APIs; it must keep building with Command Line Tools alone. Deployment target is macOS 14 (ScreenCaptureKit screenshot API) for the server and the extension app.
- stdout carries only JSON-RPC messages, one per line; anything else goes to stderr.
