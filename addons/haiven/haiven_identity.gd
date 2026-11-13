## Headless identity and Message of the Day state for Godot games.
##
## The generated REST and WebSocket APIs remain the wire surface. This facade
## validates and joins public MOTD reads, signed-in MOTD events, sign-in-method
## snapshots, browser-owned SSO link initiation, link outcome events, and
## unlinking. Every operation fails finitely in release exports.
class_name HaivenIdentity
extends RefCounted

const RestError := preload("haiven_rest_error.gd")
const PROVIDERS := ["google", "apple"]
const _MOTD_FIELDS := ["id", "title", "body", "url", "startsAt", "endsAt"]
const _IDENTITY_FIELDS := ["provider", "email"]
const _LINK_FAILURE_FIELDS := ["provider", "code"]
const _METHOD_FIELDS := ["hasPassword", "identities"]

signal motd_changed(message: Variant)
signal sign_in_methods_changed(methods: Dictionary)
signal identity_linked(identity: Dictionary)
signal identity_link_failed(failure: Dictionary)
signal diagnostic(code: String, detail: Variant)

## Defensive snapshots: mutating a returned Dictionary never mutates the facade.
var current_motd: Variant:
	get:
		return _copy(_current_motd)
var current_sign_in_methods: Dictionary:
	get:
		return _current_sign_in_methods.duplicate(true)

var _api: RefCounted
var _api_error := ""
var _integration_id: String
var _browser_link_adapter: RefCounted
var _current_motd: Variant = null
var _current_sign_in_methods: Dictionary = {}
var _account_generation := 0
var _methods_revision := 0
# Per-provider change counters. A snapshot touches every provider; a link or
# unlink touches only its own, so a mutation can tell a same-provider race from
# an unrelated one.
var _provider_revisions: Dictionary = {}
var _motd_revision := 0
var _last_motd_id := ""

var _ws_api: RefCounted
var _realtime_generation := 0
var _linked_handler: Callable
var _link_failed_handler: Callable
var _motd_handler: Callable

## `api` is [HaivenRestApi]. `ws_api` is an optional [HaivenWsApi] already
## connected to the game's session.
##
## `browser_link_adapter` is optional so MOTD and sign-in-method reads still
## work on hosts without a browser integration. When supplied, it must expose
## `begin_link(provider) -> {ok: bool, error?: String, detail?: Variant}`. The
## adapter, not this facade, owns the security boundary: it opens the popup
## synchronously before yielding, performs the POST from that same browser
## context so the federation cookie stays there, and navigates that popup to the
## returned redirect. [method begin_link] fails closed without this adapter.
func _init(
	api: RefCounted,
	integration_id: String,
	ws_api: RefCounted = null,
	browser_link_adapter: RefCounted = null,
) -> void:
	_api = api
	_api_error = _validate_api(api)
	_integration_id = integration_id.strip_edges()
	_browser_link_adapter = browser_link_adapter
	if ws_api != null:
		attach_realtime(ws_api)


## Reads the public pre-sign-in MOTD. A 204/no-body answer is explicit. A newer
## realtime MOTD wins over an older REST request still in flight.
func load_motd() -> Dictionary:
	if _api_error != "":
		return _failure(_api_error)
	if _integration_id.is_empty():
		return _failure("missing_integration_id")
	var request_revision := _motd_revision
	var response: Variant = await _api.get_motd(_integration_id)
	if request_revision != _motd_revision:
		return _failure("superseded", "motd")
	if response is RestError:
		return _request_failure(response)
	if response == null:
		var empty_revision := _set_motd(null)
		if empty_revision != _motd_revision:
			return _failure("superseded", "motd_callback")
		return {"ok": true, "motd": null}
	var normalized := _normalize_motd(response)
	if normalized.is_empty():
		return _failure("invalid_motd_response", response)
	var committed_revision := _set_motd(normalized)
	if committed_revision != _motd_revision:
		return _failure("superseded", "motd_callback")
	return {"ok": true, "motd": normalized.duplicate(true)}


