# Runner #3 of the published gaming corpus, and the first one driven through an
# addon rather than through a raw socket.
#
# `sdks/js/test/conformance.test.ts` and `sdks/dotnet/Haiven.Sdk.Conformance` both drive a
# bare transcript client on purpose — a bug in the binding must not be able to
# mask a server assertion. This one deliberately does the opposite and drives
# `addons/haiven`, because the question #sdkconformance names is not "does the
# server answer" (two runners already say yes) but **whether the signal-based
# Godot idiom can be driven by the conformance step vocabulary at all**.
# `session_test.gd` answered that in miniature, against an in-process socket and
# hand-written frames. This answers it the only way that settles it: the real
# published suite, against the real backend, through the real addon.
#
# The fixture is owned by `scripts/check-godot.py`, which builds and starts
# `haiven-api/cmd/wsfixture`, reads its announced endpoints and passes them
# in as environment. Godot cannot read a subprocess's stdout, and the announce
# line is how the fixture publishes its port — so the process lifecycle lives
# where it can be observed and GDScript keeps only the part that is about the
# protocol.

extends SceneTree

const Protocol := preload("res://addons/haiven/haiven_protocol.gd")
const Session := preload("res://addons/haiven/haiven_session.gd")

## This runner's name in the corpus, taken from `spec/targets/gaming/godot.yaml`.
const RUNNER := "godot-headless"

## The published target profile this runner is.
const PROFILE := "gaming/godot"

## What this runner's token source and fixture can supply, declared rather than
## inferred. A scenario needing something absent from this list has to waive;
## without the declaration it would fail deep in a transcript as a protocol
## error and read as a server bug.
const CAPABILITIES := ["token.valid", "token.expired", "fixture.push"]

var failures: Array[String] = []
var checks: int = 0
var executed: int = 0

var _suite: Dictionary = {}
var _base_url: String = ""
var _ws_url: String = ""

var _socket: WebSocketPeer = null
var _session: RefCounted = null
var _inbox: Array[Dictionary] = []

# The corpus names a request id per step, and the addon mints ids through an
# injected Callable. Driving that Callable from a variable set immediately
# before each step is how a runner controls correlation without the addon
# growing a per-call id argument no game would ever pass.
var _next_request_id: String = ""


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)


# --- fixture HTTP ------------------------------------------------------------
#
# `HTTPRequest` is a Node and wants a scene tree and a signal round trip; this
# script is already a polling loop, so `HTTPClient` is both smaller and the same
# shape as everything else here.

func _http(method: int, path: String, body: String = "") -> Dictionary:
	var trimmed := _base_url.replace("http://", "")
	var pieces := trimmed.split(":")
	if pieces.size() != 2:
		return {"error": "base url %s is not host:port" % _base_url}

	var client := HTTPClient.new()
	if client.connect_to_host(pieces[0], int(pieces[1])) != OK:
		return {"error": "could not connect to %s" % _base_url}

	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		client.poll()
		OS.delay_msec(5)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"error": "fixture did not accept a connection"}

	var headers := PackedStringArray(["Content-Type: application/json"])
	if client.request(method, path, headers, body) != OK:
		return {"error": "request %s failed to send" % path}

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		OS.delay_msec(5)

	if not client.has_response():
		return {"error": "no response for %s" % path}

	var code := client.get_response_code()
	var raw := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk := client.read_response_body_chunk()
		if chunk.size() == 0:
			OS.delay_msec(5)
		else:
			raw += chunk

	return {"status": code, "body": raw.get_string_from_utf8()}


