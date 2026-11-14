# Adversarial headless coverage for identity/MOTD state and the browser-owned
# link seam. Generated REST and WebSocket APIs remain in the path under test.
extends SceneTree

const Identity := preload("res://addons/haiven/haiven_identity.gd")
const RestApi := preload("res://addons/haiven/haiven_rest_api.gd")
const RestError := preload("res://addons/haiven/haiven_rest_error.gd")
const WsApi := preload("res://addons/haiven/haiven_ws_api.gd")

const MOTD_1 := "00000000-0000-4000-8000-000000000001"
const MOTD_2 := "00000000-0000-4000-8000-000000000002"
const MOTD_3 := "00000000-0000-4000-8000-000000000003"


class FakeTransport:
	extends RefCounted
	var responses: Array[Variant] = []
	var sent: Array[Dictionary] = []
	var before_reply: Callable

	func next(response: Variant, callback: Callable = Callable()) -> void:
		responses.append(response)
		before_reply = callback

	func request(method: String, path: String, body: Variant, content_type: String) -> Variant:
		sent.append({"method": method, "path": path, "body": _copy(body), "content_type": content_type})
		if before_reply.is_valid():
			var callback := before_reply
			before_reply = Callable()
			callback.call()
		return responses.pop_front()

	func _copy(value: Variant) -> Variant:
		return value.duplicate(true) if value is Dictionary or value is Array else value


class BrowserLinkAdapter:
	extends RefCounted
	var response: Variant = {"ok": true}
	var before_return: Callable
	var providers: Array[String] = []
	var steps: Array[String] = []

	func begin_link(provider: String) -> Variant:
		providers.append(provider)
		# This fake makes the adapter contract observable: popup first, POST with
		# that browser context/cookie jar, then redirect the same popup.
		steps.append("popup")
		steps.append("same_browser_post")
		steps.append("same_popup_redirect")
		if before_return.is_valid():
			var callback := before_return
			before_return = Callable()
			callback.call()
		return response


class RetainingWs:
	extends RefCounted
	var handlers := {
		"account.identity.linked": [],
		"account.identity.link.failed": [],
		"motd": [],
	}
	var retained := {
		"account.identity.linked": [],
		"account.identity.link.failed": [],
		"motd": [],
	}
	var invoke_during_subscribe := false

	func on_account_identity_linked(handler: Callable) -> void:
		_add("account.identity.linked", handler)

	func on_account_identity_link_failed(handler: Callable) -> void:
		_add("account.identity.link.failed", handler)

	func on_motd(handler: Callable) -> void:
		_add("motd", handler)

	func off_event(type: String, handler: Callable) -> void:
		handlers[type].erase(handler)

	func emit(type: String, payload: Variant) -> void:
		for handler: Callable in handlers[type].duplicate():
			handler.call(payload, {"type": type, "payload": payload})

	func emit_retired(type: String, index: int, payload: Variant) -> void:
		retained[type][index].call(payload, {"type": type, "payload": payload})

	func clear_all() -> void:
		for event_type: String in handlers:
			handlers[event_type].clear()
			retained[event_type].clear()

	func _add(type: String, handler: Callable) -> void:
		handlers[type].append(handler)
		retained[type].append(handler)
		if invoke_during_subscribe:
			var payload: Dictionary = (
				{"provider": "apple", "email": "subscribe@example.test"}
				if type == "account.identity.linked"
				else {"provider": "apple", "code": "popup_closed"}
				if type == "account.identity.link.failed"
				else {
					"id": "00000000-0000-4000-8000-000000000002",
					"body": "subscribe",
					"startsAt": "2026-10-14T00:00:00Z",
				}
			)
			handler.call(payload, {"type": type, "payload": payload})


class InvalidWs:
	extends RefCounted


var failures: Array[String] = []
var checks := 0


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)


func motd(identity: String = MOTD_1, body: String = "New rewards are live.") -> Dictionary:
	return {
		"id": identity,
		"title": "Update",
		"body": body,
		"url": "https://news.haiven.gg/update",
		"startsAt": "2026-10-14T00:00:00Z",
	}


