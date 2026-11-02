# Mocking and blocking requests (`route`)

Rules belong to one tab and last until `unroute` or the tab closes. They survive reloads and page loads within a site.

```bash
safari t5 route '*/api/cart*' --status 500 --body '{"error":"down"}'   # fake an error
safari t5 route '*/api/user' --body @user.json                        # fake data from a file (≤ 1 MB)
safari t5 route '*/api/feed' --status 200 --body '[]' --type application/json
safari t5 route '*.png' --block                                       # fail the request
safari t5 route --list
safari t5 unroute '*/api/cart*'      # one rule; `unroute` alone removes all
```

- Patterns: a glob over the whole URL (`*` = anything: `*/api/*`), a plain substring (`/api/cart`), or `re:REGEX`. The newest matching rule wins; `route` with a pattern that already has a rule replaces it.
- `--status` defaults to 200. Without `--type`, a body starting with `{` or `[` is `application/json`, else `text/plain`.
- Mocked: the page's `fetch` and `XMLHttpRequest`. The page sees the fake answer; nothing goes to the network.
- `--block` also stops images, scripts, styles, fonts and frames (through the extension's request blocking).
- Set the route, then `go reload`: the rule then applies from the page's first request. Without the reload only later requests are mocked.
- `logs --net` marks mocked requests `(mocked)`; action results report mocked 4xx/5xx like real ones (`· failed: n2 GET 500 …`).
- Not mocked: the page's own document (the top-level load), WebSockets, service-worker requests and anything before the extension was enabled. After `go` to another site, safari re-applies the rules once that page loads; a click that leaves the site loses them until you `route` again.
- Without the Safari CLI Bridge extension, rules start only once safari touches each new page, and `--block` covers fetch/XHR only.

Use routes in the user's real session with care: a mocked API answer can trigger real follow-up requests (a mocked "cart empty" may lead the page to change the real cart). Prefer read-only endpoints, and `unroute` when done.
