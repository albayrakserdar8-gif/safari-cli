# safari-cli

[Türkçe](README.tr.md)

A `safari` command that lets coding agents (Claude Code, opencode, anything with a shell) drive your real Safari, with your logged-in sessions. One Swift binary, no dependencies. Forked from [safari-mcp](https://github.com/sadopc/safari-mcp): same engine, a CLI and a skill instead of an MCP server.

It talks to Safari through the optional **Safari CLI Bridge** extension when it is installed, and through Apple Events otherwise.

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
| Dialogs, file upload, iframes | Yes (iframes with the extension) | Yes | Yes | — |
| Network interception | fetch/XHR mocking and request blocking (`route`) | Yes | Yes (`route`) | — |
| Cookies, saved state, PDF | Yes (`cookies`, `state`, `pdf`) | Yes | Yes | — |
| Web search with cited sources | Through the sites it opens | No | Through the sites it opens | Yes (SearxNG) |
| LLM | The agent's | None of its own | The agent's | Any: Ollama, OpenAI, Claude, Gemini, Groq |
| Setup | Swift build, optional Safari extension | npm or pip package | npm package (Node 18+), skill via `install --skills` | Docker image (includes SearxNG) |
| Platform | macOS 14+ | macOS, Windows, Linux | macOS, Windows, Linux | Anywhere Docker runs |
| Best for | Everyday tasks on sites you are logged into | Testing, CI, repeatable automation | Agent-driven testing and automation in a separate browser | Private research questions with cited answers |

## Why a CLI instead of MCP

- Output can be filtered and saved in the shell (`| grep`, `| head`, `> page.md`), so long pages need not enter the conversation.
- Known sequences run in one shell command with `&&`; loops crawl pages without each result reaching the model.
- No server registration: any agent that can run a command can use it, and a rebuild takes effect on the next command.
- The usage guide lives in a skill that is loaded only for browser tasks.

## Install

Needs macOS 14 or later and the Command Line Tools (Xcode only for the extension).

```bash
git clone https://github.com/albayrakserdar8-gif/safari-cli.git
cd safari-cli && make install
```

`make install` builds the binary, links it into `/opt/homebrew/bin` (or `/usr/local/bin`; set `PREFIX=` for another place) and links the skill for Claude Code and opencode. `make uninstall` removes the links.

A background daemon keeps tab ids and the extension connection between commands. The first `safari` command starts it (about 0.2 s), later commands take a few milliseconds, and it exits after 30 idle minutes. After a rebuild, the next command restarts it on the new binary. `safari status` shows its state, `safari stop` stops it.

### Skill

`Skill/safari-browser/SKILL.md` teaches the agent the core commands and the rules: work in its own tab, prefer `read` over screenshots, and ask before submitting, buying or deleting anything. Details (forms, scraping, `js`, cookies and storage, mocking, recording) live in `references/` files the agent reads only when a task needs them. `make install` links it into `~/.claude/skills` and `~/.config/opencode/skills`.

In Claude Code, adding `"Bash(safari:*)"` to `permissions.allow` in `~/.claude/settings.json` stops the per-command prompts.

### Safari extension (recommended)

With the extension, no Automation or "Allow JavaScript from Apple Events" permission is needed, iframes can be read, HTTP status codes (404) are reported, network logging starts when the page opens, and screenshots of a visible tab need no Screen Recording permission. Without it, safari falls back to Apple Events.

Building it needs Xcode:

1. Add an Apple ID in Xcode > Settings > Accounts (a free account works).
2. Open `Extension/Safari MCP Bridge/Safari MCP Bridge.xcodeproj` and pick your Personal Team under Signing & Capabilities for both targets.
3. Build and install:
   ```bash
   Extension/build.sh --schedule
   ```
   `--schedule` adds a weekly job that re-signs the extension, because free-account signatures expire.
4. In Safari > Settings > Extensions, enable **Safari CLI Bridge** and allow it on every website. For private tabs, also turn on "Allow in Private Browsing". After an update that adds a permission (cookies, in the November 2026 build), Safari may turn the extension off until you enable it again.

The daemon and extension talk over `127.0.0.1` (ports 47391–47399) and authenticate each other with a key in `~/.config/safari-mcp/token`, so other pages or local programs cannot connect. The extension is the same one safari-mcp uses; both can be installed at once.

Safari does not let extensions into `file://` pages; those always use Apple Events.

## Permissions

| Permission | Used for | With extension | Without |
|---|---|---|---|
| Safari extension, on every website | Everything | Required | — |
| Automation (control Safari) | Everything | Not needed | Required, asked on first use |
| Safari > Settings > Developer > "Allow JavaScript from Apple Events" | Everything except `tabs` | Not needed | Required |
| Screen Recording | `shot` | Only when the tab is not on screen | Required |
| Accessibility | `--os`, native dialogs, exact screenshot cropping | Optional | Optional; needed for private windows |

These go to the app that runs the agent (your terminal). If the Developer tab is missing, turn on Settings > Advanced > "Show features for web developers". Note that "Allow JavaScript from Apple Events" applies to every app allowed to control Safari.

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
| `T table [--rows CSS] [--json]` | A table or list of cards as TSV/JSON, with each row's link and `data-id` |
| `T crawl [--next TEXT] [--pages N]` | `table` on each page of a paged list, following "Next", merged and deduplicated |
| `rate [SITE [S\|off]]` | Seconds between page loads per site (`rate example.com 8-14`), saved |
| `T click R`, `dblclick`, `hover`, `fill`, `type`, `select`, `key`, `scroll`, `wait`, `upload`, `drop`, `dialog` | Act on the page (`drop` drops files on a drop zone) |
| `T locator R`, `T highlight R` | A CSS selector for R that lasts across page loads; a box around R in your view |
| `T js CODE [R]` | Run JavaScript in the page (async function body, 15 s limit; `-` reads stdin); an element after the code is `el` |
| `T shot [--full]` | JPEG of the viewport, an element, a region or the whole page; prints its path |
| `T resize W H` | Viewport size, in a window that holds only agent tabs |
| `T route PATTERN`, `T unroute` | Mock the page's fetch/XHR answers (`--status`, `--body`), or `--block` requests |
| `T storage`, `T cookies` | List, get, set or delete localStorage/sessionStorage, or the site's cookies (HttpOnly too with the extension) |
| `T state save\|load FILE` | The site's cookies and web storage to a file (mode 0600) and back |
| `T check R`, `T uncheck R` | Set a checkbox or radio; safe to repeat |
| `T pdf` | The page as a paged PDF, rendered from a snapshot of its DOM in the background |
| `T record`, `T record --stop` | Record what you do in a tab, printed as `safari` commands to replay |
| `T logs` | Console and network logs, with response bodies by `--id` |
| `downloads [--wait]` | Recent downloads from Safari's list; `--wait` until they finish, then the saved paths |

Results go to stdout; errors to stderr with exit status 1 (2 for wrong usage). Long results are capped (`--max N`, `--max 0` for all); notes such as `… N more chars; --offset K` and row counts go to stderr, so piped data stays clean. `-o FILE` writes the whole result of `read`, `text`, `links`, `table` and `js` to a file.

How it behaves:

- **Refs.** `read` gives each element a ref like `e12`, which the actions use. Refs last for the current page only.
- **Tabs.** Tabs get stable ids like `t3`. Before every action Safari checks it is still the expected tab, so safari never acts on the wrong one. Commands without a tab id use the last tab used; new tabs open in the background. `open --private` opens a private window (later private tabs join it); `tabs` marks such tabs `(private)`. Tabs opened with `open` are marked `(agent)`; if no command uses one for 30 minutes, the daemon closes it, unless it is the visible tab in one of your windows or was brought forward with `show`. `SAFARI_TAB=t3` in the environment makes t3 the tab for commands that name none.
- **Rich text.** `select R "words"` selects text in a field or editor; `key cmd+b R` (or `cmd+i`, `cmd+u`) then formats it, also in editors inside frames that cannot take focus.
- **Results.** Actions wait for page loads and report `→ title | url` when the page changes. They also report new text, failed requests (4xx/5xx) and other fields that changed.
- **Input.** By default clicks and typing are in-page events: Safari stays in the background and you keep your cursor. `--os` sends real mouse/keyboard events for sites that ignore in-page events; it briefly brings Safari to the front.
- **Dialogs.** `alert` is accepted, `confirm`/`prompt` are dismissed unless `dialog` or `click --answer` sets an answer first. Each one is reported in the result. Only tabs safari works in are affected; your own browsing keeps normal dialogs.
- **Screenshots.** If Safari is on another Space or full screen, it is brought forward for about a second, then the previous app comes back.
- **Bot checks.** `open`, `go` and `wait --load` recognise check pages (Cloudflare "Just a moment…", PerimeterX, captchas) and wait up to 20 s for them to pass by themselves; the result then describes the real page. A check that stays is an error naming the tab, so you can show it and solve it, then `wait --load`.
- **Pacing.** `safari rate SITE 8-14` (or `go --delay 8-14`) spaces page loads on a site. The daemon hands out time slots and the command waits for its own, so several agents on one site queue up and the daemon stays free. A bot check or a 429/503 answer slows the site down for the session (4-8 s without a rule, else double).

## Resource use

Measured on one Mac:

| | |
|---|---|
| Skill | about 1,450 tokens, loaded only for browser tasks; eight `references/` files (400-850 tokens each) are read only when a task needs them (the MCP version sent about 875 tokens of tool schemas every session, plus its skill) |
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

This was tested on one Mac (macOS 27), not across a wide range of sites.

## Limits

- Closed shadow DOM is not read. Up to 8 iframes are read; without the extension only same-origin frames whose CSP allows it.
- Some sites ignore in-page events, and `hover` only emulates readable CSS `:hover` rules. Use `--os` there.
- On sites with strict CSP (GitHub, Gmail), the extension runs `js` in an isolated context: it sees the DOM but not the page's JavaScript variables.
- HTTP status codes are only reported with the extension.
- Without the extension, logs start when safari first touches the page, and dialogs that open before that block calls for 20 s (answerable via Accessibility).
- Agents share one daemon, so they must put the tab id first (or set `SAFARI_TAB`) once more than one new tab is open.
- `route` mocks the page's fetch and XHR, not the page's own document, WebSockets or service workers; it starts with each page only with the extension. A click that leaves the site drops the routes until `route` runs again.
- `record` needs the extension, covers one site in one tab, and does not record rich-text editors or password values.
- `shot --full` scrolls the page itself; pages that scroll an inner box show only their first screen.
- `pdf` lays out a snapshot of the page again with JavaScript off: images that need the user's login, content drawn by scripts after load and cross-origin canvases may be missing.
- Without the extension `cookies` sees only cookies the page can read (no HttpOnly, no domain or expiry), and `state load` cannot restore HttpOnly cookies.
- Without the extension, a tab can be lost if it navigates elsewhere while tabs open or close at the same time; safari then returns an error instead of guessing.
- Bot checks are recognised by their titles and markup; others pass unnoticed. Pacing covers `go`, `open` and `crawl`, not clicks that load a page.
- `text` mode trims link text and data-table cells (200 chars, 60 rows); complex tables may lose layout. Tables used for page layout are read as text.
- Full browser control (real input, all network traffic) would need Safari's Web Inspector protocol, which only Apple-signed apps may use with your own Safari. Apple's `safaridriver --mcp` offers it in a separate, clean session without your tabs or cookies.

## Development

```bash
Tests/smoke.sh                                             # CLI and daemon test, no Safari permission needed
(cd Tests && python3 -m http.server 8765 --bind 127.0.0.1)  # serve test pages
```

Open `http://127.0.0.1:8765/fixture.html` with `safari open` for manual checks (form, dialogs, delayed element, table, fetch, iframe). `route.html` (fetch/XHR buttons and an image) and `drop.html` (a drop zone) cover `route` and `drop`.

## License

[MIT](LICENSE)
