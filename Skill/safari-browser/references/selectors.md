# Stable selectors, highlighting, elements in js, window size

## `locator`: a selector that outlives the page

Refs (`e12`) die on every page load. For a script or a sequence you will run again, turn a ref into a CSS selector:

```bash
safari t5 locator e10        # --sel 'button[data-testid="buy"]'  e10 button "Buy"
safari t5 click --sel 'button[data-testid="buy"]'
```

Plain text has refs too: `read -q "some words"` lists it as `eN text "…"`, for `locator`, `highlight` and `js`.

It prefers test hooks (`data-testid`, `data-test`, `data-qa`, `data-cy`), stable ids, `name`, `aria-label`, `placeholder`, `href`, then a short path from the nearest stable id (`#login > button`, `form:nth-of-type(2) > input`), and checks that the selector matches only that element. The last kind breaks when the layout changes, so re-check it after site updates. Elements in a shadow root have no `--sel`; use refs there. `--sel` looks in the top page only.

## `highlight`: show the user an element

```bash
safari t5 highlight e10             # red box for 5 s
safari t5 highlight e10 --for 0     # until: safari t5 highlight --hide
```

Use it before asking the user to confirm something ("I will click this"). It draws in the tab, so the user sees it only when the tab is visible (`safari t5 show`, if they want to look).

## `js` on one element

An element after the code is `el` inside it:

```bash
safari t5 js 'el.value' e4
safari t5 js 'getComputedStyle(el).color' --sel '#logo'
safari t5 js 'el.dataset' --xy 300,200
```

Refs inside frames (`f1e4`) cannot be `el`: js runs in the top page.

## Window size (responsive checks)

`resize` sets the viewport, and only in a window that holds nothing but your tabs, so the user's windows keep their size:

```bash
safari open URL --window --id-only   # → t7, in a separate window
safari t7 resize 390 844            # → t7 viewport 390x844
safari t7 shot
```

## Cleaning up

`safari close --agents` closes every tab opened with `open` that is not on screen or `show`n (plus windows that hold only agent tabs). It lists the ones it kept.

## Several agents at once

Each agent should name its tab: `safari t5 read`. `SAFARI_TAB=t5` in the environment makes t5 the tab for every command that names none, where the environment lasts between commands (not in harnesses that start a new shell per call); an explicit tab id still wins.
