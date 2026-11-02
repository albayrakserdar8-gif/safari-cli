# Reading pages in detail

## Output format

- Every read starts with `title | url | scroll Y/MAX`.
- `read` lines are `e12 role "name"`; a field's value follows as `="Small"`, a checked box as `checked`. Controls without text are named from their icon or test hook (`button "trash"`); `(danger)` marks delete styling. Be sure before clicking either.
- `text` is markdown: links as `text[3]` with the URLs listed at the end, field values `[=v]`, checkboxes `[x]`/`[ ]`, table cells separated by ` | ` (a literal pipe is `\|`).
- `(+N controls off-screen …)` means `read --full` or `-q` would show more.

## Searching

- `read -q "sign in"`: controls and text anywhere on the page, best 10 hits.
- `text -q "pricing refund"`: BM25-ranked blocks of the main content (header or nav text: `read -q`).
- `links -q docs`: links whose text or URL contains every word.
- Wrap a pattern in slashes for a regular expression, with optional flags: `read -q '/^(sign in|log in)$/i'`, `text -q '/\d+[.,]\d{2} TL/'`, `links -q '/\.pdf$/'`. `read` matches it against each control's name, `text` against each block (paragraph, list item, table row; in page order, not ranked), `links` against text and URL. A bad pattern exits 1.
- A search with no hits (`no text matches …`) still exits 0.

## Scoping and caps

- `--ref e40` or `--sel "main table"` reads one part. Long header and nav: `read --sel main`.
- Field values are cut at 60 chars; `read --ref e7` on one field shows its whole value.
- Infobox facts sit at the top: `text --max 1500` beats `-q` for them.
- `--max N` sets the cap (read/text/links/table 6000, js 4000; 0 = all); `--offset K` continues; `-o FILE` writes the whole result.

## Changes

- `read --diff` shows `+` added, `~` changed, `-` gone controls since your last read of that view.
- On one page an element keeps its ref; elements a re-render creates (sorting, filtering, a new list item) get new ones.
- Lazy content exists only after scrolling to it: `scroll`, then `read --diff`.

## Frames and hidden content

- Iframes appear as `--- frame f1 <url>` blocks with refs like `f1e5`. `(N iframes not read …)` names frames out of reach; do not act in them.
- Shadow-root content, and text only an attribute holds (exact dates behind "Jul 15"), needs `js`: `js 'document.querySelector("relative-time").getAttribute("datetime")'`.

## Screenshots

`shot` writes a JPEG to the temp folder (`-o file.jpg` to choose) and prints its path; open that file to see it. `shot e12`, `shot --sel canvas` or `--region x,y,w,h` (viewport px) crops. Canvas and image content exist only here. If Safari is on another Space it comes forward for about a second. Whole page: `shot --full` (see `storage-and-files.md`).

## Recipe: find something on a site

`open URL` → `read -q search` → `fill eN "query" && key Enter eN` → `text -q "<what you need>"` (or `table` for result lists).
