# Headless coverage for the generated WebSocket surface. The send Callable
# records frames the way HaivenSession.send returns them, so this measures the
# generated half alone: the wire type and payload each request hands the session,
# and that the router delivers events -- the OAuth identity-link pair included --
# while leaving replies and unknown types on the host's unhandled-frame path.
extends SceneTree

const WsApi := preload("res://addons/haiven/haiven_ws_api.gd")

var failures: Array[String] = []
var checks := 0
var _sent: Array[Dictionary] = []


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)


func _initialize() -> void:
	call_deferred("_run")


func _send(type: String, payload: Variant) -> Dictionary:
	var frame := {"type": type, "requestId": "rq-%d" % (_sent.size() + 1)}
	if payload != null:
		frame["payload"] = payload
	_sent.append(frame)
	return frame


func _run() -> void:
	var api := WsApi.new(_send)

	var message := {"channelId": "c1", "content": "hi"}
	var frame: Dictionary = api.chat_send(message)
	check("a request goes out under its wire type", _sent[-1].get("type") == "chat.send")
	check("with its payload unchanged", _sent[-1].get("payload") == message)
	check("returning the queued frame", frame.get("requestId") == "rq-1")

	api.transport_ping()
	check("ping goes out as ping without a payload", _sent[-1].get("type") == "ping" and not _sent[-1].has("payload"))
	check("and expects pong", WsApi.REQUESTS["ping"]["reply_type"] == WsApi.PONG)
	check("the OAuth link event names its contract",
		WsApi.EVENT_PAYLOADS.get("account.identity.linked") == "AccountIdentityLinkedV0")

	var linked: Array = []
	var on_linked := func(payload: Variant, _frame: Dictionary) -> void: linked.append(payload)
	api.on_account_identity_linked(on_linked)
	var identity := {"provider": "google", "email": "player@example.test"}
	check("an identity-link event is handled",
		api.dispatch({"type": "account.identity.linked", "payload": identity}))
	check("by its handler, with the payload", linked == [identity])
	var versions: Array = []
	api.on_entitlements_updated(func(payload: Variant, _frame: Dictionary) -> void: versions.append(payload))
	check("the entitlement refresh hint is handled",
		api.dispatch({"type": WsApi.ENTITLEMENTS_UPDATED, "payload": {"projectionVersion": 5}}))
	check("with the new projection version", versions == [{"projectionVersion": 5}])
	var motds: Array = []
	api.on_motd(func(payload: Variant, _frame: Dictionary) -> void: motds.append(payload))
	check("the Message of the Day is handled",
		api.dispatch({"type": WsApi.MOTD, "payload": {"id": "m1", "body": "New rewards are live."}}))
	check("with its body", motds.size() == 1 and motds[0].get("body") == "New rewards are live.")
	check("a reply is never routed as an event",
		not api.dispatch({"type": "account.identity.linked", "requestId": "", "success": true}))
	check("an event minted after this build stays unhandled",
		not api.dispatch({"type": "entitlements.minted.later", "payload": {}}))
	api.off_event("account.identity.linked", on_linked)
	check("and so does one whose handler unsubscribed",
		not api.dispatch({"type": "account.identity.linked", "payload": identity}))

	_report()


func _report() -> void:
	if failures.is_empty():
		print("ok   GDScript generated WebSocket surface")
		print("HAIVEN_TEST_PASS ws %d" % checks)
		quit(0)
		return
	for failure in failures:
		print("FAIL ", failure)
	quit(1)
