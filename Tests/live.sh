#!/bin/bash
# Live regression test (make test-live): drives the user's real Safari through the shared daemon and
# the Safari CLI Bridge extension, against the pages in Tests/ served on a free 127.0.0.1 port.
# It opens background tabs and closes exactly those on exit; it never touches other tabs.
# Exit 77 (skip) when the extension is not connected. LIVE_INTRUSIVE=1 adds shot and --os input,
# which bring Safari forward. Run from the project root: Tests/live.sh [BIN]
BIN="$(cd "$(dirname "${1:-.build/release/safari}")" && pwd)/$(basename "${1:-.build/release/safari}")"
DIR="$(cd "$(dirname "$0")" && pwd)"
# The real daemon and config: a separate daemon would fight it for the extension connection.
unset SAFARI_CLI_HOME SAFARI_TAB
base=${TMPDIR:-/tmp}
tmp=$(mktemp -d "${base%/}/safari-live.XXXXXX")
fail=0 nok=0 nfail=0 nskip=0
TABS=() SERVER="" RATE_RESET="" COOKIE="" T=""

cleanup() {
  [ -n "$COOKIE" ] && [ -n "$T" ] && "$BIN" "$T" cookies --delete "$COOKIE" >/dev/null 2>&1
  local t
  for t in "${TABS[@]}"; do "$BIN" "$t" close >/dev/null 2>&1; done
  [ -n "$RATE_RESET" ] && "$BIN" rate 127.0.0.1 off >/dev/null 2>&1
  "$BIN" rate 127.0.0.1 reset >/dev/null 2>&1   # a hold left by the block page checks
  [ -n "$SERVER" ] && kill "$SERVER" 2>/dev/null && wait "$SERVER" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

st=$("$BIN" status 2>&1)
if [[ $st != *"extension connected"* ]]; then
  echo "skip live test: the Safari CLI Bridge extension is not connected (safari status: ${st//$'\n'/ })"
  exit 77
fi

python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$DIR" >"$tmp/http.log" 2>&1 &
SERVER=$!
PORT=""
for _ in $(seq 50); do
  PORT=$(sed -nE 's/^Serving HTTP on .* port ([0-9]+).*/\1/p' "$tmp/http.log")
  [ -n "$PORT" ] && break
  sleep 0.1
done
[ -n "$PORT" ] || { echo "FAIL could not start python3 -m http.server: $(cat "$tmp/http.log")"; exit 1; }
URL="http://127.0.0.1:$PORT" LURL="http://localhost:$PORT"   # two origins, one server
echo "serving Tests/ on $URL"

ok()   { echo "ok   $1"; nok=$((nok + 1)); }
skip() { echo "skip $1"; nskip=$((nskip + 1)); }
bad()  {
  echo "FAIL $1"; shift
  local l; for l in "$@"; do printf '%s\n' "$l" | head -40 | sed 's/^/       /'; done
  fail=1; nfail=$((nfail + 1))
}
# s ARGS…: run safari; OUT = stdout, ERR = stderr, RC = exit status.
s() { OUT=$("$BIN" "$@" 2>"$tmp/err"); RC=$?; ERR=$(<"$tmp/err"); LAST="safari $*"; }
j() { s "$T" js "$@"; }
got() { printf '%s\nexit %s\nstdout: %s' "$LAST" "$RC" "$OUT"; [ -n "$ERR" ] && printf '\nstderr: %s' "$ERR"; }
# is NAME WANT: exit 0 and stdout exactly WANT.
is() { if [ "$RC" = 0 ] && [ "$OUT" = "$2" ]; then ok "$1"; else bad "$1" "want exit 0, stdout: $2" "$(got)"; fi; }
# has NAME TEXT…: exit 0 and stdout contains every TEXT.
has() {
  local n="$1" w; shift
  [ "$RC" = 0 ] || { bad "$n" "want exit 0" "$(got)"; return; }
  for w in "$@"; do [[ $OUT == *"$w"* ]] || { bad "$n" "want in stdout: $w" "$(got)"; return; }; done
  ok "$n"
}
# like NAME RE…: exit 0 and a stdout line matches each extended regex (!RE: none may match).
like() {
  local n="$1" re; shift
  [ "$RC" = 0 ] || { bad "$n" "want exit 0" "$(got)"; return; }
  for re in "$@"; do
    if [[ $re == '!'* ]]; then
      grep -Eq -- "${re#!}" <<<"$OUT" && { bad "$n" "want no line matching: ${re#!}" "$(got)"; return; }
    else
      grep -Eq -- "$re" <<<"$OUT" || { bad "$n" "want a line matching: $re" "$(got)"; return; }
    fi
  done
  ok "$n"
}
# errs NAME RC TEXT: exit RC and stderr contains TEXT.
errs() { if [ "$RC" = "$2" ] && [[ $ERR == *"$3"* ]]; then ok "$1"; else bad "$1" "want exit $2, stderr containing: $3" "$(got)"; fi; }
# json NAME EXPR [ARG…]: stdout is one JSON object (d), stderr is empty, and the Python expression
# EXPR holds; rc is the exit status, a the ARGs.
json() {
  local n="$1" e="$2"; shift 2
  if [ -z "$ERR" ] && python3 -c 'import json,sys; o=sys.argv[1]; d=json.loads(o); rc=int(sys.argv[3]); a=sys.argv[4:]; sys.exit(0 if len(o.splitlines())==1 and eval(sys.argv[2]) else 1)' "$OUT" "$e" "$RC" "$@" 2>/dev/null
  then ok "$n"; else bad "$n" "want one JSON object with: $e, nothing on stderr" "$(got)"; fi
}
# holds NAME COMMAND…: a plain shell test.
holds() { local n="$1"; shift; if "$@"; then ok "$n"; else bad "$n" "failed: $*"; fi; }
# rx TEXT: TEXT as a literal in an extended regex.
rx() { printf '%s' "$1" | sed 's/[][\.*^$?+(){}|]/\\&/g'; }
# ref ROLE NAME: the ref (e12, f1e3) of the control whose name is NAME (or starts with "NAME "),
# from `read -q` on the tab's current page. Refs are never hard-coded: they differ between loads.
ref() {
  local line re='^((f[0-9]+)?e[0-9]+) ([a-z]+) "([^"]*)"'
  while IFS= read -r line; do
    if [[ $line =~ $re ]] && [ "${BASH_REMATCH[3]}" = "$1" ] && [[ ${BASH_REMATCH[4]} == "$2" || ${BASH_REMATCH[4]} == "$2 "* ]]; then
      echo "${BASH_REMATCH[1]}"; return 0
    fi
  done < <("$BIN" "$T" read -q "$2" 2>/dev/null)
  echo "no-ref-for-$1-$2"; return 1
}
forget() { local t keep=(); for t in "${TABS[@]}"; do [ "$t" != "$1" ] && keep+=("$t"); done; TABS=("${keep[@]}"); }

# Pacing: bot checks below slow the site down for the daemon's session; undo that at the end
# unless the user paces 127.0.0.1 themselves. A temporary rule is a leftover of an earlier run.
s rate 127.0.0.1
if [[ $OUT == *"not paced"* || $OUT == *"temporary"* ]]; then RATE_RESET=1; "$BIN" rate 127.0.0.1 off >/dev/null 2>&1; fi

# --- tabs: open, list, close, gone
s open "$URL/fixture.html" --id-only --delay 0
if [ "$RC" = 0 ] && [[ $OUT =~ ^t[0-9]+$ ]]; then T=$OUT; TABS+=("$T"); ok "open --id-only prints the new tab's id"
else bad "open --id-only prints the new tab's id" "$(got)"; exit 1; fi
s tabs
like "tabs lists it as an agent tab, not the visible one" "^$T \(agent\) safari-cli fixture \| $(rx "$URL/fixture.html")$"
s open "$URL/list.html?p=1" --id-only --delay 0
if [ "$RC" = 0 ] && [[ $OUT =~ ^t[0-9]+$ ]]; then
  B=$OUT; TABS+=("$B")
  s "$B" read
  like "a second tab reads its own page" "^List \| $(rx "$URL/list.html?p=1")" '^e[0-9]+ link "Sonraki"$'
  s "$B" close
  is "close" "closed $B"
  [ "$RC" = 0 ] && forget "$B"
  s "$B" read
  errs "a closed tab is gone" 1 "Tab $B is gone"
  s "$B" read --json
  json "--json: a closed tab is kind gone, exit 1" 'rc==1 and d["ok"] is False and d["kind"]=="gone" and d["tab"]==a[0]' "$B"
  s tabs
  like "tabs no longer lists it" "!^$B[ *]" "^$T "
else
  bad "open a second tab" "$(got)"
fi

# --- reading the fixture
s "$T" read
like "read: page line and controls" "^safari-cli fixture \| $(rx "$URL/fixture.html")" '^e[0-9]+ textbox "Name"$' \
  '^e[0-9]+ combobox "Size' '^e[0-9]+ checkbox "Newsletter"$' '^e[0-9]+ radio "Red"$' '^e[0-9]+ button "Send"$' '^e[0-9]+ link "details link"$'
like "read: frame block with frame refs" "^--- frame f[0-9]+ $(rx "$URL/frame.html")$" \
  '^f[0-9]+e[0-9]+ textbox "Frame field"$' '^f[0-9]+e[0-9]+ button "Frame confirm"$'
s "$T" read --json
json "read --json: tab, url, the text, no nav" 'rc==0 and d["ok"] and d["tab"]==a[0] and d["url"]==a[1] and "textbox \"Name\"" in d["text"] and "nav" not in d' "$T" "$URL/fixture.html"
s "$T" read -q Newsletter
like "read -q: the matching control only" '^e[0-9]+ checkbox "Newsletter"$' '!button "Send"' '!textbox "Name"'
s "$T" text
has "text: page and frame as markdown" "# Fixture" "  1. Conference" "| Pear \| green | 0.90 |" $'```\nline one\nline two\n```' \
  "### Inside the frame" "Frame paragraph text."
# A script runner that merges stdout and stderr: the data first, then the note marked "note: ".
M=$("$BIN" "$T" text --max 50 2>&1)
holds "merged streams: data first, the note last as note: …" bash -c '[[ $(head -1 <<<"$1") == "safari-cli fixture | "* && $(tail -1 <<<"$1") == "note: … "*" more chars; --offset "* ]] || { echo "$1" >&2; false; }' _ "$M"
s "$T" text --max 50
holds "separate streams: the note alone on stderr, unmarked" bash -c '[[ $1 == "… "*" more chars"* && $2 == "safari-cli fixture | "* ]]' _ "$ERR" "$OUT"
s "$T" links
like "links: names and URLs" '^e[0-9]+ "About" https://example\.com/about$' '^e[0-9]+ "details link" /fixture\.html#details$' \
  '^e[0-9]+ "Elsewhere" https://example\.org/$'
s "$T" table
is "table: the fixture's table as TSV" "$(printf 'Fruit\tPrice\nApple\t1.20\nPear | green\t0.90')"
errs "table: row count note on stderr" 0 "2 rows from table"

# --- acting: a change made by a timer after a click still counts (act waits up to 1.2 s more);
# checked by the page, not by `· new text`, which lists only lines in the viewport.
s "$T" click "$(ref button 'Add later')"
like "click waits for a change made by a 1 s timer" '^clicked e[0-9]+ button "Add later"' '!no change on the page'
j 'var l = document.getElementById("late"); return l ? l.textContent : "not yet"'
is "…which is in the page when the click returns" 'Arrived late'
# …also right after a fill that moved focus into a field: the trusted `change` WebKit fires when
# the click takes focus away is not the page's reaction to the click.
NAME=$(ref textbox Name)
s "$T" fill "$NAME" Zed
s "$T" click "$(ref button 'Remove later')"
j 'document.getElementById("late") ? "still there" : "gone"'
is "click right after a fill waits for a change made by a timer" gone
s "$T" wait --sel '#late' --gone --timeout 3   # in step for what follows, whatever the result

# --- form input
SIZE=$(ref combobox Size); NEWS=$(ref checkbox Newsletter); RED=$(ref radio Red); SEND=$(ref button Send)
s "$T" fill "$NAME" 'Ada → e5 x'
is "fill one field: a value with → and e5 stays as typed" "filled $NAME textbox \"Name\" =\"Ada → e5 x\""
j 'document.forms.f.name.value'
is "fill: the page has the value" 'Ada → e5 x'
s "$T" fill "$NAME=Bo → e5" "$SIZE=Large" "$NEWS=true"
has "fill several fields" "filled $NAME textbox \"Name\" =\"Bo → e5\"" "selected \"Large\" in $SIZE combobox" "$NEWS checkbox \"Newsletter\" checked"
like "fill several fields: no navigation reported" '!\| https?://'
j 'var f=document.forms.f;return [f.name.value,f.size.value,f.news.checked].join("|")'
is "fill several fields: the page has all three" 'Bo → e5|Large|true'
s "$T" uncheck "$NEWS"
is "uncheck" "$NEWS checkbox \"Newsletter\" unchecked"
s "$T" check "$RED"
is "check a radio" "$RED radio \"Red\" checked"
s "$T" check "$RED"
is "check again is safe" "$RED radio \"Red\" checked"
j 'var f=document.forms.f;return f.news.checked+"|"+f.c.value'
is "check/uncheck: the page agrees" 'false|r'
s "$T" select "$SIZE" Small
has "select an option" "selected \"Small\" in $SIZE combobox"
j 'document.forms.f.size.value'
is "select: the page agrees" Small
s "$T" fill "$NAME" ''
s "$T" type "$NAME" 'hi'
is "type into a field" "typed into $NAME textbox \"Name\" =\"hi\""
s "$T" type ' there.'
is "type without a ref goes to the focused field" "typed into $NAME textbox \"Name\" =\"hi there.\""
s "$T" key cmd+a "$NAME"
is "key cmd+a selects the field's text" "key cmd+a (all selected)"
s "$T" key Backspace "$NAME"
is "key Backspace deletes it" 'key Backspace =""'
s "$T" fill "$NAME" Zed
s "$T" click "$SEND"
is "click that changes text in place: · new text" "clicked $SEND button \"Send\" · new text: \"submitted Zed\""
s "$T" fill "$NAME" Yan
s "$T" key Enter "$NAME"
is "key Enter submits: · new text" 'key Enter · new text: "submitted Yan"'

# --- frames (before any --answer on the top page)
FF=$(ref textbox 'Frame field'); FC=$(ref button 'Frame confirm')
s "$T" fill "$FF" 'framed → e5'
is "fill a field in a frame" "filled $FF textbox \"Frame field\" =\"framed → e5\""
s "$T" read -q 'Frame field'
like "read shows the frame field's value" "^$FF textbox \"Frame field\" =\"framed → e5\"$"
s "$T" click "$FC"
has "frame confirm is dismissed by default" '· new text: "frame confirm false"' '⚠ dialog (frame) confirm "Frame sure?" → dismissed'
s "$T" click "$FC" --answer accept
has "frame confirm with --answer accept" '· new text: "frame confirm true"' '⚠ dialog (frame) confirm "Frame sure?" → accepted'

# --- dialogs on the top page
s "$T" click "$(ref button Alert)"
has "alert is accepted and reported" '· new text: "alert done"' '⚠ dialog alert "Hello" → accepted'
CONFIRM=$(ref button Confirm)
s "$T" click "$CONFIRM"
has "confirm is dismissed by default" '· new text: "confirm false"' '⚠ dialog confirm "Delete it?" → dismissed'
s "$T" click "$CONFIRM" --answer accept
has "click --answer accept" '· new text: "confirm true"' '⚠ dialog confirm "Delete it?" → accepted'
s "$T" click "$(ref button Prompt)" --answer 'Ada Lovelace'
has "click --answer TEXT answers a prompt" '· new text: "prompt Ada Lovelace"' '⚠ dialog prompt "Your name?" → "Ada Lovelace"'
# An answer given for the top page must not stay armed in its frames.
s "$T" click "$FC"
has "frame confirm after a top-page --answer is still dismissed" '⚠ dialog (frame) confirm "Frame sure?" → dismissed'

# --- wait
j 'setTimeout(function(){var p=document.createElement("p");p.id="later2";p.textContent="Shows up later";document.body.appendChild(p)},1200);return "armed"'
s "$T" wait "Shows up later" --timeout 8
has "wait for text that appears" 'text "Shows up later" present after'
j 'setTimeout(function(){document.getElementById("later2").remove()},800);return 1'
s "$T" wait --sel '#later2' --gone --timeout 8
has "wait --sel … --gone" 'selector #later2 gone after'
s "$T" wait "Never there" --timeout 1
errs "wait times out with exit 1" 1 'timed out after 1s waiting for text "Never there" to appear'

# --- js
j '1+2'
is "js: a bare expression" 3
j 'const a = [1, 2]; return a.map(x => x * 3)'
is "js: return, values as JSON" '[3,6]'
j '({a: 1, b: "two"})'
is "js: an object" '{"a":1,"b":"two"}'
j 'window.__liveG = 41; return 0'
j '__liveG + 1'
is "js: globals persist in the page between calls" 42
j '"x".repeat(5000)' -o "$tmp/js.txt"
is "js -o FILE" "wrote 5000 chars → $tmp/js.txt"
n=$(tr -d '\n' <"$tmp/js.txt" | wc -c | tr -d ' '); x=$(tr -d '\nx' <"$tmp/js.txt" | wc -c | tr -d ' ')
holds "js -o FILE: the whole result in the file" test "$n chars, $x not x" = "5000 chars, 0 not x"
j '"y".repeat(100)' --max 10
is "js --max: capped stdout" yyyyyyyyyy
errs "js --max: the note on stderr" 0 "… 90 more chars"
j '"y".repeat(100)' --max 10 --json
json "js --json: the text, and the note in notes" 'rc==0 and d["text"]=="y"*10 and any("90 more chars" in x for x in d["notes"])'
j '"a\n\x1eb"'
is "js: a \\x1e line in the result is data, not a note" $'a\nb'
j 'var p = document.createElement("p"); p.id = "fake"; p.textContent = "\x1efake note"; document.querySelector("h1").after(p); return 1'
s "$T" text --max 0
holds "text: a \\x1e line on the page is data, not a note" bash -c '[[ $1 == *"fake note"* && $2 != *"fake note"* ]]' _ "$OUT" "$ERR"
j 'document.getElementById("fake").remove(); return 1'
s "$T" storage local live_x $'a\x1eb'
s "$T" storage local live_x
is "storage: a \\x1e in a value is dropped" ab
s "$T" storage --delete live_x
j 'throw new Error("boom")'
errs "js: a thrown error exits 1" 1 "Error: boom"

# --- logs
s "$T" logs --clear
j 'console.log("live-log", {k: 1, s: "v"}, [1, 2]); return 0'
s "$T" logs
has "logs: console line with object arguments" 'log live-log {"k":1,"s":"v"} [1,2]'
s "$T" click "$(ref button Log)"
s "$T" logs --errors
like "logs --errors" '^error broken$' '!careful' '!live-log'
s "$T" logs --warn
like "logs --warn: warnings and errors" '^warn careful$' '^error broken$' '!live-log'
s "$T" logs --new
is "logs --new: nothing since the last logs call" "(nothing new)"
s "$T" click "$(ref button 'Fetch missing')"
like "click reports a failed request" '· failed: n[0-9]+ GET 404 /missing\.json$'
j 'return (await (await fetch("api/data.json")).text()).trim()'
is "js: await a fetch" '{"items":[1,2,3]}'
s "$T" logs --net -p data.json
like "logs --net: the fetch with an id" '^n[0-9]+ GET 200 api/data\.json '
NID=$(sed -nE 's/^(n[0-9]+) GET 200 api\/data\.json .*/\1/p' <<<"$OUT" | tail -1)
s "$T" logs --id "${NID:-n0}"
has "logs --id: the response body" "${NID:-n0} GET 200 api/data.json" "application/json" '{"items":[1,2,3]}'

# --- storage, cookies, state
s "$T" storage local live_k 'v → 1 e5'
has "storage: set" 'set "live_k"'
s "$T" storage local live_k
is "storage: get" 'v → 1 e5'
s "$T" storage
like "storage: list" '^live_k = v → 1 e5$'
s "$T" storage --delete live_k
is "storage: delete" 'deleted "live_k"'
s "$T" storage local live_k
errs "storage: a deleted key is gone" 1 'no localStorage key "live_k"'
s "$T" storage session live_s sv
s "$T" storage session
like "storage session: set and list" '^live_s = sv$'
s "$T" storage session --delete live_s
s "$T" storage session live_s
errs "storage session: delete" 1 'no sessionStorage key "live_s"'
CK=safari_cli_live
s "$T" cookies "$CK" abc
has "cookies: set" "set $CK = abc"
COOKIE=$CK
s "$T" cookies
like "cookies: list" "^$CK = abc  127\.0\.0\.1/ "
s "$T" cookies "$CK"
is "cookies: get" abc
j 'document.cookie'
has "cookies: the page sees it" "$CK=abc"
s "$T" cookies --delete "$CK"
is "cookies: delete" "deleted $CK"
[ "$RC" = 0 ] && COOKIE=""
s "$T" cookies "$CK"
errs "cookies: a deleted cookie is gone" 1 "no cookie $CK"
s "$T" storage local live_st 'saved v'
s "$T" state save "$tmp/state.json"
has "state save" "1 local" "→ $tmp/state.json"
holds "state save: the file is private (0600)" test "$(stat -f %Lp "$tmp/state.json" 2>/dev/null)" = 600
s "$T" storage --delete live_st
s "$T" state load "$tmp/state.json"
has "state load reloads the page" "reloaded: safari-cli fixture | $URL/fixture.html"
s "$T" storage local live_st
is "state load: localStorage is back" 'saved v'
s "$T" storage --delete live_st

# --- locator, highlight (refs again: state load reloaded the page)
NAME=$(ref textbox Name); SEND=$(ref button Send)
s "$T" locator "$NAME"
is "locator prefers the name attribute" "--sel 'input[name=\"name\"]'  $NAME textbox \"Name\""
s "$T" locator "$SEND"
SEL=$(sed -nE "s/^--sel '(.*)'  $SEND button \"Send\"$/\1/p" <<<"$OUT")
holds "locator: a selector for the button" test -n "$SEL"
s "$T" fill --sel 'input[name="name"]' viaSel
s "$T" click --sel "${SEL:-none}"
has "the located selector clicks the same button" '· new text: "submitted viaSel"'
s "$T" highlight "$SEND" --for 0
is "highlight --for 0" "highlighted $SEND button \"Send\" until highlight --hide"
j 'document.querySelectorAll("[data-smcp-hl]").length'
is "highlight: the box is in the page" 1
s "$T" highlight --hide
is "highlight --hide" "removed 1 highlight"
j 'document.querySelectorAll("[data-smcp-hl]").length'
is "highlight --hide: the box is gone" 0

# --- navigation, table and crawl on list.html
s "$T" go "$URL/list.html?p=1" --delay 0
is "go URL" "List | $URL/list.html?p=1"
s "$T" go "$URL/list.html?p=1" --delay 0 --json
json "go --json: nav, url and title of the loaded page" 'rc==0 and d["nav"] is True and d["url"]==a[0] and d["title"]=="List" and d["tab"]==a[1]' "$URL/list.html?p=1" "$T"
s "$T" table --json
json "table --json: rows, not text" 'rc==0 and "text" not in d and len(d["rows"])==4 and d["rows"][0]["id"]=="1001"'
s "$T" table
like "table: rows with link and id columns, ad and hidden rows left out" "^Title	Year	Price	link	id$" \
  "^Car 1	2021	1\.000 TL	$(rx "$URL/item.html?id=1")	1001$" "^Car 4	2024	4\.000 TL	$(rx "$URL/item.html?id=4")	1004$" '!Advertise' '!hidden'
holds "table: header and 4 rows" test "$(grep -c . <<<"$OUT")" = 5
errs "table: the note names the table" 0 "4 rows from table#results"
j 'p'
is "js sees the page's own variables" 1
SON=$(ref link Sonraki)
s "$T" click "$SON"
is "click that navigates: → title | url" "clicked $SON link \"Sonraki\" → List | $URL/list.html?p=2"
s "$T" go back --delay 0
is "go back" "List | $URL/list.html?p=1"
s "$T" go forward --delay 0
is "go forward" "List | $URL/list.html?p=2"
j 'document.title = "changed"; return document.title'
s "$T" go reload --delay 0
is "go reload" "List | $URL/list.html?p=2"
j 'setTimeout(function(){ location.href = "list.html?p=1" }, 50); return "abcdefghij"' --max 4
is "js that navigates: the capped result, then the page" "abcd → List | $URL/list.html?p=1"
holds "…and the note on stderr, without the page" bash -c '[[ $1 == *"… 6 more chars"* && $1 != *"→"* ]]' _ "$ERR"
s "$T" go "$URL/list.html?p=1" --delay 0
s "$T" crawl --delay 0
like "crawl: 3 pages merged" "^Title	Year	Price	link	id$" "^Car 1	2021	1\.000 TL	$(rx "$URL/item.html?id=1")	1001$" \
  "^Car 12	2022	12\.000 TL	$(rx "$URL/item.html?id=12")	1012$"
holds "crawl: header and 12 rows, no duplicates" test "$(grep -c . <<<"$OUT")/$(cut -f5 <<<"$OUT" | sort -u | grep -c .)" = 13/13
errs "crawl: progress on stderr" 0 "page 3/5 · 4 rows, 4 new"
errs "crawl: stops at the last page" 0 "no next page; done"
s "$T" go "$URL/list.html?p=1" --delay 0
s "$T" crawl --delay 0 --json
json "crawl --json: 12 rows from 3 pages, progress in notes" 'rc==0 and len(d["rows"])==12 and d["pages"]==3 and "no next page; done" in d["notes"]'

# --- drop
s "$T" go "$URL/drop.html" --delay 0
printf 'hello drop file' >"$tmp/drop.txt"
s "$T" drop --sel '#zone' "$tmp/drop.txt"
has "drop a file" "dropped 1 file(s) on"
s "$T" wait "hello drop file" --timeout 5
j 'document.getElementById("out").textContent'
is "the drop zone got the file" "dropped drop.txt (15 B): hello drop file"
s "$T" drop --sel '#zone' --text 'plain → e5'
has "drop text" "dropped text on"
j 'document.getElementById("out").textContent'
is "the drop zone got the text" "dropped text: plain → e5"

# --- route: mock, block, redirect, delay, unroute
s "$T" go "$URL/route.html" --delay 0
has "go route.html" "$URL/route.html"
j 'typeof show'
is "js sees functions the page defined" function
s "$T" route '*/api/data.json' --body '{"mocked":true}'
is "route: mock" 'routed */api/data.json → 200 application/json (15 B body)'
LEASES=1
if [[ $ERR == *"from before route leases"* ]]; then
  LEASES=""
  echo "     (this Safari runs an extension main.js from before route leases: lease checks are skipped; rebuild it with Extension/build.sh)"
fi
# lease NAME: true when the extension's main.js has route leases, else a skip line.
lease() { [ -n "$LEASES" ] && return 0; skip "$1 (extension main.js predates route leases)"; return 1; }
if lease "the page's route copy is {o,t,x,l} with a live lease"; then
  j 'var c=JSON.parse(sessionStorage.getItem("__smcp_routes"));return [typeof c.o,c.o.length>0,c.t>0,c.x>Date.now(),c.l.length,c.l[0].p].join(" ")'
  is "the page's route copy is {o,t,x,l} with a live lease" 'string true true true 1 */api/data.json'
fi
s "$T" click --sel '#f'
has "mocked fetch" '· new text: "fetch 200 {\"mocked\":true}"'
s "$T" click --sel '#x'
has "mocked XHR" '· new text: "xhr 200 {\"mocked\":true}"'
s "$T" route --list
is "route --list" '*/api/data.json → 200 application/json (15 B body)'
s "$T" route '*/api/data.json' --block
is "route --block" 'routed */api/data.json → blocked'
s "$T" click --sel '#f'
has "blocked fetch fails" '· new text: "fetch failed: '
s "$T" route '*/api/data.json' --redirect "$URL/list.html?redir=1"
is "route --redirect" "routed */api/data.json → redirect $URL/list.html?redir=1"
j 'var r = await fetch("api/data.json"), t = await r.text(); return r.url + " " + /<title>(.*?)<\/title>/.exec(t)[1]'
is "redirected fetch reaches the target" "$URL/list.html?redir=1 List"
s "$T" route '*/api/data.json' --body 'slow one' --delay 300
is "route mock --delay 300" 'routed */api/data.json → 200 text/plain; charset=utf-8 (8 B body, 300 ms delay)'
j 'var t = performance.now(), b = await (await fetch("api/data.json")).text(); return b + " " + (performance.now() - t >= 280)'
is "the delayed mock answers after 300 ms" "slow one true"
s "$T" logs --net -p data.json
like "logs --net marks mocked and blocked requests" '^n[0-9]+ GET ERR api/data\.json .*\(blocked\)$' '^n[0-9]+ GET 200 api/data\.json .*\(mocked\)$'
s "$T" unroute '*/api/data.json'
is "unroute PATTERN" 'removed route */api/data.json'
s "$T" route --list
is "route --list after unroute" "no routes on $T"
j 'sessionStorage.getItem("__smcp_routes")'
is "unroute clears the page's copy" null
j 'return (await (await fetch("api/data.json")).text()).trim()'
is "after unroute the fetch is real" '{"items":[1,2,3]}'
s "$T" unroute nope
errs "unroute of an unknown pattern exits 1" 1 "no route nope on $T"

# --- route lifecycle: origin A (127.0.0.1) → origin B (localhost), unroute there, back to A
s "$T" route '*/api/data.json' --body '{"mocked":"A"}'
s "$T" go "$LURL/route.html" --delay 0
has "go to another origin" "$LURL/route.html"
j 'return await (await fetch("api/data.json")).text()'
is "routes follow the tab to the other origin" '{"mocked":"A"}'
s "$T" unroute
is "unroute (all) on origin B" 'removed 1 route'
j 'sessionStorage.getItem("__smcp_routes")'
is "origin B's copy is cleared" null
s "$T" go "$URL/route.html" --delay 0
j 'sessionStorage.getItem("__smcp_routes")'
is "back on origin A: the copy left there is cleared" null
j 'return (await (await fetch("api/data.json")).text()).trim()'
is "back on origin A: the fetch is not mocked" '{"items":[1,2,3]}'
TITLE='for (var i = 0; i < 60 && document.title.indexOf("·") < 0; i++) await new Promise(r => setTimeout(r, 50)); return document.title'
if lease "a copy with another daemon's tag is dropped by the next agent call"; then
  j 'sessionStorage.setItem("__smcp_routes", JSON.stringify({o: "other.1", t: 600000, x: Date.now() + 600000, l: [{p: "*/api/data.json", k: "block"}]})); return 1'
  s "$T" go reload --delay 0
  j "$TITLE"
  is "a copy within its lease applies from the start of a load" 'route test · failed'
  s "$T" read   # an agent call: it names the tag the daemon stands behind ('' here)
  j 'sessionStorage.getItem("__smcp_routes")'
  is "a copy with another daemon's tag is dropped by the next agent call" null
  j 'return (await (await fetch("api/data.json")).text()).trim()'
  is "…and the fetch is real again" '{"items":[1,2,3]}'
fi
if lease "a copy past its lease is ignored at load"; then
  j 'sessionStorage.setItem("__smcp_routes", JSON.stringify({o: "other.2", t: 600000, x: Date.now() - 1000, l: [{p: "*/api/data.json", k: "block"}]})); return 1'
  s "$T" go reload --delay 0
  j "$TITLE"
  is "a copy past its lease is ignored at load" 'route test · {"items":[1,2,3]}'
fi

# --- intrusive: these bring Safari forward or switch the visible tab
if [ "${LIVE_INTRUSIVE:-}" = 1 ]; then
  s "$T" go "$URL/fixture.html" --delay 0
  s "$T" shot -o "$tmp/shot.jpg"
  has "shot -o FILE" "$tmp/shot.jpg"
  holds "shot: the file is a JPEG" test "$(od -An -tx1 -N3 "$tmp/shot.jpg" 2>/dev/null | tr -d ' \n')" = ffd8ff
  NAME=$(ref textbox Name)
  s "$T" fill "$NAME" ''
  s "$T" type "$NAME" 'kiwi.io' --os
  j 'document.forms.f.name.value'
  is "type --os: i and . arrive as typed (any keyboard layout)" 'kiwi.io'
  s "$T" key cmd+a "$NAME" --os
  s "$T" key Backspace "$NAME" --os
  j 'document.forms.f.name.value'
  is "key --os cmd+a, Backspace clears the field" ''
  s "$T" type "$NAME" 'li.Si' --os
  s "$T" key Enter "$NAME" --os
  s "$T" wait 'submitted li.Si' --timeout 5
  has "key Enter --os submits the form" 'submitted li.Si'
else
  skip "shot, type --os, key --os (set LIVE_INTRUSIVE=1: they bring Safari forward)"
fi

# --- bot checks (last: they slow the site down, undone by RATE_RESET)
s "$T" go "$URL/challenge.html" --delay 0
has "a bot check that passes is waited out" "$URL/fixture.html" "(passed a "
[ -n "$RATE_RESET" ] && "$BIN" rate 127.0.0.1 off >/dev/null 2>&1
s "$T" go "$URL/captcha.html" --delay 0
errs "a captcha that stays exits 1" 1 "did not clear"

# --- block page (last of all: it holds 127.0.0.1 for 15 min, ended by rate 127.0.0.1 reset)
"$BIN" rate 127.0.0.1 reset >/dev/null 2>&1   # no slot left over from the checks above
t0=$(python3 -c 'import time; print(time.time())')
s "$T" go "$URL/blocked.html" --delay 0
took=$(python3 -c 'import sys, time; print(time.time() - float(sys.argv[1]))' "$t0")
errs "a block page fails at once" 1 "127.0.0.1 blocked this browser (block page)"
holds "…within 4 s, without waiting for it to clear ($took s)" python3 -c 'import sys; sys.exit(float(sys.argv[1]) >= 4)' "$took"
s "$T" go "$URL/fixture.html" --delay 0
errs "the site is then held" 1 "loads are held for 15 more min"
s "$T" go "$URL/fixture.html" --delay 0 --json
json "--json: the held site is kind blocked" 'rc==1 and d["ok"] is False and d["kind"]=="blocked" and "held" in d["error"]'
s rate 127.0.0.1
has "rate SITE shows the hold" "held 15 min"
s rate 127.0.0.1 reset
has "rate SITE reset ends it" "127.0.0.1: hold and temporary slowdown ended"
s "$T" go "$URL/fixture.html" --delay 0
has "after the reset the site loads" "$URL/fixture.html"
BLK='var a = document.createElement("a"); a.href = "blocked.html"; a.id = "blk"; a.textContent = "to the block page"; document.body.prepend(a); return 1'
j "$BLK"
s "$T" click --sel '#blk'
errs "a click that leads to a block page exits 1, naming the click" 1 "clicked "
holds "…and the block" bash -c '[[ $1 == *" → t"*": 127.0.0.1 blocked this browser"* ]]' _ "$ERR"
"$BIN" rate 127.0.0.1 reset >/dev/null 2>&1
s "$T" go "$URL/fixture.html" --delay 0
j "$BLK"
s "$T" click --sel '#blk' --json
json "click --json into a block page: kind blocked" 'rc==1 and d["kind"]=="blocked" and d["tab"]==a[0]' "$T"
"$BIN" rate 127.0.0.1 reset >/dev/null 2>&1
s "$T" go "$URL/fixture.html" --delay 0
j 'setTimeout(function(){ location.href = "blocked.html" }, 50); return "x"'
errs "js that leads to a block page exits 1" 1 "the script navigated → t"
"$BIN" rate 127.0.0.1 reset >/dev/null 2>&1

echo "$nok ok, $nfail failed, $nskip skipped in ${SECONDS} s"
exit $fail
