#!/bin/bash
# End to end: stand in for the app on a scratch socket, run the real hook against
# a real PreToolUse payload, and check the JSON Claude Code would receive.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/app/.build/debug/squawk-hook"
[ -x "$hook" ] || { echo "build first: swift build --package-path app"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"; kill %1 2>/dev/null || true' EXIT
sock="$work/sock"

payload='{"session_id":"s1","cwd":"'"$root"'","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"toolu_smoke","permission_mode":"default","tool_input":{"command":"rm -rf build"}}'
# Codex: a different event, no tool_use_id, and a different reply shape.
codex_payload='{"session_id":"s1","cwd":"'"$root"'","hook_event_name":"PermissionRequest","tool_name":"Bash","turn_id":"t-1","permission_mode":"auto","tool_input":{"command":"rm -rf build"}}'

run_case() {
  local decision="$1" expect="$2" body="${3:-$payload}"
  python3 - "$sock" "$decision" <<'PY' &
import json, os, socket, sys
path, decision = sys.argv[1], sys.argv[2]
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path); srv.listen(1); srv.settimeout(10)
conn, _ = srv.accept()
line = b""
while not line.endswith(b"\n"):
    chunk = conn.recv(4096)
    if not chunk: break
    line += chunk
req = json.loads(line)
print("APP_SAW " + json.dumps({k: req.get(k) for k in ("id","tool","summary","tty")}), file=sys.stderr)
conn.sendall((json.dumps({"v":1,"id":req["id"],"decision":decision,"reason":"smoke"})+"\n").encode())
conn.close(); srv.close(); os.unlink(path)
PY
  sleep 0.5
  out="$(printf '%s' "$body" | SQUAWK_SOCKET="$sock" SQUAWK_WAIT=10 "$hook")"
  wait %1 2>/dev/null || true
  echo "hook stdout: $out"
  echo "$out" | grep -q "$expect" || { echo "FAIL: expected $expect"; exit 1; }
  echo "  ok: $decision"
}

echo "== case 1: approve =="
run_case allow '"permissionDecision":"allow"'

echo "== case 2: deny =="
run_case deny '"permissionDecision":"deny"'

echo "== case 3: Codex PermissionRequest, its own reply shape =="
run_case allow '"decision":{"behavior":"allow"}' "$codex_payload"

echo "== case 4: Codex deny carries a message =="
run_case deny '"behavior":"deny"' "$codex_payload"

echo "== case 5: auto mode on PreToolUse must NOT gate =="
auto_payload='{"session_id":"s1","cwd":"'"$root"'","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"t_auto","permission_mode":"auto","tool_input":{"command":"rm -rf build"}}'
out="$(printf '%s' "$auto_payload" | SQUAWK_SOCKET="$sock" SQUAWK_WAIT=5 "$hook")"
[ -z "$out" ] && echo "  ok: fell through to normal flow" || { echo "FAIL: gated auto mode"; exit 1; }

echo "== case 6: no socket, must fail open (silent, exit 0) =="
out="$(printf '%s' "$payload" | SQUAWK_SOCKET="$work/absent" "$hook")"; code=$?
[ -z "$out" ] && [ "$code" = 0 ] && echo "  ok: silent, exit 0" || { echo "FAIL: expected silence"; exit 1; }

echo "== case 7: garbage stdin, must fail open =="
out="$(printf 'not json' | SQUAWK_SOCKET="$sock" "$hook")"; code=$?
[ -z "$out" ] && [ "$code" = 0 ] && echo "  ok: silent, exit 0" || { echo "FAIL"; exit 1; }

echo "== case 8: MCP handshake and tool list =="
handshake='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
out="$(printf '%s\n' "$handshake" | SQUAWK_SOCKET="$work/absent" "$hook" --mcp)"
lines="$(printf '%s' "$out" | grep -c . || true)"
[ "$lines" = 2 ] || { echo "FAIL: expected 2 replies, got $lines"; echo "$out"; exit 1; }
echo "$out" | grep -q '"protocolVersion"' || { echo "FAIL: no handshake"; exit 1; }
echo "$out" | grep -q '"name":"speak"' || { echo "FAIL: speak not listed"; exit 1; }
echo "  ok: notification answered with silence, tool listed"

echo "== case 9: speak reaches the app and its answer comes back =="
python3 - "$sock" <<'PY' &
import json, os, socket, sys
path = sys.argv[1]
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path); srv.listen(1); srv.settimeout(10)
conn, _ = srv.accept()
line = b""
while not line.endswith(b"\n"):
    chunk = conn.recv(4096)
    if not chunk: break
    line += chunk
ask = json.loads(line)
assert ask["kind"] == "speak", ask
print("APP_SAW " + json.dumps({k: ask.get(k) for k in ("kind", "text")}), file=sys.stderr)
conn.sendall((json.dumps({"v": 1, "kind": "speak", "spoke": True,
                          "detail": "Said out loud: " + ask["text"]}) + "\n").encode())
conn.close(); srv.close(); os.unlink(path)
PY
sleep 0.5
call='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"speak","arguments":{"text":"the migration is done"}}}'
out="$(printf '%s\n' "$call" | SQUAWK_SOCKET="$sock" "$hook" --mcp)"
wait %1 2>/dev/null || true
echo "hook stdout: $out"
echo "$out" | grep -q '"isError":false' || { echo "FAIL: reported an error"; exit 1; }
echo "$out" | grep -q 'Said out loud: the migration is done' || { echo "FAIL: no answer"; exit 1; }
echo "  ok: spoken, and the app's answer came back"

echo "== case 10: no app, must answer at once rather than hang =="
out="$(printf '%s\n' "$call" | SQUAWK_SOCKET="$work/absent" "$hook" --mcp)"; code=$?
[ "$code" = 0 ] || { echo "FAIL: exit $code"; exit 1; }
echo "$out" | grep -q '"isError":true' || { echo "FAIL: claimed it spoke"; exit 1; }
echo "$out" | grep -q 'not running' || { echo "FAIL: did not say why"; exit 1; }
echo "  ok: said so, and did not block the agent"

echo "== case 11: nothing but JSON-RPC ever reaches stdout =="
out="$(printf '%s\n' "$handshake" | SQUAWK_SOCKET="$work/absent" "$hook" --mcp)"
printf '%s\n' "$out" | while IFS= read -r one; do
  [ -z "$one" ] && continue
  printf '%s' "$one" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' \
    || { echo "FAIL: not JSON on stdout: $one"; exit 1; }
done
echo "  ok: every line parses"

echo "ALL SMOKE PASSED"