## Reads password and linked-identity state. A newer realtime link event wins
## over a REST snapshot that started earlier.
func load_sign_in_methods() -> Dictionary:
	if _api_error != "":
		return _failure(_api_error)
	var generation := _account_generation
	var request_revision := _methods_revision
	var response: Variant = await _api.get_users_me_sign_in_methods()
	if generation != _account_generation:
		return _failure("session_changed")
	if request_revision != _methods_revision:
		return _failure("superseded", "sign_in_methods")
	if response is RestError:
		return _request_failure(response)
	var normalized := _normalize_sign_in_methods(response)
	if normalized.is_empty():
		return _failure("invalid_sign_in_methods_response", response)
	var committed_revision := _set_sign_in_methods(normalized)
	if generation != _account_generation:
		return _failure("session_changed")
	if committed_revision != _methods_revision:
		return _failure("superseded", "sign_in_methods_callback")
	return {"ok": true, "methods": normalized.duplicate(true)}


## Begins a Google or Apple link only through the injected browser-context
## adapter. It never POSTs through the game transport and then opens a system
## browser: that split loses the federation cookie and violates popup ordering.
func begin_link(provider: String) -> Dictionary:
	var normalized_provider := provider.to_lower().strip_edges()
	if not normalized_provider in PROVIDERS:
		return _failure("invalid_provider", provider)
	if _browser_link_adapter == null or not _browser_link_adapter.has_method("begin_link"):
		return _failure("browser_link_adapter_required")
	var generation := _account_generation
	var response: Variant = await _browser_link_adapter.call("begin_link", normalized_provider)
	if generation != _account_generation:
		return _failure("session_changed")
	if not response is Dictionary or not response.get("ok") is bool:
		return _failure("invalid_browser_link_response", response)
	if bool(response["ok"]):
		if not _has_only_keys(response, ["ok"]):
			return _failure("invalid_browser_link_response", response)
		return {"ok": true, "provider": normalized_provider}
	if not _has_only_keys(response, ["ok", "error", "detail"]):
		return _failure("invalid_browser_link_response", response)
	var error_code := String(response.get("error", ""))
	if not _is_error_code(error_code):
		return _failure("invalid_browser_link_response", response)
	return _failure(error_code, response.get("detail"))


## Unlinks one provider through authenticated game REST. The generated raw POST
## link operation stays available on [HaivenRestApi], but it is not a complete
## browser flow and this facade deliberately does not call it.
func unlink(provider: String) -> Dictionary:
	if _api_error != "":
		return _failure(_api_error)
	var normalized_provider := provider.to_lower().strip_edges()
	if not normalized_provider in PROVIDERS:
		return _failure("invalid_provider", provider)
	var generation := _account_generation
	var request_revision := _methods_revision
	var provider_revision := _provider_revision(normalized_provider)
	var response: Variant = await _api.delete_users_me_sign_in_methods_sso_provider(
		normalized_provider
	)
	if generation != _account_generation:
		return _failure("session_changed")
	# A change to another provider (for example an Apple link completing while
	# Google unlinks) does not make this server-confirmed unlink stale: apply it
	# on top so both changes survive. A relink of the same provider or a fresh
	# snapshot still wins.
	if request_revision != _methods_revision and (
		response is RestError or provider_revision != _provider_revision(normalized_provider)
	):
		return _failure("superseded", "unlink")
	if response is RestError:
		return _request_failure(response)
	var committed_revision := _remove_identity(normalized_provider)
	if generation != _account_generation:
		return _failure("session_changed")
	if committed_revision != _methods_revision:
		return _failure("superseded", "unlink_callback")
	return {"ok": true, "provider": normalized_provider}


