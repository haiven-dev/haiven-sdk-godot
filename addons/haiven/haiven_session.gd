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

## The server refused the re-auth credential (`auth.failure` on a live socket),
## with its code. Not a lapse: the session stops re-authenticating, and the game
## has to sign the player in again.
signal authentication_failed(code: String)

## A frame this SDK refused to decode, with a finite SDK-local code and a
## message. Today the only code is [constant HaivenProtocol.INTEGER_PRECISION_EXCEEDED]:
## the frame carried an integer beyond 2^53 - 1, which `JSON.parse_string`
## would have rounded. The frame is dropped -- no other signal sees it -- and
## the session stays open.
signal decode_error(code: String, message: String)

## The socket closed, with the code and reason the server gave.
signal closed(code: int, reason: String)

enum State { PENDING, AUTHENTICATED, EXPIRED, CLOSED }

var state: State = State.PENDING

## What the close means for the credential, a [enum HaivenProtocol.CloseKind],
## once the session is closed; -1 before. Set before [signal closed] is emitted.
var close_kind: int = -1

# A WebSocketPeer, or any object with the polling methods this class calls on
# it -- the client conformance runner drives the session through a scripted one.
var _socket: Object
var _token: Callable
var _next_id: Callable
var _counter := 0

# FORCED, exactly as in the other bindings. The socket is writable before it is
# usable: the server reads one frame from a new connection and requires it to be
# `auth`, so anything a caller sends in that window would be consumed as the
# handshake. Every binding pays for this queue.
var _pending: Array[Dictionary] = []

# Requests the server refused or dropped, held for resend after re-auth.
var _awaiting_resend: Array[Dictionary] = []

# Written and not yet answered, oldest first. Only what the server names as
# refused or dropped is resent from here: a request it accepted before a lapse
# has its reply parked and replayed, so a blind resend duplicates it.
var _in_flight: Array[Dictionary] = []

var _opened := false


## `token` is a Callable returning the current access token, or an object with a
## `read()` method such as [HaivenTokenStore].
##
## A Callable rather than a String, for the same reason the assembled TypeScript
## client reads through a token store: a token refreshed on the REST side after
## this session was constructed must reach the next handshake, and a captured
## copy cannot.
func _init(socket: Object, token: Variant, next_id: Callable = Callable()) -> void:
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

	var ready: int = _socket.get_ready_state()

	if ready == WebSocketPeer.STATE_OPEN and not _opened:
		_opened = true
		_authenticate()

	while _socket.get_available_packet_count() > 0:
		_receive(_socket.get_packet().get_string_from_utf8())

	if ready == WebSocketPeer.STATE_CLOSED:
		var was := state
		state = State.CLOSED
		_pending.clear()
		_awaiting_resend.clear()
		_in_flight.clear()
		if was != State.CLOSED:
			var code: int = _socket.get_close_code()
			var reason: String = _socket.get_close_reason()
			close_kind = Protocol.classify_close(code, reason)
			closed.emit(code, reason)
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
	if frame.get("type") != Protocol.AUTH:
		_in_flight.append(frame)
	_socket.send_text(JSON.stringify(frame))


# Removes and returns the unanswered request with this id, or an empty Dictionary.
func _take_in_flight(request_id: String) -> Dictionary:
	for index in _in_flight.size():
		if _in_flight[index].get("requestId") == request_id:
			var frame := _in_flight[index]
			_in_flight.remove_at(index)
			return frame
	return {}


# Sends recovered requests now if the session is usable, else after the next auth.success.
func _requeue(frames: Array[Dictionary]) -> void:
	for frame in frames:
		if state == State.AUTHENTICATED:
			_write(frame)
		else:
			_awaiting_resend.append(frame)


func _handle_expired(frame: Dictionary) -> void:
	# A correlated notice names the one request the lapse refused.
	var request_id: String = str(frame.get("requestId", ""))
	if request_id != "":
		var refused := _take_in_flight(request_id)
		if not refused.is_empty():
			_awaiting_resend.append(refused)
	# Re-auth on the SAME socket, once per episode. The server never asked for a
	# reconnect, and a binding that reconnects here pays for a new handshake and
	# loses the receive window for nothing.
	if state == State.EXPIRED:
		return
	state = State.EXPIRED
	expired.emit()
	_authenticate()


# The overflow half of an expiry. It arrives after the auth.success that ended
# the episode, so what it names goes out at once rather than waiting.
func _handle_dropped(frame: Dictionary) -> void:
	var report: Variant = frame.get("payload")
	if typeof(report) != TYPE_DICTIONARY:
		return
	var named: Array[Dictionary] = []
	for id in report.get("requestIds", []):
		var dropped := _take_in_flight(str(id))
		if not dropped.is_empty():
			named.append(dropped)
	# A truncated list is a sample: every request still unanswered is suspect.
	# Read before resending, because a resend is in flight again.
	var suspect: Array[Dictionary] = []
	if report.get("truncated") == true:
		suspect = _in_flight.duplicate()
		_in_flight.clear()
	_requeue(named)
	_requeue(suspect)


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

	# The parse above has already rounded any integer beyond 2^53 - 1, so the
	# check reads the raw text. Before frame_received: a rounded frame is
	# announced nowhere, not even raw.
	var unsafe := Protocol.find_unsafe_integer(text)
	if unsafe != "":
		decode_error.emit(
			Protocol.INTEGER_PRECISION_EXCEEDED,
			"integer %s exceeds 2^53 - 1 and cannot be decoded without rounding" % unsafe,
		)
		return

	# Raw first, and unconditionally. Emitting after the interpretation below
	# would put the early returns between a frame and its own announcement.
	frame_received.emit(frame)

	var type: String = frame.get("type", "")

	if type == Protocol.AUTH_SUCCESS:
		# A replayed handshake reply on an authenticated session changes nothing.
		if state == State.AUTHENTICATED:
			return
		state = State.AUTHENTICATED
		authenticated.emit()
		_flush()
		return

	if type == Protocol.AUTH_EXPIRED:
		_handle_expired(frame)
		return

	if type == Protocol.AUTH_FAILURE:
		# Stay expired and stop: a further auth.expired starts no re-auth.
		state = State.EXPIRED
		authentication_failed.emit(str(frame.get("error", "")))
		return

	if type == Protocol.AUTH_EXPIRED_DROPPED:
		_handle_dropped(frame)
		return

	# The one classification, through the one function that asks has().
	if Protocol.is_reply(frame):
		var answered: String = str(frame.get("requestId", ""))
		if answered != "":
			_take_in_flight(answered)
		reply_received.emit(frame)
	else:
		event_received.emit(frame)
