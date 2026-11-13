# Headless coverage for the engine-native game-login handoff. Network transport
# is injected here so the test can inspect the exact HTTPRequest form boundary;
# the addon uses HTTPRequest itself when that seam is omitted.
extends SceneTree

const Handoff := preload("res://addons/haiven/haiven_handoff.gd")
const TokenStore := preload("res://addons/haiven/haiven_token_store.gd")
const Transport := preload("res://addons/haiven/haiven_http_transport.gd")

const NOW := 1_789_646_400_000
const REDIRECT := "haiven-example://auth/callback?mode=login"
const ENTRY := "https://app.haiven.gg/connect/game?from=godot"
const EXCHANGE := "https://api.haiven.gg/v0/auth/handoff/exchange"

var failures: Array[String] = []
var checks := 0
var _now := NOW
var _entropy: Array[PackedByteArray] = []
var _opened: Array[String] = []
var _requests: Array[Dictionary] = []
# When set, the injected exchange returns this instead of a 200 credential.
var _exchange_response := {}
var _exchange_payload := {
	"access_token": "header.eyJleHAiOjF9.signature",
	"token_type": "Bearer",
	"expires_in": 300,
}


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var verifier := "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
	_entropy = [_decode_base64_url(verifier), _filled_bytes(7)]
	var tokens := TokenStore.new("old-access")
	var handoff := _coordinator(tokens)
	root.add_child(handoff)

	var start: Dictionary = handoff.begin_login()
	check("begin succeeds", start.get("ok") == true)
	check("the injected launcher receives the authorization URL", _opened == [start["authorization_url"]])
	var authorization := _query(String(start["authorization_url"]))
	check("the entry URL's existing query survives", authorization.get("from") == "godot")
	check("the integration id is present", authorization.get("integration_id") == "example-game")
	check("the handoff asks for redirect completion", authorization.get("completion") == "redirect")
	check("the configured redirect URI is present", authorization.get("redirect_uri") == REDIRECT)
	check("the state is a separate 256-bit value", String(start["state"]).length() == 43 and start["state"] != verifier)
	check("the challenge method is S256", authorization.get("code_challenge_method") == "S256")
	check(
		"the RFC 7636 S256 vector matches",
		authorization.get("code_challenge") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
	)

	var mismatched_target: Dictionary = await handoff.complete(
		"haiven-example://other/callback?mode=login&code=attacker&state=%s" % start["state"]
	)
	check("a mismatched callback target is rejected", mismatched_target.get("error") == "callback_target_mismatch")
	var mismatched_state: Dictionary = await handoff.complete(_callback("attacker-state"))
	check("a mismatched state is rejected", mismatched_state.get("error") == "unknown_or_consumed_state")
	check("untrusted callbacks never reach the exchange", _requests.is_empty())

	var completed: Dictionary = await handoff.complete(_callback(start["state"]))
	check("a trusted callback completes", completed.get("ok") == true)
	var credential: Dictionary = completed.get("credential", {})
	check("the access token is returned", credential.get("access_token") == "header.eyJleHAiOjF9.signature")
	check("the token type is returned", credential.get("token_type") == "Bearer")
	check("the relative expiry becomes absolute milliseconds", credential.get("expires_at_msec") == NOW + 300_000)
	check("the shared store owns the new token", tokens.read() == "header.eyJleHAiOjF9.signature")
	check("the shared store owns its expiry", tokens.expires_at_msec == NOW + 300_000)
	check("JWT-shaped bearer claims do not override exchange metadata", tokens.expires_at_msec != 1000)
	check("the exchange uses the configured endpoint", _requests[0].get("url") == EXCHANGE)
	check("the exchange declares form encoding", _requests[0].get("headers") == PackedStringArray([Handoff.FORM_CONTENT_TYPE]))
	var form := _query("?" + String(_requests[0].get("body")))
	check("the exchange form has only the four contract fields", form.keys().size() == 4)
	check("the exchange code is decoded then form encoded", form.get("code") == "one use/code")
	check("the exchange carries the transient verifier", form.get("code_verifier") == verifier)
	check("the exchange binds integration and redirect", form.get("integration_id") == "example-game" and form.get("redirect_uri") == REDIRECT)

	var replay: Dictionary = await handoff.complete(_callback(start["state"]))
	check("a replay is rejected", replay.get("error") == "unknown_or_consumed_state")
	check("a replay cannot exchange twice", _requests.size() == 1)

	for reason in [Handoff.END_EXPIRED, Handoff.END_REST_401, Handoff.END_WS_EXPIRED]:
		tokens.write("rejected", NOW + 300_000)
		_entropy = [_filled_bytes(20 + _opened.size()), _filled_bytes(40 + _opened.size())]
		var opens_before := _opened.size()
		var restarted: Dictionary = handoff.restart_login(reason)
		check("%s clears the rejected credential" % reason, tokens.read().is_empty())
		check("%s starts a fresh handoff" % reason, restarted.get("ok") == true and _opened.size() == opens_before + 1)

	# Expiry consumes the verifier without going to the network.
	_entropy = [_filled_bytes(8), _filled_bytes(9)]
	var expiring := _coordinator(tokens, 1000)
	root.add_child(expiring)
	var expiring_start: Dictionary = expiring.begin_login()
	_now += 1001
	var expired: Dictionary = await expiring.complete(_callback(expiring_start["state"]))
	check("an expired transaction is rejected", expired.get("error") == "expired_transaction")
	check("expiry happens before exchange", _requests.size() == 1)

	# Cancellation is explicit and shares the same one-use boundary as replay.
	_now = NOW
	_entropy = [_filled_bytes(10), _filled_bytes(11)]
	var cancellable := _coordinator(tokens)
	root.add_child(cancellable)
	var cancellable_start: Dictionary = cancellable.begin_login()
	check("a pending transaction can be cancelled", cancellable.cancel(cancellable_start["state"]))
	check("cancellation is one-use", not cancellable.cancel(cancellable_start["state"]))
	var cancelled: Dictionary = await cancellable.complete(_callback(cancellable_start["state"]))
	check("a cancelled callback is rejected", cancelled.get("error") == "unknown_or_consumed_state")
	check("cancellation happens before exchange", _requests.size() == 1)

	# A game handoff must never acquire a long-lived refresh credential.
	_entropy = [_filled_bytes(12), _filled_bytes(13)]
	_exchange_payload["refresh_token"] = "must-not-cross-the-boundary"
	var forbidden := _coordinator(tokens)
	root.add_child(forbidden)
	var forbidden_start: Dictionary = forbidden.begin_login()
	var rejected: Dictionary = await forbidden.complete(_callback(forbidden_start["state"]))
	check("refresh credentials are rejected", rejected.get("error") == "forbidden_refresh_credential")
	check("a rejected credential does not replace the session token", tokens.read().is_empty())

	# ADR 0041: a durable credential arrives with a null expires_in.
	_entropy = [_filled_bytes(14), _filled_bytes(15)]
	_exchange_payload = {"access_token": "durable-access", "token_type": "Bearer", "expires_in": null}
	var saved := SavedTokens.new()
	var durable := _coordinator(saved)
	root.add_child(durable)
	var durable_start: Dictionary = durable.begin_login()
	var durable_completed: Dictionary = await durable.complete(_callback(durable_start["state"]))
	check("a null expires_in completes", durable_completed.get("ok") == true)
	check("a durable credential has no expiry", durable_completed.get("credential", {}).get("expires_at_msec") == -1)
	check("a durable credential never expires", saved.expires_at_msec == -1 and not saved.is_expired(NOW * 10))
	check("the persistent store saved the durable credential", saved.persisted.get("access_token") == "durable-access")

	_entropy = [_filled_bytes(16), _filled_bytes(17)]
	_exchange_payload = {"access_token": "handoff-access", "token_type": "Bearer"}
	var missing := _coordinator(TokenStore.new())
	root.add_child(missing)
	var missing_start: Dictionary = missing.begin_login()
	var missing_result: Dictionary = await missing.complete(_callback(missing_start["state"]))
	check("a missing expires_in is still refused", missing_result.get("error") == "invalid_credential")

	# SDK-HANDOFF-11: a finite lifetime is a whole number of seconds. 86400.5
	# is the case a relative-tolerance comparison would wrongly accept.
	var entropy_seed := 18
	for refused_expiry: Variant in [1.5, 86400.5, -1]:
		_entropy = [_filled_bytes(entropy_seed), _filled_bytes(entropy_seed + 1)]
		entropy_seed += 2
		_exchange_payload = {"access_token": "handoff-access", "token_type": "Bearer", "expires_in": refused_expiry}
		var refusing := _coordinator(TokenStore.new())
		root.add_child(refusing)
		var refusing_start: Dictionary = refusing.begin_login()
		var refusing_result: Dictionary = await refusing.complete(_callback(refusing_start["state"]))
		check("expires_in %s is refused" % str(refused_expiry), refusing_result.get("error") == "invalid_credential")

	# A second coordinator over a store whose memory was lost stands in for the
	# next launch: it reuses the saved credential and opens no browser.
	saved.forget_memory()
	var relaunch := _coordinator(saved)
	root.add_child(relaunch)
	var resumed_signals: Array[Dictionary] = []
	var failed_signals: Array[String] = []
	relaunch.completed.connect(func(value: Dictionary) -> void: resumed_signals.append(value))
	relaunch.failed.connect(func(error: String) -> void: failed_signals.append(error))
	var opens_before_resume := _opened.size()
	var resumed: Dictionary = relaunch.resume()
	check("a saved credential is reused at start", resumed.get("ok") == true)
	check("reuse makes the credential live", saved.read() == "durable-access")
	check("reuse opens no browser", _opened.size() == opens_before_resume)
	check("reuse emits completed like a finished handoff", resumed_signals.size() == 1)

	saved.persisted = JSON.parse_string(JSON.stringify({"access_token": "json-access", "expires_at_msec": NOW + 1000}))
	saved.forget_memory()
	check("a JSON-backed store's whole-float expiry is reused", relaunch.resume().get("ok") == true and saved.expires_at_msec == NOW + 1000)

	saved.persisted = {"access_token": "fractional-access", "expires_at_msec": float(NOW) + 1000.5}
	saved.forget_memory()
	var fractional_resume: Dictionary = relaunch.resume()
	check("a fractional saved expiry is not reused", fractional_resume.get("error") == "no_saved_credential")
	check("a fractional saved expiry is cleared", saved.persisted.is_empty())

	saved.write("expired-access", NOW)
	saved.forget_memory()
	var expired_resume: Dictionary = relaunch.resume()
	check("an expired saved credential is not reused", expired_resume.get("error") == "no_saved_credential")
	check("an expired saved credential is cleared", saved.persisted.is_empty())
	var empty_resume: Dictionary = relaunch.resume()
	check("nothing saved resumes nothing", empty_resume.get("error") == "no_saved_credential")
	check("finding nothing saved is not a failure", failed_signals.is_empty())

	# The default exchange is bounded like HaivenHttpTransport: a stalled request
	# times out instead of holding complete() open forever, and a redirect cannot
	# carry the code and verifier to another URL.
	_entropy = [_filled_bytes(30), _filled_bytes(31)]
	var stalled := _coordinator(TokenStore.new())
	root.add_child(stalled)
	var request: HTTPRequest = stalled._new_exchange_request()
	check(
		"the default exchange has a finite timeout",
		request.timeout > 0.0 and is_equal_approx(request.timeout, Transport.DEFAULT_TIMEOUT_SECONDS),
	)
	check("the default exchange follows no redirects", request.max_redirects == 0)
	check("the default exchange caps the response body", request.body_size_limit == Transport.DEFAULT_BODY_SIZE_LIMIT)
	request.free()

	# A timed-out exchange settles complete() with a failure, so the caller can
	# offer a retry and a fresh handoff can start.
	var stalled_failures: Array[String] = []
	stalled.failed.connect(func(error: String) -> void: stalled_failures.append(error))
	var stalled_start: Dictionary = stalled.begin_login()
	_exchange_response = {"result": HTTPRequest.RESULT_TIMEOUT, "status": 0, "body": ""}
	var timed_out: Dictionary = await stalled.complete(_callback(stalled_start["state"]))
	check("a timed-out exchange fails", timed_out.get("ok") == false and timed_out.get("error") == "exchange_timeout")
	check("a timed-out exchange emits failed", stalled_failures == ["exchange_timeout"])
	check("a timed-out exchange has consumed its state", not stalled.cancel(stalled_start["state"]))
	_entropy = [_filled_bytes(32), _filled_bytes(33)]
	check("a fresh handoff starts after a timeout", stalled.begin_login().get("ok") == true)

	_entropy = [_filled_bytes(34), _filled_bytes(35)]
	var redirected_start: Dictionary = stalled.begin_login()
	_exchange_response = {"result": HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED, "status": 302, "body": ""}
	var redirected: Dictionary = await stalled.complete(_callback(redirected_start["state"]))
	check("a redirected exchange fails without following", redirected.get("error") == "exchange_http_302")

	_entropy = [_filled_bytes(36), _filled_bytes(37)]
	var truncated_start: Dictionary = stalled.begin_login()
	_exchange_response = {
		"result": HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED,
		"status": 200,
		"body": JSON.stringify({"access_token": "partial", "token_type": "Bearer", "expires_in": 300}),
	}
	var truncated: Dictionary = await stalled.complete(_callback(truncated_start["state"]))
	check("an incomplete 2xx exchange is not a credential", truncated.get("error") == "exchange_http_0")
	_exchange_response = {}

	_report()


