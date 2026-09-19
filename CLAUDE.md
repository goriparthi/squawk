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
app/Sources/SquawkCore/    UI-free: the wire protocol, roster state, hook output,
                           and every rule the pet lives by: Pose3D and the
                           springs, the walk (Gait), the dance and groove, the
                           beat detector and spectrum meter, wellness, the cast,
                           bubble placement, the face's expressions and frames
app/Sources/Squawk/        AppKit: AppDelegate orchestrates; updateFace decides
                           the mood. Companion3D/ is the SceneKit model, its
                           view and its pose writer. FaceAnimator + FaceArtist
                           are shared by the flat dial and the model's screen.
                           SystemAudio is the Core Audio tap; PrivacyWatch the
                           mic and camera; NowPlaying asks players and browsers
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
- **An arc dies with its hook, not just with its deadline.** `RequestServer`
  waits in slices and peeks the socket for EOF, because a killed agent would
  otherwise leave an arc sitting there, still clickable, answering nobody.
- **The menu bar glyph goes amber when something waits.** That is a state
  colour, not the brand's; the kit says the template carries no amber, and this
  is a deliberate exception because the bar has to say "you" without being read.
- **Open at Login registers whatever copy is running.** Register from a build
  directory and macOS remembers that path. `Squawk --disable-open-at-login`
  exists so the way out does not require a click in the same copy.
- **Buttons are `FirstMouseButton`.** The panel is answered while another app
  has focus, so a plain `NSButton` would spend the first click activating the
  window.

## The face

The dial has eyes, in the manner of a small companion display: feeling is
carried by eye shape alone, never by detail, because at this size detail is
noise. `FaceExpression` is the discrete mood, `FaceFrame` is the continuous
state actually drawn, and `FaceView` runs a `CADisplayLink` that eases one
toward the other. Nothing sets a drawn value directly.

- **Do not animate through `animator()`.** A custom property is not animatable
  through the proxy, so `face.animator().lidPhase = 0` silently snapped. That is
  why the loop exists.
- **Offscreen renders have no display link**, so `settle()` jumps to the target.
  Without it every face in `--preview-faces` drew as the default.
- Approach is exponential and frame-rate independent, so the motion is the same
  at 60 and 120.
- **The eyes are wider than tall and carry no dark cut.** An earlier notch along
  the lower edge read as a pupil looking down, which is the opposite of alert.
- A poke is decided on mouse up, not mouse down, because dragging the dial
  somewhere is not prodding it.

## Uninstall

Remove **every** copy, via `NSWorkspace.urlsForApplications(withBundleIdentifier:)`,
not just `Bundle.main.bundleURL`. Installing from a DMG as well as from a build
leaves two, and removing only the one being run from looks exactly like
uninstall having failed. The confirmation names each path, because an uninstall
that trashes something unnamed is worse than one that misses it.

## Borrowed from OpenPets

Three ideas came from reading OpenPets (MIT, github.com/OpenPetsHQ/openpets),
which solves an adjacent problem well. No code was copied.

- **Writes to another tool's config are atomic, with a backup first.** Squawk
  was writing `~/.claude/settings.json` non-atomically, so dying mid-write would
  have cost the user every setting in it, not just Squawk's entry.
- **Install state is classified, not a boolean.** `missing` / `installed` /
  `needsUpdate` / `conflict` / `invalid`, surfaced by `squawk-hook --status`. A
  stale path is the failure that looks most like the app being broken, and it
  now names itself.
- **Nothing sensitive reaches the screen.** They never put agent text in a
  speech bubble at all. Squawk has to show the command, so it redacts instead:
  see `ToolSummary.redact`.

## Drawing quality

The companion is drawn, not composed from images, so quality is a code concern:

- **Shell lighter than the scope.** The scope has to read as an inset screen. At
  the same tone the head is just a dark blob.
- **Every filled shape gets a clipped sheen** and the figure gets a soft ground
  shadow. A flat fill has no volume, and without contact shadow it floats.
- **One arm is built and the other mirrored.** Computing both from a signed side
  rendered a symmetric pose lopsided, and chasing the sign is worse than making
  symmetry structural.
- `--preview-body` renders the companion offscreen on a neutral field. Judging it
  by screenshotting the live window photographs whatever is behind it.

## The body

`BodyPose.pose(for:)` maps every expression to two arm poses and a lean, in
core, so the poses are testable and every mood has to differ. `BodyGeometry`
derives the whole silhouette from the head diameter, which is the only size the
user sets.

