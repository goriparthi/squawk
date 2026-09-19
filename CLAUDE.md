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

## Noises

`Chirp` holds the notes, in core, so a beep can be tested: every one starts
and ends at silence (a note that does not clicks, and the click is louder than
the note), none is louder than 0.32, and none lasts a quarter second.
`Chirps` wraps them in a WAV header once and plays them.

- **It never chirps over something else.** Not over music, which it is already
  dancing to, and not over its own voice. A toy that beeps across your track
  gets switched off, and rightly.
- One note per dance step, running a pentatonic phrase rather than the same
  beep, so a routine has a tune and cannot land on a sour note.
- **Every character has its own groove.** `Chirp.groove(for:)` gives each one
  a tempo, a pattern, a swing and a bass figure written to its tagline, and
  `CompanionView.ownTempo` follows it so the moves are in time with the loop
  rather than near it. The bar is exactly four beats or it drifts, and it has
  to end near silence or every repeat clicks. A test asserts no two characters
  produce the same bar: two that match are a copied line, not a character.
  A detected beat still wins, because dancing to your record beats dancing to
  itself, and the loop stops the moment a track starts.
- **A very dark shell only works because it is lit rather than filled.** Soot
  sits at 0x14171A; at a flat black the body loses its edges and reads as a
  hole in the screen.

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

## Speaking

The pet can say what your agents are waiting on. `Briefing` turns the roster
into facts and `Utterance` turns those into a sentence, both in core and both
tested, so whatever speaks is handed something it cannot invent.

- **It talks with nothing installed.** `SystemVoice` is `AVSpeechSynthesizer`,
  and it picks the best English voice present, preferring the enhanced and
  premium ones the user downloads in System Settings. With none of those the
  system voice is the compact Samantha, which is why the neural option exists.
- **Piper's own macOS build cannot be used.** Its last release (2023.11.14-2)
  ships an x86_64 binary inside `piper_macos_aarch64.tar.gz`, unsigned, with
  its dylibs missing entirely; it cannot load. The engine is sherpa-onnx
  (Apache 2.0), which runs the same Piper voices, ships ad-hoc signed native
  arm64 and x64 builds, and is current. `VoicePack` keeps one binary and the
  one library it loads out of the thirty in that release.
- **Catalogue order is preference.** With no voice chosen, the first one
  installed speaks, which is why Alan leads: downloading a voice and still
  being read to by the compact system one is not what installing it meant.
- **Downloads are pinned by hash, not by signature.** A third party binary
  carries no signature of ours to check, so the exact bytes are the check:
  every entry's SHA-256 was downloaded and hashed here and matches the digest
  GitHub records for the asset. Never add a catalog entry whose hash was not
  verified this way.
- **Every voice tarball carries the same 18 MB of phonemes.** The first one
  installed keeps them and the rest share, or four voices cost 72 MB in
  duplicated `espeak-ng-data`.
- **A neural line costs about two and a half seconds before any sound**, all
  of it loading the model in a fresh process. Lines are cached as audio keyed
  by voice and text, so anything said twice is instant. Do not assume an
  announcement is immediate.
- `--voice-status`, `--say "<text>" [--voice piper:<id>]` and
  `--install-voice <id>` exercise all of it without the menu.

**A model on the machine may rephrase it**, and nothing depends on one.
`Phrasing` builds the facts and judges the reply; `Ollama` does the asking.

- **The model only rephrases.** It never decides, never sees anything it was
  not given, and `Phrasing.accept` throws away a reply that drops a project,
  loses the count, loses a risk warning, or arrives as reasoning or markdown.
  A dropped warning is the one that matters: a model did exactly that in
  testing, which is why that check exists.
- **It is still a small model.** It will occasionally blur which project did
  what, and no check catches that. The bubble always shows the exact command;
  the spoken line is a nudge. This is why it is off by default.
- **It looks things up before it answers.** `Lookup.grounding` tries the named
  thing as a title, then Wikipedia's own search, and hands the summary to the
  model. That is the difference between "I have no information" and "According
  to the 2020 census, Denver has a population of 715,522".
- **A wrong article is worse than no article.** Wikipedia's search ranks
  "tallest mountain in Colorado" as "List of tallest buildings in Denver", and
  a model grounded on that will tell you about buildings, confidently.
  `Question.isRelevant` requires every meaningful word of the title to appear
  in the question, and drops the result otherwise.
