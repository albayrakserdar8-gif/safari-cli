#!/bin/bash
# CLI smoke test: needs no Safari permission. Run from the project root after building.
BIN="$(cd "$(dirname "${1:-.build/release/safari}")" && pwd)/$(basename "${1:-.build/release/safari}")"
export SAFARI_CLI_HOME="/tmp/safari-cli-smoke-$$"
trap '"$BIN" stop >/dev/null 2>&1; rm -rf "$SAFARI_CLI_HOME"' EXIT
fail=0

check() {  # name, then a command that must succeed
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi
}
code() { "$BIN" "$@" >/dev/null 2>&1; echo $?; }
parses() {  # expected JSON fragment, then a command line (bash_env_tN: SAFARI_TAB=tN)
  local want="$1"; shift
  local env=()
  if [[ $1 == bash_env_t* ]]; then env=(env "SAFARI_TAB=${1#bash_env_}"); shift; fi
  local got; got=$("${env[@]}" "$BIN" --parse "$@" 2>&1)
  if [[ "$got" == *"$want"* ]]; then echo "ok   parse: $*"; else echo "FAIL parse: $* → $got"; fail=1; fi
}

check "help exits 0" test "$(code help)" = 0
check "help for one verb" bash -c '"$0" help fill | grep -q "fill R"' "$BIN"
check "unknown verb is a usage error" test "$(code frob)" = 2
check "missing element is a usage error" test "$(code t3 click)" = 2
check "unknown option is a usage error" test "$(code t3 read --nope)" = 2
check "global verb takes no tab" test "$(code t3 tabs)" = 2
check "close needs a tab" test "$(code close)" = 2

parses '"args":{"action":"new","url":"x.com"},"out":null,"tool":"tabs"' open x.com
parses '"mode":"text"' t5 text -q pricing
parses '"query":"pricing"' t5 text -q pricing
parses '"fields":{' t5 fill e4=Ada e6=true
parses '"text":"a=b"' t5 fill e4 a=b
parses '"x":120' t5 click --xy 120,300
parses '"dy":-400' t5 scroll -400
parses '"dy":400' t5 scroll e30 400
parses '"text":"accept"' t5 click e12 --answer accept
parses '"action":"rclick"' t5 click e12 --right
parses '"to":"e6"' t5 drag e4 --to e6
parses '"selector":"canvas"' t5 shot --sel canvas
check "ref and --sel together is a usage error" test "$(code t3 click e1 --sel a)" = 2
check "drag needs --to" test "$(code t3 drag e1)" = 2
parses '"kind":"network"' t5 logs --id n4
parses '"region":[0,0,100,50]' t5 shot --region 0,0,100,50
parses '"max_chars":300' t5 read --max=300
parses '"action":"select","ref":"e9","tab":"t5","text":"brown fox"' t5 select e9 "brown fox"
parses '"timeout":5,"wait":true},"out":null,"tool":"downloads"' downloads --wait --timeout 5
check "downloads takes no tab" test "$(code t3 downloads)" = 2
check "downloads lists without a daemon" bash -c '"$0" downloads >/dev/null && [ ! -S "$SAFARI_CLI_HOME/sock" ]' "$BIN"
check "make install dry run" make -n install
parses '"max_chars":0,"tab":"t5"},"out":"f.txt","tool":"js"' t5 js 1 -o f.txt
parses '"max_chars":0,"mode":"text"' t5 text -o f.md
parses '"max_chars":300,"mode":"text"' t5 text -o f.md --max 300
parses '"json":true,"max_chars":0,"rows":".card","tab":"t5"},"out":"x.json","tool":"table"' t5 table --rows .card --json -o x.json
parses '"delay":[8,14],"next":"Sonraki","pages":3,"tab":"t5"},"out":"a.tsv","tool":"crawl"' t5 crawl --next Sonraki --pages 3 --delay 8-14 -o a.tsv
parses '"delay":[5,5],"tab":"t5","url":"x.com"},"out":null,"tool":"navigate"' t5 go x.com --delay 5
parses '"delay":[2,3],"idonly":true' open x.com --id-only --delay 2-3
parses '"action":"wait","load":true' t5 wait --load
parses '"args":{"range":"off","site":"x.com"},"out":null,"tool":"rate"' rate x.com off
check "crawl needs a tab" test "$(code crawl)" = 2
check "bad --delay is a usage error" test "$(code t3 go x.com --delay soon)" = 2
check "bad rate is a usage error" test "$(code rate x.com fast)" = 2
check "rate takes no tab" test "$(code t3 rate)" = 2
check "wait --load with text is a usage error" test "$(code t3 wait --load hi)" = 2
parses '"tab":"t9"},"out":null,"tool":"read"' bash_env_t9 read
parses '"action":"closeagents"},"out":null,"tool":"tabs"' close --agents
check "close --agents takes no tab" test "$(code t3 close --agents)" = 2
parses '"action":"resize","height":844,"tab":"t5","width":390' t5 resize 390 844
check "resize needs two sizes" test "$(code t3 resize 390)" = 2
check "resize refuses tiny sizes" test "$(code t3 resize 10 10)" = 2
parses '"window":true' open x.com --window
parses '"code":"el.value","ref":"e3","tab":"t5"' t5 js el.value e3
parses '"code":"el.value","selector":"#q"' t5 js el.value --sel '#q'
check "js with a frame ref is a usage error" test "$(code t3 js el.value f1e3)" = 2
check "bad SAFARI_TAB is a usage error" bash -c 'SAFARI_TAB=five "$0" read >/dev/null 2>&1; [ $? = 2 ]' "$BIN"
check "SAFARI_TAB is ignored by global verbs" bash -c 'SAFARI_TAB=t9 "$0" --parse open x.com | grep -qv t9' "$BIN"
check "an explicit tab beats SAFARI_TAB" bash -c 'SAFARI_TAB=t9 "$0" --parse t5 read | grep -q "\"tab\":\"t5\""' "$BIN"
parses '"ref":"e4","tab":"t5"},"out":null,"tool":"locator"' t5 locator e4
parses '"ref":"e4","secs":0,"tab":"t5"},"out":null,"tool":"highlight"' t5 highlight e4 --for 0
parses '"hide":true,"tab":"t5"},"out":null,"tool":"highlight"' t5 highlight --hide
check "highlight --hide takes no element" test "$(code t3 highlight e4 --hide)" = 2
parses '"action":"add","body":"[1,2]","pattern":"*/api/*","status":500' t5 route '*/api/*' --status 500 --body '[1,2]'
parses '"action":"add","block":true,"pattern":"*.png"' t5 route '*.png' --block
parses '"action":"list","tab":"t5"},"out":null,"tool":"route"' t5 route --list
parses '"action":"remove","pattern":"*.png"' t5 unroute '*.png'
check "route --block with --status is a usage error" test "$(code t3 route x --block --status 500)" = 2
check "route with a bad status is a usage error" test "$(code t3 route x --status 99)" = 2
check "route with a bad regex is a usage error" test "$(code t3 route 're:(' )" = 2
check "route needs a pattern" test "$(code t3 route)" = 2
parses '"area":"session","key":"k","tab":"t5","value":"v"},"out":null,"tool":"storage"' t5 storage session k v
parses '"del":"k","tab":"t5"},"out":null,"tool":"storage"' t5 storage --delete k
parses '"clear":true,"tab":"t5"},"out":null,"tool":"storage"' t5 storage --clear
parses '"action":"drop","dtext":"hi","selector":"#zone"' t5 drop --sel '#zone' --text hi
check "drop needs files or text" test "$(code t3 drop e4)" = 2
parses '"stop":true,"tab":"t5"},"out":null,"tool":"record"' t5 record --stop
check "record needs a tab" test "$(code record)" = 2
parses '"full":true,"tab":"t5"},"out":null,"tool":"screenshot"' t5 shot --full
check "shot --full with an element is a usage error" test "$(code t3 shot e4 --full)" = 2

