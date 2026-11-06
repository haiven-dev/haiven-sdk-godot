# Can the signal-based Godot idiom be driven by the conformance step vocabulary?
#
# That was the open half of #sdkgodot. The corpus's verbs are PULL-shaped —
# `expect` means "the next frame to arrive must match", `expectSilence` means
# "nothing arrives within ms" — and an idiomatic Godot API is PUSH-shaped: it
# emits signals and the game connects handlers. A push API has no "next frame"
# to hand anybody.
#
# The question matters beyond Godot. If the answer were no, the corpus would need
# a seventh verb or a subscribe concept, and every runner would pay for the one
# binding that could not be driven.
#
# This runs against a real WebSocketPeer on both ends: a TCPServer accepts a
# connection in-process and `accept_stream` upgrades it, so the transport under
# test is the engine's own rather than a model of it, and no backend is needed.

extends SceneTree

# preload rather than the `class_name` globals the addon declares. Global class
# names are resolved from the import cache, which a project run straight through
# `--script` has never generated — so relying on them here would make the test
# pass or fail on whether someone had opened the editor first. A consumer that
# imports the addon normally does get `HaivenSession` and `HaivenProtocol` as
# globals; this file just refuses to depend on that.
const Protocol := preload("res://addons/haiven/haiven_protocol.gd")
const Session := preload("res://addons/haiven/haiven_session.gd")
const TokenStore := preload("res://addons/haiven/haiven_token_store.gd")

var failures: Array[String] = []
var checks: int = 0
var _server: TCPServer
var _peer: WebSocketPeer
var _session: RefCounted

# The adaptation under test: signals in, a queue out. If this is enough to serve
# `expect` and `expectSilence`, the vocabulary survives contact with a push API.
var _inbox: Array[Dictionary] = []

# Everything the classified arms saw, to show they did NOT see the handshake.
var _classified: Array[Dictionary] = []


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)


func _pump(ms: int) -> void:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		_session.poll()
		if _peer != null:
			_peer.poll()
		elif _server.is_connection_available():
			_peer = WebSocketPeer.new()
			_peer.accept_stream(_server.take_connection())
		OS.delay_msec(2)


## `expect`: the next frame to arrive. The queue is what makes this expressible.
func _next_frame(ms: int = 2000) -> Dictionary:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if not _inbox.is_empty():
			return _inbox.pop_front()
		_pump(10)
	return {}


## `expectSilence`: nothing arrives in the window. Only expressible because the
## engine keeps being driven while we wait — a bare sleep would pass by not
## polling, which is the failure mode this verb exists to catch.
func _silent_for(ms: int) -> bool:
	_pump(ms)
	return _inbox.is_empty()


## What the server end received, as parsed client frames.
func _server_received(ms: int = 2000) -> Dictionary:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		_pump(10)
		if _peer != null and _peer.get_available_packet_count() > 0:
			return Protocol.parse(_peer.get_packet().get_string_from_utf8())
	return {}


