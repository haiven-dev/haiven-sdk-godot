# Godot spike — GDScript and .NET bindings

## The question

**Does the outbound envelope's discriminant survive the crossing into GDScript,
and is dynamic typing enough to make it survive for free?**

The two server frames are told apart by the **presence** of `success`, not its
value (F10). C# needed `bool?` plus an explicit presence check, because a
non-nullable `bool` maps an absent field to `false` and turns every event into a
failed reply. GDScript is dynamically typed and `JSON.parse_string` yields a
`Dictionary`, so the prediction was that presence survives at no cost.

The prediction was half right, which is why it was worth measuring.

## What has been answered

**Presence survives — through `has()`, and only through `has()`.**
`Dictionary.has("success")` is the GDScript equivalent of C#'s
`TryGetProperty`, and a binding built on it discriminates correctly.

**But the natural idiom is the broken one.** `frame.get("success")` answers
`null` for an absent key, and `null` is falsy. So:

```gdscript
if frame.get("success"):   # WRONG
```

takes the same branch for *absent* and for *present and false* — which is exactly
the collapse a non-nullable `bool` causes in C#, in a language that was supposed
to be immune to it. Dynamic typing did not remove the trap; it moved it from the
type declaration to the call site, where it is less visible and more idiomatic.

**So the finding generalises rather than being a C# quirk.** The discriminant is
fragile in every language with a falsy null, and the only correct spelling is an
explicit presence question. Any binding written against `success` truthiness is
wrong, and it is wrong in the direction that silently breaks correlation for
every refused request.

`is_reply` is neutered to the truthy form as a check: it fails exactly one
assertion, *a refused reply is still a reply*, and Godot exits 1.

## The addon, and what the transport cost

`addons/haiven` is the addon: `plugin.cfg`, the protocol, and a session over
`WebSocketPeer`. `session_test.gd` drives it against a **real** socket on both
ends — a `TCPServer` accepts a loopback connection in-process and
`accept_stream` upgrades it — so the transport under test is the engine's own,
and no backend is needed.

**No socket abstraction, and none wanted.** `WebSocketPeer` is engine-native and
takes no injection, so this cannot share the `SocketLike` / `IHaivenSocket` seam.
It also does not need it: that seam exists because a browser, Electron and
React Native disagree about what a socket is, and Godot's already works
everywhere Godot ships.

**Godot charges for it in polling instead.** `WebSocketPeer` has no signals of
its own — nothing arrives unless someone calls `poll()` — so the session is
`poll()` in, signals out, and cannot be constructed and left alone the way the
TypeScript session can.

**The corpus verbs are drivable, but not through the obvious signals.** The
corpus is pull-shaped (`expect` is "the next frame to arrive") and an idiomatic
addon is push-shaped, so a runner needs a queue in between. That much was
expected. What was not: connecting `reply_received` and `event_received` — the
obvious pair — makes the handshake reply **invisible**, because the session
consumes `auth.success` and `auth.expired` into its own semantic signals and the
classified arms are not exhaustive. A runner asserting `expect type:
auth.success` sees nothing and cannot tell that from a server that sent nothing.

So the addon grew a `frame_received` arm that emits every inbound frame before
interpreting any of it. One line, and the corpus verbs are expressible. The test
pins the reason it exists: it asserts the classified arms did **not** see the
handshake, so the raw arm cannot later be deleted as redundant.

## Game login handoff

`HaivenHandoff` binds the first-party game-login flow to Godot's own primitives:
`Crypto` supplies two independent 256-bit values, `HashingContext` applies the
RFC 7636 S256 transform, `OS.shell_open` launches the first-party page, and an
`HTTPRequest` child performs the form-encoded code exchange. The URL launcher
and exchange are injectable for console/mobile host adapters and deterministic
tests; the engine implementations are the defaults.

```gdscript
var tokens := HaivenTokenStore.new()
var handoff := HaivenHandoff.new({
	"entry_url": "https://app.haiven.gg/connect/game",
	"exchange_url": "https://api.haiven.gg/v0/auth/handoff/exchange",
	"integration_id": "my-game",
	"redirect_url": "my-game://auth/callback",
}, tokens)
add_child(handoff) # HTTPRequest needs the scene tree.

var start := handoff.begin_login() # OS.shell_open by default

# Deliver the custom-scheme URI received from the platform integration.
var result := await handoff.complete(callback_uri)

# The same owner is read again on every WebSocket handshake and re-auth.
var session := HaivenSession.new(WebSocketPeer.new(), tokens)
```