- **There is no web search, and adding one is a decision, not a feature.**
  Every keyless option is dead or useless: DuckDuckGo's instant answers return
  nothing for ordinary questions. A real search means someone's API key and
  the user's questions leaving the machine, which is the opposite of the rest
  of this design. Wikipedia is the compromise: keyless, attributable, and
  enough for facts about things that exist.
- **Grounding beats model size, and its absence looks like stupidity.** Adding
  the situation made both models answer "who wrote Dracula" with "I have no
  information", because nothing matched `Question.subject` so nothing was
  looked up, and they had been told to admit ignorance. Verb shapes ("who
  wrote", "who invented") name a thing as surely as "what is" does. That
  extraction is in core precisely because it broke silently once.
- **The preference order is measured.** A seven billion instruct model answers
  questions about the journal noticeably better than a three billion one and
  still returns inside two seconds, so `qwen2.5:7b-instruct` leads and the
  small ones stay for a smaller Mac. Nothing is required: with no Ollama at
  all the clock, the date and the weather still answer.
- **Reasoning models are unusable here.** qwen3:4b narrates its working into
  the reply through `think: false`, `/no_think`, a system instruction and a
  worked example alike, and every one of those replies is refused. Small
  instruct models answer properly: `llama3.2:3b` is the default and takes
  about 650 ms warm, against a 2.5 s deadline.
- **Never ask a big model.** Loading qwen3-coder:30b at its default 262144
  context wanted 45 GB on a 36 GB Mac and took minutes while the machine
  thrashed. Squawk asks for `num_ctx` 2048 and only uses models it knows are
  small, or one the user named themselves.
- **Cloud models are filtered out.** The briefing says what your agents are
  about to run, so anything named `:cloud` is skipped even when Ollama lists it.
- `--test-phrasing` prints the plain sentence, the model's, and the time.

## Saying hello

It greets you on launch, in the bubble, and out loud when Speak Aloud is on.
`Greeting` holds the lines and the rule: never the same one twice running, so
the last is kept in the config and excluded next time. A pet with one
catchphrase is a doorbell. The pool changes after 10pm and before 6am, because
being at the desk then is a decision rather than a schedule. It is the lowest
`Speech.Kind` there is and gives way to anything, and it stays quiet when
something is already waiting.

## Answering questions of its own

Off by default, because it is a different job from answering for your agents.
`Asking` routes one question, and the order is the whole design.

- **Anything with a right answer is worked out, never generated.** A model
  states today's date with total confidence and is wrong, because it cannot
  know it. `Answers.exact` handles the clock and returns nil for everything
  else, in about 50 ms, and it is reached first.
- **The weather is fetched, not remembered.** Open-Meteo, no key and no
  account, and the place comes from the Mac's own time zone ("America/Denver"
  to "Denver") rather than from the location service: asking for that
  permission to answer "is it raining" is a poor trade. `weatherPlace`
  overrides it. Cached for ten minutes.
- **A question naming a thing is looked up first.** `Lookup` fetches the
  Wikipedia summary and hands it to the model as grounding, so an answer about
  a real thing comes from a record of it rather than from what a three billion
  parameter model half remembers.
- **Only what is genuinely open ended reaches the model**, with a short memory
  so a follow up means something, and a system prompt that tells it to say it
  does not know. This is the one part of the app allowed to invent, and it is
  kept away from everything that answers for your agents.
- **Switched off must not look broken.** Understanding a question and then
  doing nothing is the worst thing it can do, because it is indistinguishable
  from a fault; it says which it is, at most once every two minutes so it does
  not repeat itself at everyone who talks nearby.
- **An older build silently drops settings it does not know.** `SquawkConfig`
  encodes the fields it has, so running a previous version rewrites the file
  without the newer keys and they come back as defaults. This is how
  `answersQuestions` turned itself off mid-session. Worth knowing before
  running an old build against a current config.
- `--ask "<question>"` runs the whole path without a microphone, which is the
  only way to test it when the built-in mic is in use: it rejects the Mac's
  own speakers by design, so a command played through `say` is never heard.

## What it knows

`Journal` keeps a week of what happened: every request that arrived, every
approval and denial, and what it was asked. `Situation` turns that, the
roster, the clock and the desk into a handful of lines handed to the model as
grounding on every question.

- **This is the whole argument for the assistant.** Any model can name the
  capital of Australia; only this one can say you denied a drop table in
  collect_db an hour ago. Without the journal it is a worse version of
  something you already have.
