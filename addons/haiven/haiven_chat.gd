# Headless chat over HaivenSession: the GDScript counterpart of the .NET core's
# HaivenChat and the C++ core's FChatCore.
#
# A session is one socket, so this outlives sessions: attach each session the
# game opens, including after a reconnect. Every send carries a client message
# id; a send unanswered when its socket closes becomes UNCONFIRMED, and the next
# attach resends it under the same id, which the server deduplicates. Nothing
# here fails on a network error: a send without a usable session is kept and
# resent on attach, so a chat failure never interrupts gameplay.
#
#     var chat := HaivenChat.new()
#     chat.outgoing_changed.connect(_on_outgoing_changed)
#     chat.message_received.connect(_on_message)
#     chat.attach(session)
#     chat.send(channel_id, "gg")
class_name HaivenChat
extends RefCounted

# Preloaded by path, not the `HaivenSession` global; see haiven_session.gd.
const Session := preload("haiven_session.gd")

const CHAT_SEND := "chat.send"
const CHAT_TYPING := "chat.typing"
const CHAT_MESSAGE := "chat.message"
const CHAT_MESSAGE_UPDATED := "chat.message.updated"
const CHAT_MESSAGE_DELETED := "chat.message.deleted"

## Where a message this player sent stands.
enum OutgoingState {
	## Written, or queued until the session authenticates; no reply yet.
	SENDING,
	## The socket closed before the reply, or no session was attached. The next
	## attach resends it.
	UNCONFIRMED,
	## Accepted and visible to the channel (`allowed` or `warned`).
	ACCEPTED,
	## Accepted but held for moderation (`pending`, `review_pending`, or a state
	## minted after this build).
	HELD,
	## Accepted but not shown (`hidden` or `blocked`).
	REMOVED,
	## Refused with an error code; resending the same message cannot succeed.
	REFUSED,
}


## One message this player sent, tracked by its client message id.
class OutgoingMessage:
	extends RefCounted
	## The deduplication key: a resend under it is the same message to the server.
	var client_message_id: String
	var channel_id: String
	var content: String
	## "" for a top-level message.
	var parent_message_id: String
	var state: OutgoingState = OutgoingState.SENDING
	## Set from an accepted reply.
	var message_id: String = ""
	## The raw moderation state from an accepted reply.
	var moderation_state: String = ""
	## The error code from a refusal.
	var error: String = ""

	func _init(id: String, channel: String, text: String, parent: String) -> void:
		client_message_id = id
		channel_id = channel
		content = text
		parent_message_id = parent


## An outgoing message changed state.
signal outgoing_changed(message: OutgoingMessage)

## `chat.message`: a message reached a channel this player is in. Includes the
## echo of this player's own sends; [method find] tells those apart.
signal message_received(message: Dictionary)

## `chat.message.updated`: a message was edited.
signal message_updated(message: Dictionary)

## `chat.message.deleted`: a message was deleted.
signal message_deleted(message: Dictionary)

## `chat.typing`: someone is typing.
signal typing(payload: Dictionary)

var _new_client_message_id: Callable
var _outbox: Array[OutgoingMessage] = []
# The request each in-flight send went out under, on the attached session.
var _by_request: Dictionary = {}
var _session: RefCounted


## `new_client_message_id` returns a fresh id per send; the default is random.
func _init(new_client_message_id: Callable = Callable()) -> void:
	_new_client_message_id = (
		new_client_message_id if new_client_message_id.is_valid() else _random_client_message_id
	)


static func _random_client_message_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


## Messages this player sent, oldest first, until [method forget].
func outbox() -> Array[OutgoingMessage]:
	return _outbox.duplicate()


## The tracked message with this client message id, or null.
func find(client_message_id: String) -> OutgoingMessage:
	for message in _outbox:
		if message.client_message_id == client_message_id:
			return message
	return null


## Uses this session from now on, and resends every unconfirmed message through
## it. Attach each new session after a reconnect.
func attach(session: RefCounted) -> void:
	detach()
	_session = session
	session.reply_received.connect(_on_reply)
	session.event_received.connect(_on_event)
	session.closed.connect(_on_closed)
	if not _usable():
		return
	for message in _outbox:
		if message.state == OutgoingState.UNCONFIRMED:
			_write(message)


