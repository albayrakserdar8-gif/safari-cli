#!/bin/bash
# Protocol smoke test: needs no Safari permission. Run from the project root after building.
BIN="${1:-.build/release/safari-mcp}"

printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"ping"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"nope","arguments":{}}}' \
  'not json' \
  '{"jsonrpc":"2.0","id":5,"method":"resources/list"}' \
  '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"act","arguments":{}}}' \
  | "$BIN" | python3 -c '
import json, sys

lines = sys.stdin.read().splitlines()
msgs = [json.loads(l) for l in lines]
by_id = {m["id"]: m for m in msgs}
fail = 0

def check(name, ok):
    global fail
    print(("ok   " if ok else "FAIL ") + name)
    fail |= not ok

check("one reply per request, none for the notification", len(msgs) == 7)
check("negotiates the client protocol version", by_id[1]["result"]["protocolVersion"] == "2025-06-18")
check("ping", by_id[2]["result"] == {})
tools = by_id[3]["result"]["tools"]
check("lists 8 tools with schemas", len(tools) == 8 and all(t["inputSchema"]["type"] == "object" for t in tools))
check("unknown tool is a protocol error", by_id[4]["error"]["code"] == -32602)
check("bad JSON is a parse error", by_id[None]["error"]["code"] == -32700)
check("unknown method", by_id[5]["error"]["code"] == -32601)
check("tool input error is isError", by_id[6]["result"]["isError"] is True)

size = len(json.dumps(tools, separators=(",", ":")))
print(f"tool schemas: {size} chars, about {size // 4} tokens")
check("tool schemas stay under 3600 chars (about 900 tokens)", size < 3600)
sys.exit(fail)
'
