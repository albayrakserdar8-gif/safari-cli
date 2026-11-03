# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`safari-cli`: a `safari` command that lets coding agents (Claude Code, opencode) drive the user's real Safari, used through the `safari-browser` skill. One Swift binary, no dependencies; it runs as a thin client plus an auto-started daemon. Forked from `safari-mcp` (remote `upstream`), whose MCP layer was replaced. It talks to Safari only through the Safari CLI Bridge extension (`Extension/`), which is required; the Apple Events backend was removed in November 2026. It is an independent project; do not copy code from Anthropic's Claude in Chrome extension, do not use its OAuth token or bridge, and keep "Claude" out of the product name.

`README.md` (English) and `README.tr.md` (Turkish) are the user-facing reference for setup, permissions and known limits. Keep them short and in step with each other.

## Commands

```bash
swift build -c release          # .build/release/safari (symlinked as /opt/homebrew/bin/safari)
make install                    # build + link binary and skill (Claude Code, opencode); make uninstall
make test                       # all checks, run locally (there is no CI): build, page-script syntax, smoke test
Tests/smoke.sh                  # CLI parser + daemon lifecycle test, needs no Safari permission
Tests/smoke.sh .build/debug/safari
Extension/build.sh              # regenerate main.js, build, sign and install the Safari extension (needs Xcode)
(cd Tests && python3 -m http.server 8765 --bind 127.0.0.1)   # serve the test pages
```