## Atomically replaces realtime routing. An invalid candidate leaves the current
## router attached. Retired handlers are generation-bound and ignore late calls.
func attach_realtime(ws_api: RefCounted) -> Dictionary:
	var invalid := _validate_ws_api(ws_api)
	if invalid != "":
		return _failure(invalid)

	var candidate_generation := _realtime_generation + 1
	# Routers commonly retain event handlers. Capture only a WeakRef so the
	# facade and router do not form a RefCounted cycle when their owner exits.
	var owner := weakref(self)
	var candidate_linked := func(payload: Variant, frame: Dictionary) -> void:
		var target: Variant = owner.get_ref()
		if target != null:
			target.call("_on_identity_linked", payload, frame, candidate_generation)
	var candidate_failed := func(payload: Variant, frame: Dictionary) -> void:
		var target: Variant = owner.get_ref()
		if target != null:
			target.call("_on_identity_link_failed", payload, frame, candidate_generation)
	var candidate_motd := func(payload: Variant, frame: Dictionary) -> void:
		var target: Variant = owner.get_ref()
		if target != null:
			target.call("_on_motd", payload, frame, candidate_generation)

	# Candidate callbacks cannot mutate state until all three are installed.
	ws_api.on_account_identity_linked(candidate_linked)
	ws_api.on_account_identity_link_failed(candidate_failed)
	ws_api.on_motd(candidate_motd)

	var old_ws := _ws_api
	var old_linked := _linked_handler
	var old_failed := _link_failed_handler
	var old_motd := _motd_handler
	_realtime_generation = candidate_generation
	_ws_api = ws_api
	_linked_handler = candidate_linked
	_link_failed_handler = candidate_failed
	_motd_handler = candidate_motd
	_detach_handlers(old_ws, old_linked, old_failed, old_motd)
	return {"ok": true}


func detach_realtime() -> void:
	var old_ws := _ws_api
	var old_linked := _linked_handler
	var old_failed := _link_failed_handler
	var old_motd := _motd_handler
	_realtime_generation += 1
	_ws_api = null
	_linked_handler = Callable()
	_link_failed_handler = Callable()
	_motd_handler = Callable()
	_detach_handlers(old_ws, old_linked, old_failed, old_motd)


func clear_account() -> void:
	_account_generation += 1
	_methods_revision += 1
	# Realtime handlers belong to the authenticated account that attached them.
	# Invalidate and remove them before exposing cleared state so a late frame
	# from that router cannot be applied to a replacement account.
	detach_realtime()
	if not _current_sign_in_methods.is_empty():
		_current_sign_in_methods = {}
		sign_in_methods_changed.emit({})


func dismiss_motd() -> void:
	if _current_motd == null:
		return
	_motd_revision += 1
	_current_motd = null
	motd_changed.emit(null)


func _on_identity_linked(payload: Variant, _frame: Dictionary, realtime_generation: int) -> void:
	if realtime_generation != _realtime_generation:
		return
	var normalized := _normalize_identity(payload)
	if normalized.is_empty():
		diagnostic.emit("invalid_identity_linked_event", _copy(payload))
		return
	var account_generation := _account_generation
	var committed_revision := _upsert_identity(normalized)
	if realtime_generation != _realtime_generation or account_generation != _account_generation:
		return
	if committed_revision != _methods_revision:
		return
	identity_linked.emit(normalized.duplicate(true))


func _on_identity_link_failed(
	payload: Variant,
	_frame: Dictionary,
	realtime_generation: int,
) -> void:
	if realtime_generation != _realtime_generation:
		return
	var normalized := _normalize_link_failure(payload)
	if normalized.is_empty():
		diagnostic.emit("invalid_identity_link_failed_event", _copy(payload))
		return
	identity_link_failed.emit(normalized.duplicate(true))


func _on_motd(payload: Variant, _frame: Dictionary, realtime_generation: int) -> void:
	if realtime_generation != _realtime_generation:
		return
	var normalized := _normalize_motd(payload)
	if normalized.is_empty():
		diagnostic.emit("invalid_motd_event", _copy(payload))
		return
	_set_motd(normalized)


