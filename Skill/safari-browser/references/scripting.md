# Running safari from a script or REPL

Some harnesses run shell commands from a script (a JavaScript REPL, say) rather than an interactive shell. There:

- **Every call is a new shell.** `export`, `cd` and `T=$(…)` do not carry over. Keep the tab id in a script variable and put it first on every command.
- **stderr may be merged into stdout.** safari then prints the data first and the notes after it, each as `note: …`. Simpler: `--json` (any verb, anywhere before `--`) prints one JSON object on stdout and nothing on stderr; the exit status stays the same.

```
{"ok":true,"tab":"t5","url":"…","title":"…","nav":true,"text":"…","notes":["… 812 more chars; --offset 5990 (or --max 0, -o FILE)"]}
{"ok":false,"kind":"blocked","error":"t5: example.com blocked this browser …","tab":"t5"}
```

`url` comes with almost every call on a tab, `title` mainly after calls that loaded a page, `nav` only when one did. `table` and `crawl` give `rows` (objects; `crawl` adds `pages`) instead of `text`; with `-o FILE`, `file` and `chars`; `shot` gives `files`. A failure can carry `rows` and `notes` too (a crawl that stopped on page 3). `--id-only` is ignored with `--json`.

- **A non-zero exit may throw.** Exit 1 is an ordinary outcome, so run safari so that it does not throw and branch on `ok` and `kind`:

| kind | meaning |
|---|---|
| `gone` | the tab id is no longer valid: `safari tabs` |
| `timeout` | `wait` or `js` ran out of time |
| `check` | a bot check that stayed: show it to the user |
| `blocked` | the site blocked the browser, or its loads are held: stop and tell the user |
| `offline` | the extension is not connected |
| `noanswer`, `dialog` | Safari did not answer, most likely a native dialog: `dialog accept` or `dismiss` |
| `usage` | wrong arguments (exit 2) |
| `error` | anything else: read `error` |

- **The daemon handles one call at a time,** for every agent, in order. Parallel calls (`Promise.all`) save time only where the client waits by itself: pacing between page loads, `pdf`, `crawl`, `downloads --wait`. Never run calls without a tab id in parallel.
- **Fetch once, filter in code:** `--max 0` (or `-o FILE` for very large pages), then filter in the script, rather than paging with `--offset`.
- Long crawls take minutes: give the command a long enough timeout, or run it in the background with `-o FILE`.

Example, for a harness that runs shell commands from JavaScript with a `$` tag (an array value becomes one argument per item; `.nothrow()` keeps a non-zero exit from throwing). `--json` goes first, so text after a `--` stays text:

```js
const safari = async (...a) => JSON.parse((await $`safari --json ${a}`.nothrow()).stdout);
const o = await safari('open', 'https://example.com');
if (!o.ok) throw new Error(`${o.kind}: ${o.error}`);
const t = o.tab;
const r = await safari(t, 'text', '--max', '0');
const hits = r.ok ? r.text.split('\n').filter(l => /price/i.test(l)) : [];
await safari(t, 'close');
```
