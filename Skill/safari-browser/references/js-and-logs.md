# JavaScript and logs

## `js`

```bash
safari t5 js 'document.title'                       # a bare expression is returned
safari t5 js 'const n = document.links.length; return n * 2'
safari t5 js 'el.getAttribute("datetime")' e12      # an element after the code is `el`
safari t5 js - <<'EOF'
const rows = [...document.querySelectorAll('tr')];
return rows.map(r => r.innerText).join('\n');
EOF
```

- Several statements need `return`. Strings print as plain text, other values as JSON. Async code is fine; 15 s limit.
- It runs in the top frame only; frame content: `read`/`text`.
- Use it for data `read` and `text` do not show. Do not click or type with it when `click`/`fill` can.
- `(page CSP blocks eval: …)` means the code ran with DOM access but without the page's own JavaScript variables.
- Output is capped at 4000 chars: `--max 0` or `-o FILE` for more.

## `logs`

```bash
safari t5 logs                 # console
safari t5 logs --errors        # or --warn
safari t5 logs --new           # only lines since your last logs call
safari t5 logs --net           # requests, with ids like n4
safari t5 logs --net -p .jpg   # images, scripts and styles only with -p (a plain substring)
safari t5 logs --id n4         # one response body
safari t5 logs --clear
```

- `ERR` means no response was seen (aborted, blocked or cached), not always a failure.
- Capture starts when safari first touches the page (with the extension: when the page opens). Pages loaded before the extension was enabled need a reload.
- After an action, `· failed: n7 POST 400 …` already names failed requests; `logs --id n7` shows the body.
