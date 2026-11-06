## Engine-native game-login handoff with S256 PKCE.
##
## The coordinator owns only transient verifier state. A game delivers its
## custom-scheme callback to [method complete], which consumes that state before
## making the exchange. Successful credentials are written to the shared token
## store that [HaivenSession] reads for every handshake.
class_name HaivenHandoff
extends Node

signal completed(credential: Dictionary)
signal failed(error: String)

const Protocol := preload("haiven_protocol.gd")
const DEFAULT_TRANSACTION_LIFETIME_MSEC := 15 * 60 * 1000
const PKCE_BYTES := 32
const FORM_CONTENT_TYPE := "Content-Type: application/x-www-form-urlencoded"
const END_EXPIRED := "expired"
const END_REST_401 := "rest_401"
const END_WS_EXPIRED := "ws_expired"

var _entry_url: String
var _exchange_url: String
var _integration_id: String
var _redirect_url: String
var _instructions_id: String
var _screen_hint: String
var _transaction_lifetime_msec: int
var _tokens: RefCounted
var _launch_url: Callable
var _exchange: Callable
var _now: Callable
var _random_bytes: Callable
var _transactions: Dictionary = {}
var _configuration_error := ""


## Required options are `entry_url`, `exchange_url`, `integration_id`, and
## `redirect_url`. `launch_url`, `exchange`, `now`, and `random_bytes` are host
## seams for platforms or deterministic tests; omitted launch/exchange call
## [method OS.shell_open] and an engine [HTTPRequest], respectively.
func _init(
	options: Dictionary,
	tokens: RefCounted,
	launch_url: Callable = Callable(),
	exchange: Callable = Callable(),
	now: Callable = Callable(),
	random_bytes: Callable = Callable(),
) -> void:
	_entry_url = String(options.get("entry_url", ""))
	_exchange_url = String(options.get("exchange_url", ""))
	_integration_id = String(options.get("integration_id", ""))
	_redirect_url = String(options.get("redirect_url", ""))
	_instructions_id = String(options.get("instructions_id", ""))
	_screen_hint = String(options.get("screen_hint", ""))
	_transaction_lifetime_msec = int(options.get(
		"transaction_lifetime_msec", DEFAULT_TRANSACTION_LIFETIME_MSEC
	))
	_tokens = tokens
	_launch_url = launch_url if launch_url.is_valid() else _open_url
	_exchange = exchange if exchange.is_valid() else _http_exchange
	_now = now if now.is_valid() else _system_now
	_random_bytes = random_bytes if random_bytes.is_valid() else _secure_random_bytes
	_configuration_error = _validate_configuration()


## Starts a one-use transaction, launches the first-party login page, and
## returns `{ok, authorization_url, state}`. Launch failures discard the
## verifier rather than leaving a transaction that can unexpectedly complete.
func begin_login() -> Dictionary:
	if not _configuration_error.is_empty():
		return _failure(_configuration_error)

	var verifier := _base64_url(_as_bytes(_random_bytes.call(PKCE_BYTES)))
	var state := _base64_url(_as_bytes(_random_bytes.call(PKCE_BYTES)))
	if verifier.length() < 43 or state.length() < 43:
		return _failure("insufficient_entropy")

	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return _failure("sha256_unavailable")
	if context.update(verifier.to_utf8_buffer()) != OK:
		return _failure("sha256_unavailable")
	var challenge := _base64_url(context.finish())

	_transactions[state] = {
		"code_verifier": verifier,
		"created_at_msec": int(_now.call()),
	}
	var authorization_url := _build_authorization_url(state, challenge)
	var launch_result: Variant = _launch_url.call(authorization_url)
	if launch_result is int and int(launch_result) != OK:
		_transactions.erase(state)
		return _failure("url_launch_failed")

	return {
		"ok": true,
		"authorization_url": authorization_url,
		"state": state,
	}