## A token of the kind a scenario asks for, never a ttl.
##
## `valid` and `expired` are properties the server will observe; a ttl is a
## fixture affordance. The fixture mints, so this source supplies both — a
## deployment source could only sign in, which is why the corpus waives exactly
## one scenario for `deployment` rather than all of them.
func _token(kind: String) -> String:
	var ttl := "-1s" if kind == "expired" else "1h"
	var answer := _http(HTTPClient.METHOD_GET, "/control/token?ttl=" + ttl.uri_encode())
	if answer.has("error") or answer.get("status") != 200:
		failures.append("could not mint a %s token: %s" % [kind, answer])
		return ""
	var parsed: Variant = JSON.parse_string(String(answer.get("body", "")))
	if typeof(parsed) != TYPE_DICTIONARY:
		failures.append("token endpoint did not answer an object")
		return ""
	return String((parsed as Dictionary).get("token", ""))


func _push(frame: Dictionary) -> bool:
	var answer := _http(HTTPClient.METHOD_POST, "/control/push", JSON.stringify(frame))
	if answer.has("error"):
		return false
	# Any 2xx. The endpoint answers 202, not 200 — it hands the frame to the
	# broker and the write pump delivers it, so "accepted" is the honest code and
	# a runner testing for equality with 200 reads a working push as a refusal.
	var status := int(answer.get("status", 0))
	return status >= 200 and status < 300


# --- the step vocabulary -----------------------------------------------------

func _pump(ms: int) -> void:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if _session != null:
			_session.poll()
		OS.delay_msec(2)


## `expect`: the next frame to arrive.
##
## The corpus is pull-shaped and the addon is push-shaped, so the adaptation is
## one ordered queue filled from `frame_received`. It has to be that arm and not
## `reply_received` / `event_received`: the session consumes `auth.success` and
## `auth.expired` into its own semantic signals, so a runner on the classified
## arms sees nothing for the handshake and cannot tell that from a silent server.
func _next_frame(ms: int = 3000) -> Dictionary:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if not _inbox.is_empty():
			return _inbox.pop_front()
		_pump(10)
	return {}


## `expectSilence`: nothing arrives in the window.
##
## Only expressible because the engine keeps being driven while we wait. A bare
## `OS.delay_msec` would pass by not polling, which is the exact failure this
## verb exists to catch.
func _silent_for(ms: int) -> bool:
	_pump(ms)
	return _inbox.is_empty()


func _open(token: String) -> bool:
	_socket = WebSocketPeer.new()
	if _socket.connect_to_url(_ws_url) != OK:
		return false
	_session = Session.new(
		_socket,
		func() -> String: return token,
		func() -> String: return _next_request_id,
	)
	_session.frame_received.connect(func(frame: Dictionary) -> void: _inbox.append(frame))
	return true


func _teardown() -> void:
	if _session != null:
		_session.close()
		_pump(120)
	_session = null
	_socket = null
	_inbox.clear()


func _key_set(frame: Dictionary) -> Array:
	var keys: Array = frame.keys()
	keys.sort()
	return keys


func _run_scenario(scenario: Dictionary) -> void:
	var id := String(scenario.get("id", "?"))
	var steps: Array = scenario.get("steps", [])
	var connected := false

	for index in steps.size():
		var step: Dictionary = steps[index]
		var verb := String(step.get("do", ""))

		match verb:
			"connect":
				# Deliberately deferred. An idiomatic session authenticates on
				# open — it is handed a token callable and handshakes itself —
				# so `connect` and `auth` are not separable here. The guard below
				# refuses any corpus shape that would need them to be.
				connected = true
				if index + 1 >= steps.size() or String((steps[index + 1] as Dictionary).get("do", "")) != "auth":
					failures.append("%s: connect is not followed by auth; this runner cannot separate them" % id)
					return

			"auth":
				if not connected:
					failures.append("%s: auth before connect" % id)
					return
				var kind := String(step.get("token", "valid"))
				var token := _token(kind)
				if token.is_empty():
					return
				_next_request_id = String(step.get("requestId", ""))
				if not _open(token):
					failures.append("%s: could not open %s" % [id, _ws_url])
					return
				# The handshake is written by the session the moment the socket
				# reports open, from inside poll().
				_pump(40)

			"send":
				var frame: Dictionary = step.get("frame", {})
				_next_request_id = String(frame.get("requestId", ""))
				_session.send(String(frame.get("type", "")), frame.get("payload"))

			"push":
				if not _push(step.get("frame", {})):
					failures.append("%s: the fixture refused a push" % id)
					return

			"expect":
				var arrived := _next_frame()
				check("%s: expects a %s" % [id, step.get("type")], arrived.get("type") == step.get("type"))
				if step.has("keys"):
					var wanted: Array = (step["keys"] as Array).duplicate()
					wanted.sort()
					check("%s: exact key set" % id, _key_set(arrived) == wanted)
				for field in (step.get("fields", {}) as Dictionary):
					check("%s: %s" % [id, field], arrived.get(field) == step["fields"][field])

			"expectSilence", "expect_silence":
				check("%s: silence" % id, _silent_for(int(step.get("ms", 500))))

			_:
				failures.append("%s: unknown step \"%s\"" % [id, verb])
				return

	executed += 1