- **The head is the head, whatever the style.** `CircleBackgroundView.headFrame`
  is the single source of truth for where it is, and the ring, face and card are
  laid out against it rather than the canvas. An earlier version pinned them to
  the canvas, which put the face above the head in full style.
- **Set constraint constants at creation, not only on resize.** The first layout
  happens before any resize call, so a constant that is only corrected later is
  wrong on screen until something moves.
- The card lives in the bubble in full style, because covering the eyes defeats
  the point of having a body.

## Settings

`~/.squawk/config.json`, 0600, written on every change. `Settings` is the only
thing that touches it. The old defaults domain is migrated once and then
cleared, so there is never more than one source of truth. The window frame is
the exception: AppKit still owns that through its autosave name.

Scheduled checks are "a slot has passed that the last check predates", not
"24 hours have elapsed". That way a machine asleep at ten checks on waking
instead of skipping the day.

## Risk signal

`RiskSignal` is deliberately crude and deliberately not a security control. It
decides how the dial looks, never what is allowed, so a miss costs nothing: the
request is still a prompt. Pipes into a shell are matched on the segment rather
than as a substring, so `grep | shuf` is not mistaken for `curl x | sh`.

Risk is judged on the entry you are being shown, not the worst thing queued, so
the face matches the command under your eyes.

## Brand

The GitHub mark is a third-party mark used only to identify the row that opens
Squawk's own repository, never as Squawk branding. It is Simple Icons CC0, the
same vector and the same shape of helper `redline` uses, recorded in
`design/THIRD_PARTY_NOTICES.md`. Unlike redline's it is `@MainActor` rather than
lock guarded, because this repo does not buy compilation with
`nonisolated(unsafe)`.

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

## Agents

One hook binary serves both, but they differ in three ways, all carried by
`AgentHost` and `AgentEvent`:

- **Event.** Claude Code decides on `PreToolUse`, which fires before it has
  decided whether to ask, so `GatePolicy` filters it by permission mode. Codex
  has `PermissionRequest`, which fires only at the moment of asking, so it is
  never filtered. Registering Codex on its `PreToolUse` over-prompts exactly the
  way Claude Code did before the gate policy.
- **Reply shape.** Claude Code takes a flat `permissionDecision`; Codex nests
  `decision.behavior`. Sending one the other's shape is silently ignored.
- **Input.** Codex sends `turn_id` and no `tool_use_id`, so `toolUseId` is
  optional and `requestId` falls back rather than failing the decode.

Codex has no `Notification` equivalent, so a Codex question does not reach the
dial.

Ollama is not an agent harness. It serves models and never asks permission to
run anything, so there is nothing to hook.

## What reaches the dial

An attention entry has **no hook waiting on it**, so nothing times out to clear
it. It therefore needs its own way out: a Dismiss action, a clear when that
session sends anything new (proving it is no longer idle), and a shorter expiry
than a decision. Without those it sat on the dial with no way to remove it.

The face shows only when nothing is waiting. A reaction used to take the middle
for over a second, hiding a request that still needed answering.


`PreToolUse` is a decision: a hook is blocked and the dial answers it.
`Notification` is attention: the agent wants the human, nothing is blocked, and
the hook posts and exits. Attention entries carry `needsDecision: false`, draw
blue rather than amber, and offer only Open pane, because a question cannot be
answered from the dial. Without the Notification hook a session waiting on a
question is invisible, which is exactly how it looked before it existed.

**PreToolUse runs before Claude Code decides whether it would even ask**, so
gating every mode turns silent auto-approval into a dial prompt on every call.
`GatePolicy` steps in only for modes that actually prompt, and an unknown or
absent mode does not gate: over-prompting is the failure that makes this app
worse than not having it. These sessions run `auto`, which is not gated;
`SQUAWK_GATE_MODES=default,auto` opts back in.

**Always is standing permission.** It persists to `~/.squawk/rules.json` and
applies to every future session, so it states its scope and takes a
confirmation. A stray click once granted `Bash(rm -rf)` silently, which is why
the rules are listed and revocable in the menu. Session rules are in memory and
do not confirm.

## Updates

**Never block the main thread waiting for async work.** `NSAlert.runModal`
spins a nested run loop, and work hopping back to the main actor is not
reliably serviced there, so the completion never arrived and the update sat
forever. `ProgressPanel` is an ordinary non-modal window, and the completion
comes back through `DispatchQueue.main`, not a `Task`.

**Test the flow, not the half that is easy to reach.** `--stage-update` drove
only the download and verify, which always worked; the hang was in the panel
half it never touched, and it shipped twice. `--test-update` runs the real
thing, panel and swap included.

