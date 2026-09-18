# Squawk

A native macOS floating dock for approving agent tool calls without switching to
the terminal. Swift 6, AppKit, no package dependencies.

This file is the institutional knowledge for the repo: conventions, commands,
architecture, and the mistakes that have actually bitten. Read it before
changing anything.

## Commands

```sh
make test          # offline unit suite. Must be green before any commit.
make smoke         # end to end: real hook binary against a stand in app
make bundle        # assemble dist/Squawk.app
make run           # install to ~/Applications and launch
make install-hook  # register the PreToolUse hook, backing up settings.json
```

`swift build` needs only the Command Line Tools. XCTest needs Xcode, which is
why `make test` sets `DEVELOPER_DIR`.

## Architecture

```
app/Sources/SquawkCore/    UI-free: the wire protocol, roster state, tool
                           summaries, hook output JSON, tty validation, sockets
app/Sources/Squawk/        AppKit: the panel, the ring, the detail card, the
                           socket server, pane focus
app/Sources/squawk-hook/   the PreToolUse hook binary, bundled at
                           Contents/Helpers/squawk-hook
app/Tests/                 the offline suite
design/                    the brand kit: SVG sources and design tokens
app/Resources/generated/   PNGs and the .icns, rendered from design/, committed
scripts/smoke.sh           end to end protocol check
scripts/render-icon.swift  rasterises design/ into the shipped assets
```

**Logic belongs in `SquawkCore`.** It is UI-free and therefore testable. If
something in the AppKit layer is worth a test, move it down first.

## The rules that matter

- **The hook fails open, always.** Every error path in `squawk-hook` exits 0
  with no output, which falls through to the normal terminal prompt. An agent
  must never block on a UI that is not running. Any new branch in that binary
  gets the same treatment, and `make smoke` covers it.
- **Never write into a terminal pane.** Squawk selects panes. Injecting
  keystrokes was tried and lands partial lines when the shell is still
  initialising. See `docs/design.md`.
- **A tty is validated, not escaped.** It is interpolated into AppleScript, so
  `PaneFocus.isValidTTY` refuses anything that is not `/dev/tty` plus
  alphanumerics. Do not relax this into an escaping function.
- **An arc expires on the budget its own hook declared** (`waitSeconds`), not on
  a lifetime the app picks. The app used to guess, and an arc that outlived its
  hook let you approve into a closed socket with no feedback.
- **The panel is laid out with constraints only.** A hand set frame for the ring
  drifted against the panel height and the rounded corner clipped it. The ring
  and the card are one centred column; the card collapses when nothing waits, so
  the dial sits in the middle rather than above three disabled buttons.
- **Labels must lose the width argument.** The command label keeps full
  compression resistance by default, wins against the card's width, and drags
  the whole window wider than its frame. Every label in the card is low priority
  horizontally and truncates.
- **Buttons are `FirstMouseButton`.** The panel is answered while another app
  has focus, so a plain `NSButton` would spend the first click activating the
  window.

## Brand

`design/` is the source of truth and `app/Resources/generated/` is derived from
it. Never hand edit a generated PNG or the `.icns`; change the SVG and run
`make icon`.

- Colours live in `design/squawk_design_tokens.json` and are mirrored in
  `Palette`. Change the token first.
- State colours are named for the state, not the hue: waiting, running, error,
  complete. Do not introduce a raw hex at a call site.
- The menu bar gets `StatusTemplate.png` as a template image so macOS tints it.
  The full colour icon never goes in the menu bar.
- Every mark is concentric: the ring, the centre blip, and the 45 degree tail
  all share one centre. Two of the three supplied SVGs were off, so if you edit
  a mark, re-check that the arc endpoints actually lie on the stated radius.

## Conventions

- Swift 6 language mode, warning-free.
- No package dependencies. This is a product property, not an accident.
- Comments say why, not what, and stay to two lines.
- No em dashes anywhere: UI copy, comments, commit messages, docs.
- Commit messages: one imperative line, then at most three or four lines of body
  when the why is not obvious. No Claude co-author trailers. No ticket prefixes;
  this is a personal project and does not use Jira.

## Gotchas

- The socket is `~/.squawk/sock`, chmod 0600, because it carries approval
  authority. `sockaddr_un` caps the path at 104 bytes, which `SocketPath`
  checks rather than truncating silently.
- Pane focus needs Automation permission for iTerm2; macOS prompts on first use.
- Verifying a click with synthetic events (`cliclick`, System Events) needs
  Accessibility permission for the calling process. Without it the click is
  dropped silently and looks like an app bug.
