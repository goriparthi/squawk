#!/bin/bash
# Registers the PreToolUse hook in ~/.claude/settings.json, preserving whatever
# hooks are already there. Idempotent: re-running updates the path in place.
set -euo pipefail

binary="${1:-}"
if [ -z "$binary" ]; then
  if [ -x "$HOME/Applications/Squawk.app/Contents/Helpers/squawk-hook" ]; then
    binary="$HOME/Applications/Squawk.app/Contents/Helpers/squawk-hook"
  else
    binary="$(cd "$(dirname "$0")/.." && pwd)/app/.build/debug/squawk-hook"
  fi
fi
[ -x "$binary" ] || { echo "no squawk-hook at $binary"; exit 1; }

settings="$HOME/.claude/settings.json"
[ -f "$settings" ] || echo '{}' > "$settings"
cp "$settings" "$settings.squawk-backup"

SQUAWK_HOOK_BIN="$binary" SQUAWK_SETTINGS="$settings" python3 - <<'PY'
import json, os

path = os.environ["SQUAWK_SETTINGS"]
binary = os.environ["SQUAWK_HOOK_BIN"]
with open(path) as handle:
    settings = json.load(handle)

hooks = settings.setdefault("hooks", {})
entries = hooks.setdefault("PreToolUse", [])

def is_squawk(entry):
    return any("squawk-hook" in h.get("command", "") for h in entry.get("hooks", []))

entries[:] = [e for e in entries if not is_squawk(e)]
entries.append({
    "matcher": "*",
    "hooks": [{
        "type": "command",
        "command": binary,
        "timeout": 150,
        "statusMessage": "Waiting on Squawk",
    }],
})

with open(path, "w") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
print("registered PreToolUse ->", binary)
PY
echo "backup at $settings.squawk-backup"