**Never hand a subprocess a Pipe nothing reads.** `Installer.run` sends stderr to
`FileHandle.nullDevice`. An unread pipe deadlocks once the child fills the
buffer while this side blocks reading stdout. Every step also has a deadline,
and so does the download: `URLSession.shared` waits indefinitely on a stalled
connection, which is indistinguishable from a frozen dialog.

Cancel genuinely stops it. It used to dismiss the sheet while staging ran on,
which would have swapped the app out from under someone who said no.


An update is verified before anything is swapped, and both gates must pass:
Gatekeeper via `spctl`, and a `codesign` requirement pinning the team id. The
team is a codesign requirement rather than a grep of codesign's text output,
because that output contains the app's own filename, which an attacker chooses.
The staged copy is verified too, not only the one on the mounted image. The
installed app is moved aside rather than deleted, so a failed swap can put it
back.

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
- Synthetic clicks (`cliclick`) do land on this machine, including menu bar
  items and buttons in the non activating panel. An earlier assumption that they
  were blocked was wrong; the failures then were bad coordinates. Aim from a
  fresh screenshot, and remember a stray click can toggle a real menu item.
  Events posted to Squawk's own pid (`~/i3logix/claude_scripts/poke-own-app.swift`)
  cannot reach other apps, but aimed from the *menu's* window bounds instead of
  the panel's they opened the menu. Capture the layer 3 panel first, and prefer
  `--check-hits`, which tests routing without clicking anything.
- **Block edits by brace matching, not by two text anchors.** An end anchor
  that sits earlier in the file than the start anchor slices to an empty
  string, and replacing the empty string inserts between every character:
  `CompanionScene.swift` was written out at 2.3 million lines twice and the
  compiler ran for eleven minutes on it. `replace_block()` in the session
  scripts matches braces; anything else asserts the range is non empty.
- **TCC-gated work is silently denied from a terminal.** The audio tap ran and
  delivered correctly shaped blocks of pure zeros when launched from a shell;
  from the real app it worked. AppleScript to Music, Spotify and browsers does
  the same. Test those through `open -a dist/Squawk.app --args <flag>` and
  write results to a file; `log show` does not reliably surface the app's
  `NSLog` either, so a missing log line proves nothing.
- **`make dmg | tail -1` reports `tail`'s exit code.** The DMG step fails on
  purpose when it cannot notarize; piped without `set -o pipefail` that failure
  was invisible and the release step ran anyway.
- **The tummy is `CompanionScene.body`, the mesh, not `bodyPivot`.** The
  shoulder pads, badge, meter and lamp hang off the same pivot, and matching
  on it made a double tap on a shoulder a dance. A single tap on the tummy
  does nothing on purpose: `PetClick` explains why.
- **A number typed in beside a chain is wrong the moment the chain changes.**
  The shadow, the camera framing and the headphone framing were each hardcoded
  next to the geometry they depended on, and each drifted as the pet grew: the
  shadow ended at the knees, the feet went out of frame, the band was clipped.
  `Size.soleY`, `topY`, `framedHeight` derive from the chain now. Keep it so.
- **A running average seeded at zero is a beat detector that fires on silence
  ending.** `BeatDetector` seeds from its first block. The onset test reads
  linear energy, never the compressed display bands, which pin at 1.0 against
  real audio and have no ratios left to detect with.
- **`SCNView` cannot be paced.** It renders on a display link of its own at
  whatever `preferredFramesPerSecond` maps to on the panel (118 when asked for
  60, 24 when asked for 30, on the 120Hz built in display), and `isPlaying`
  and `rendersContinuously` change nothing. `CompanionView` is an `MTKView`
  that `SCNRenderer` paints once per tick of the pose loop, so that loop's
  `CADisplayLink` is the frame rate, and `FramePace` decides it. The drawable
  is `.bgra8Unorm_srgb`; plain `.bgra8Unorm` rendered the shell black. Frame
  rate is nearly the whole CPU bill: 120 renders a second cost 40% of a core,
  60 about 20%, 24 about 10%.
- **A measurement that renders is a measurement of itself.** `showsStatistics`
  and an `SCNSceneRendererDelegate` both make SceneKit render every frame.
  Count frames with a plain counter in the loop written to a file, and read
  `ps -o %cpu` with the load average beside it: a busy machine reads twenty
  points low.
- **Every activity needs a way out.** `.arriving` had none, so after walking
  on the pet counted as moving for the rest of the day: full frame rate, no
  idle breath or groove, and the body pose the app set was never applied,
  which is what "the refusal does not point" looked like from outside.
