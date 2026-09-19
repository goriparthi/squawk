# Squawk

**[squawk website](https://goriparthi.github.io/squawk/)** &middot;
[download](https://github.com/goriparthi/squawk/releases/latest)

A desk companion for people who work with coding agents. It answers for them,
reacts to them, and looks after you while they run.

You are reading Slack. An agent in another window wants to run
`git push --force origin main`. A small robot on your desktop turns to you and
holds the command up in a speech bubble; you click Approve or Deny and the agent
carries on. Nothing is typed into your terminal and nothing steals your focus.

It is not a notification that happens to have a face. The face is the point: it
is calm when nothing is waiting, alert when something is, and **wary when the
command is one you would want to read twice**. It gets bored of being ignored,
cross at being prodded, and pleased when you answer. Rub its tummy and it tells
you a fortune. Play music and it puts headphones on, shows the spectrum on its
chest and nods on the beat. Let it, and it will remind you to rest your eyes and
get some water.

In aviation a transponder squawk is how an aircraft announces who it is and what
it needs.

## What it does

| | |
|---|---|
| **Answers for your agents** | Approve, Deny, Allow for this session, Always allow, or jump to the terminal pane it came from. Through a hook, so nothing is typed anywhere |
| **Has a face about it** | Sixteen expressions driven by what is actually happening, interpolated rather than switched, with colour carrying what shape cannot |
| **Has a body** | A modelled companion with arms, hands, knees and ankles, walking on and off screen with a real gait, every joint on a spring so nothing snaps |
| **Reacts to music** | Wears headphones, shows a five band meter on its chest, nods on the beat, and dances at the tempo of whatever is playing |
| **Says when you are being watched** | A lamp on its chest, orange for the microphone and green for the camera, in the colours macOS uses for its own dots |
| **Looks after you** | Eye breaks, posture, water, and a word when it gets late. Off until you ask |
| **Has a cast** | Six characters, each with their own shell, accent and eye colour |

Everything that interrupts you is off by default. Everything that watches
anything asks first, or does not need to.

## Agents
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
them into `app/Resources/generated/`, which is what the bundle ships.

The mark is the pet: its head on the brand tile, with the amber chest badge that
means something is waiting. The menu bar glyph is the same head as a silhouette,
tinted whole, cyan at rest and amber the moment an agent needs you.

The original Command Scope mark is kept at
`design/squawk_command_scope_icon.svg`: an open ring for an air traffic scope, a
chevron for a command prompt, and an amber underscore for the cursor at the
moment an agent is waiting for clearance. It described a dial, and this stopped
being a dial.

## The face

The eyes are calm when nothing is waiting, look about when left alone a while
and heavy after longer, alert when a decision is up and wider still when several
are, curious when a session wants you with nothing to decide, and **wary when
the command is one you would want to read twice**: `rm -rf`, a force push, a
dropped table, a destroy against production.

They are startled by something arriving while asleep, relieved when a backlog
clears, and they acknowledge every answer before settling back. Music gets its
own kind of happy: eyes shut, head over, mouth open, because a pet that wore its
approval face at a song looked like it was congratulating you for it.

Colour carries what shape cannot, easing in and back out: amber when wary,
orange when cross, red once it has given up on you, and bright blue when sad.

Commands are redacted before they are drawn. The dial sits on screen during
screen shares, so a token in an approval prompt is a token you have published.
They blink on an uneven rhythm, glance about, and breathe, because a face on a
metronome reads as a machine ticking.

Prod it and it plays along. Keep prodding and it stops being funny. Keep going
after that and it points at you and says NO.

The wary face is a reading aid, not a safety control: it changes how the pet
looks, never what is allowed, and anything it misses is still a prompt.

## The body

Every joint runs through a critically damped spring, so a mood arrives and a
limb follows through rather than snapping between keyframes. It walks on and off
screen at a human cadence, with heel strike, a knee that gives as the weight
lands, toe off, hip sway, counter rotating shoulders, and an arm that trails its
own leg by seven percent of a stride.

**Pet → Squawk Dial** is the dial alone: a circle, a face, and the card inside
it. **Pet → Squawk** is the modelled companion, and the card moves into a
speech bubble above its head so it never covers the eyes. The bubble slides back
onto the display when the pet is parked near an edge, and its tail slides the
other way so it still points at the head.

**Character** picks who is on screen. Same creature, six colourways.

## Music

**React to Audio** is off until you turn it on, and macOS asks for permission
the first time. It reads the system mix through a Core Audio process tap, which
is public API; the now playing information is not, so what it knows is the
sound itself. A 1024 point FFT, five octave spaced bands, decibels rather than
amplitude, fast attack and slow release.

The beat comes from onset detection on the bottom two bands against a running
average, so a sustained bass note is not a beat however loud. Measured against
generated material of known tempo it lands within half a beat per minute. Start
a dance while music is playing and the routine runs at the track's tempo.

Rub its tummy while something is playing and it tells you what it can hear: the
track and artist when Music or Spotify is playing, through their own public
scripting interfaces, and the tempo whoever is making the sound.

Nothing is recorded. Five numbers reach the pet and nothing leaves the process.

## Looking after you

**Look After Me** is off by default. Turned on, the pet acts out an eye break
every twenty minutes, a posture check, a stretch, a glass of water, and says
something when it gets late. One at a time, never while something is waiting on
you, nothing at all for the first twelve minutes after you sit down, and the
most overdue one wins so a long day does not always lead with whichever interval
is shortest.

**Break Reminder** is separate and also off: it is about being ignored rather
than about you, and makes the pet restless after long enough with nothing
answered.

## Privacy

A lamp on its chest lights **orange** while anything on the machine is using the
microphone and **green** while anything is using the camera, the same colours
macOS uses for its own dots. The camera wins when both are lit, since that is
the greater exposure.

Both answers come from public frameworks: Core Audio's per process
`kAudioProcessPropertyIsRunningInput`, and AVFoundation's
`isInUseByAnotherApplication`. Neither opens the device, so neither needs
permission and neither turns a light on by itself. Squawk excludes its own
process, so listening to your music never lights the microphone.

## Settings

Settings live in `~/.squawk/config.json`, readable and hand editable:

```json
{
  "openAtLogin": false,
  "checkForUpdates": true,
  "updateCheckTimes": ["10:00", "15:00"],
  "alwaysShowDial": false,
  "dialDiameter": 360,
  "dialOpacity": 1.0,
  "petStyle": "full",
  "character": "pip",
  "reactsToAudio": false,
  "wellness": false,
  "breakReminderMinutes": 0
}
```

Update checks run at the times listed, in local time. A machine asleep at 10:00
checks when it wakes rather than skipping the slot. An unparseable time is
dropped rather than resetting the file.

## The menu

The dial lives in the menu bar. Its glyph goes amber with a count the moment an
agent is waiting, so the bar says "you" without being read.

| | |
|---|---|
| Pet Size | a slider from 50 to 480 pt, plus small, medium and large presets. It grows about its own centre, and stays where you drag it between restarts |
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