func _set_motd(message: Variant) -> int:
	if message == null:
		_motd_revision += 1
		if _current_motd == null:
			return _motd_revision
		_current_motd = null
		var revision := _motd_revision
		motd_changed.emit(null)
		return revision
	var message_id := String(message.get("id", ""))
	_motd_revision += 1
	if message_id == _last_motd_id:
		return _motd_revision
	_last_motd_id = message_id
	_current_motd = message.duplicate(true)
	var revision := _motd_revision
	motd_changed.emit(_current_motd.duplicate(true))
	return revision


func _provider_revision(provider: String) -> int:
	return int(_provider_revisions.get(provider, 0))


func _touch_provider(provider: String) -> void:
	_provider_revisions[provider] = _provider_revision(provider) + 1


func _set_sign_in_methods(methods: Dictionary) -> int:
	for provider: String in PROVIDERS:
		_touch_provider(provider)
	_methods_revision += 1
	_current_sign_in_methods = methods.duplicate(true)
	var revision := _methods_revision
	sign_in_methods_changed.emit(_current_sign_in_methods.duplicate(true))
	return revision


func _upsert_identity(identity: Dictionary) -> int:
	_touch_provider(identity["provider"])
	if _current_sign_in_methods.is_empty():
		_methods_revision += 1
		return _methods_revision
	var identities: Array = _current_sign_in_methods.get("identities", []).duplicate(true)
	for index in identities.size():
		if String(identities[index].get("provider", "")) == identity["provider"]:
			identities[index] = identity.duplicate(true)
			_current_sign_in_methods["identities"] = identities
			_methods_revision += 1
			var revision := _methods_revision
			sign_in_methods_changed.emit(_current_sign_in_methods.duplicate(true))
			return revision
	identities.append(identity.duplicate(true))
	_current_sign_in_methods["identities"] = identities
	_methods_revision += 1
	var revision := _methods_revision
	sign_in_methods_changed.emit(_current_sign_in_methods.duplicate(true))
	return revision


func _remove_identity(provider: String) -> int:
	_touch_provider(provider)
	if _current_sign_in_methods.is_empty():
		_methods_revision += 1
		return _methods_revision
	var kept: Array = []
	var removed := false
	for identity: Variant in _current_sign_in_methods.get("identities", []):
		if identity is Dictionary and String(identity.get("provider", "")) == provider:
			removed = true
		else:
			kept.append(_copy(identity))
	if not removed:
		_methods_revision += 1
		return _methods_revision
	_current_sign_in_methods["identities"] = kept
	_methods_revision += 1
	var revision := _methods_revision
	sign_in_methods_changed.emit(_current_sign_in_methods.duplicate(true))
	return revision


func _normalize_motd(value: Variant) -> Dictionary:
	if not value is Dictionary or not _has_only_keys(value, _MOTD_FIELDS):
		return {}
	var message: Dictionary = value
	if not message.get("id") is String or not _is_uuid(String(message["id"])):
		return {}
	if not message.get("body") is String:
		return {}
	if not message.get("startsAt") is String or not _is_datetime(String(message["startsAt"])):
		return {}
	if message.has("title") and not message["title"] is String:
		return {}
	if message.has("endsAt") and (
		not message["endsAt"] is String or not _is_datetime(String(message["endsAt"]))
	):
		return {}
	if message.has("url") and (
		not message["url"] is String or not _is_secure_web_url(String(message["url"]))
	):
		return {}
	var normalized := message.duplicate(true)
	normalized["id"] = String(normalized["id"]).to_lower()
	return normalized


func _normalize_sign_in_methods(value: Variant) -> Dictionary:
	if not value is Dictionary or not _has_only_keys(value, _METHOD_FIELDS):
		return {}
	var methods: Dictionary = value
	if not methods.get("hasPassword") is bool or not methods.get("identities") is Array:
		return {}
	var identities: Array = []
	for value_identity: Variant in methods["identities"]:
		var identity := _normalize_identity(value_identity)
		if identity.is_empty():
			return {}
		identities.append(identity)
	return {"hasPassword": methods["hasPassword"], "identities": identities}