func _initialize() -> void:
	_server = TCPServer.new()
	if _server.listen(0, "127.0.0.1") != OK:
		failures.append("could not listen on a loopback port")
		_report()
		return

	var socket := WebSocketPeer.new()
	if socket.connect_to_url("ws://127.0.0.1:%d" % _server.get_local_port()) != OK:
		failures.append("could not open a loopback socket")
		_report()
		return

	var tokens := TokenStore.new("access-1")
	_session = Session.new(socket, tokens)

	# The adaptation: one ordered queue, filled from the RAW arm.
	#
	# `reply_received` and `event_received` were the obvious choice and they are
	# the wrong one — that is the measurement. They are not exhaustive: the
	# session consumes `auth.success` and `auth.expired` into its own semantic
	# signals, so a runner connected only to the classified arms never sees the
	# handshake reply it is supposed to assert on. `frame_received` was added to
	# the addon in response, and it is what makes the corpus's `expect`
	# expressible against a push API at all.
	_session.frame_received.connect(func(frame: Dictionary) -> void: _inbox.append(frame))

	_session.reply_received.connect(func(frame: Dictionary) -> void: _classified.append(frame))
	_session.event_received.connect(func(frame: Dictionary) -> void: _classified.append(frame))

	# `connect` + `auth`: the session authenticates on open, with no prompting.
	var handshake := _server_received()
	check("the session authenticates on open", handshake.get("type") == "auth")
	check("with the token the callable returned", handshake.get("payload") == "access-1")

	_peer.send_text('{"type":"auth.success","requestId":"","success":true}')

	# `expect`: a reply, pulled from the queue a signal filled.
	var accepted := _next_frame()
	check("expect can pull a frame a signal delivered", accepted.get("type") == "auth.success")
	check("and it classifies as a reply", Protocol.is_reply(accepted))

	# `expectSilence`: the handshake reply is the whole handshake (F13).
	check("expectSilence is expressible against a push API", _silent_for(400))

	# The classified arms stay non-exhaustive on purpose — a game wants
	# `authenticated`, not a raw handshake frame — so this pins the reason the
	# raw arm exists rather than leaving it looking redundant.
	check("the handshake reply reached no classified arm", _classified.is_empty())

	# `send`, now that the session is usable.
	_session.send("ping")
	var ping := _server_received()
	check("send reaches the wire once authenticated", ping.get("type") == "ping")
	check("and carries a request id", not String(ping.get("requestId", "")).is_empty())

	# `push`: a server-initiated frame, which must NOT read as a reply.
	_peer.send_text('{"type":"chat.message","payload":{"id":"m1"}}')
	var event := _next_frame()
	check("push delivers an event", event.get("type") == "chat.message")
	check("an event is not a reply", not Protocol.is_reply(event))

	# The collapse this binding exists to avoid, through the real transport
	# rather than through a parsed literal: a refused reply is still a reply.
	_peer.send_text('{"type":"ping","requestId":"req-2","success":false,"error":"rate_limited"}')
	var refused := _next_frame()
	check("a refused reply is still a reply", Protocol.is_reply(refused))
	check("and did not classify as an event", Protocol.succeeded(refused) == false)

	# Queueing before the handshake is not optional — the server would eat an
	# early frame as the auth frame. Driven here by lapsing the session, which
	# is the other state that must not write.
	tokens.write("access-2", Time.get_ticks_msec() + 60_000)
	_peer.send_text('{"type":"chat.send","requestId":"req-3","success":false,"error":"unauthorized"}')
	_peer.send_text('{"type":"auth.expired","requestId":"","success":false}')
	_pump(200)
	check("a lapsed session re-authenticates on the same socket", _session.state == Session.State.EXPIRED)

	var reauth := _server_received()
	check(
		"the re-auth reads the handoff store instead of a captured token",
		reauth.get("type") == "auth" and reauth.get("payload") == "access-2",
	)

	_session.close()
	_pump(200)
	check("close reaches the closed state", _session.state == Session.State.CLOSED)
	check(
		"the caller's own close is a transport close",
		_session.close_kind == Protocol.CloseKind.TRANSPORT,
	)

	# A close says what it means for the credential (haiven-api websocket.md,
	# Game sockets): a refused or revoked credential needs a new sign-in, a
	# dropped connection keeps it, and no 1008 is worth reconnecting into.
	var cases := [
		[1008, "unauthorized", Protocol.CloseKind.CREDENTIAL_REFUSED],
		[1008, "credential_revoked", Protocol.CloseKind.CREDENTIAL_REVOKED],
		[1008, "parental_consent_denied", Protocol.CloseKind.POLICY],
		[1000, "", Protocol.CloseKind.TRANSPORT],
		[1006, "", Protocol.CloseKind.TRANSPORT],
		[1000, "credential_revoked", Protocol.CloseKind.TRANSPORT],
	]
	var classified := true
	for case in cases:
		var kind: int = Protocol.classify_close(case[0], case[1])
		classified = classified and kind == case[2]
		classified = (
			classified
			and Protocol.close_may_reconnect(kind) == (kind == Protocol.CloseKind.TRANSPORT)
		)
	check("a close classifies by its code and reason alone", classified)
	check(
		"only a refused or revoked credential requires a new sign-in",
		Protocol.close_requires_sign_in(Protocol.CloseKind.CREDENTIAL_REFUSED)
		and Protocol.close_requires_sign_in(Protocol.CloseKind.CREDENTIAL_REVOKED)
		and not Protocol.close_requires_sign_in(Protocol.CloseKind.POLICY)
		and not Protocol.close_requires_sign_in(Protocol.CloseKind.TRANSPORT),
	)

	_report()


func _report() -> void:
	if failures.is_empty():
		print("ok   GDScript session over WebSocketPeer")
		print("HAIVEN_TEST_PASS session %d" % checks)
		quit(0)
		return

	for failure in failures:
		print("FAIL ", failure)
	quit(1)