- **Counts are not enough.** Given only "approved 3, denied 1, across three
  projects", a model asked which project the denial was in picks one, and
  picks wrong. The actual entries go in the grounding, truncated.
- **It never leaves the machine.** Cloud models are filtered out of the
  model list precisely because this is what would be sent to them. The file is
  `~/.squawk/journal.json`, 0600, a week and 4000 entries at the most.
- **Questions and answers are left out of the grounding.** What it was asked a
  minute ago is already in the conversation, and feeding it back as fact is
  how a model ends up quoting itself as a source.
- **The week is readable, not only speakable.** `HistoryWindow` shows it
  grouped by day, oldest first with the newest at the bottom the way a log
  reads, colour coded by what happened. Built on a text view rather than a
  table so a command can be selected and copied straight out, which is the
  thing anyone actually wants from a list of commands.
- **A window that has never been displayed caches as a blank rectangle.**
  `cacheDisplay` on its content view produced a white page; the preview flag
  shows it for real and it is captured from the screen.
- **It is theirs to erase.** "Forget This Week" is an alternate item under
  This Week, behind option, and it confirms. A week of what someone approved
  is a record of their work.
- **"Today" is an adverb.** `Answers.exact` matched it and answered "what did
  I approve today" with the date. Match the question, not a word in it.

## Listening

Two ways in, both off until asked for, both recognised on this Mac only
(`requiresOnDeviceRecognition`). `Listening` parses what was said and
`VoiceCommand` decides what may be done about it, both in core with tests.

- **The rules about not guessing are the feature.** `VoiceCommand` never
  chooses between two matching projects, never decides an attention entry,
  asks again out loud before approving anything `RiskSignal` calls risky, and
  lets that question lapse after twelve seconds so a stray yes decides nothing.
  Denying goes straight through: it is the safe direction.
- **A decision waits for the end of the sentence.** Acting on a partial
  transcript fires "approve" against whatever is selected before "squawk" has
  been heard. Status, open and quiet may act on partials; decisions may not.
- **Voice answers take the same path as a click** (`finish(id:decision:)`), so
  they are logged, faced and replied to identically. "Always" is never
  available by voice.
- **The hotkey is Carbon's `RegisterEventHotKey`**, not an event monitor or a
  tap, because those want Accessibility permission to notice one combination.
  Asking to watch every keystroke in order to catch one is not a trade worth
  offering. Registration fails if another app owns the combination, and the
  menu says so rather than going quiet.
- **An on device session ends by itself** after about a minute, so the wake
  word restarts it; without that it works once after launch and never again.
- **Its own name is also a project name.** "squawk" is both what it answers to
  and the repo people work in, so `afterWake` takes the *earliest* mention and
  keeps everything after it. Taking the latest left nothing after it, and every
  spoken command naming this repo silently did nothing. `Listening.command` is
  where that and the partial-transcript rule live, in core, because both bugs
  were in app-layer glue that nothing could test.
- **The lamp is the indicator, not the ears.** `PrivacyWatch` leaves Squawk's
  own pid out because the audio tap is not listening to the room; the ears
  are, so `applyPrivacy` puts it back and the lamp lights amber the whole time
  it listens. The ear discs also glow, but they are against the side of the
  head and nearly invisible from the front: a glint, not a signal. Do not move
  the indicator onto them.
- **A callback that answers off the main thread must not inherit the main
  actor.** `Ears` is `@MainActor`, so every closure written inside it is main
  actor isolated, and Swift inserts a check that traps when the closure is
  actually called on another queue. `SFSpeechRecognizer.requestAuthorization`,
  `AVCaptureDevice.requestAccess`, `installTap` and `recognitionTask` all
  answer elsewhere, and the first of them killed the app the moment anyone
  turned push to talk on: `EXC_BREAKPOINT` in `swift_task_checkIsolated`.
  They are `nonisolated` and `@Sendable` now, and only plain values cross to
  the main actor: a recognition result is not safe to send. Any new callback
  from a framework gets the same treatment. Read the crash report rather than
  guessing: this one had been happening during testing and was mistaken for
  consent never being granted.
- **Changing the microphone kills a running engine.** Plugging headphones in
  or pulling them out replaces the input device under `AVAudioEngine`, which
  keeps running and delivers nothing. The lamp stayed lit while the pet heard
  nothing at all. `AVAudioEngineConfigurationChange` rebuilds it.
