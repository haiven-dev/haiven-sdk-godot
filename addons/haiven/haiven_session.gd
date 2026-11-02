# The session, over Godot's own WebSocketPeer.
#
# There is no socket abstraction here and that is the point of difference from
# the other two bindings. `WebSocketPeer` is engine-native and takes no
# injection, so this cannot share the `SocketLike` / `IHaivenSocket` seam that
# TypeScript and C# needed — and it does not need one, because Godot's socket
# already works on every target Godot ships to, which is exactly what that seam
# was buying elsewhere.
#
# What Godot does force instead is POLLING. `WebSocketPeer` has no signals of its
# own: nothing arrives unless someone calls `poll()`, so a session has to be
# driven from a frame callback. That is the shape of this class — signals out,
# a `poll()` in — and it is why an addon cannot simply be constructed and left
# alone the way the TypeScript session can.
class_name HaivenSession
extends RefCounted

# Preloaded by path rather than used as the global `HaivenProtocol` the sibling
# file declares. A `class_name` is registered from the editor's import cache, so
# a global reference makes the addon depend on having been imported — which is
# true for a consumer and false for a headless script run, and the failure is a
# parse error rather than anything that names the cause.
const Protocol := preload("haiven_protocol.gd")

## Every inbound frame, before the session interprets any of it.
##
## This exists because the classified arms below are NOT exhaustive, and that is
## easy to miss. `auth.success` and `auth.expired` are consumed into
## [signal authenticated] and [signal expired], so a listener connected only to
## [signal reply_received] and [signal event_received] never sees them — which is
## correct for a game and wrong for anything that has to observe the protocol
## rather than use it. A conformance runner asserting on `auth.success` connects
## here; measured in `session_test.gd`, where connecting only the classified arms
## made the handshake reply invisible.
signal frame_received(frame: Dictionary)

## A frame arrived that answers one this client sent.
signal reply_received(frame: Dictionary)

## A frame arrived that this client did not ask for.
signal event_received(frame: Dictionary)

## The handshake completed and the session is usable.
signal authenticated()

## The server lapsed the session. Re-auth has already been sent.
signal expired()

## The socket closed, with the code and reason the server gave.
signal closed(code: int, reason: String)

enum State { PENDING, AUTHENTICATED, EXPIRED, CLOSED }

var state: State = State.PENDING

var _socket: WebSocketPeer
var _token: Callable
var _next_id: Callable
var _counter := 0

# FORCED, exactly as in the other bindings. The socket is writable before it is
# usable: the server reads one frame from a new connection and requires it to be
# `auth`, so anything a caller sends in that window would be consumed as the
# handshake. Every binding pays for this queue.
var _pending: Array[Dictionary] = []

# Requests the server accepted and then discarded, held for resend after re-auth.
var _awaiting_resend: Array[Dictionary] = []

var _opened := false


## `token` is a Callable returning the current access token, or an object with a
## `read()` method such as [HaivenTokenStore].
##
## A Callable rather than a String, for the same reason the assembled TypeScript
## client reads through a token store: a token refreshed on the REST side after
## this session was constructed must reach the next handshake, and a captured
## copy cannot.
func _init(socket: WebSocketPeer, token: Variant, next_id: Callable = Callable()) -> void:
	_socket = socket
	_token = token if token is Callable else Callable(token, "read")
	_next_id = next_id if next_id.is_valid() else _default_id


func _default_id() -> String:
	_counter += 1
	return "req-%d" % _counter


## Drives the socket. Call this every frame; nothing arrives without it.
##
## Returns false once the session is closed, so a caller can stop polling
## without having to read [member state].
func poll() -> bool:
	if state == State.CLOSED:
		return false

	_socket.poll()

	var ready := _socket.get_ready_state()

	if ready == WebSocketPeer.STATE_OPEN and not _opened:
		_opened = true
		_authenticate()

	while _socket.get_available_packet_count() > 0:
		_receive(_socket.get_packet().get_string_from_utf8())

	if ready == WebSocketPeer.STATE_CLOSED:
		var was := state
		state = State.CLOSED
		if was != State.CLOSED:
			closed.emit(_socket.get_close_code(), _socket.get_close_reason())
		return false

	return true


## Sends a frame, queueing it if the session is not usable yet. Returns the frame sent.
func send(type: String, payload: Variant = null) -> Dictionary:
	var frame := Protocol.frame(type, _next_id.call(), payload)

	if state == State.AUTHENTICATED:
		_write(frame)
	elif state == State.CLOSED:
		push_error("haiven: send on a closed session")
	else:
		# PENDING or EXPIRED: the server would either eat this as the handshake
		# or refuse and discard it.
		_pending.append(frame)

	return frame


## Closes the socket deliberately.
func close(code: int = 1000, reason: String = "") -> void:
	if state == State.CLOSED:
		return
	_socket.close(code, reason)


func _authenticate() -> void:
	_write(Protocol.frame(Protocol.AUTH, _next_id.call(), _token.call()))


func _write(frame: Dictionary) -> void:
	_socket.send_text(JSON.stringify(frame))


func _flush() -> void:
	var queued := _awaiting_resend + _pending
	_awaiting_resend.clear()
	_pending.clear()
	for frame in queued:
		_write(frame)


func _receive(text: String) -> void:
	var frame := Protocol.parse(text)
	if frame.is_empty():
		return

	# Raw first, and unconditionally. Emitting after the interpretation below
	# would put the early returns between a frame and its own announcement.
	frame_received.emit(frame)

	var type: String = frame.get("type", "")

	if type == Protocol.AUTH_SUCCESS:
		state = State.AUTHENTICATED
		authenticated.emit()
		_flush()
		return

	if type == Protocol.AUTH_EXPIRED:
		# Re-auth on the SAME socket. The server never asked for a reconnect, and
		# a binding that reconnects here pays for a new handshake and loses the
		# receive window for nothing.
		if state != State.EXPIRED:
			state = State.EXPIRED
			expired.emit()
			_authenticate()
		return

	# The one classification, through the one function that asks has().
	if Protocol.is_reply(frame):
		reply_received.emit(frame)
	else:
		event_received.emit(frame)
