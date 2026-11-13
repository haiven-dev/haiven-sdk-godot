# Headless coverage of HaivenChat over a scripted socket: sends tracked by
# client message id, moderation states mapped to outcomes, refusals, the close
# that leaves sends unconfirmed, and the resend under the same id on the next
# session. The same cases as sdks/cpp/test/chat_test.cpp and the .NET tests.
extends SceneTree

const Session := preload("res://addons/haiven/haiven_session.gd")
const Chat := preload("res://addons/haiven/haiven_chat.gd")


class FakeSocket:
	extends RefCounted
	var sent: Array[Dictionary] = []
	var _inbox: Array[String] = []
	var _state := WebSocketPeer.STATE_OPEN

	func poll() -> void:
		pass

	func get_ready_state() -> int:
		return _state

	func get_available_packet_count() -> int:
		return _inbox.size()

	func get_packet() -> PackedByteArray:
		return _inbox.pop_front().to_utf8_buffer()

	func send_text(text: String) -> int:
		sent.append(JSON.parse_string(text))
		return OK

	func close(_code: int = 1000, _reason: String = "") -> void:
		_state = WebSocketPeer.STATE_CLOSED

	func get_close_code() -> int:
		return 1006

	func get_close_reason() -> String:
		return ""

	func deliver(frame: Dictionary) -> void:
		_inbox.append(JSON.stringify(frame))

	func sends() -> Array[Dictionary]:
		return sent.filter(func(frame: Dictionary) -> bool: return frame.get("type") == "chat.send")


var failures: Array[String] = []
var checks := 0
var changes: Array[String] = []
var received: Array[Dictionary] = []
var _ids := 0


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)


func next_id() -> String:
	_ids += 1
	return "cm-%d" % _ids


## A session over `socket`, polled through its handshake.
func open(socket: FakeSocket) -> RefCounted:
	var session: RefCounted = Session.new(socket, func() -> String: return "token")
	session.poll()
	socket.deliver({"type": "auth.success", "requestId": socket.sent[0]["requestId"], "success": true})
	session.poll()
	return session


func reply(socket: FakeSocket, session: RefCounted, send: Dictionary, moderation_state: String) -> void:
	socket.deliver({"type": "chat.send", "requestId": send["requestId"], "success": true,
		"payload": {"message": {"id": "m-" + send["payload"]["clientMessageId"]}, "moderationState": moderation_state}})
	session.poll()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	check("allowed and warned are accepted",
		Chat.state_for("allowed") == Chat.OutgoingState.ACCEPTED
		and Chat.state_for("warned") == Chat.OutgoingState.ACCEPTED)
	check("hidden and blocked are removed",
		Chat.state_for("hidden") == Chat.OutgoingState.REMOVED
		and Chat.state_for("blocked") == Chat.OutgoingState.REMOVED)
	check("pending and unknown states are held",
		Chat.state_for("pending") == Chat.OutgoingState.HELD
		and Chat.state_for("something_new") == Chat.OutgoingState.HELD)

	var chat: RefCounted = Chat.new(next_id)
	chat.outgoing_changed.connect(func(message: RefCounted) -> void:
		changes.append("%s:%s" % [message.client_message_id, Chat.OutgoingState.keys()[message.state]]))
	chat.message_received.connect(func(message: Dictionary) -> void: received.append(message))

	var offline: RefCounted = chat.send("general", "early")
	check("a send with no session is kept unconfirmed", offline.state == Chat.OutgoingState.UNCONFIRMED)

	var socket := FakeSocket.new()
	var session := open(socket)
	chat.attach(session)
	var first := socket.sends()
	check("attaching resends the unconfirmed message under its id",
		first.size() == 1 and first[0]["payload"]["clientMessageId"] == "cm-1"
		and offline.state == Chat.OutgoingState.SENDING)

	var held: RefCounted = chat.send("general", "gg", "m-parent")
	var held_frame: Dictionary = socket.sends()[1]
	check("a send carries channel, content, client id and parent",
		held_frame["payload"] == {"channelId": "general", "content": "gg", "clientMessageId": "cm-2",
			"parentMessageId": "m-parent"})
	reply(socket, session, first[0], "allowed")
	reply(socket, session, held_frame, "review_pending")
	check("an allowed reply is accepted with its message id",
		offline.state == Chat.OutgoingState.ACCEPTED and offline.message_id == "m-cm-1"
		and offline.moderation_state == "allowed")
	check("a review_pending reply is held", held.state == Chat.OutgoingState.HELD)

	var refused: RefCounted = chat.send("general", "bad")
	socket.deliver({"type": "chat.send", "requestId": socket.sends()[2]["requestId"], "success": false,
		"error": "content_too_long"})
	session.poll()
	check("a refusal keeps its error code",
		refused.state == Chat.OutgoingState.REFUSED and refused.error == "content_too_long")

	socket.deliver({"type": "chat.message", "payload": {"id": "m-9", "channelId": "general", "content": "hi"}})
	socket.deliver({"type": "presence.updated", "payload": {"userId": "u-2"}})
	session.poll()
	check("chat.message is surfaced, other events are not", received.size() == 1 and received[0]["id"] == "m-9")
	check("find tells an own echo apart",
		chat.find("cm-2") == held and chat.find("someone-else") == null)

	var lost: RefCounted = chat.send("general", "lost")
	socket.close()
	session.poll()
	check("a send unanswered at close is unconfirmed", lost.state == Chat.OutgoingState.UNCONFIRMED)
	check("answered sends keep their outcome", offline.state == Chat.OutgoingState.ACCEPTED)

	var after_close: RefCounted = chat.send("general", "while offline")
	check("a send on a closed session is kept, not written",
		after_close.state == Chat.OutgoingState.UNCONFIRMED and socket.sends().size() == 4)

	var next_socket := FakeSocket.new()
	var next_session := open(next_socket)
	chat.attach(next_session)
	var resent := next_socket.sends().map(func(frame: Dictionary) -> String: return frame["payload"]["clientMessageId"])
	check("the next session resends every unconfirmed message, oldest first, under the same ids",
		resent == ["cm-4", "cm-5"])
	reply(next_socket, next_session, next_socket.sends()[0], "quarantined")
	check("an unknown moderation state reads as held", lost.state == Chat.OutgoingState.HELD)

	chat.forget(refused)
	check("forget stops tracking a message", chat.outbox().size() == 4 and chat.find("cm-3") == null)
	check("every state change was signalled", changes.has("cm-1:UNCONFIRMED") and changes.has("cm-4:HELD"))

	chat.detach()
	next_socket.deliver({"type": "chat.message", "payload": {"id": "m-10", "channelId": "general", "content": "x"}})
	next_session.poll()
	check("a detached chat hears nothing", received.size() == 1)

	if failures.is_empty():
		print("ok   GDScript chat")
		print("HAIVEN_TEST_PASS chat %d" % checks)
		quit(0)
		return
	for failure in failures:
		print("FAIL ", failure)
	quit(1)