The package has no XCTest target; `Tests/smoke.sh` is the only automated test and covers argument parsing (`safari --parse …` prints the tool call a command maps to) and the daemon (start, restart for another build, stop). Xcode is installed, but it is only needed for the extension. `Tests/fixture.html` (form, dialogs, delayed element, table, fetch, and an iframe loading `Tests/frame.html`) is for manual checks with `tabs new`; `Tests/list.html?p=1` (paged table for `table`/`crawl`), `challenge.html` (a bot check that passes after 3 s) and `captcha.html` (one that never does) cover the newer verbs. Open it with `safari open http://127.0.0.1:8765/fixture.html`: the extension cannot reach `file://` pages, and safari refuses them. `route.html` loads `mock/app.js`, `mock/style.css` and `mock/pic.png`, which are missing until `route --global` mocks them. `safari --ext OP '{json}'` sends one raw op to the extension (e.g. `--ext sessionrules`; `"tab":"t3"` fills in a tab's address).

The page scripts are JS strings inside Swift (`source`, and `mainSource`, which becomes the extension's main.js); `make test` syntax-checks both. By hand:

```bash
awk '/static let source = #"""/{f=1;next} /^    """#/{f=0} f' Sources/safari/PageAgent.swift > /tmp/agent.js && node --check /tmp/agent.js
```

Drive it by hand: `safari help`, `safari status`, `safari open URL`, `safari t5 read`. Use `SAFARI_CLI_HOME=/tmp/x` (short path: the socket path must stay under 104 bytes) for a separate daemon, as the smoke test does.

A rebuild takes effect on the next command: the client sends its build id (path, size, mtime) and a daemon from another build answers `restart` and exits.

The page agent is injected once per document and never replaced, so a page that already carries `window.__smcp` keeps the old agent after a rebuild. Reload the page (or open a new tab) before judging a change to `PageAgent.swift`.

Refs (`e12`) are assigned in scan order and differ between page loads; never hard-code one in a test sequence, take it from a `read` in the same session.

Real-page behaviour can only be tested against the user's live Safari. Open your own tab with `safari open`, work only there, and close it afterwards; the user is browsing in the same window.

## Architecture

One backend: `ExtBrowser` (`Browser.swift`, over `Bridge.swift` to the extension). Every tab-targeted op takes a `TabRef` + `Expect` that the extension checks in the same step that acts. When the extension is not connected, `Bridge.call` throws a setup message (`downReason`), which every command shows. macOS-level helpers that no extension can replace stay: CGEvent input (`Input.swift`), ScreenCaptureKit and Accessibility (`Capture.swift`).

Request path: `main.swift` → `CLI.swift` (argv → one `Tools` call: tool name + the same argument dictionary the MCP tools took; the only place the syntax and `help` live) → `Client.swift` (unix socket `~/.config/safari-cli/sock`, one JSON line each way; starts the daemon when it cannot connect, writes screenshot JPEGs to `$TMPDIR/safari-cli/` and prints their path; exit 0 / 1 tool error / 2 usage) → `Daemon.swift` (`safari --daemon`: flock on `daemon.lock` so only one runs, accept loop on a side thread, requests handled in order on the main queue, whose run loop must stay free when idle or macOS reports the process as "Not Responding"; 30 min idle exit; log in `daemon.log`; every 5 min, and at idle exit, `Tools.reap` closes tabs opened with `open` (`(agent)` in `tabs`) that no call named for 30 min, except `show`n ones and ones visible in a window that also holds the user's tabs (`close --agents` runs the same with no age limit); `SAFARI_CLI_REAP=<s>` shortens this for tests) → `Tools.swift` (the tools in `Tools.names` and all tab/navigation logic) → `Browser.swift` (`ExtBrowser` over `Bridge.swift` to the extension) → `PageAgent.swift` (JS that runs inside the page). `downloads` is handled in the client (`Downloads.swift`: Safari's `~/Library/Safari/Downloads.plist`, else the download folder), so `--wait` never holds the shared daemon.

### Output, pacing and crawl

- Result lines starting with `\u{1E}` are notes (continuation hints, row counts, js context notes): `Client.split` prints them to stderr so stdout stays data. `-o FILE` (read/text/links/table/js) makes the client write the data to the file; the CLI then sets `max_chars` 0 (no cap) unless `--max` was given.
- `State.swift` (`state save|load`) and `Pdf.swift` (`pdf`) also run in the client over existing tools. `pdf` takes a DOM snapshot through `js` (form state into attributes, canvases as images, CSSOM-only styles as text, scripts removed) and prints it from an off-screen `WKWebView` with JavaScript off; `createPDF` (one long page) is the fallback.
- `cookies` goes through the extension's `cookies` op (`browser.cookies`, needs the `cookies` manifest permission) and falls back to the page agent's `document.cookie` (`cookies()`), which sees no HttpOnly cookies. Both reply `{ok: [...]}`; `Tools.cookies` formats the lines.
- `Rate.swift`: per-site pacing. Before `navigate` or `tabs new URL`, `Client.pace` asks the daemon (`reserve`) for the site's next slot and sleeps in the client, never in the daemon. Rules live in `rate.json`; `passCheck` and 429/503 answers call `backoff` (session-only). `safari --reserve URL [lo hi]` asks for a slot without navigating (smoke test).
- `table` is a page-agent op (`table()` next to `chunk()`): the biggest visible table, `--rows` matches, or, when no table has 3+ rows, guessed cards (`cards()`: the best-scoring group of siblings sharing tag and first class, followed down single-child wrappers, nav/menus and one-cell items left out; the note names a `--rows` selector that matches exactly them), ad/separator rows (under half the usual cell count) and all-empty columns dropped, `link` and `id` columns added.
- `Crawl.swift`: `crawl` runs in the client: `table`, find the next link (`rel=next`, "Next"/"Sonraki", or `--next`), pace, `navigate`, repeat; rows deduplicated by `id`.

### Tab identity (`Tools.swift`)

Safari only addresses tabs by `window id` + index, which shifts when tabs open, close or move. safari gives the model stable ids (`t3`) and maps them to positions:

- `sync()` re-lists tabs and carries ids over by aligning the old and new URL sequence per window (LCS). Unmatched tabs we have worked in are found by a handle stored in the page agent (`__smcp.h`); otherwise they are dropped and the model gets a "gone" error.
- `exec` runs checked JS (count + URL), `poll` runs it with the URL check off for use while a navigation is in flight, and both keep the tracked URL fresh. `guardedOp` is the same retry-after-`sync` loop for non-JS operations.
- A same-position URL change is trusted only within one host for tabs carrying a handle. This strictness is deliberate: losing an id costs the model one `tabs` call, adopting the wrong tab acts on the user's page.
- `tabs new private:true` reuses a window whose tabs are private, else `Browser.newPrivateWindow` (extension), else presses File > New Private Window through Accessibility (`Capture.newPrivateWindow`, found by its shift-cmd-N shortcut so any UI language works) and takes the window that was not there before. `Tab.priv` comes from the extension (`p`) or from having opened the tab so; Normal `tabs new` never opens into a private window.
- Ids survive the daemon: `next-tab` in `~/.config/safari-cli/` keeps the counter, so an id is never reused, and `tabs.json` keeps id, URL and page handle of tabs we worked in (and `opened`). A new daemon gives a tab its old id when the page still carries that handle and is on the same site (Safari's extension tab ids change between connections, so they are not used for this). `tabs new` stamps the handle right after the load.
- The default tab is the last one used. Once it is closed, `defaultLost` makes calls without `tab` fail instead of falling back to the user's visible tab. All agents and sessions share one daemon, so once more than one tab from `tabs new` (`opened`) is open, calls without `tab` fail too.

### Navigation waits

`waitLoad` decides when a page change is done; a loaded page is accepted only if it is still at the same address about 250 ms later (script redirects). Signals, in order of reliability:

- a marker (`window.__smcpOld = <mark>`) set on the document being left; `mark` is bumped after every wait so a marked page restored from the back-forward cache is not taken for the old one;
- Safari's tab URL versus `location.href`: they differ while a navigation is pending but not committed (`PageState.pending`);
- a `beforeunload` flag in the agent ("leaving").

After `navigate` and `tabs new`, `passCheck` looks for a bot-check page (`botJS`: Cloudflare, PerimeterX, captchas, check-like titles, only with an HTTP error, such a title or an almost empty page) and waits up to 20 s for it to pass; one that stays is a `ToolError` naming the tab. `wait --load` is `waitLoad` + `passCheck`.

`navigate` marks then waits; `act` and `js` call `settle`/a short check afterwards and append `→ title | url` when the page or its address changed. When changing this code, the failure to avoid is a result that describes the previous page.

### Page agent (`PageAgent.swift`)

Injected once per document (`window.__smcp`), then each call is one small extension message. It owns: the element scan behind `read` (modes `interactive`/`all`, `query` search), the markdown walker `md` behind `text` (with BM25 `rank` for `text`+`query`) and `links`, the ref map (`e12` → `WeakRef`), synthetic input for `act`, console/fetch/XHR hooks for `logs`, and result slots for async `js`.

- Every `__smcp.call` carries the tab's handle and is a no-op on mismatch.
- Script results are not awaited, so `js` starts the code, stores the result in a slot and polls `__smcp.take`.
- User code for `js` is embedded as an async function body, never `eval`'d (page CSP would block it).
- The main-world part (`mainSource`: console/fetch/XHR hooks, dialog answers, the `js` runner) is separate from `source`: `mainSource` is the extension's `main.js` (MAIN world, `document_start`, all frames) and the agent runs in the isolated world, reaching it with `mcall` over `__smcp_q`/`__smcp_r` DOM events. Dialog answering is armed only once the agent touches the page (and its frames, via postMessage); a sessionStorage flag keeps it armed across same-site navigations, so the user's own browsing keeps native dialogs.
- Clicks are dispatched to the innermost element under the target's centre (including through open shadow roots), as a real click would be.
- Safari's window is usually not key while safari works, so `focus()` moves focus without firing `focus`/`blur`. `foc()` sends those events itself (only when `!document.hasFocus()`); forms that commit on blur (Angular) depend on it.
- The call envelope carries `u0`, the address before the call; `act` settles against it, so a `history.pushState` route change is reported as `→ title | url`. After a click or key with no navigation, `act` asks the agent for `delta`: up to 3 new visible text lines (`· new text:`) and the fetch/XHR requests answered 4xx/5xx since the action (`· failed:`, from `M.fails` over the `M.net` counter; no-response `ERR` lines are left out, they are mostly aborted beacons).
- When `settle` saw no change, `act` polls the `watch()` flag (`fx`) for up to 1.2 s more, so a change made by a timer still counts; `watch()` stops observing after 3 s without setting the flag.
- After the action, `act` waits (≤ 2 s) for fetch/XHR requests started since it (`M.pend` over `M.nn`), then `delta` also lists other form fields whose value changed (`fsnap`/`fdelta`, `· also changed:`).
- `hover` emulates CSS `:hover`: `hcss` copies readable `:hover` rules with `.__smcp_hover` into a constructed stylesheet (not blocked by CSP) and `hov` puts the class on the element and its ancestors; later clicks move it, like a pointer.
- `scan` keeps a role-only control (`role=menuitem` on an `<li>`) listed but also descends into it when it holds real controls (`hold`); any `<a>` inside a listed control counts as a link. Controls sharing role and name get `(in "…")` from `ctx`: the first text line of their largest ancestor that holds no other one of them. Contenteditable roots are `textbox` with their text as the value. `md` writes field values as `[=v]` and checkboxes as `[x]`/`[ ]`.
- Dispatched key events do not perform the browser's default action. `keydef` does it for editing keys in fields and contenteditable when the page did not cancel the keydown (select all, delete, caret moves, characters, Enter in multi-line fields), and the result shows the value. In contenteditable, shift+arrows report the selection, and cmd+b/i/u fall back to `execCommand` when the page left them alone (an editor in a cross-origin frame cannot take focus, so Quill there ignores its own shortcuts); the result reports `(bold on)` from `queryCommandState`. `select` on a field or editor selects matching text (`seltxt`). A key without a target goes to the frame of the last targeted act (`focusFrame`).
- `read` ends with notes for what it left out: `(+N controls off-screen …)`, and `(N iframes not read …)` for frames neither backend could script.
- Refs are per element (WeakMap), so an element keeps its ref across reads of one document. `diff` relies on this: `S.last` keeps the previous body per mode/root/query and lines are matched by ref, else by text.
- `text` output ends each returned chunk with the URLs of the `[n]` links in that chunk; same-page fragment links get no number.
- `mainSource` replaces `alert`/`confirm`/`prompt`; while the page is armed, alert is acknowledged and confirm/prompt are dismissed unless `act dialog` set the answer (`M.dp`, via `M.policy`). Answered dialogs travel in the call envelope (`d`) and `Tools.call` appends them as `⚠ dialog` lines; dialogs in child frames are posted to the top frame and marked `(frame)`. Dialogs the override does not catch (during the first load of a site the agent has not touched) are native: the call times out after 20 s, the tab is put in `blocked`, and `act dialog` answers through Accessibility (`Capture.dialog`), selecting a background tab first because Safari only shows a dialog in the visible tab. While a native dialog is up, Safari's AX window list can be empty; use the focused window.
- Network lines carry ids (`n4`); text/JSON bodies of the last 50 fetch/XHR responses are kept for `logs id`.

### Extension bridge (`Bridge.swift`, `Extension/`)

- `Bridge` listens on a localhost WebSocket (Network.framework) on the first free port in 47391–47399; one per daemon (an old safari-mcp server can hold another port at the same time). The extension's persistent MV2 background page (`Extension/Safari MCP Bridge/Safari MCP Bridge Extension/Resources/background.js`) tries every port every 2 s.
- Handshake: both sides sign each other's nonce with HMAC-SHA256 of the token in `~/.config/safari-mcp/token` (created by the daemon, mode 0600). The extension gets the token from its native handler (`SafariWebExtensionHandler.swift`, sandboxed with a read-only exception for `~/.config/safari-mcp/`). Only `safari-web-extension://` origins may connect.
- Safari can run two copies of the extension for a while after an update, each with its own tab and window ids. All authenticated connections are kept, requests go to the oldest, and `generation` changes when that one drops, so `Tools.reconnected` re-matches its tabs and forgets its routes.
- Ops: `tabs`, `run`, `seturl`, `close`, `select`, `raise`, `newtab`, plus `rules`/`resetrules` (route), `cookies`, `resize`, `newpriv` (a private window via `windows.create({incognito})`, checked before the URL loads), `status` and `reqs` (webRequest), `frames` (webNavigation), `win` and `shot` (captureVisibleTab). Reply fields must not be named `id`: that is the request id.
- In extension mode tabs carry `xid` (Safari's tab id) and `sync` matches by it before the URL alignment.
- `read` appends `--- frame fN <url>` blocks for child frames (`frameBlocks`). Frame refs are `fNeM`; `frameOf` strips them and `inFrame` routes the call: through `ext.frame`. Safari does not let the extension script srcdoc/about:blank frames (it lists srcdoc with an empty URL), so those come from `aeFrames` (the top document's iframes), stored as negative frame ids that `inFrame` routes through `aeFrame`: `agent()` wraps its code in `frameJS` to run in the frame window's own `Function` (same-origin frames whose CSP allows it; others return `Tools.noFrame`). `frameIDs` is reset on reconnect.
- `route` (`Tools.route`) keeps each tab's routes (newest last). Plain routes go to the page (`route` agent op → `M.setRoutes`, sessionStorage `__smcp_routes`, which same-origin frames pick up through the `storage` event; `followRoutes` re-sends them after any call that left the tab on another origin): main.js adds the mock's secret marker (`__smcp_m=<id>`) to matching fetch/XHR, and a network rule for that marker alone redirects them to `MockServer` (a direct fetch of the http mock server is blocked as mixed content on https pages; a rule redirect is not); it also sends them to the `--redirect` target, rejects them (`--block`), or sets headers. `--global` routes become declarativeNetRequest session rules (`networkRules`, `rules` op, owned per daemon port and dropped 5 s after that daemon disconnects); mocks redirect to `<base>/g`. `MockServer` is plain HTTP on 127.0.0.1:47401–47409, one unguessable `/m/<id>` per mock, CORS echoing the page's origin, optional delay. `pruneRoutes` (after every call and `reap`) drops routes, mocks and global rules of tabs that are gone; a new daemon clears its port's rules on connect.
- Why plain routes stay in the page: Safari 27.2 applies session rules to every tab whatever `tabIds`/`excludedTabIds` say, ignores blocking webRequest, and its webRequest `tabId` for one tab's subresources varies (seen: the real id and the id minus 2), so neither rules nor a gate on the mock server can tell tabs apart; WebKit's memory cache also shares a mocked image between tabs. Tried and removed in November 2026: per-tab rules, and a gate that sent other tabs back to the real URL.
- Other declarativeNetRequest quirks found on Safari 27.2: redirects need the `declarativeNetRequestWithHostAccess` permission and apply only to pages loaded after it was granted; a rule whose `resourceTypes` lists `object` next to other types is ignored, and so is every rule when an `allow` rule has no `resourceTypes`; between two redirects the LOWER priority wins, between other actions the higher (so `rules` numbers redirects newest-lowest, then the mock-origin `allow`, then blocks and header rules); `modifyHeaders` takes only standard header names; regexes have no `|`, `{n}`, lookaround or `\d`, and match case-insensitively; iframe loads can be typed `main_frame`; an `http://127.0.0.1` redirect target works from https pages.
- `record` lives in `mainSource` too (the recorder must start with each page): `M.recStart`/`M.recStop`, state in sessionStorage `__smcp_rec`, trusted events only, targets from `selOf` (the same selector builder `locator` uses through `M.loc`, after the isolated agent marks the element with `data-smcp-el`). `js` with an element uses the same mark.
- `main.js` is generated from `PageAgent.mainSource` by `Extension/gen.sh`; never edit it directly. `Extension/build.sh` regenerates it, builds with automatic signing for the team in the project, and installs to `~/Applications`. `--schedule` adds a weekly launchd job (`com.sadopc.safari-mcp.resign`) because free-account signatures expire.
- Safari does not let extensions into `file://` pages; serve test pages over HTTP (`python3 -m http.server` in `Tests/`).
- Test the not-connected errors without disabling the extension by holding ports 47391–47399 with plain sockets before a separate daemon starts (`SAFARI_CLI_HOME`): it then reports the ports as busy.

### Screenshots (`Capture.swift`)

Capture uses ScreenCaptureKit in a child process: the daemon re-executes itself as `safari --grab <json>` and kills it after 6 s. A capture that never calls back blocks all later captures from processes of the same executable, so it must stay out of the long-lived daemon. macOS does not render windows on an inactive Space; when the window is not on screen, `screenshot` raises Safari briefly and then reactivates the previous app.

`Input.swift` sends real mouse/keyboard events via CGEvent for `os: true`. It needs Accessibility permission, raises Safari (`osAct` measures only after raising, refuses when `geom` reports the target covered, and puts the user's visible tab and front app back), and maps viewport coordinates to the screen through the page's scroll area found with the Accessibility API. Typed events must clear modifier flags, or a preceding key combo (cmd+a) leaks into them.

## Skill

`Skill/safari-browser/SKILL.md` is the usage guide agents load for browser tasks (symlinked into `~/.claude/skills/` for Claude Code and `~/.config/opencode/skills/` for opencode; keep its wording agent-neutral). Keep it in step with `CLI.swift`: when a verb, option, default or result note changes, update the skill and `CLI.verbs` help too. Hints inside results (`--offset K`, `--full`, `--os`, `safari tabs`) use CLI syntax.

## Repository

Fork of `github.com/sadopc/safari-mcp` (remote `upstream`), default branch `main`. Keep the "Limits" / "Sınırlar" and "Testing status" / "Sınanma durumu" sections of both READMEs honest when behaviour changes.

## Design constraints

- Token cost is a primary goal. Nothing is sent per session except the skill's one-line description; the skill body (about 1,550 tokens) loads for browser tasks, and `Tests/smoke.sh` fails above 7500 chars. Details go into `Skill/safari-browser/references/*.md` (each under 4000 chars, read only when the skill's "Specific tasks" list points there); `SKILL.md` keeps the rules, a quick start, the reading table and the core actions. Results are terse lines that agents can pipe and filter, `read` is capped by `max_chars` with an `offset` continuation, and screenshots are opt-in JPEGs. Keep additions equally short.
- The binary has no dependencies and uses no Xcode-only APIs; it must keep building with Command Line Tools alone. Deployment target is macOS 14 (ScreenCaptureKit screenshot API) for the server and the extension app.
- The client's stdout carries only the result; errors go to stderr. The daemon never inherits the caller's stdout (the shell would wait for it) and is spawned as a child of the shell, not a launchd job, so its TCC permissions are the terminal's.
