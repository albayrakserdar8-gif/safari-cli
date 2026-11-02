# Mocking, blocking and rewriting requests (`route`)

A plain `route` acts on the tab's own fetch/XHR (its frames too), inside the page: mocked and blocked requests never reach the network, and other tabs are untouched. Rules follow the tab to other sites and last until `unroute` or the tab closes; after a click that leaves the site they apply once the next safari command runs.

```bash
safari t5 route '*/api/cart*' --status 500 --body '{"error":"down"}'   # fake an error
safari t5 route '*/api/user' --body @user.json                        # data from a file (≤ 20 MB, binary ok)
safari t5 route '*/api/feed' --body '[]' --delay 2000                 # slow answer (ms)
safari t5 route '*/api/x' --status 429 --resp-header 'Retry-After: 30'
safari t5 route '*/track*' --block                                    # fail the request
safari t5 route '*/v1/*' --redirect https://staging.example.com/v1/x  # real request elsewhere
safari t5 route 'api.example.com' --header 'Accept-Language: de'      # change a real request
safari t5 route --list
safari t5 unroute '*/api/cart*'      # one rule; `unroute` alone removes all
```

Scripts, styles, images, fonts, frames and the page itself need `--global`, which uses Safari's network rules. **They apply to every Safari tab, the user's own too** (Safari cannot limit them to one tab), until `unroute`, the tab closes or the daemon stops. Ask the user first, keep patterns narrow, `unroute` when done.

```bash
safari t5 route '*/app.js' --body 'console.log("mock")' --type js --global
safari t5 route '*/logo.png' --body @logo.png --global                # type from the file name
safari t5 route '*/landing' --body '<h1>test</h1>' --type html --global --doc   # the page itself
```

- Patterns: a glob over the whole URL (`*` = anything: `*/api/*`; add a trailing `*` for query strings), a plain substring (`/api/cart`), or `re:REGEX`. Matching ignores case. A pattern that already has a rule is replaced; the newest matching rule wins.
- `--status` defaults to 200. `--type`: json, js, css, html, text, xml, svg, png, jpg, gif, webp or a full content type; without it a body starting with `{` or `[` is JSON, else text.
- `--header 'Name: value'` (repeatable; `'Name:'` removes, fetch only) changes the real request; `--resp-header` the mocked response, or the real one (fetch only, not XHR).
- Mocks come from a local server, so `response.url` is `http://127.0.0.1:4740x/…`.
- `--global` limits (Safari's rules): standard header names only, no `|`, `{n}` or lookahead in `re:`, `--block` beats an overlapping mock, a `--doc` mock page has the `127.0.0.1` origin and no site cookies. Set the route, then `go reload` to cover the page's first requests.
- `logs --net` marks routed requests `(mocked)` or `(blocked)`; action results report mocked 4xx/5xx like real ones.
- Not covered: Worker and service-worker requests, `sendBeacon`, `EventSource`, WebSocket messages. An empty pattern is refused, and so is a `--global` one that matches everything.

Use routes in the user's real session with care: a mocked API answer can trigger real follow-up requests (a mocked "cart empty" may lead the page to change the real cart). Prefer read-only endpoints, and `unroute` when done.