## Reuses the credential the token store saved, so a restart does not send the
## player back to the browser. Call it before [method begin_login]: it returns
## `{ok: true, credential}` or `{ok: false, error: "no_saved_credential"}`, and
## the caller then begins a handoff. Finding nothing is not a failure, so it does
## not emit [signal failed]. A saved credential past its expiry is cleared. A
## reused credential emits [signal completed] like a finished handoff.
func resume() -> Dictionary:
	if not _configuration_error.is_empty():
		return _failure(_configuration_error)
	var none := {"ok": false, "error": "no_saved_credential"}
	if not _tokens.has_method("load_credential"):
		return none
	var loaded: Variant = _tokens.call("load_credential")
	if not loaded is Dictionary or (loaded as Dictionary).is_empty():
		return none
	var saved: Dictionary = loaded
	var access_token: Variant = saved.get("access_token")
	var saved_expiry: Variant = saved.get("expires_at_msec", -1)
	# A store that round-trips through JSON hands back a whole float, which
	# compares exactly; a relative-tolerance check would also pass fractions.
	var expiry_is_integer := (
		saved_expiry is int
		or (saved_expiry is float and float(saved_expiry) == floorf(float(saved_expiry)))
	)
	var expires_at := int(saved_expiry) if expiry_is_integer else 0
	if (
		not access_token is String
		or String(access_token).is_empty()
		or not expiry_is_integer
		or (expires_at >= 0 and int(_now.call()) >= expires_at)
	):
		_tokens.call("clear")
		return none
	_tokens.call("write", access_token, expires_at)
	var credential := {
		"access_token": access_token,
		"token_type": "Bearer",
		"expires_at_msec": expires_at,
	}
	completed.emit(credential)
	return {"ok": true, "credential": credential}


## Clears a bearer ended by metadata expiry, REST 401, or auth.expired and
## starts a fresh handoff. Game credentials never use the web refresh route.
func restart_login(reason: String) -> Dictionary:
	if reason not in [END_EXPIRED, END_REST_401, END_WS_EXPIRED]:
		return _failure("invalid_credential_end_reason")
	_tokens.call("clear")
	return begin_login()


## Delivers the callback URI and exchanges its code. The returned dictionary is
## `{ok: true, credential: {access_token, token_type, expires_at_msec}}` or
## `{ok: false, error}`, where `expires_at_msec` is -1 for a durable credential
## (ADR 0041). State is consumed before the network request.
func complete(callback_url: String) -> Dictionary:
	if not _configuration_error.is_empty():
		return _failure(_configuration_error)

	var callback := _parse_absolute_url(callback_url)
	var expected := _parse_absolute_url(_redirect_url)
	if callback.is_empty() or not _same_callback_target(callback, expected):
		return _failure("callback_target_mismatch")

	var callback_query: Dictionary = callback["query"]
	var state := String(callback_query.get("state", ""))
	if state.is_empty():
		return _failure("missing_state")
	if callback_query.has("error"):
		_transactions.erase(state)
		return _failure("callback_error:%s" % String(callback_query["error"]))
	var code := String(callback_query.get("code", ""))
	if code.is_empty():
		_transactions.erase(state)
		return _failure("missing_code")

	# `take` is the one-use boundary. Mismatch, replay, and cancellation all land
	# here without allowing attacker-controlled input to reach the exchange.
	var transaction: Dictionary = _transactions.get(state, {})
	_transactions.erase(state)
	if transaction.is_empty():
		return _failure("unknown_or_consumed_state")
	if int(_now.call()) - int(transaction["created_at_msec"]) > _transaction_lifetime_msec:
		return _failure("expired_transaction")

	var body := _form_encode([
		["code", code],
		["code_verifier", String(transaction["code_verifier"])],
		["integration_id", _integration_id],
		["redirect_uri", _redirect_url],
	])
	var response: Dictionary = await _exchange.call(
		_exchange_url,
		PackedStringArray([FORM_CONTENT_TYPE]),
		body,
	)
	var parsed := _parse_exchange_response(response)
	if not parsed.get("ok", false):
		return _failure(String(parsed.get("error", "exchange_failed")))

	var credential: Dictionary = parsed["credential"]
	_tokens.call("write", credential["access_token"], credential["expires_at_msec"])
	completed.emit(credential)
	return {"ok": true, "credential": credential}