func _normalize_identity(value: Variant) -> Dictionary:
	if not value is Dictionary or not _has_only_keys(value, _IDENTITY_FIELDS):
		return {}
	if not value.get("provider") is String or not value.get("email") is String:
		return {}
	var provider := String(value["provider"])
	var email := String(value["email"])
	if not provider in PROVIDERS or email.is_empty() or _has_control(email):
		return {}
	return {"provider": provider, "email": email}


func _normalize_link_failure(value: Variant) -> Dictionary:
	if not value is Dictionary or not _has_only_keys(value, _LINK_FAILURE_FIELDS):
		return {}
	if not value.get("provider") is String or not value.get("code") is String:
		return {}
	var provider := String(value["provider"])
	var code := String(value["code"])
	if not provider in PROVIDERS or not _is_error_code(code):
		return {}
	return {"provider": provider, "code": code}


func _validate_api(api: RefCounted) -> String:
	if api == null:
		return "invalid_api"
	for method: String in [
		"get_motd",
		"get_users_me_sign_in_methods",
		"delete_users_me_sign_in_methods_sso_provider",
	]:
		if not api.has_method(method):
			return "invalid_api"
	return ""


func _validate_ws_api(ws_api: RefCounted) -> String:
	if ws_api == null:
		return "invalid_ws_api"
	for method: String in [
		"on_account_identity_linked",
		"on_account_identity_link_failed",
		"on_motd",
		"off_event",
	]:
		if not ws_api.has_method(method):
			return "invalid_ws_api"
	return ""


func _detach_handlers(ws_api: RefCounted, linked: Callable, failed: Callable, motd: Callable) -> void:
	if ws_api == null:
		return
	if linked.is_valid():
		ws_api.off_event("account.identity.linked", linked)
	if failed.is_valid():
		ws_api.off_event("account.identity.link.failed", failed)
	if motd.is_valid():
		ws_api.off_event("motd", motd)


func _request_failure(error: RestError) -> Dictionary:
	return _failure(error.code if _is_error_code(error.code) else "request_failed", error)


func _failure(code: String, detail: Variant = null) -> Dictionary:
	return {"ok": false, "error": code, "detail": _copy(detail)}


static func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value


## Shared public URL policy for host-owned presentation actions.
static func is_secure_web_url(url: String) -> bool:
	return _is_secure_web_url(url)


static func _has_only_keys(value: Dictionary, allowed: Array) -> bool:
	for key: Variant in value:
		if not key is String or not key in allowed:
			return false
	return true


static func _is_uuid(value: String) -> bool:
	if value.length() != 36:
		return false
	for index in value.length():
		if index in [8, 13, 18, 23]:
			if value[index] != "-":
				return false
		elif not value[index].to_lower() in "0123456789abcdef":
			return false
	return true