## Persists across a simulated restart: [method forget_memory] drops what the
## base class holds in memory, as a new process would.
class SavedTokens extends "res://addons/haiven/haiven_token_store.gd":
	var persisted := {}

	func write(next_access_token: String, next_expires_at_msec: int) -> void:
		super.write(next_access_token, next_expires_at_msec)
		persisted = {"access_token": next_access_token, "expires_at_msec": next_expires_at_msec}

	func clear() -> void:
		super.clear()
		persisted = {}

	func load_credential() -> Dictionary:
		return persisted.duplicate()

	func forget_memory() -> void:
		access_token = ""
		expires_at_msec = -1


func _coordinator(tokens: RefCounted, lifetime_msec: int = 15 * 60 * 1000) -> Node:
	return Handoff.new(
		{
			"entry_url": ENTRY,
			"exchange_url": EXCHANGE,
			"integration_id": "example-game",
			"redirect_url": REDIRECT,
			"transaction_lifetime_msec": lifetime_msec,
		},
		tokens,
		_launch,
		_exchange,
		func() -> int: return _now,
		_random_bytes,
	)


func _launch(url: String) -> int:
	_opened.append(url)
	return OK


func _exchange(url: String, headers: PackedStringArray, body: String) -> Dictionary:
	_requests.append({"url": url, "headers": headers, "body": body})
	if not _exchange_response.is_empty():
		return _exchange_response
	return {"status": 200, "body": JSON.stringify(_exchange_payload)}


