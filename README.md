# Squawk

A floating dock for approving what your coding agents want to do, without
switching to the terminal.

You are reading Slack. An agent in another window wants to run
`git push --force origin main`. Squawk shows you the command on a dial that
floats above whatever you are doing, you click Approve or Deny, and the agent
carries on. Nothing is typed into your terminal and nothing steals your focus.

The window is a circle, and only the circle. Its corners are transparent, so a
click that misses the dial goes to whatever is behind it. Each waiting session
is one arc; hover an arc to read the full command beside the dial, since the
line inside the ring is truncated to fit. Drag it anywhere and it stays put.

In aviation a transponder squawk is how an aircraft announces who it is and what
it needs. Each waiting session is one arc on the dial.

## How it works

Squawk registers a `PreToolUse` hook with Claude Code. When an agent is about to
use a tool, the hook hands the pending call to the app over a Unix socket and
waits. You answer on the ring, the app replies, and the hook returns the
decision Claude Code asked for.

```
claude ──PreToolUse──> squawk-hook ──unix socket──> Squawk.app
                            ^                           │
                            └────── allow / deny ───────┘
```

**It fails open, always.** If the app is not running, the socket is gone, the
payload is malformed, or you simply ignore it, the hook exits silently and you
get your normal terminal prompt. An agent is never stuck waiting on a UI that
is not there.

Squawk selects panes; it never types into them. Injecting keystrokes into a TUI
races the shell and lands partial lines, so "Open pane" brings the real iTerm2
pane forward and you answer it there.

## Install

```sh
make install       # build and copy to ~/Applications
make install-hook  # register the PreToolUse hook in ~/.claude/settings.json
open ~/Applications/Squawk.app
```

`make install-hook` backs up `settings.json` first and is idempotent.

## Commands

```sh
make test          # unit suite, offline
make smoke         # end to end hook protocol check
make bundle        # assemble dist/Squawk.app
make run           # install and launch
make uninstall     # remove the installed app
```

## Configuration

| Variable | Default | What it does |
|---|---|---|
| `SQUAWK_WAIT` | 120 | Seconds the hook waits before giving up and falling through to the terminal prompt. Capped at 540. |
| `SQUAWK_SOCKET` | `~/.squawk/sock` | Socket path, for running a second instance in a test. |

Set the hook's `timeout` in `settings.json` higher than `SQUAWK_WAIT`, so the
hook controls the fallthrough rather than Claude Code cutting it off.

## Brand

`design/` holds the SVG sources and the design tokens. `make icon` rasterises
them into `app/Resources/generated/`, which is what the bundle ships. The mark is
a Command Scope: the open ring is an air traffic scope, the chevron is a command
prompt, and the amber underscore is the cursor at the moment an agent is waiting
for clearance.

## Terminals

Approving and denying works in **any** terminal. It runs through a Claude Code
hook, so nothing in that path touches the terminal at all.

Only "Open pane" is terminal specific, and Squawk works out which terminal a
request came from by walking the parent processes of the hook.

| Terminal | Open pane | How |
|---|---|---|
| iTerm2 | exact pane | matches the session's `tty` |
| Terminal.app | exact tab | matches the tab's `tty` |
| Ghostty 1.3+ | best effort | its AppleScript exposes no `tty`, so it matches the working directory and can land on the wrong split when two sessions share one |
| kitty, WezTerm, Alacritty, anything else | brings the app forward | no scripted lookup, so Squawk activates the owning application |

macOS asks for Automation permission the first time Squawk drives a terminal.

## Requirements

macOS 14+, Swift 6. No package dependencies.

## Status

Early. The protocol, expiry, and fail-open paths are covered by tests and a
smoke check. See `docs/design.md` for what is deliberately not built yet.

## License

MIT