Verifier state stays only in the coordinator's memory and is consumed before
the exchange. Callback scheme, host, port, path, and any query fields configured
on the redirect must match before state is touched; mismatched, expired,
cancelled, and replayed transactions cannot reach HTTP. The credential boundary
accepts only an access token, token type, and relative expiry, converts expiry to
absolute Unix milliseconds, and rejects any refresh token.

`handoff_test.gd` pins the S256 vector, exact four-field form body, shared
token-plus-expiry ownership, target/state mismatch, replay, expiry,
cancellation, and the no-refresh-token boundary in a headless engine run.

## The conformance runner, and what driving the addon cost

`conformance_test.gd` is runner #3 of the published `gaming/v0` corpus, and the
first one that is **not** a raw socket. The node and dotnet runners drive a bare
transcript client on purpose, so a bug in the binding cannot mask a server
assertion. This one drives `addons/haiven` deliberately, because the open
question was never "does the server answer" — two runners already say yes — but
whether the signal-based idiom can be driven by the step vocabulary against the
real thing. `session_test.gd` answered that in miniature with hand-written
frames; this answers it with the published suite and a real backend.

**It can, and the raw arm is why.** All four scenarios execute and pass through
the addon. Pointing the runner's queue at `reply_received` / `event_received` —
the obvious pair — instead of `frame_received` fails seven assertions across
all four scenarios, every one of them a handshake the session had already
consumed into `authenticated` / `expired`:

```
FAIL handshake-succeeds-and-says-nothing-else: expects a auth.success
FAIL handshake-into-a-lapsed-session-says-so: expects a auth.expired
FAIL a-reply-is-correlated-to-the-frame-it-answers: expects a auth.success
```

That is the failure mode worth naming: it is indistinguishable from a server
that sent nothing. The classified arms are non-exhaustive **by design** — a game
wants `authenticated`, not a raw handshake frame — so the raw arm is not
redundancy, it is the only way anything can observe the protocol rather than use
it.

**`connect` and `auth` are not separable through an idiomatic session.** The
corpus states them as two steps; an addon handed a token callable handshakes
itself the moment the socket opens, so the runner defers `connect` and does the
real work at `auth`, where the token kind is finally known. It refuses any
scenario shape that would need them apart, rather than pretending. A raw-socket
runner has no such constraint — which is precisely the difference between
testing a protocol and testing a binding.

**Request-id correlation costs one injected Callable.** The corpus names a
request id per step and the addon mints ids internally; driving its `next_id`
Callable from a variable set before each step is enough. No per-call id argument
was added — no game would ever pass one.

**The fixture lives in Python, not GDScript.** Godot cannot read a subprocess's
stdout, and the fixture announces its bound port on exactly that. So
`scripts/check-godot.py` builds and runs `haiven-backend/cmd/wsfixture`, reads
the announce line and passes the endpoints in as environment; GDScript keeps
only the part that is about the protocol. The stage skips loudly without the
backend checkout or Go, like the rest of the live tier, and the harness
recomputes the expected scenario count from the suite document rather than
trusting the number the runner reports about itself — a waiver that swallowed a
scenario fails the stage instead of going quietly green on a suite that stopped
testing anything.

## The .NET flavour

`addons/haiven/dotnet` is the C# side of the addon. `GodotWebSocket` is the thin
engine adapter: it implements the same `IHaivenSocket` seam used by the Unity
package and turns `WebSocketPeer.poll()` into open, receive, and close events.
`HaivenDotNetSession` is a scene-tree node that polls it from `_Process` and
exposes raw-frame, reply, event, authentication, expiry, and close signals.

The protocol and session state machine are not a Godot copy.
`Haiven.Godot.csproj` references the netstandard2.1 project which supplies the
Unity package's core, so both engines use the same parsing, first-frame auth,
pre-auth queue, correlation, and same-socket re-auth behaviour. The headless C#
runner proves that shared state machine against an injected socket; the Godot
project proves the adapter and source-generated signals compile against
`Godot.NET.Sdk/4.5.1`.

The installed editor is the standard build, not the .NET build, so opening the
C# node in an engine and making a live connection remain unmeasured. Godot 4 C#
projects also cannot export to the web; use the GDScript flavour for web targets.

## Still open

The complete generated REST surface remains separate work. The auth handoff has
measured its structural constraint: `HTTPRequest` is a Node, so
`HaivenHandoff` is also a Node and must be attached to the scene tree before a
default exchange. The protocol/session objects remain plain `RefCounted`s.