out=$("$BIN" status 2>&1)
check "daemon starts and answers status" grep -q "daemon pid" <<<"$out"
pid=$(sed -E 's/daemon pid ([0-9]+).*/\1/' <<<"$out")
check "second call reaches the same daemon" bash -c '"$0" status | grep -q "pid $1 "' "$BIN" "$pid"
# Needs Safari: the unknown id makes the daemon list Safari's tabs.
check "tool errors exit 1" test "$(code t999 read)" = 1
reply=$(python3 -c '
import socket, sys
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
s.sendall(b"{\"v\":\"other-build\",\"tool\":\"status\"}\n"); print(s.makefile().readline())' "$SAFARI_CLI_HOME/sock")
check "another build gets restart" grep -q '"restart":true' <<<"$reply"
out=$("$BIN" status 2>&1)
check "client restarts the daemon" bash -c '[[ "$1" == *"daemon pid"* && "$1" != *"pid $2 "* ]]' _ "$out" "$pid"
# Pacing slots are handed out by the daemon; nothing navigates here.
check "unpaced site gets no wait" test "$("$BIN" --reserve https://example.com/a)" = 0.0
check "rate set" bash -c '"$0" rate example.com 2-3 | grep -q "2-3 s"' "$BIN"
check "rate saved" grep -q '"example.com"' "$SAFARI_CLI_HOME/rate.json"
check "first page of a paced site goes at once" test "$("$BIN" --reserve https://www.example.com/a)" = 0.0
check "next page waits the site's pace" bash -c 'w=$("$0" --reserve https://sub.example.com/b); [[ $w == 2.* || $w == 3.0 ]]' "$BIN"
check "rate off" bash -c '"$0" rate example.com off | grep -q "no longer"' "$BIN"
check "--delay paces an unpaced site" bash -c '"$0" --reserve https://x.org 1 1 >/dev/null; [ "$("$0" --reserve https://x.org 1 1)" = 1.0 ]' "$BIN"
check "stop" bash -c '"$0" stop | grep -q stopped' "$BIN"

size=$(wc -c < Skill/safari-browser/SKILL.md)
echo "skill: $size chars, about $((size / 4)) tokens"
check "skill stays under 12500 chars" test "$size" -lt 12500
for f in Skill/safari-browser/references/*.md; do
  check "$(basename "$f") stays under 4000 chars" test "$(wc -c < "$f")" -lt 4000
done
exit $fail