func methods(provider: String = "google", email: String = "player@example.test") -> Dictionary:
	return {"hasPassword": true, "identities": [{"provider": provider, "email": email}]}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var transport := FakeTransport.new()
	var api := RestApi.new(transport.request)
	var ws := WsApi.new(func(_type: String, _payload: Variant) -> Dictionary: return {})
	var adapter := BrowserLinkAdapter.new()
	var identity := Identity.new(api, "partner game", ws, adapter)
	var motds: Array = []
	var method_snapshots: Array = []
	var linked: Array = []
	var link_failures: Array = []
	var diagnostics: Array = []
	identity.motd_changed.connect(func(value: Variant) -> void: motds.append(value))
	identity.sign_in_methods_changed.connect(func(value: Dictionary) -> void: method_snapshots.append(value))
	identity.identity_linked.connect(func(value: Dictionary) -> void: linked.append(value))
	identity.identity_link_failed.connect(func(value: Dictionary) -> void: link_failures.append(value))
	identity.diagnostic.connect(func(code: String, detail: Variant) -> void: diagnostics.append([code, detail]))

	# Strict MOTD reads and defensive state.
	var first_motd := motd()
	transport.next(first_motd)
	var loaded: Dictionary = await identity.load_motd()
	check("the public MOTD read succeeds", loaded.get("ok") and loaded["motd"] == first_motd)
	check("the MOTD read uses the integration query", transport.sent[-1]["path"] == "/motd?integration_id=partner%20game")
	check("a public MOTD updates the view model", motds == [first_motd])
	var exposed_motd: Dictionary = identity.current_motd
	exposed_motd["body"] = "caller mutation"
	check("the exposed MOTD is a defensive snapshot", identity.current_motd["body"] == first_motd["body"])

	transport.next(motd(MOTD_1.to_upper()))
	await identity.load_motd()
	check("UUID case normalizes onto the stable duplicate boundary", motds.size() == 1)
	identity.dismiss_motd()
	ws.dispatch({"type": WsApi.MOTD, "payload": motd()})
	check("a dismissed stable UUID stays dismissed", motds.size() == 2 and motds[-1] == null)

	transport.next(null)
	check("204 is an explicit successful no-MOTD result", await identity.load_motd() == {"ok": true, "motd": null})

	var malformed_motds := [
		{"id": "not-a-uuid", "body": "x", "startsAt": "2026-10-14T00:00:00Z"},
		{"id": MOTD_2, "body": "x", "startsAt": "2026-02-30T00:00:00Z"},
		{"id": MOTD_2, "body": "x", "startsAt": "2026-10-14 00:00:00Z"},
		{"id": MOTD_2, "body": "x", "startsAt": "2026-10-14T00:00:00Z", "url": "https://user@evil.test/x"},
		{"id": MOTD_2, "body": "x", "startsAt": "2026-10-14T00:00:00Z", "url": "https:///x"},
		{"id": MOTD_2, "body": "x", "startsAt": "2026-10-14T00:00:00Z", "url": "https://haiven.gg:70000/x"},
		{"id": MOTD_2, "body": "x", "startsAt": "2026-10-14T00:00:00Z", "url": "https://haiven.gg:/x"},
		{"id": MOTD_2, "body": "x", "startsAt": "2026-10-14T00:00:00Z", "url": "https://[::::]/x"},
		{"id": MOTD_2, "body": "x", "startsAt": "2026-10-14T00:00:00Z", "extra": true},
	]
	for invalid_motd: Dictionary in malformed_motds:
		transport.next(invalid_motd)
		var invalid_result: Dictionary = await identity.load_motd()
		check(
			"malformed UUID/date/HTTPS-host/shape fails closed: %s" % JSON.stringify(invalid_motd),
			invalid_result.get("error") == "invalid_motd_response",
		)

	# A realtime mutation supersedes an older REST request.
	transport.next(motd(MOTD_2, "old REST"), func() -> void:
		ws.dispatch({"type": WsApi.MOTD, "payload": motd(MOTD_3, "new realtime")})
	)
	var stale_motd: Dictionary = await identity.load_motd()
	check("realtime MOTD supersedes an older REST request", stale_motd.get("error") == "superseded")
	check("the newer realtime MOTD remains current", identity.current_motd["id"] == MOTD_3)

	# Signal callback reentrancy cannot turn an invalidated commit into success.
	var reentrant_transport := FakeTransport.new()
	var reentrant_identity := Identity.new(RestApi.new(reentrant_transport.request), "game")
	reentrant_identity.motd_changed.connect(
		func(_value: Variant) -> void: reentrant_identity.dismiss_motd(),
		Object.CONNECT_ONE_SHOT,
	)
	reentrant_transport.next(motd())
	var reentrant_motd: Dictionary = await reentrant_identity.load_motd()
	check("a reentrant MOTD callback supersedes the awaiting read", reentrant_motd.get("error") == "superseded")
	check("the reentrant dismissal wins", reentrant_identity.current_motd == null)

	# Strict sign-in-method reads and defensive state.
	transport.next(methods())
	var listed: Dictionary = await identity.load_sign_in_methods()
	check("sign-in methods use the generated operation", listed.get("ok") and transport.sent[-1]["path"] == "/users/me/sign-in-methods")
	var exposed_methods := identity.current_sign_in_methods
	exposed_methods["identities"][0]["email"] = "caller@example.test"
	check("the exposed methods are a defensive snapshot", identity.current_sign_in_methods["identities"][0]["email"] == "player@example.test")

	for invalid_methods: Dictionary in [
		{"hasPassword": true, "identities": [], "extra": true},
		{"hasPassword": true, "identities": [{"provider": "Google", "email": "p@example.test"}]},
		{"hasPassword": true, "identities": [{"provider": "google", "email": "p@example.test", "extra": true}]},
	]:
		transport.next(invalid_methods)
		check("malformed sign-in-method payload fails closed", (await identity.load_sign_in_methods()).get("error") == "invalid_sign_in_methods_response")

	# Link initiation is browser-context-owned and fails closed without an adapter.
	var no_adapter := Identity.new(api, "partner game", null, null)
	var requests_before := transport.sent.size()
	var missing_adapter: Dictionary = await no_adapter.begin_link("google")
	check("linking fails closed without the browser adapter", missing_adapter.get("error") == "browser_link_adapter_required")
	check("the facade never POSTs link initiation through game REST", transport.sent.size() == requests_before)

	var started: Dictionary = await identity.begin_link(" APPLE ")
	check("the adapter owns a successful provider link", started == {"ok": true, "provider": "apple"})
	check("popup precedes same-browser POST and same-popup redirect", adapter.steps == ["popup", "same_browser_post", "same_popup_redirect"])
	check("adapter linking still makes no game-transport request", transport.sent.size() == requests_before)

	adapter.response = {"ok": false, "error": "popup_blocked", "detail": {"recoverable": true}}
	var blocked: Dictionary = await identity.begin_link("google")
	check("a finite adapter refusal preserves its code", blocked.get("error") == "popup_blocked" and blocked["detail"] == {"recoverable": true})
	adapter.response = {"ok": true, "redirectUrl": "https://not-allowed.example"}
	check("an overbroad adapter success is rejected", (await identity.begin_link("google")).get("error") == "invalid_browser_link_response")

	var callback_adapter := BrowserLinkAdapter.new()
	var callback_identity := Identity.new(api, "game", null, callback_adapter)
	callback_adapter.before_return = callback_identity.clear_account
	check("account replacement during adapter completion invalidates it", (await callback_identity.begin_link("google")).get("error") == "session_changed")

	# Generated raw REST access still exists, but is tested as a raw operation.
	transport.next({"redirectUrl": "https://auth.example/authorize"})
	var raw_link: Variant = await api.post_users_me_sign_in_methods_sso_provider("google")
	check("the generated raw POST remains separately available", raw_link["redirectUrl"] == "https://auth.example/authorize" and transport.sent[-1]["path"] == "/users/me/sign-in-methods/sso/google")

	# Strict realtime payloads and REST-vs-event revision ordering.
	var linked_event := {"provider": "apple", "email": "apple@example.test"}
	check("the generated router delivers strict link completion", ws.dispatch({"type": WsApi.ACCOUNT_IDENTITY_LINKED, "payload": linked_event}))
	check("link completion reaches the high-level signal", linked == [linked_event])
	check("link completion updates a loaded snapshot", identity.current_sign_in_methods["identities"].size() == 2)

	ws.dispatch({"type": WsApi.ACCOUNT_IDENTITY_LINKED, "payload": {"provider": "apple", "email": "p@example.test", "extra": true}})
	ws.dispatch({"type": WsApi.ACCOUNT_IDENTITY_LINK_FAILED, "payload": {"provider": "google", "code": "Bad-Code"}})
	check("extra fields and malformed codes are diagnostic-only", linked.size() == 1 and link_failures.is_empty() and diagnostics.size() >= 2)

	var failed_event := {"provider": "google", "code": "identity_already_linked"}
	ws.dispatch({"type": WsApi.ACCOUNT_IDENTITY_LINK_FAILED, "payload": failed_event})
	check("a strict link failure preserves its finite code", link_failures == [failed_event])

	transport.next(methods("google", "old@example.test"), func() -> void:
		ws.dispatch({"type": WsApi.ACCOUNT_IDENTITY_LINKED, "payload": {"provider": "apple", "email": "new@example.test"}})
	)
	var stale_methods: Dictionary = await identity.load_sign_in_methods()
	check("a link event supersedes an older methods REST read", stale_methods.get("error") == "superseded")
	check("the link event remains in cached methods", identity.current_sign_in_methods["identities"].any(func(value: Dictionary) -> bool: return value["email"] == "new@example.test"))

	var empty_race_transport := FakeTransport.new()
	var empty_race_ws := WsApi.new(func(_type: String, _payload: Variant) -> Dictionary: return {})
	var empty_race_identity := Identity.new(
		RestApi.new(empty_race_transport.request), "game", empty_race_ws
	)
	empty_race_transport.next(methods(), func() -> void:
		empty_race_ws.dispatch({"type": WsApi.ACCOUNT_IDENTITY_LINKED, "payload": linked_event})
	)
	var empty_race: Dictionary = await empty_race_identity.load_sign_in_methods()
	check("a link event supersedes REST even before a cache exists", empty_race.get("error") == "superseded")
	check("the stale REST snapshot is not installed after that event", empty_race_identity.current_sign_in_methods.is_empty())

	transport.next(null, func() -> void:
		ws.dispatch({"type": WsApi.ACCOUNT_IDENTITY_LINKED, "payload": {"provider": "apple", "email": "relinked@example.test"}})
	)
	var stale_unlink: Dictionary = await identity.unlink("apple")
	check("a newer link event supersedes an unlink mutation", stale_unlink.get("error") == "superseded")
	check("the newer relink is not removed", identity.current_sign_in_methods["identities"].any(func(value: Dictionary) -> bool: return value["email"] == "relinked@example.test"))

	check("google is linked before the cross-provider unlink race", identity.current_sign_in_methods["identities"].any(func(value: Dictionary) -> bool: return value["provider"] == "google"))
	transport.next(null, func() -> void:
		ws.dispatch({"type": WsApi.ACCOUNT_IDENTITY_LINKED, "payload": {"provider": "apple", "email": "cross@example.test"}})
	)
	var cross_unlink: Dictionary = await identity.unlink("google")
	check("a link event for another provider does not supersede a successful unlink", cross_unlink.get("ok") == true and cross_unlink.get("provider") == "google")
	check("the cross-provider unlink removes its provider", not identity.current_sign_in_methods["identities"].any(func(value: Dictionary) -> bool: return value["provider"] == "google"))
	check("the cross-provider link survives the unlink", identity.current_sign_in_methods["identities"].any(func(value: Dictionary) -> bool: return value["email"] == "cross@example.test"))

	# Reentrant methods listeners cannot leak an identity event across logout.
	var linked_before := linked.size()
	identity.sign_in_methods_changed.connect(
		func(_value: Dictionary) -> void: identity.clear_account(),
		Object.CONNECT_ONE_SHOT,
	)
	ws.dispatch({"type": WsApi.ACCOUNT_IDENTITY_LINKED, "payload": {"provider": "google", "email": "new-player@example.test"}})
	check("clear from a methods callback suppresses the stale linked signal", linked.size() == linked_before)
	check("clear from a methods callback wins the state race", identity.current_sign_in_methods.is_empty())
	check(
		"account clear detaches its current realtime router",
		not ws.dispatch({"type": WsApi.ACCOUNT_IDENTITY_LINKED, "payload": linked_event})
		and identity.current_sign_in_methods.is_empty(),
	)
	transport.next(methods("apple", "replacement@example.test"))
	var replacement_methods: Dictionary = await identity.load_sign_in_methods()
	check("replacement account state can load after clear", replacement_methods.get("ok"))
	check(
		"the old router cannot mutate replacement account state",
		not ws.dispatch({"type": WsApi.ACCOUNT_IDENTITY_LINKED, "payload": linked_event})
		and identity.current_sign_in_methods == methods("apple", "replacement@example.test"),
	)

	# Realtime replacement is atomic and retired callbacks are inert.
	var first_router := RetainingWs.new()
	var second_router := RetainingWs.new()
	first_router.invoke_during_subscribe = true
	var linked_before_attach := linked.size()
	check("a valid custom router attaches", identity.attach_realtime(first_router).get("ok"))
	check("candidate callbacks are inert until attachment commits", linked.size() == linked_before_attach)
	first_router.invoke_during_subscribe = false
	var invalid_attach: Dictionary = identity.attach_realtime(InvalidWs.new())
	check("an invalid replacement fails without detaching the current router", invalid_attach.get("error") == "invalid_ws_api")
	first_router.emit("account.identity.link.failed", failed_event)
	check("the old router remains live after invalid replacement", link_failures.size() == 2)
	check("a valid replacement attaches", identity.attach_realtime(second_router).get("ok"))
	var failures_before_retired := link_failures.size()
	first_router.emit_retired("account.identity.link.failed", 0, failed_event)
	check("a retired router callback is generation-bound", link_failures.size() == failures_before_retired)
	second_router.emit("account.identity.link.failed", failed_event)
	check("the replacement router owns new events", link_failures.size() == failures_before_retired + 1)
	identity.detach_realtime()
	second_router.emit_retired("account.identity.link.failed", 0, failed_event)
	check("a callback retained after detach is inert", link_failures.size() == failures_before_retired + 1)

	# REST callback reentrancy cannot report a stale success.
	var methods_transport := FakeTransport.new()
	var methods_identity := Identity.new(RestApi.new(methods_transport.request), "game")
	methods_identity.sign_in_methods_changed.connect(
		func(_value: Dictionary) -> void: methods_identity.clear_account(),
		Object.CONNECT_ONE_SHOT,
	)
	methods_transport.next(methods())
	var reentrant_methods: Dictionary = await methods_identity.load_sign_in_methods()
	check("clear from a REST methods callback invalidates the awaiting result", reentrant_methods.get("error") == "session_changed")
	check("the reentrant clear leaves no account snapshot", methods_identity.current_sign_in_methods.is_empty())

	var invalid := Identity.new(null, "")
	check("invalid API configuration fails without assertions", (await invalid.load_motd()).get("error") == "invalid_api")

	# The retained callbacks intentionally model transports that hold stale
	# handlers. Break those test-owned cycles, then let this coroutine return so
	# local RefCounted values are released before the leak-sensitive report.
	first_router.clear_all()
	second_router.clear_all()
	call_deferred("_report")


func _report() -> void:
	if failures.is_empty():
		print("ok   GDScript identity, account linking, and MOTD")
		print("HAIVEN_TEST_PASS identity %d" % checks)
		quit(0)
		return
	for failure in failures:
		print("FAIL ", failure)
	quit(1)
