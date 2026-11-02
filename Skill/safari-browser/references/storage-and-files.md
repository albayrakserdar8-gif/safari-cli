# Web storage, dropping files, whole-page screenshots

## `storage`: localStorage and sessionStorage of the tab's site

```bash
safari t5 storage                    # list localStorage (values cut at 120 chars)
safari t5 storage session            # list sessionStorage
safari t5 storage local cart         # one value, whole (--max N caps it)
safari t5 storage local theme dark   # set
safari t5 storage --delete theme     # (add `session` for sessionStorage)
safari t5 storage --clear
```

Storage often holds the user's tokens and settings. Read it to debug; set, delete or clear only in your own tab and when the user asks. Cookies are not available.

## `drop`: drag files in from outside the page

For drop zones without a file input (`upload` needs an `<input type=file>`). `read` lists controls only, so find the zone by its text: `read -q "drop"` (or `read -q "drag"`) gives its ref.

```bash
safari t5 drop e7 report.pdf photo.png    # ≤ 10 MB total
safari t5 drop --sel '.dropzone' --text 'plain text'
```

`(no drop handler took it: wrong element?)` means nothing accepted the drop: `read` again and drop on the zone's inner element, or check the result with `text -q`.

## `shot --full`: the whole page

```bash
safari t5 shot --full -o page.jpg
```

Scrolls one screen at a time, captures each, and stacks them (12 screens or 16000 px at most: a long article at phone width is cut, and the result then says `top N of M px`; read the rest with `text`). Fixed and sticky bars appear once, at the top. The scroll position is restored afterwards. It takes about 0.5 s per screen. Pages that scroll an inner box instead of the page only show their first screen. To capture another width, open a separate window and `resize` it first (see `selectors.md`).