- **A continuous session is one growing string.** It keeps everything said
  near the machine, never resetting while anyone keeps talking, so after a few
  minutes the wake word sits thousands of characters back with a whole
  conversation after it, and that conversation is read as the command. Only
  the last `Listening.tailLimit` characters are considered.
- **The sentence arrives after the key is up.** Clearing the held flag on
  release made the app ask a push to talk utterance for a wake word it was
  never going to have, and restarting the wake word on a timer cancelled the
  task that still owed us that sentence. The wake word now waits for the final
  transcript, and `awaitingHeldSentence` carries the hold across it.
- **One line can only be loud if the rest are not.** Full scale is full scale:
  `AVSpeechUtterance.volume` and `AVAudioPlayer.volume` both stop at 1. So
  everything it says sits at `SystemVoice.ordinaryVolume` and leaves headroom,
  and the refusal is the one thing that reaches the ceiling, slower and lower
  as well as louder.
- **Everything it says aloud goes through `speakOnly`**, whatever put the
  words in the bubble, so one place stops the microphone first and one place
  logs it. `speakAloud` is that plus the bubble, for answers that have no
  other route on screen.
- **An answer is shown as well as said.** Spoken alone it is a second of
  quiet speech from whatever the output device happens to be, and there is no
  sign at all that it understood you. It goes in the bubble as a `.reply`,
  which does not yield to work: you asked for it.
- **`ListeningLog` is how a silent command gets explained**, and it is the
  only thing in the app that writes a transcript anywhere. It records the
  hotkey, the transcript tail, the parsed intent, the outcome and what was
  said. It holds speech, so it is one click off in the menu and turning it off
  deletes what is already there.
- **The wake word is the persona's name**, so it is whatever character is
  configured: "Pip" by default, not the app's name. "Squawk" always works too.
- **Consent needs a human.** Both prompts come from the bundle and from
  nowhere else, and a test that runs unattended records `permitted: false`
  and exits. `--test-ears <file> [seconds]` writes what it heard and what it
  would have done.

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
  cannot reach other apps, and they never reach the non activating panel at
  all: the panel's `sendEvent` saw nothing, while the same events once opened
  the status menu. The pet's clicks are checked by `--check-hits`, which
  synthesises mouse events straight into the view (`SpeechScene.clicksAreUnderstood`).
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
  giggles and never counts as a poke: `PetClick` explains why.
- **A number typed in beside a chain is wrong the moment the chain changes.**
  The shadow, the camera framing and the headphone framing were each hardcoded
  next to the geometry they depended on, and each drifted as the pet grew: the
  shadow ended at the knees, the feet went out of frame, the band was clipped.
  `Size.soleY`, `topY`, `framedHeight` derive from the chain now. Keep it so.
- **Sound is not music.** `MusicPresence` used to come on at the first noise,
  so a call, a video, a notification and the pet's own voice all put
  headphones on it. It now needs a few seconds of sound that is shaped like
  music (energy under 160Hz, not concentrated in the two speech bands) or a
  tempo the detector has settled on, which nothing but music produces. Eased
  rather than counted, with hysteresis, so a quiet passage does not take the
  headphones off and a bar of talking over a track does not either.
- **The pet wears the mark on its chest** where the badge goes, lit in its own
  accent so it belongs to the creature rather than looking stuck on, and only
  while a model is genuinely running. The music meter still takes that spot
  when a track is on; `restChest` decides what goes back afterwards.
- **The Ollama mark appears only where a model is really doing the work**, the
  same rule the GitHub mark follows: identification, never decoration, and
  never a badge for something that is not running. Both are Simple Icons CC0
  and recorded in `design/THIRD_PARTY_NOTICES.md`.
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
- **A fixed integration slice is a frame rate bug waiting to happen.** The
  springs stepped in 1/90 s slices; the ankle spring (0.08 s response) grew by
  1.048 per slice at that size, invisible at 120fps where a frame was one
  shorter step, and fatal at 30fps: the feet jittered, then went to infinity
  and vanished. The slice is now derived from each spring's own response.
  `Squawk --simulate <fps> <seconds> <face> <out.png> [--arrive|--dance|--music]`
  runs the real pose loop headless and prints every joint; use it before
  changing a spring, a pose, or the frame rate.
- **Every activity needs a way out.** `.arriving` had none, so after walking
  on the pet counted as moving for the rest of the day: full frame rate, no
  idle breath or groove, and the body pose the app set was never applied,
  which is what "the refusal does not point" looked like from outside.