## Cancels a pending callback transaction. Returns false if it was already
## consumed, expired, cancelled, or never belonged to this coordinator.
func cancel(state: String) -> bool:
	if not _transactions.has(state):
		return false
	_transactions.erase(state)
	return true


func _http_exchange(url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var request := HTTPRequest.new()
	add_child(request)
	var request_error := request.request(url, headers, HTTPClient.METHOD_POST, body)
	if request_error != OK:
		request.queue_free()
		return {"status": 0, "body": "", "transport_error": request_error}
	var raw: Array = await request.request_completed
	request.queue_free()
	return {
		"result": int(raw[0]),
		"status": int(raw[1]),
		"headers": raw[2],
		"body": (raw[3] as PackedByteArray).get_string_from_utf8(),
	}


func _parse_exchange_response(response: Dictionary) -> Dictionary:
	if int(response.get("status", 0)) < 200 or int(response.get("status", 0)) >= 300:
		return {"ok": false, "error": "exchange_http_%d" % int(response.get("status", 0))}
	var text := String(response.get("body", ""))
	var value: Variant = JSON.parse_string(text)
	if not value is Dictionary:
		return {"ok": false, "error": "invalid_credential"}
	# The parse has already rounded an integer beyond 2^53 - 1 (`expires_in`,
	# say), so the check reads the raw text and refuses rather than trusting it.
	if Protocol.find_unsafe_integer(text) != "":
		return {"ok": false, "error": Protocol.INTEGER_PRECISION_EXCEEDED}
	var payload: Dictionary = value
	if payload.has("refresh_token"):
		return {"ok": false, "error": "forbidden_refresh_credential"}
	var access_token: Variant = payload.get("access_token")
	var token_type: Variant = payload.get("token_type")
	var expires_in: Variant = payload.get("expires_in")
	# Present but null for a durable credential (ADR 0041).
	var durable := payload.has("expires_in") and expires_in == null
	# A finite lifetime is a whole number of seconds (SDK-HANDOFF-11). The
	# comparison is exact: is_equal_approx scales its tolerance with the value
	# and would accept 86400.5.
	var expiry_is_integer := (
		expires_in is int
		or (expires_in is float and float(expires_in) == floorf(float(expires_in)))
	)
	if (
		not access_token is String
		or String(access_token).is_empty()
		or not token_type is String
		or String(token_type).is_empty()
		or not (durable or (expiry_is_integer and int(expires_in) >= 0))
	):
		return {"ok": false, "error": "invalid_credential"}
	return {
		"ok": true,
		"credential": {
			"access_token": access_token,
			"token_type": token_type,
			"expires_at_msec": -1 if durable else int(_now.call()) + int(expires_in) * 1000,
		},
	}


func _build_authorization_url(state: String, challenge: String) -> String:
	var fragmentless := _entry_url.get_slice("#", 0)
	var base := fragmentless.get_slice("?", 0)
	var original_query := ""
	var question := fragmentless.find("?")
	if question >= 0:
		original_query = fragmentless.substr(question + 1)
	var replacements := {
		"integration_id": _integration_id,
		"completion": "redirect",
		"redirect_uri": _redirect_url,
		"state": state,
		"code_challenge": challenge,
		"code_challenge_method": "S256",
	}
	if not _instructions_id.is_empty():
		replacements["instructions_id"] = _instructions_id
	if not _screen_hint.is_empty():
		replacements["screen_hint"] = _screen_hint

	var fields: Array = []
	for field in original_query.split("&", false):
		var raw_name := String(field).get_slice("=", 0)
		if not replacements.has(_query_decode(raw_name)):
			fields.append(field)
	for name in replacements:
		fields.append("%s=%s" % [_query_encode(name), _query_encode(replacements[name])])
	return base + "?" + "&".join(fields)


func _same_callback_target(callback: Dictionary, expected: Dictionary) -> bool:
	if (
		callback["scheme"] != expected["scheme"]
		or callback["host"] != expected["host"]
		or callback["port"] != expected["port"]
		or callback["path"] != expected["path"]
	):
		return false
	var callback_query: Dictionary = callback["query"]
	for name in expected["query"]:
		if callback_query.get(name) != expected["query"][name]:
			return false
	return true


func _parse_absolute_url(value: String) -> Dictionary:
	var scheme_end := value.find("://")
	if scheme_end <= 0:
		return {}
	var scheme := value.substr(0, scheme_end).to_lower()
	var remainder := value.substr(scheme_end + 3).get_slice("#", 0)
	var query_text := ""
	var question := remainder.find("?")
	if question >= 0:
		query_text = remainder.substr(question + 1)
		remainder = remainder.substr(0, question)
	var slash := remainder.find("/")
	var authority := remainder if slash < 0 else remainder.substr(0, slash)
	var path := "" if slash < 0 else remainder.substr(slash)
	if authority.is_empty() or authority.contains("@"):
		return {}
	var host := authority
	var port := ""
	if authority.begins_with("["):
		var bracket := authority.find("]")
		if bracket < 0:
			return {}
		host = authority.substr(0, bracket + 1)
		if authority.length() > bracket + 1:
			if authority[bracket + 1] != ":":
				return {}
			port = authority.substr(bracket + 2)
	else:
		var colon := authority.rfind(":")
		if colon >= 0:
			host = authority.substr(0, colon)
			port = authority.substr(colon + 1)
	return {
		"scheme": scheme,
		"host": host.to_lower(),
		"port": port,
		"path": path,
		"query": _parse_query(query_text),
		"fragment": value.get_slice("#", 1) if value.contains("#") else "",
	}


func _parse_query(value: String) -> Dictionary:
	var result := {}
	for field in value.split("&", false):
		var text := String(field)
		var equals := text.find("=")
		var name := text if equals < 0 else text.substr(0, equals)
		var field_value := "" if equals < 0 else text.substr(equals + 1)
		result[_query_decode(name)] = _query_decode(field_value)
	return result


func _form_encode(fields: Array) -> String:
	var encoded: PackedStringArray = []
	for field in fields:
		encoded.append("%s=%s" % [_query_encode(field[0]), _query_encode(field[1])])
	return "&".join(encoded)


func _query_encode(value: Variant) -> String:
	return String(value).uri_encode()


func _query_decode(value: String) -> String:
	return value.replace("+", " ").uri_decode()


func _validate_configuration() -> String:
	var entry := _parse_absolute_url(_entry_url)
	var exchange := _parse_absolute_url(_exchange_url)
	var redirect := _parse_absolute_url(_redirect_url)
	if entry.is_empty() or not _is_secure_web_target(entry):
		return "invalid_entry_url"
	if exchange.is_empty() or not _is_secure_web_target(exchange):
		return "invalid_exchange_url"
	if redirect.is_empty() or not String(redirect["fragment"]).is_empty():
		return "invalid_redirect_url"
	if _integration_id.strip_edges().is_empty():
		return "missing_integration_id"
	if _transaction_lifetime_msec <= 0:
		return "invalid_transaction_lifetime"
	if _tokens == null or not _tokens.has_method("write") or not _tokens.has_method("clear"):
		return "invalid_token_store"
	return ""


func _is_secure_web_target(url: Dictionary) -> bool:
	if url["scheme"] == "https":
		return true
	return url["scheme"] == "http" and url["host"] in ["127.0.0.1", "localhost", "[::1]"]


func _failure(error: String) -> Dictionary:
	failed.emit(error)
	return {"ok": false, "error": error}


func _base64_url(value: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(value).replace("+", "-").replace("/", "_").rstrip("=")


func _as_bytes(value: Variant) -> PackedByteArray:
	return value if value is PackedByteArray else PackedByteArray()


func _secure_random_bytes(size: int) -> PackedByteArray:
	return Crypto.new().generate_random_bytes(size)


func _system_now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _open_url(url: String) -> int:
	return OS.shell_open(url)