func _random_bytes(_size: int) -> PackedByteArray:
	return _entropy.pop_front() if not _entropy.is_empty() else PackedByteArray()


func _callback(state: String) -> String:
	return "%s&code=%s&state=%s" % [REDIRECT, "one use/code".uri_encode(), state.uri_encode()]


func _query(url: String) -> Dictionary:
	var question := url.find("?")
	var result := {}
	if question < 0:
		return result
	for field in url.substr(question + 1).split("&", false):
		var text := String(field)
		var equals := text.find("=")
		var name := text if equals < 0 else text.substr(0, equals)
		var value := "" if equals < 0 else text.substr(equals + 1)
		result[name.replace("+", " ").uri_decode()] = value.replace("+", " ").uri_decode()
	return result


func _decode_base64_url(value: String) -> PackedByteArray:
	var base64 := value.replace("-", "+").replace("_", "/")
	while base64.length() % 4 != 0:
		base64 += "="
	return Marshalls.base64_to_raw(base64)


func _filled_bytes(value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(32)
	bytes.fill(value)
	return bytes


func _report() -> void:
	if failures.is_empty():
		print("ok   GDScript game auth handoff")
		print("HAIVEN_TEST_PASS handoff %d" % checks)
		quit(0)
		return
	for failure in failures:
		print("FAIL ", failure)
	quit(1)