## Running it

```
make check        # from the repository root
```

`make check` skips loudly without `godot`, and skips just as loudly when the
editor on `PATH` is not the pinned version — an Arch 4.7.2 is not a run this
project is measured on. `scripts/check-godot.py` holds that pin as
`PINNED_VERSION`, which is also what `GODOT_EXPECTED_VERSION` defaults to, so
the dedicated target refuses a wrong editor up front instead of failing later
inside the import. `make check-godot-ci` requires the editor and Python 3: it
fails on a missing engine, a wrong version, import/script errors, timeout, or
missing completion records (13 protocol, 15 session, and 34 handoff assertions). Each run
imports a temporary clean project so an existing editor cache cannot hide an
import failure. Logs remain in `build/godot-results/`, including on failure.

The `Godot editor` CI job runs on every PR and main push with the official
Godot **4.5.1 stable** Linux editor, pinned by release URL and SHA-256 digest.
The official 4.7.2 binary reported `Parameter "singleton" is null` during this
project's headless import, so it is not the CI pin.
It has a ten-minute job limit, a 120-second limit per engine stage, and always
uploads logs. There is no engine-availability skip in this job. Repository
branch protection can require the `Godot editor` status check.

`make check-godot-dotnet` is separate from the GDScript engine stages. It builds
the addon against the pinned Godot .NET SDK and skips loudly without `dotnet`;
`make check-csharp` exercises the shared session state machine without an engine.

To reproduce with an explicit editor:

```sh
GODOT_BIN=/path/to/godot GODOT_EXPECTED_VERSION=4.5.1 make check-godot-ci
```

`GODOT_LOG_DIR` and `GODOT_TIMEOUT_SECONDS` override the log location and per-stage
timeout. CI checks the engine version before import. See the
[Godot command-line reference](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)
for `--headless`, `--import`, and `--script`.

## Releases

release-please cuts every release from `main`. Work lands on `sdk-dev`. The
Promotion PR workflow keeps one `sdk-dev` -> `main` pull request open, and
release-please keeps one release pull request open on `main` that bumps
`version` in `addons/haiven/plugin.cfg`, `CHANGELOG.md`, and
`.release-please-manifest.json`. To release:

1. Merge the promotion pull request with a merge commit, not squash or rebase,
   so `main` holds each `sdk-dev` commit.
2. Before merging the release pull request, merge the open promotion pull
   request, if any, and wait for release-please to update the release pull
   request, so `main` holds every `sdk-dev` commit. release-please reads `main`
   in commit-date order and stops at the latest release commit, so an `sdk-dev`
   commit dated before a release commit but promoted after it is never
   released. For the same reason, squash- or rebase-merge pull requests into
   `sdk-dev`, and rebase local commits onto `sdk-dev` before pushing, so no
   commit reaches `main` dated before the latest release.
3. Merge the release pull request. release-please tags `v<version>` and creates
   the GitHub release.
4. Merge `main` back into `sdk-dev` with a merge commit.

Do not bump `plugin.cfg` or push a `v<version>` tag by hand. release-please owns
both; a hand-made tag leaves the manifest behind, and release-please then
proposes a version whose tag already exists.

The `v<version>` tag push runs `.github/workflows/release.yml`, which publishes
three assets to the GitHub release for that tag:

- `haiven-godot-addon-<version>.zip`: `addons/haiven/`; unzip it into a Godot
  project root.
- `haiven-godot-dotnet-<version>.zip`: `Haiven.Godot.dll` and
  `Haiven.Sdk.Core.dll` with their `.pdb` files, built from `Haiven.Godot.csproj`
  in Release against the haiven-sdk-unity and haiven-sdk-dotnet commits pinned in
  the workflow.
- `SHA256SUMS`: checksums of both zips (`sha256sum -c SHA256SUMS`).

The tag must match `version` in `addons/haiven/plugin.cfg`, or the build fails
before anything is published; the release pull request keeps the two in step.
A version with a pre-release suffix (`v1.2.3-rc.1`) is published as a GitHub
pre-release. Pull requests against `main` and manual runs build the same
assets as a workflow artifact and do not publish.

To build the assets locally (Python 3.9+, `git`, and a .NET SDK):

```sh
python3 ci/package_release.py --out build/dist \
  --sdk-unity ../haiven-sdk-unity --sdk-dotnet ../haiven-sdk-dotnet
```
