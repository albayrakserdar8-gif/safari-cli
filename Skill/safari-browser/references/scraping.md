# Tables, paged lists and slow scraping

## `table`: rows as data

```bash
safari t5 table                     # TSV of the biggest visible table (or repeated cards), plus link and id columns
safari t5 table --json -o rows.json
safari t5 table --rows ".card"      # a list of cards: one row per match
safari t5 table --sel "#results table"
```

Without a table of 3+ rows, `table` guesses repeated cards (a product grid, results) and names them on stderr: `20 rows from cards article.product_pod (guessed; pin with --rows 'article.product_pod')`. Card columns are named after the card's parts (`h3`, `product_price`); button text is left out. If it picked the wrong list, give `--rows`; pass the same `--rows` to `crawl` when the guess could change between pages. Ad and separator rows and empty columns are dropped. Tables used for page layout are read poorly; use `text` there.

## Pacing per site

Sites that block fast crawling get a pace: seconds between page loads, saved.

```bash
safari rate example.com 8-14    # random 8-14 s between loads on example.com and its subdomains
safari rate                     # list
safari rate example.com off
safari t5 go URL --delay 8-14   # one call only
```

`go` and `open` wait for the site's slot (`(waited 9.4 s: pacing …)`). The daemon hands out slots, so several agents on one site queue up. A bot check or a 429/503 answer slows the site down for the session. Clicks that load a page are not paced.

## `crawl`: a paged list in one command

```bash
safari t5 crawl --pages 5 -o rows.tsv          # from this page: table, next page, repeat
safari t5 crawl --next "Sonraki" --rows ".card" --json -o rows.json
```

It follows `rel=next` or a link named "Next"/"Sonraki" (or `--next TEXT`), merges the rows and drops duplicates by `id`. Progress goes to stderr. Unpaced sites get 3-6 s between pages. A crawl of many pages takes minutes: run it in the background.

## Loops

Shell loops keep bulk output out of the conversation:

```bash
for u in $(cat urls.txt); do safari t5 go "$u" >/dev/null && safari t5 text --max 2000 >> pages.md; done
```

Write to files and grep them instead of printing everything.
