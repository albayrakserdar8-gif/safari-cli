# safari-cli

[Türkçe](README.tr.md)

A `safari` command that lets coding agents (Claude Code, opencode, anything with a shell) drive your real Safari, with your logged-in sessions. One Swift binary, no dependencies. Forked from [safari-mcp](https://github.com/sadopc/safari-mcp): same engine, a CLI and a skill instead of an MCP server.

It talks to Safari through the **Safari CLI Bridge** extension, which is required: it reaches every tab and frame, and can intercept network traffic.

Independent project, not affiliated with Anthropic. It was written because Claude in Chrome only works in Chromium browsers.

## When to use it

Good for everyday work on sites you are logged into: reading, searching, filling forms, navigating. For web app testing, CI or repeatable automation, use Playwright (or Apple's `safaridriver`) instead; [playwright-cli](https://github.com/microsoft/playwright-cli) gives an agent the same in a separate browser. To get researched answers with sources rather than act on pages, a search engine like [Vane](https://github.com/ItzCrazyKns/Vane) fits better.

| | safari-cli | Playwright | playwright-cli | Vane |
|---|---|---|---|---|
| What it is | CLI that drives your Safari | Browser automation library | Playwright's CLI for coding agents | Self-hosted AI answer engine |
| Driven by | Claude Code, opencode, any agent with a shell | Your scripts, or an agent through Playwright MCP | Claude Code, Copilot, any agent with a shell (through its skill) | Its own LLM pipeline, from its web UI or API |
| Browser | Your open Safari | A separate browser it launches | Its own Chromium, Firefox or WebKit (headless by default), or Chrome/Edge it attaches to | Headless Chromium (via Playwright), only to read pages |
| Your logged-in sessions | Yes | Only with saved profiles or state | With a persistent profile, or by attaching to your Chrome | No |
| Clicks, typing, forms | Yes | Yes | Yes | No, read-only |
| Dialogs, file upload, iframes | Yes | Yes | Yes | — |
| Network interception | Per tab: mock, block, redirect or change headers of fetch/XHR. `--global`: any request (scripts, styles, images, frames, the page itself), in every tab (`route`) | Yes | Yes (`route`) | — |
| Cookies, saved state, PDF | Yes (`cookies`, `state`, `pdf`) | Yes | Yes | — |
| Web search with cited sources | Through the sites it opens | No | Through the sites it opens | Yes (SearxNG) |
| LLM | The agent's | None of its own | The agent's | Any: Ollama, OpenAI, Claude, Gemini, Groq |
| Setup | Swift build and the Safari extension (needs Xcode) | npm or pip package | npm package (Node 18+), skill via `install --skills` | Docker image (includes SearxNG) |
| Platform | macOS 14+ | macOS, Windows, Linux | macOS, Windows, Linux | Anywhere Docker runs |
| Best for | Everyday tasks on sites you are logged into | Testing, CI, repeatable automation | Agent-driven testing and automation in a separate browser | Private research questions with cited answers |

## Why a CLI instead of MCP

- Output can be filtered and saved in the shell (`| grep`, `| head`, `> page.md`), so long pages need not enter the conversation.
- Known sequences run in one shell command with `&&`; loops crawl pages without each result reaching the model.
- No server registration: any agent that can run a command can use it, and a rebuild takes effect on the next command.
- The usage guide lives in a skill that is loaded only for browser tasks.

## How it works

`safari` parses the verb, sends one request to a background daemon over a unix socket, and prints the reply. The daemon drives Safari through the extension's WebSocket, and works in the page with two injected scripts: one in the page's own world (console and fetch hooks, dialogs, `js`, routes) and one in the extension's isolated world (refs, reading, actions). `docs/architecture.png` shows the whole picture; `docs/architecture.excalidraw` is the editable scene.

## Install

Needs macOS 14 or later, the Command Line Tools, and Xcode for the Safari extension.

```bash
git clone https://github.com/albayrakserdar8-gif/safari-cli.git
cd safari-cli && make install
```

`make install` builds the binary, links it into `/opt/homebrew/bin` (or `/usr/local/bin`; set `PREFIX=` for another place) and links the skill for Claude Code and opencode. `make uninstall` removes the links.

A background daemon keeps tab ids and the extension connection between commands. The first `safari` command starts it (about 0.2 s), later commands take a few milliseconds, and it exits after 30 idle minutes. After a rebuild, the next command restarts it on the new binary. `safari status` shows its state, `safari stop` stops it.

### Skill

`Skill/safari-browser/SKILL.md` teaches the agent the core commands and the rules: work in its own tab, prefer `read` over screenshots, and ask before submitting, buying or deleting anything. Details (forms, scraping, `js`, cookies and storage, mocking, recording) live in `references/` files the agent reads only when a task needs them. `make install` links it into `~/.claude/skills` and `~/.config/opencode/skills`.

In Claude Code, adding `"Bash(safari:*)"` to `permissions.allow` in `~/.claude/settings.json` stops the per-command prompts.

### Safari extension (required)

Every command goes through the extension; without it, commands fail with a message saying how to turn it on. `safari status` shows whether it is connected. Building it needs Xcode:

1. Add an Apple ID in Xcode > Settings > Accounts (a free account works).
2. Open `Extension/Safari MCP Bridge/Safari MCP Bridge.xcodeproj` and pick your Personal Team under Signing & Capabilities for both targets.
3. Build and install:
   ```bash
   Extension/build.sh --schedule
   ```
   `--schedule` adds a weekly job that re-signs the extension, because free-account signatures expire.
4. In Safari > Settings > Extensions, enable **Safari CLI Bridge** and allow it on every website. For private tabs, also turn on "Allow in Private Browsing". After an update that adds a permission (cookies, and network rules with host access for `route`, in November 2026), Safari may turn the extension off until you enable it again; reload pages that were open before.

The daemon and extension talk over `127.0.0.1` (ports 47391–47399) and authenticate each other with a key in `~/.config/safari-mcp/token`, so other pages or local programs cannot connect. The extension is the same one safari-mcp uses; both can be installed at once. `route` answers mocked requests from a second listener on `127.0.0.1` (ports 47401–47409), at unguessable paths.

Safari does not let extensions into `file://` pages, so safari refuses them; serve the folder over HTTP (`python3 -m http.server`).

## Permissions

| Permission | Used for | Needed |
|---|---|---|
| Safari extension, on every website | Everything | Required |
| Screen Recording | `shot` of a tab that is not on screen | Only then |
| Accessibility | `--os`, native dialogs, exact screenshot cropping, opening a private window | Optional |

These go to the app that runs the agent (your terminal). Automation and "Allow JavaScript from Apple Events" are no longer used.

## Usage

Just ask the agent:

- "List my open Safari tabs."
- "Search Wikipedia for the Bosphorus Bridge and tell me when it opened."
- "Fill in the form on this page with these details, but don't submit it."

## Commands

`safari help` lists them all. `T` is a tab id (`t3`), `R` a ref from `read` (`e12`).

| Command | What it does |
|---|---|
| `tabs`, `open URL [--private\|--window]`, `T show`, `T close`, `close --agents` | List, open (in the background, or in a window of its own), show, close tabs; `--agents` closes every agent tab not on screen |
| `T go URL\|back\|forward\|reload [--delay S]` | Load and wait |
| `T read`, `T text`, `T links` | Controls with refs, page as markdown, links; `-q` to search (`-q '/regex/i'` too), `--diff` for changes only |
| `T table [--rows CSS] [--json]` | A table or list of cards as TSV/JSON, with each row's link and `data-id`; without `--rows` it finds repeated cards itself |
| `T crawl [--next TEXT] [--pages N]` | `table` on each page of a paged list, following "Next", merged and deduplicated |
| `rate [SITE [S\|off\|reset]]` | Seconds between page loads per site (`rate example.com 8-14`), saved; `reset` ends a hold after a block page |
| `T click R`, `dblclick`, `hover`, `fill`, `type`, `select`, `key`, `scroll`, `wait`, `upload`, `drop`, `dialog` | Act on the page (`drop` drops files on a drop zone) |
| `T locator R`, `T highlight R` | A CSS selector for R that lasts across page loads; a box around R in your view |
| `T js CODE [R]` | Run JavaScript in the page (async function body, 15 s limit; `-` reads stdin); an element after the code is `el` |
| `T shot [--full]` | JPEG of the viewport, an element, a region or the whole page; prints its path |
| `T resize W H` | Viewport size, in a window that holds only agent tabs |
| `T route PATTERN`, `T unroute` | Mock the tab's fetch/XHR (`--status`, `--body`, `--resp-header`, `--delay`), `--block` or `--redirect` them, or change their `--header`s. `--global` does the same for every kind of request, in every tab; `--doc` adds the page itself |
| `T storage`, `T cookies` | List, get, set or delete localStorage/sessionStorage, or the site's cookies (HttpOnly too) |
| `T state save\|load FILE` | The site's cookies and web storage to a file (mode 0600) and back |
| `T check R`, `T uncheck R` | Set a checkbox or radio; safe to repeat |
| `T pdf` | The page as a paged PDF, rendered from a snapshot of its DOM in the background |
| `T record`, `T record --stop` | Record what you do in a tab, printed as `safari` commands to replay |
| `T logs` | Console and network logs, with response bodies by `--id` |
| `downloads [--wait]` | Recent downloads from Safari's list; `--wait` until they finish, then the saved paths |

Results go to stdout; errors to stderr with exit status 1 (2 for wrong usage). Long results are capped (`--max N`, `--max 0` for all); notes such as `… N more chars; --offset K` and row counts go to stderr, so piped data stays clean. When stderr and stdout are the same pipe (agent harnesses that run commands from a script), the notes come after the data, marked `note: `. `-o FILE` writes the whole result of `read`, `text`, `links`, `table` and `js` to a file.

`--json` works with every verb: one JSON object on stdout and nothing on stderr, with the same exit status. It holds `ok`, the tab id, its `url` (`title` mainly after a call that loaded a page, `nav` when one did), the `text` and the `notes`; on failure `kind` (`gone`, `timeout`, `check`, `blocked`, `offline`, `noanswer`, `dialog`, `usage` or `error`) and `error`. `table` and `crawl` put their rows in `rows`. This changed in November 2026: `table --json` and `crawl --json` used to print a bare array, so `jq '.[]'` becomes `jq '.rows[]'` (with `-o FILE` the file still holds the array).

How it behaves:

- **Refs.** `read` gives each element a ref like `e12`, which the actions use. Refs last for the current page only.
- **Tabs.** Tabs get stable ids like `t3`. Before every action Safari checks it is still the expected tab, so safari never acts on the wrong one. Commands without a tab id use the last tab used; new tabs open in the background. `open --private` opens a private window (later private tabs join it); `tabs` marks such tabs `(private)`. Tabs opened with `open` are marked `(agent)`; if no command uses one for 30 minutes, the daemon closes it, unless it is the visible tab in one of your windows or was brought forward with `show`. `SAFARI_TAB=t3` in the environment makes t3 the tab for commands that name none.
- **Rich text.** `select R "words"` selects text in a field or editor; `key cmd+b R` (or `cmd+i`, `cmd+u`) then formats it, also in editors inside frames that cannot take focus.
- **Results.** Actions wait for page loads and report `→ title | url` when the page changes. They also report new text, failed requests (4xx/5xx) and other fields that changed.
- **Input.** By default clicks and typing are in-page events: Safari stays in the background and you keep your cursor. `--os` sends real mouse/keyboard events for sites that ignore in-page events; it briefly brings Safari to the front.
- **Dialogs.** `alert` is accepted, `confirm`/`prompt` are dismissed unless `dialog` or `click --answer` sets an answer first. Each one is reported in the result. Only tabs safari works in are affected; your own browsing keeps normal dialogs.
- **Screenshots.** If Safari is on another Space or full screen, it is brought forward for about a second, then the previous app comes back.
- **Bot checks.** `open`, `go` and `wait --load` recognise check pages (Cloudflare "Just a moment…", PerimeterX, captchas) and wait up to 20 s for them to pass by themselves; the result then describes the real page. A check that stays is an error naming the tab, so you can show it and solve it, then `wait --load`. A block page (Cloudflare's "Sorry, you have been blocked", "Access denied" with HTTP 403) is not a check: `go`, `open`, `wait --load`, and a `click` or `js` that loads one, fail at once with `blocked`, and further loads and reloads of that site are refused for 15 minutes (`safari rate SITE reset` ends that; back and forward still work). safari does not try to get around blocks: no fingerprint changes, no retries.
- **Pacing.** `safari rate SITE 8-14` (or `go --delay 8-14`) spaces page loads on a site. The daemon hands out time slots and the command waits for its own, so several agents on one site queue up and the daemon stays free. A site without a rule gets 2-4 s between loads (the first load goes at once; `localhost` and `127.*` are exempt, `--delay 0` skips it). A bot check or a 429/503 answer slows the site down for the session (4-8 s without a rule, else double).

## Resource use

Measured on one Mac:

| | |
|---|---|
| Skill | about 1,760 tokens, loaded only for browser tasks; nine `references/` files (400-850 tokens each) are read only when a task needs them (the MCP version sent about 875 tokens of tool schemas every session, plus its skill) |
| Default `read` | about 500 tokens (Wikipedia home), 1,100 (Hacker News) |
| Call time | `read` 7–60 ms, actions 170–470 ms, `shot` 0.9–2.1 s; about 10 ms more per command, 0.2 s for the first one that starts the daemon |
| Memory | 9 MB idle, about 34 MB after use |
| Idle CPU | 0 |

One daemon serves every agent and session; it exits after 30 idle minutes.

## Testing status

The page engine was tested in safari-mcp over six rounds in which Claude Haiku agents did real tasks using only the tool descriptions: Wikipedia, Hacker News, MDN, GitHub, DuckDuckGo, sign-up, cart and checkout flows on demo shops (automationexercise, Toolshop/Angular, saucedemo/React, demowebshop), the-internet and TodoMVC. Bugs found in each round were fixed; by the last rounds all tasks finished correctly without falling back to `js` or `os: true` for actions, and call counts on the hardest tasks roughly halved. The CLI was then tested in one round of eight parallel Claude Haiku agents that had only the skill, sharing one daemon: Wikipedia, Hacker News, MDN site search, GitHub (release, issue search, file tree), DuckDuckGo with a screenshot, saucedemo checkout, the-internet widgets and TodoMVC. All eight finished correctly without `--os`, in 7–37 commands. `js` was needed only to read text the CLI did not show: a full Hacker News comment, a date year held in an attribute and a GitHub code view. The first two of these were fixed afterwards: layout tables and lists of `<article>` results now read in full, and `read --ref` on one field shows its whole value. A second round of eight harder tasks (demoqa form with date picker, autocomplete and React selects; Toolshop/Angular cart; TinyMCE, nested frames, upload, hovers, infinite scroll and shadow DOM on the-internet; a paged books.toscrape crawl to a file; a five-article Wikipedia comparison; automationexercise sign-up, order and account deletion; GitHub release notes, source, merged PRs and contributors; Hacker News plus external articles) finished correctly except a right-click, which had no command then. It led to `click --right`, names for icon-only buttons (one agent had removed a cart item through a button listed as "btn"), `open --id-only`, plain-text `js` strings and fuller `select` errors. A third round covered other areas: several tabs at once, private windows (no logins leaked), debugging (JS errors, broken images, 404/500, response bodies), Quill and CodeMirror editors, sliders and drag and drop, Turkish sites (no garbled characters), canvas content read from screenshots, and misuse (unknown ids and refs, unreachable hosts, timeouts, wrong arguments). It led to `drag`, exit 1 for a navigation that does not load and for a `js` timeout, usage errors for conflicting element arguments, and tab ids that survive a daemon restart. Formatting failed in Quill inside a cross-origin frame, where the page cannot take focus; this led to `select R "text"` for fields and editors, formatting shortcuts that fall back to the browser's editing commands, and reported selections and formatting state. Downloads (`safari downloads`) and the closing of forgotten agent tabs came out of the same round. A fourth round, after a real scraping session on sahibinden.com, added `table`, `crawl`, `rate`, bot-check handling and clean stdout (notes to stderr, `-o FILE`). Three parallel Claude Haiku agents then crawled sahibinden.com at 8-14 s per page (111 listings over 3 pages, no block, no duplicates), books.toscrape.com and Wikipedia tables, and drove local bot-check and pacing pages. Misaligned columns in tables with colspan/rowspan and cut-off titles in card lists were fixed after that round. `table` still reads layout tables (Hacker News) poorly.

A fifth round tested the features taken from playwright-cli (`locator`, `highlight`, `js` with an element, `open --window` and `resize`, `SAFARI_TAB`, `close --agents`, `route`, `storage`, `drop`, `record`, `shot --full`). Each was first checked by hand on the local test pages (`fixture.html`, `route.html`, `drop.html`) and on Wikipedia. Then four Claude Haiku agents, which had only the skill and its `references/` files, worked in parallel on one daemon:
- logging in to the-internet with selectors from `locator`, after a reload, with no refs;
- mocking, failing (500) and blocking the fruit API of demo.playwright.dev/api-mocking and the local `route.html`;
- editing TodoMVC's todos through localStorage, dropping a file on the-internet's drag-and-drop upload zone, and a full-page shot of a Wikipedia article;
- the Bootstrap site at 1280x800 and 390x844 in a window of its own, plus `SAFARI_TAB` scripts.

A fifth agent recorded a login and logout on the-internet with real input (`--os`) and replayed it in a new tab. All tasks finished in 22–56 commands.

Fixed after the round:
- `resize` reported the size before Safari's toolbar settled (844 instead of 806).
- `shot --full` called a cut page "whole page".
- Generated and recorded selectors could be a bare tag (`button`).
- Enter in a form recorded an extra click on the submit button.
- `go` failed from a blank tab, so a replay could not start there.

A `<select>` option could not be chosen with real input in Safari's native menu, so recording `<select>` changes is untested.

A sixth round tested the second batch taken from playwright-cli (`check`/`uncheck`, regex `-q`, `cookies`, `state`, `pdf`) after the skill was cut to a core of about 1,450 tokens with details in `references/`. Five Claude Haiku agents worked in parallel on one daemon, each given the path of the skill: the new features on the fixture, Wikipedia, GitHub and TodoMVC; forms and flows (saucedemo checkout, demoqa, alerts, upload); scraping (books.toscrape with pacing, Wikipedia tables, Hacker News); debugging and mocking (logs, broken images, 404/500, `route`, `locator`, screenshots); and everyday research in several tabs (GitHub, MDN search, DuckDuckGo, a Turkish news site, bold text in TinyMCE). All tasks finished in 32-80 commands, except one GitHub page that answered 404. The forms agent never opened a `references/` file and found the answer to a prompt, date pickers and react-select dropdowns by trial; the skill's task list was then rewritten to name situations ("a form with date pickers, dropdowns…") instead of topics.

A seventh round gave four agents only the task and "use the user's Safari", with no path and no mention of the skill or its references, on sites not used before: unusual inputs (Selenium's web form with colour, range, datalist and date; jQuery UI's datepicker in a frame; key presses, slider, hovers, drag and drop), dynamic pages (delayed content, infinite scroll, shadow DOM, a sortable table, a paged crawl and an AJAX mock on scrapethissite), logins and sessions (a test login, carrying a saucedemo login into a private window, cookies checked against httpbin, an MDN PDF), and parallel tabs and robustness (a three-tab script, a quotes.toscrape crawl, Bootstrap at 390 and 1280 px, a search on hepsiburada, deliberate errors). Every agent loaded the skill by itself, and three of the four read the reference that matched their task; the fourth used `safari help` instead. All tasks finished in about 60-80 commands, except the private-window login.

Fixed after these rounds:
- `js` with an arrow function that has a block body (`map(r => { …; return x })`) returned `undefined`: any `return` in the code made it a function body.
- `check` on an element that is not a checkbox or radio, and `uncheck` on a selected radio, reported "not changed" with exit 0; both now exit 1 with the reason.
- `open` on an unreachable host returned a tab id with exit 0; it now exits 1 and closes the tab.
- `crawl` counted a "Next" link that led back to the same rows (scrapethissite's first page) as a page; such pages are now skipped.
- In a private window `cookies` and `state load` wrote to the normal window's cookies, so the restored login did not take; the extension now uses the private tab's cookie store.
- `drag --to` takes a CSS selector as well as a ref; regex patterns in "no match" messages are shown as typed; the skill says `go reload` (an agent tried `reload`).

An eighth round (November 2026) followed the removal of the Apple Events backend and the rewrite of `route`. Each step was first checked by hand on Safari 27.2 against `route.html`, `fixture.html`, example.com and httpbin.org, which is how the network-rule quirks in CLAUDE.md were found. Then Claude Haiku agents worked in parallel on one daemon: a regression pass over every everyday command (all passed), two rounds of feature tests for `route`, and two adversarial rounds. The first adversarial round showed that Safari applies network rules to every tab, which led to the current split between per-tab routes and `--global`.

Fixed after these rounds:
- Plain mocks failed on https pages (mixed content); they now reach the mock server through a network-rule redirect keyed to a secret marker.
- An empty pattern matched every request, and a header value with a line break became two headers; both are refused, as is a `--global` pattern that matches everything.
- Routes were not re-applied after a move to another port or a script navigation, missed URLs with a `#fragment` and iframes loaded before the route, and a reused XHR was logged as failed.
- Global rules of a daemon that exits are removed after 5 s, so a dead mock server cannot break the user's tabs.

A ninth round (November 2026) compared safari with playwright-cli on four tasks, one Claude Haiku agent per tool and task. Both answered everything correctly; safari needed more commands on TodoMVC (`type` required an element) and on books.toscrape (`table` did not see the card grid). This led to `type` into the focused field, `--submit` on `fill` and `type`, and `table` guessing repeated cards (with the selector to pin them) and leaving button text out of cells. Rerun twice, TodoMVC took 10–13 commands instead of 16 and books.toscrape 5–9 instead of 10.

A tenth round (November 2026) was a pass over the code rather than a task round. It added a live regression script that drives the real Safari through the local test pages (134 checks: reading, acting, dialogs and frames, `wait`, `js`, logs, storage, cookies, `state`, `route` and its lifecycle, `challenge.html` and `captcha.html`) and `safari --selftest` for the pure functions. Its first runs found three real faults, now fixed: a dialog answer given on the top page stayed armed in child frames, so a later frame `confirm` was accepted; a click right after `fill` returned before a timer's change; and `js` left a stale route copy in place. The same pass gave plain routes a tag and a 37-minute lease, so a copy no daemon renews stops changing requests, and made an extension reconnect keep tab ids through the handle in the page.

An eleventh round (November 2026) came from two sessions. Agents in a harness that runs shell commands from a JavaScript REPL (stderr merged into stdout, a non-zero exit thrown as an error, a new shell per call) got notes in the middle of the data and had to parse error kinds from text; this led to the ordered, marked notes, `--json` on every verb and `references/scripting.md`. On cimri.com, a Cloudflare block page was taken for a check that would pass: safari waited 20 s and asked the user to solve it, and after a click it reported nothing wrong. Block pages now fail at once and hold the site, unruled sites get the 2-4 s pace, and `go` adds `https://` to an address like `cimri.com/arama?q=a:b`. These are covered by `make test` and by new `make test-live` checks (`Tests/blocked.html`, merged output, `--json`); no agent round has run on real sites since.

This was tested on one Mac (macOS 27), not across a wide range of sites.

## Limits

- Closed shadow DOM is not read. Up to 8 iframes are read.
- Some sites ignore in-page events, and `hover` only emulates readable CSS `:hover` rules. Use `--os` there.
- `--os` keys follow the keyboard layout (character keys are looked up on the current layout), so `cmd+i` works on Turkish Q as well as on AZERTY; `key A` types an upper-case A.
- On sites with strict CSP (GitHub, Gmail), the extension runs `js` in an isolated context: it sees the DOM but not the page's JavaScript variables.
- Dialogs during the first load of a site safari has not touched yet are Safari's own and block calls for 20 s (answerable with `dialog`, via Accessibility).
- Agents share one daemon, so they must put the tab id first (or set `SAFARI_TAB`) once more than one new tab is open.
- A plain `route` covers only the tab's own fetch/XHR, intercepted in the page (mocked ones never reach the network; Workers, `sendBeacon` and `EventSource` are not covered). Scripts, styles, images, frames and pages need `--global`: Safari's network rules ignore their tab filter, and its request events do not reliably say which tab asked, so they apply to every tab, the user's too, until `unroute`, the routing tab closes or the daemon stops. Plain routes end with the daemon too (`safari stop`, a restart for a new build, 30 min without commands): it clears them on exit, a page that stops hearing from it drops them within 37 min, and the next safari call to the tab drops any it no longer stands behind. With `--global`, Safari changes only standard header names (not custom `X-` ones), its regex engine lacks `|`, `{n}` and lookahead, a `--block` beats an overlapping mock, and a `--doc` page has the mock's origin (`127.0.0.1`), without site cookies. Workers, service workers and WebSocket messages are not mocked; a mocked fetch's `response.url` is the local mock address.
- `logs` keeps the first 4000 characters of text and JSON response bodies; streamed responses (`text/event-stream`, NDJSON) keep none. Console objects are shown as a short preview (3 levels, 10 keys or items), not full JSON.
- `record` covers one site in one tab, and does not record rich-text editors or password values.
- `shot --full` scrolls the page itself; pages that scroll an inner box show only their first screen.
- `pdf` lays out a snapshot of the page again with JavaScript off: images that need the user's login, content drawn by scripts after load and cross-origin canvases may be missing.
- In a private window whose cookie store Safari does not name, `cookies` sees only cookies the page can read (no HttpOnly).
- Safari web apps (Add to Dock) are not driven. Each runs its own copy of the extension, which safari leaves alone; `safari status` counts them as ignored.
- Data: URLs (sleeping tabs of extensions like Tab Sleeper) are hidden from extensions, so `tabs` lists them blank.
- Bot checks and block pages are recognised by their titles and markup; others pass unnoticed. Pacing and the hold after a block page cover `go`, `open` and `crawl`, not clicks that load a page; the hold lasts only as long as the daemon. safari does not get around blocks; when a site blocks the browser, the user decides what happens next.
- `main.js` (console and network hooks, dialog overrides, the recorder, route copies) runs on every page you visit, not only pages safari works in. What it keeps is bounded (previews, 4000-char bodies), and dialogs and routes act only in tabs safari has touched.
- A plain route's page copy outlives a daemon that crashed or was killed: until its lease ends (at most 37 min) or the next safari call to the tab, fetch/XHR that a mock matches still carry its `__smcp_m=…` marker, and with the redirect rule gone they reach the real site with it.
- `text` mode trims link text and data-table cells (200 chars, 60 rows); complex tables may lose layout. Tables used for page layout are read as text.
- Reading response bodies of every request, and real (trusted) input without `--os`, would need Safari's Web Inspector protocol, which only Apple-signed apps may use with your own Safari. Apple's `safaridriver --mcp` offers it in a separate, clean session without your tabs or cookies.

## Development

```bash
make test                                                   # build, page-script syntax, selftest, CLI and daemon test
make test-live                                              # live checks in the real Safari (extension on; its own background tabs)
(cd Tests && python3 -m http.server 8765 --bind 127.0.0.1)  # serve test pages
```

`make test` needs no Safari permission. `make test-live` drives the real Safari through the test pages, exits 77 when the extension is not connected, and skips the route-lease checks when the installed extension predates them. `safari --selftest` runs only the pure-function checks.

Open `http://127.0.0.1:8765/fixture.html` with `safari open` for manual checks (form, dialogs, delayed element, table, fetch, iframe). `route.html` (fetch/XHR/Worker buttons, and a script, stylesheet and image that are missing until `route` mocks them) and `drop.html` (a drop zone) cover `route` and `drop`.

## License

[MIT](LICENSE)
