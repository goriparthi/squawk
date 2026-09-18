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
- **Approve and deny are terminal agnostic; only pane focus is not.** The hook
  path touches no terminal. `PaneOpener` resolves the owning application from
  the request's parent pid chain and picks a strategy: `tty` for iTerm2 and
  Terminal.app, working directory for Ghostty, and plain activation for
  everything else. Add a terminal in `PaneFocus.Terminal`, not at a call site.
- **A tty is validated, not escaped.** It is interpolated into AppleScript, so
  `PaneFocus.isValidTTY` refuses anything that is not `/dev/tty` plus
  alphanumerics. Do not relax this into an escaping function.
- **An arc expires on the budget its own hook declared** (`waitSeconds`), not on
  a lifetime the app picks. The app used to guess, and an arc that outlived its
  hook let you approve into a closed socket with no feedback.
- **The window is square, the paint is a circle.** macOS routes mouse events by
  the window's alpha, so the unpainted corners click through to the app behind.
  `CircleBackgroundView.hitTest` returns nil outside the circle to match, and
  the shadow follows the drawn alpha, so `invalidateShadow()` runs after any
  content change.
- **A circle costs you text.** The inscribed square is about 45% of the bounding
  box, so the command inside the ring is truncated and the full text lives in the
  hover card. Never remove that card without giving the command another home;
  approving what you cannot read is the failure this app exists to prevent.
- **Hover needs `acceptsMouseMovedEvents`.** A tracking area asking for
  `.mouseMoved` silently receives nothing unless the window opts in.
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
- The mark is a Command Scope: an open scope ring, a `>` command prompt, and an
  amber cursor. The ring centre and the chevron apex share one centre. Check that
  when editing a mark: an earlier kit shipped arcs whose endpoints did not lie on
  the stated radius, and SVG silently inflates the radius to make them fit rather
  than failing, so it renders wrong instead of erroring.
- The menu bar glyph carries no amber. It is a template image and macOS supplies
  the colour, so a second colour in it would be ignored or come out wrong.

## Conventions

- Swift 6 language mode, warning-free.
- No package dependencies. This is a product property, not an accident.
- Comments say why, not what, and stay to two lines.
- No em dashes anywhere: UI copy, comments, commit messages, docs.
- Commit messages: one imperative line, then at most three or four lines of body
  when the why is not obvious. No Claude co-author trailers. No ticket prefixes;
  this is a personal project and does not use Jira.

## Gotchas

- **`NSHomeDirectory()` reads the password database, not `$HOME`.** Setting
  `HOME=` in front of a test does not isolate anything, and a run like that once
  rewrote the real `~/.claude/settings.json`. Anything that resolves a path under
  the home directory takes an explicit override: `squawk-hook --settings <path>`,
  and `HookInstaller.apply(settings:)` underneath it.
- **`settings.json` belongs to the user, not to Squawk.** The installer rewrites
  only its own `PreToolUse` entry, backs the file up first, and refuses outright
  rather than overwriting a file it could not parse.

- The socket is `~/.squawk/sock`, chmod 0600, because it carries approval
  authority. `sockaddr_un` caps the path at 104 bytes, which `SocketPath`
  checks rather than truncating silently.
- Pane focus needs Automation permission per terminal; macOS prompts on first
  use. A blocked script fails with AppleEvent error -1743, which looks like a
  bug in the lookup but is a permission the user has not granted yet.
- The Terminal.app and Ghostty focus scripts are written against their published
  scripting dictionaries but have not been exercised at runtime here. Only the
  iTerm2 path has.
- Verifying a click with synthetic events (`cliclick`, System Events) needs
  Accessibility permission for the calling process. Without it the click is
  dropped silently and looks like an app bug.
