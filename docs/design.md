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

## Why each agent gets a different event

Claude Code fires `PreToolUse` before it has decided whether it would even ask,
so answering every one of them turns silent auto-approval into a prompt on every
call. `GatePolicy` therefore steps in only for modes that actually prompt.

Codex has `PermissionRequest`, which fires at the moment of asking. That needs no
filtering, and it is why Codex is registered there rather than on its own
`PreToolUse`. The reply shapes differ too: Claude Code takes a flat
`permissionDecision`, Codex a nested `decision.behavior`.

## Why answers are remembered

Asking once and then asking again for the same shape of call is how a prompt
becomes something dismissed unread. Session and Always exist so the prompting
decays. Always is standing permission across every future session, so it names
its scope and confirms; a stray click once granted `Bash(rm -rf)` with neither.

## Not built yet

- **Answering a question from the dial.** Only decisions settle in Squawk. A
  free text answer still needs the pane, because no agent exposes a channel for
  injecting one. Claude Code's `Notification` at least makes a waiting session
  visible; Codex has no equivalent event, so a Codex question stays in its
  terminal with nothing on the dial.
- **Terminals beyond iTerm2, at runtime.** Terminal.app and Ghostty focus
  scripts are written against their published dictionaries and unit tested for
  shape, but only iTerm2 has been exercised end to end here. Automation consent
  blocked the rest.
- **Remote sessions.** Local socket only. Agents on other machines are out of
  scope until the local case is solid.
- **Policy and audit.** The interesting version of this product logs who
  approved what against which environment. The data model already carries cwd
  and session, and now the remembered rules, but nothing is persisted as a log.
