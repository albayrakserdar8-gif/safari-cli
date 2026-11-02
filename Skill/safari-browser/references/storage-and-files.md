# Cookies, web storage, saved state, PDF, drop zones, full-page shots

Cookies and storage often hold the user's session tokens. Read them to debug; set, delete, clear or save them only in your own tab and when the user asks. Never print token values into the conversation unless needed.

## `cookies`: the tab's site

```bash
safari t5 cookies                 # name = value  domain/path httpOnly secure until DATE|session
safari t5 cookies sid             # one value, whole (--max N caps it)
safari t5 cookies theme dark      # set (keeps an existing cookie's domain, path and expiry)
safari t5 cookies --delete theme
safari t5 cookies --clear         # every cookie of this site
safari t5 cookies --domain .example.com   # list another domain's cookies
```

In a private window whose cookie store Safari does not name, only cookies the page itself can see are listed (no HttpOnly), and a note on stderr says so.

## `storage`: localStorage and sessionStorage

```bash
safari t5 storage                    # list localStorage (values cut at 120 chars)
safari t5 storage session            # list sessionStorage
safari t5 storage local cart         # one value, whole
safari t5 storage local theme dark   # set
safari t5 storage --delete theme     # (add `session` for sessionStorage)
safari t5 storage --clear
```

## `state`: save and restore a site's session

```bash
safari t5 state save site.json    # cookies + localStorage + sessionStorage of the tab's origin (file mode 0600)
safari t6 state load site.json    # the tab must be on the same origin; sets everything, then reloads
```

Use it to carry a login into a private window, or to back up before a test. `load` adds and overwrites; it does not delete other keys. The file holds session tokens: keep it out of repositories and delete it when done.

## `pdf`: the page as a PDF

```bash
safari t5 pdf -o page.pdf    # prints the path and page count
```

A snapshot of the page as it is now (form values and canvases included), laid out again for paper with the site's print styles; Safari stays in the background. Images that need the user's login and content drawn by scripts after load may be missing; use `shot --full` for an exact picture.

## `drop`: drag files in from outside the page

For drop zones without a file input. Find the zone by its text (`read -q drop`), then:

```bash
safari t5 drop e7 report.pdf photo.png    # ≤ 10 MB total
safari t5 drop --sel '.dropzone' --text 'plain text'
```

`(no drop handler took it: wrong element?)`: drop on the zone's inner element, or check with `text -q`.

## `shot --full`: the whole page

```bash
safari t5 shot --full -o page.jpg
```

Scrolls one screen at a time and stacks the captures, 12 screens at most (about 10,000 px of a page in a normal window; a cut result says `top N of M px`). For a long article, `pdf` or `text` is the better whole-page copy. Fixed bars appear once. About 0.5 s per screen. Pages that scroll an inner box show only their first screen. Another width: open a separate window and `resize` it first (see `selectors.md`).
