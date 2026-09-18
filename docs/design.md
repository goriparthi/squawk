# Design notes

## Why a hook and not keystroke injection

The obvious way to approve from outside the terminal is to type into the pane.
It was tried and rejected on evidence: writing into a freshly spawned iTerm2
session landed a partial line, because the shell was still running its init and
ate the first half of the text. Anything built on that races the terminal and
fails in a way the user cannot see.

`PreToolUse` hooks can return a decision directly:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
```

and a hook that times out does not block the call, it falls through to the
normal permission flow. That gives a supported response channel and a safe
failure mode in one move.

## Why the hook declares its own deadline

The app used to expire arcs on a lifetime it picked itself. When the two numbers
disagreed, an arc outlived the hook that raised it, so clicking Approve sent a
decision into a socket nobody was reading and the user saw nothing happen. The
request now carries `waitSeconds` and each arc expires on the budget its own
hook declared.

## Why panes are selected, never written to

Same reason as above. "Open pane" is for anything you would rather read in
context or answer by typing, and it only ever brings the window forward.

## Not built yet

- **Answering a question from the dock.** Only approvals settle in Squawk. A
  free text answer still needs the pane, because there is no supported channel
  for injecting one.
- **Other terminals.** Pane focus is iTerm2 only. Everything else works
  anywhere; the button just disables itself when there is no usable tty.
- **Remote sessions.** Local socket only. Agents on other machines are out of
  scope until the local case is solid.
- **Policy and audit.** The interesting version of this product logs who
  approved what against which environment. The data model already carries cwd
  and session; nothing is persisted yet.
