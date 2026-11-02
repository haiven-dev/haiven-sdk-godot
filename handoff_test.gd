# Headless coverage for the engine-native game-login handoff. Network transport
# is injected here so the test can inspect the exact HTTPRequest form boundary;
# the addon uses HTTPRequest itself when that seam is omitted.
extends SceneTree

const Handoff := preload("res://addons/haiven/haiven_handoff.gd")
const TokenStore := preload("res://addons/haiven/haiven_token_store.gd")

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
var _exchange_payload := {
	"access_token": "handoff-access",
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
	check("the access token is returned", credential.get("access_token") == "handoff-access")
	check("the token type is returned", credential.get("token_type") == "Bearer")
	check("the relative expiry becomes absolute milliseconds", credential.get("expires_at_msec") == NOW + 300_000)
	check("the shared store owns the new token", tokens.read() == "handoff-access")
	check("the shared store owns its expiry", tokens.expires_at_msec == NOW + 300_000)
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
	check("a rejected credential does not replace the session token", tokens.read() == "handoff-access")

	_report()


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
