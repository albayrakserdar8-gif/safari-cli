# Forms, keys, rich text, uploads, downloads, dialogs

## Fields

- One command for a form: `safari t5 fill e4=Ada e5=Large e6=true` (text, `<select>` option text or value, `true`/`false` for checkboxes and radios). Quote values with spaces: `e4="Ada Lovelace"`.
- One field: `fill e4 "text"` replaces the value, `type e4 "text"` appends. `fill` replaces everything, so keep what must stay (a search filter like `is:issue`).
- Checkboxes and radios: `check e6` / `uncheck e6` (or `fill e6=true`) set the state and are safe to repeat; `click` toggles. A radio cannot be unchecked: check another option of its group.
- Every element argument can also be `--sel CSS` or `--xy X,Y`: `fill --sel 'input[name=email]' a@b.c`.
- `· also changed: …` lists fields the page changed itself (autofill, resets): check them before submitting.
- Some fields commit only when you leave them (cart quantities): `fill e7 2 && key Tab e7`, then check the result.
- `select e5 "Large"` picks an option of a `<select>`; a miss lists the options. Custom dropdowns (react-select and the like) are not `<select>`: `fill e18 Maths && key Enter e18`, or `click` the box, then `read -q` the option and `click` it.
- Date pickers: type the date into the field (`fill e18 "10 Dec 1815" && key Enter e18`) instead of paging through months. If typing is refused, open the picker, `select` its month and year boxes, then `click` the day (`read -q '/^15$/'`).
- A search box missing from `read` is often behind a search button: click that, then `read -q search`.
- To edit a list item that opens on double-click, `dblclick` its label, not its checkbox.

## Clicks and pointer

- `click e12 --right` opens a context menu. `drag e4 --to e6` (or `--to '#column-b'`) drags and drops.
- `hover e5` applies the page's CSS `:hover` rules, so hover menus open; use `--os` only when it says stylesheets were unreadable and nothing showed.
- `--os` sends real mouse and keyboard events. It brings Safari forward for a moment and needs Accessibility permission for the terminal app, which only the user can grant.
- `scroll` (one screen), `scroll -400`, `scroll e30` (into view), `scroll e30 400` (the box that holds it).

## Keys and rich text

- `key Enter` (or `cmd+a`, `Escape`, `Tab`, `shift+Tab`); add a ref to target a field. Enter in a field submits its form. A key without a ref goes to the field you last acted on.
- Editing keys work in fields and editors: `key cmd+a e4` then `key Backspace` clears.
- Rich text: `select e4 "some words"`, then `key cmd+b e4` (or `cmd+i`, `cmd+u`) reports `(bold on)`; `text --ref e4` shows `**bold**`.
- `(handled by page)`: the page's code took the key. Sliders take arrows, `Home`, `End`.

## Waiting

`wait "Order placed"` (or `--ref`, `--sel`, `--gone`, `--timeout S` up to 30). `already present` means it was there before: wait for something only the new state has.

## Files

- Upload: `upload e9 a.pdf b.png` (an `<input type=file>`, 10 MB total). Drop zones without one: `drop` (see `storage-and-files.md`).
- Download: click the link, then `safari downloads --wait` prints the saved path (exit 1 if it failed). `waiting … allow downloads from <site>`: ask the user to click Allow in Safari.

## Dialogs (alert / confirm / prompt)

- In tabs you work in: `alert` acknowledged, `confirm`/`prompt` **dismissed** by default, each reported as `⚠ dialog …`.
- To accept: `click e12 --answer accept` (or a prompt reply: `--answer "Ada"`), or `safari t5 dialog accept` before the click. Accept only when the user wants that action.
- "Safari did not answer in time; the page may be showing a dialog": a native dialog is up. Answer it with `dialog dismiss` (or `accept`).

## Recipe: check a form flow

`read` → `fill e4=… e5=…` → `click` submit → read the result line; if the outcome comes later, `wait "<success text>"` then `read --diff` → `logs --errors` if anything fails.
