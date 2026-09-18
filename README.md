# Squawk

**[squawk website](https://goriparthi.github.io/squawk/)** &middot;
[download](https://github.com/goriparthi/squawk/releases/latest)

A floating dial for approving what your coding agents want to do, without
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

## Agents

Squawk hooks the **harness**, not the model, so what matters is whether your
agent runner has a `PreToolUse` hook that can return a decision.

| | |
|---|---|
| Claude Code | yes, `~/.claude/settings.json` |
| Codex | yes, `~/.codex/hooks.json`, on `PermissionRequest`, which fires only when Codex is about to ask |
| Ollama | no. Ollama is a model runtime with no tool-approval step to intercept. Driving it through Claude Code or Codex is covered by those |
| anything else | only if it exposes an equivalent hook |

`squawk-hook --install` registers with whichever of the two it finds, or name
them with `--claude` / `--codex`.

## How it works

Squawk registers a `PreToolUse` hook with Claude Code or Codex. When an agent is about to
use a tool, the hook hands the pending call to the app over a Unix socket and
waits. You answer on the ring, the app replies, and the hook returns the
decision Claude Code asked for.

```
claude ──PreToolUse──> squawk-hook ──unix socket──> Squawk.app
                            ^                           │
                            └────── allow / deny ───────┘
```

Two things reach the dial. A **decision** is a `PreToolUse` hook waiting on an
answer, drawn amber, with Approve and Deny. **Attention** is a `Notification`:
the agent wants you but nothing is blocked, drawn blue, offering only Open pane,
because a question has to be answered where it was asked.

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

## The menu

The dial lives in the menu bar. Its glyph goes amber with a count the moment an
agent is waiting, so the bar says "you" without being read.

| | |
|---|---|
| Dial Size | a slider from 240 to 480 pt, plus small, medium and large presets. It grows about its own centre, and stays where you drag it between restarts |
| Opacity | a slider, because a dial that floats over your work all day needs to recede. Pointing at it brings it back to solid |
| Check for Updates | on demand, or once a day if you opt in. Updates install in place: the download is verified against this project's Developer ID before anything is swapped, and the old copy is kept until the new one is in |
| Open at Login | via `SMAppService`, so macOS lists it in System Settings where you can revoke it |
| Uninstall | removes the hook, the login item and `~/.squawk`, and moves the app to the Trash |

## Keyboard

While the dial has focus:

| | |
|---|---|
| Return | Approve once |
| Escape | Deny |
| S | Allow for the rest of this session |
| L | Always allow |
| O | Open the agent's pane |

From anywhere: `Cmd Shift D` shows or hides the dial, `Cmd U` checks for updates.

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