static func _is_datetime(value: String) -> bool:
	if value.length() < 20:
		return false
	if value[4] != "-" or value[7] != "-" or value[10] != "T":
		return false
	if value[13] != ":" or value[16] != ":":
		return false
	for span: String in [
		value.substr(0, 4), value.substr(5, 2), value.substr(8, 2),
		value.substr(11, 2), value.substr(14, 2), value.substr(17, 2),
	]:
		if not _is_ascii_digits(span):
			return false
	var zone_index := 19
	if value[zone_index] == ".":
		zone_index += 1
		var fraction_start := zone_index
		while zone_index < value.length() and value[zone_index] in "0123456789":
			zone_index += 1
		if zone_index == fraction_start:
			return false
	if zone_index >= value.length():
		return false
	if value[zone_index] == "Z":
		if zone_index != value.length() - 1:
			return false
	elif value[zone_index] in "+-":
		if value.length() - zone_index != 6 or value[zone_index + 3] != ":":
			return false
		var offset_hour := value.substr(zone_index + 1, 2)
		var offset_minute := value.substr(zone_index + 4, 2)
		if not _is_ascii_digits(offset_hour) or not _is_ascii_digits(offset_minute):
			return false
		if offset_hour.to_int() > 23 or offset_minute.to_int() > 59:
			return false
	else:
		return false
	var year := value.substr(0, 4).to_int()
	var month := value.substr(5, 2).to_int()
	var day := value.substr(8, 2).to_int()
	var hour := value.substr(11, 2).to_int()
	var minute := value.substr(14, 2).to_int()
	var second := value.substr(17, 2).to_int()
	if year <= 0 or month < 1 or month > 12:
		return false
	if hour > 23 or minute > 59 or second > 59:
		return false
	var days := [31, 28 if not _is_leap_year(year) else 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return day >= 1 and day <= days[month - 1]


static func _is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


static func _is_error_code(value: String) -> bool:
	if value.is_empty() or value.length() > 128 or not value[0] in "abcdefghijklmnopqrstuvwxyz":
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true


static func _is_ascii_digits(value: String) -> bool:
	if value.is_empty():
		return false
	for character: String in value:
		if not character in "0123456789":
			return false
	return true


static func _is_secure_web_url(url: String) -> bool:
	if url != url.strip_edges() or url.left(8).to_lower() != "https://" or _has_control(url):
		return false
	var remainder := url.substr(8)
	var authority_end := remainder.length()
	for separator: String in ["/", "?", "#"]:
		var found := remainder.find(separator)
		if found >= 0:
			authority_end = mini(authority_end, found)
	var authority := remainder.substr(0, authority_end)
	if authority.is_empty() or authority.contains("@") or authority.contains("\\"):
		return false
	var host := authority
	var port := ""
	var port_declared := false
	if authority.begins_with("["):
		var bracket := authority.find("]")
		if bracket <= 1:
			return false
		host = authority.substr(1, bracket - 1)
		if not _is_ipv6_literal(host):
			return false
		if authority.length() > bracket + 1:
			if authority[bracket + 1] != ":":
				return false
			port_declared = true
			port = authority.substr(bracket + 2)
	else:
		var colon := authority.rfind(":")
		if colon >= 0:
			port_declared = true
			host = authority.substr(0, colon)
			port = authority.substr(colon + 1)
		if not _is_dns_or_ipv4_host(host):
			return false
	if port_declared and (
		port.is_empty() or not port.is_valid_int() or port.to_int() < 1 or port.to_int() > 65535
	):
		return false
	return true


static func _is_dns_or_ipv4_host(host: String) -> bool:
	if host.is_empty() or host.length() > 253 or host.begins_with(".") or host.ends_with("."):
		return false
	var numeric := true
	for character: String in host:
		if not character in "0123456789.":
			numeric = false
			break
	if numeric:
		return host.is_valid_ip_address()
	for label: String in host.split(".", true):
		if label.is_empty() or label.length() > 63 or label.begins_with("-") or label.ends_with("-"):
			return false
		for character: String in label:
			if not character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789-":
				return false
	return true


static func _is_ipv6_literal(host: String) -> bool:
	if not host.is_valid_ip_address() or not host.contains(":"):
		return false
	if host.contains(".") or host.contains(":::") or host.count("::") > 1:
		return false
	var groups := host.split(":", true)
	var nonempty := 0
	for group: String in groups:
		if group.is_empty():
			continue
		nonempty += 1
		if group.length() > 4:
			return false
		for character: String in group:
			if not character.to_lower() in "0123456789abcdef":
				return false
	return nonempty <= 7 if host.contains("::") else nonempty == 8


static func _has_control(value: String) -> bool:
	for index in value.length():
		var codepoint := value.unicode_at(index)
		if codepoint < 0x20 or codepoint == 0x7f:
			return true
	return false