## Stops listening to the attached session. Unanswered sends stay SENDING until
## the next attach replaces them; call this only when discarding the chat.
func detach() -> void:
	if _session == null:
		return
	_session.reply_received.disconnect(_on_reply)
	_session.event_received.disconnect(_on_event)
	_session.closed.disconnect(_on_closed)
	_session = null
	_by_request.clear()


## Sends a message, or keeps it to send on the next attach.
func send(channel_id: String, content: String, parent_message_id: String = "") -> OutgoingMessage:
	assert(channel_id != "", "haiven: channel_id is required")
	var message := OutgoingMessage.new(_new_client_message_id.call(), channel_id, content, parent_message_id)
	_outbox.append(message)
	if _usable():
		_write(message)
	else:
		_change(message, OutgoingState.UNCONFIRMED)
	return message


## Sends `chat.typing`. Typing is best effort and is never resent.
func send_typing(channel_id: String) -> void:
	if _usable():
		_session.send(CHAT_TYPING, {"channelId": channel_id})


## Stops tracking a message, normally one in a final state.
func forget(message: OutgoingMessage) -> void:
	_outbox.erase(message)
	for request_id: String in _by_request.keys():
		if _by_request[request_id] == message:
			_by_request.erase(request_id)


## A moderation state minted after this build reads as held, never as visible.
static func state_for(moderation_state: String) -> OutgoingState:
	match moderation_state:
		"allowed", "warned":
			return OutgoingState.ACCEPTED
		"hidden", "blocked":
			return OutgoingState.REMOVED
		_:
			# pending, review_pending, and any later state: the message exists
			# but is not known to be visible.
			return OutgoingState.HELD


func _usable() -> bool:
	return _session != null and _session.state != Session.State.CLOSED


func _write(message: OutgoingMessage) -> void:
	var payload := {
		"channelId": message.channel_id,
		"clientMessageId": message.client_message_id,
		"content": message.content,
	}
	if message.parent_message_id != "":
		payload["parentMessageId"] = message.parent_message_id
	var frame: Dictionary = _session.send(CHAT_SEND, payload)
	_by_request[str(frame.get("requestId", ""))] = message
	_change(message, OutgoingState.SENDING)


func _on_reply(frame: Dictionary) -> void:
	var request_id := str(frame.get("requestId", ""))
	if not _by_request.has(request_id):
		return
	var message: OutgoingMessage = _by_request[request_id]
	_by_request.erase(request_id)
	# Exactly true, not truthiness: a refusal carries success: false.
	if frame.get("success") != true:
		message.error = str(frame.get("error", ""))
		_change(message, OutgoingState.REFUSED)
		return
	var submission: Variant = frame.get("payload")
	if submission is Dictionary:
		var sent: Variant = submission.get("message")
		if sent is Dictionary:
			message.message_id = str(sent.get("id", ""))
		message.moderation_state = str(submission.get("moderationState", ""))
	_change(message, state_for(message.moderation_state))


func _on_event(frame: Dictionary) -> void:
	var payload: Variant = frame.get("payload")
	if not payload is Dictionary:
		return
	match frame.get("type", ""):
		CHAT_MESSAGE:
			message_received.emit(payload)
		CHAT_MESSAGE_UPDATED:
			message_updated.emit(payload)
		CHAT_MESSAGE_DELETED:
			message_deleted.emit(payload)
		CHAT_TYPING:
			typing.emit(payload)


func _on_closed(_code: int, _reason: String) -> void:
	# Unanswered sends may or may not have landed; the next attach resends them
	# under the same client message id, which the server deduplicates.
	var unanswered: Array = _by_request.values()
	_by_request.clear()
	for message: OutgoingMessage in unanswered:
		_change(message, OutgoingState.UNCONFIRMED)


func _change(message: OutgoingMessage, state: OutgoingState) -> void:
	message.state = state
	outgoing_changed.emit(message)
