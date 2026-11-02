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
parses() {  # expected JSON fragment, then a command line
  local want="$1"; shift
  local got; got=$("$BIN" --parse "$@" 2>&1)
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
parses '"kind":"network"' t5 logs --id n4
parses '"region":[0,0,100,50]' t5 shot --region 0,0,100,50
parses '"max_chars":300' t5 read --max=300

out=$("$BIN" status 2>&1)
check "daemon starts and answers status" grep -q "daemon pid" <<<"$out"
pid=$(sed -E 's/daemon pid ([0-9]+).*/\1/' <<<"$out")
check "second call reaches the same daemon" bash -c '"$0" status | grep -q "pid $1 "' "$BIN" "$pid"
check "tool errors exit 1" test "$(code t999 read)" = 1
reply=$(python3 -c '
import socket, sys
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
s.sendall(b"{\"v\":\"other-build\",\"tool\":\"status\"}\n"); print(s.makefile().readline())' "$SAFARI_CLI_HOME/sock")
check "another build gets restart" grep -q '"restart":true' <<<"$reply"
out=$("$BIN" status 2>&1)
check "client restarts the daemon" bash -c '[[ "$1" == *"daemon pid"* && "$1" != *"pid $2 "* ]]' _ "$out" "$pid"
check "stop" bash -c '"$0" stop | grep -q stopped' "$BIN"

size=$(wc -c < Skill/safari-browser/SKILL.md)
echo "skill: $size chars, about $((size / 4)) tokens"
check "skill stays under 12500 chars" test "$size" -lt 12500
exit $fail