# --- entry point -------------------------------------------------------------

func _initialize() -> void:
	var suite_path := OS.get_environment("HAIVEN_CONFORMANCE_SUITE")
	_base_url = OS.get_environment("HAIVEN_FIXTURE_BASE_URL")
	_ws_url = OS.get_environment("HAIVEN_FIXTURE_WS_URL")

	if suite_path.is_empty() or _base_url.is_empty() or _ws_url.is_empty():
		# Reported, never silent. A runner whose absence is indistinguishable
		# from its success is not a runner — the whole reason the local corpus
		# fork survived as long as it did.
		print("SKIP conformance: HAIVEN_CONFORMANCE_SUITE, HAIVEN_FIXTURE_BASE_URL and HAIVEN_FIXTURE_WS_URL are required")
		quit(0)
		return

	var raw := FileAccess.get_file_as_string(suite_path)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		print("FAIL  could not read the suite at ", suite_path)
		quit(1)
		return
	_suite = parsed

	# Guarding the shape rather than assuming it: pointing this runner at the
	# http moderation suite would otherwise surface as a socket that never opens.
	check("the suite is gaming/v0", _suite.get("id") == "gaming/v0")
	check("over websocket", (_suite.get("fixture", {}) as Dictionary).get("protocol") == "websocket")
	check("corpus_version 1", _suite.get("corpus_version") == 1)

	var declared: Array = (_suite.get("fixture", {}) as Dictionary).get("capabilities", [])
	var missing: Array = []
	for capability in declared:
		if not CAPABILITIES.has(capability):
			missing.append(capability)
	check("no capability this runner cannot supply: %s" % str(missing), missing.is_empty())

	# A waiver is a recorded gap, not a skip, and a runner answers to every name
	# it has: its runner id, its published profile, and the suite's own
	# lifecycle. Read from the document rather than hardcoded, so a waiver keyed
	# to a lifecycle lapses by itself when the suite is promoted.
	var claimed := [RUNNER, PROFILE, String(_suite.get("lifecycle", ""))]
	var runnable: Array = []
	for scenario in _suite.get("scenarios", []):
		var waivers: Dictionary = (scenario as Dictionary).get("waivers", {})
		var waived := false
		for name in claimed:
			if waivers.has(name):
				print("waived %s: %s" % [(scenario as Dictionary).get("id"), waivers[name]])
				waived = true
				break
		if not waived:
			runnable.append(scenario)

	# A fully-waived suite passes while proving nothing.
	check("has scenarios to run", not runnable.is_empty())

	if failures.is_empty():
		for scenario in runnable:
			_run_scenario(scenario)
			_teardown()

	_report()


func _report() -> void:
	if failures.is_empty():
		print("ok   gaming/v0 through addons/haiven, %d scenarios" % executed)
		print("HAIVEN_TEST_PASS conformance %d" % executed)
		quit(0)
		return

	for failure in failures:
		print("FAIL ", failure)
	quit(1)
