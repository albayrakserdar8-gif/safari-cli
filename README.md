# safari-cli

[Türkçe](README.tr.md)

A `safari` command that lets coding agents (Claude Code, opencode, anything with a shell) drive your real Safari, with your logged-in sessions. One Swift binary, no dependencies. Forked from [safari-mcp](https://github.com/sadopc/safari-mcp): same engine, a CLI and a skill instead of an MCP server.

It talks to Safari through the optional **Safari MCP Bridge** extension when it is installed, and through Apple Events otherwise.

Independent project, not affiliated with Anthropic. It was written because Claude in Chrome only works in Chromium browsers.

## When to use it

Good for everyday work on sites you are logged into: reading, searching, filling forms, navigating. For web app testing, CI or repeatable automation, use Playwright (or Apple's `safaridriver`) instead. To get researched answers with sources rather than act on pages, a search engine like [Vane](https://github.com/ItzCrazyKns/Vane) fits better.

| | safari-cli | Playwright | Vane |
|---|---|---|---|
| What it is | CLI that drives your Safari | Browser automation library | Self-hosted AI answer engine |
| Driven by | Claude Code, opencode, any agent with a shell | Your scripts, or an agent through Playwright MCP | Its own LLM pipeline, from its web UI or API |
| Browser | Your open Safari | A separate browser it launches | Headless Chromium (via Playwright), only to read pages |
| Your logged-in sessions | Yes | Only with saved profiles or state | No |
| Clicks, typing, forms | Yes | Yes | No, read-only |
| Dialogs, file upload, iframes | Yes (iframes with the extension) | Yes | — |
| Network interception | No (logs only) | Yes | — |
| Web search with cited sources | Through the sites it opens | No | Yes (SearxNG) |
| LLM | The agent's | None of its own | Any: Ollama, OpenAI, Claude, Gemini, Groq |
| Setup | Swift build, optional Safari extension | npm or pip package | Docker image (includes SearxNG) |
| Platform | macOS 14+ | macOS, Windows, Linux | Anywhere Docker runs |
| Best for | Everyday tasks on sites you are logged into | Testing, CI, repeatable automation | Private research questions with cited answers |

## Why a CLI instead of MCP

- Output can be filtered and saved in the shell (`| grep`, `| head`, `> page.md`), so long pages need not enter the conversation.
- Known sequences run in one shell command with `&&`; loops crawl pages without each result reaching the model.
- No server registration: any agent that can run a command can use it, and a rebuild takes effect on the next command.
- The usage guide lives in a skill that is loaded only for browser tasks.

## Install

Needs macOS 14 or later and the Command Line Tools (Xcode only for the extension).

```bash
git clone https://github.com/sadopc/safari-cli.git
cd safari-cli && swift build -c release
ln -s "$PWD/.build/release/safari" /opt/homebrew/bin/safari     # or any folder on PATH
```

A background daemon keeps tab ids and the extension connection between commands. The first `safari` command starts it (about 0.2 s), later commands take a few milliseconds, and it exits after 30 idle minutes. After a rebuild, the next command restarts it on the new binary. `safari status` shows its state, `safari stop` stops it.

### Skill

`Skill/safari-browser/SKILL.md` teaches the agent the commands and the rules: work in its own tab, prefer `read` over screenshots, and ask before submitting, buying or deleting anything.

```bash
ln -s "$PWD/Skill/safari-browser" ~/.claude/skills/safari-browser            # Claude Code
ln -s "$PWD/Skill/safari-browser" ~/.config/opencode/skills/safari-browser   # opencode
```

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
4. In Safari > Settings > Extensions, enable **Safari MCP Bridge** and allow it on every website. For private tabs, also turn on "Allow in Private Browsing".

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
| `tabs`, `open URL [--private]`, `T show`, `T close` | List, open (in the background), show, close tabs |
| `T go URL\|back\|forward\|reload` | Load and wait |
| `T read`, `T text`, `T links` | Controls with refs, page as markdown, links; `-q` to search, `--diff` for changes only |
| `T click R`, `dblclick`, `hover`, `fill`, `type`, `select`, `key`, `scroll`, `wait`, `upload`, `dialog` | Act on the page |
| `T js CODE` | Run JavaScript in the page (async function body, 15 s limit; `-` reads stdin) |
| `T shot` | JPEG of the viewport, an element or a region; prints its path |
| `T logs` | Console and network logs, with response bodies by `--id` |

Results go to stdout; errors to stderr with exit status 1 (2 for wrong usage).

How it behaves:

- **Refs.** `read` gives each element a ref like `e12`, which the actions use. Refs last for the current page only.
- **Tabs.** Tabs get stable ids like `t3`. Before every action Safari checks it is still the expected tab, so safari never acts on the wrong one. Commands without a tab id use the last tab used; new tabs open in the background. `open --private` opens a private window (later private tabs join it); `tabs` marks such tabs `(private)`.
- **Results.** Actions wait for page loads and report `→ title | url` when the page changes. They also report new text, failed requests (4xx/5xx) and other fields that changed.
- **Input.** By default clicks and typing are in-page events: Safari stays in the background and you keep your cursor. `--os` sends real mouse/keyboard events for sites that ignore in-page events; it briefly brings Safari to the front.
- **Dialogs.** `alert` is accepted, `confirm`/`prompt` are dismissed unless `dialog` or `click --answer` sets an answer first. Each one is reported in the result. Only tabs safari works in are affected; your own browsing keeps normal dialogs.
- **Screenshots.** If Safari is on another Space or full screen, it is brought forward for about a second, then the previous app comes back.

## Resource use

Measured on one Mac:

| | |
|---|---|
| Skill | about 2,100 tokens, loaded only for browser tasks (the MCP version sent about 875 tokens of tool schemas every session, plus its skill) |
| Default `read` | about 500 tokens (Wikipedia home), 1,100 (Hacker News) |
| Call time | `read` 7–60 ms, actions 170–470 ms, `shot` 0.9–2.1 s; about 10 ms more per command, 0.2 s for the first one that starts the daemon |
| Memory | 9 MB idle, about 34 MB after use |
| Idle CPU | 0 |

One daemon serves every agent and session; it exits after 30 idle minutes.

## Testing status

The page engine was tested in safari-mcp over six rounds in which Claude Haiku agents did real tasks using only the tool descriptions: Wikipedia, Hacker News, MDN, GitHub, DuckDuckGo, sign-up, cart and checkout flows on demo shops (automationexercise, Toolshop/Angular, saucedemo/React, demowebshop), the-internet and TodoMVC. Bugs found in each round were fixed; by the last rounds all tasks finished correctly without falling back to `js` or `os: true` for actions, and call counts on the hardest tasks roughly halved. The CLI layer is new: it was checked by hand on the test page with both the extension and Apple Events, but not yet in agent rounds on real sites.

This was tested on one Mac (macOS 27), not across a wide range of sites.

## Limits

- Closed shadow DOM is not read. Up to 8 iframes are read; without the extension only same-origin frames whose CSP allows it.
- Some sites ignore in-page events, and `hover` only emulates readable CSS `:hover` rules. Use `--os` there.
- On sites with strict CSP (GitHub, Gmail), the extension runs `js` in an isolated context: it sees the DOM but not the page's JavaScript variables.
- HTTP status codes are only reported with the extension.
- Without the extension, logs start when safari first touches the page, and dialogs that open before that block calls for 20 s (answerable via Accessibility).
- Agents share one daemon, so they must put the tab id first once more than one new tab is open.
- Without the extension, a tab can be lost if it navigates elsewhere while tabs open or close at the same time; safari then returns an error instead of guessing.
- `text` mode trims link text and table cells; complex tables may lose layout.
- Full browser control (real input, all network traffic) would need Safari's Web Inspector protocol, which only Apple-signed apps may use with your own Safari. Apple's `safaridriver --mcp` offers it in a separate, clean session without your tabs or cookies.

## Development

```bash
Tests/smoke.sh                                             # CLI and daemon test, no Safari permission needed
(cd Tests && python3 -m http.server 8765 --bind 127.0.0.1)  # serve test pages
```

Open `http://127.0.0.1:8765/fixture.html` with `safari open` for manual checks (form, dialogs, delayed element, table, fetch, iframe).

## License

[MIT](LICENSE)
