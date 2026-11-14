## Production HTTPRequest transport for [HaivenRestApi].
##
## Add this node to the scene tree before making requests, then inject
## [method request] and [method url] into [HaivenRestApi]. A fresh HTTPRequest
## node is used for each in-flight call because HTTPRequest itself only permits
## one request at a time.
class_name HaivenHttpTransport
extends Node

const RestError := preload("haiven_rest_error.gd")
const Protocol := preload("haiven_protocol.gd")

const DEFAULT_TIMEOUT_SECONDS := 10.0
const DEFAULT_BODY_SIZE_LIMIT := 8 * 1024 * 1024
const DEFAULT_MAX_CONCURRENT := 8

const _SDK_INVALID_CONFIGURATION := "sdk_invalid_configuration"
const _SDK_INVALID_REQUEST := "sdk_invalid_request"
const _SDK_INVALID_RESPONSE := "sdk_invalid_response"
const _SDK_REQUEST_CANCELLED := "sdk_request_cancelled"
const _SDK_CONCURRENCY_LIMIT := "sdk_concurrency_limit"

const _METHODS := {
	"GET": HTTPClient.METHOD_GET,
	"POST": HTTPClient.METHOD_POST,
	"PUT": HTTPClient.METHOD_PUT,
	"PATCH": HTTPClient.METHOD_PATCH,
	"DELETE": HTTPClient.METHOD_DELETE,
}


class RequestState:
	extends RefCounted

	signal settled(value: Variant)

	var http: HTTPRequest
	var done := false


var _base_url := ""
var _app_id := ""
var _token_source := Callable()
var _timeout_seconds := DEFAULT_TIMEOUT_SECONDS
var _body_size_limit := DEFAULT_BODY_SIZE_LIMIT
var _max_concurrent := DEFAULT_MAX_CONCURRENT
var _allow_insecure_loopback := false
var _configuration_error := ""
var _active: Dictionary = {}


func _init(
	base_url: String,
	app_id: String = "",
	token_source: Callable = Callable(),
	options: Dictionary = {},
) -> void:
	_app_id = app_id
	_token_source = token_source
	_read_options(options)
	if _configuration_error.is_empty() and _has_header_control(_app_id):
		_set_configuration_error("The Haiven app id contains a forbidden header character.")
	if _configuration_error.is_empty():
		_base_url = _validated_base_url(base_url)


## Sends one generated REST operation and resolves to its decoded JSON body,
## null for an empty success, or a [HaivenRestError].
func request(method: String, path: String, body: Variant, content_type: String) -> Variant:
	if not is_configured():
		return _local_error(_SDK_INVALID_CONFIGURATION, _configuration_error)
	if not is_inside_tree():
		return _local_error(
			_SDK_INVALID_CONFIGURATION,
			"HaivenHttpTransport must be inside the scene tree before requesting.",
		)
	if not _METHODS.has(method):
		return _local_error(_SDK_INVALID_REQUEST, "Unsupported HTTP method: %s." % method)
	if not _is_safe_path(path):
		return _local_error(_SDK_INVALID_REQUEST, "The request path is not a safe relative API path.")
	if _active.size() >= _max_concurrent:
		return _local_error(
			_SDK_CONCURRENCY_LIMIT,
			"The Haiven HTTP concurrency limit (%d) was reached." % _max_concurrent,
		)

	var encoded := _encode_body(body, content_type)
	if encoded.error is RestError:
		return encoded.error

	var headers := PackedStringArray(["Accept: application/json", "X-Haiven-SDK: godot/0.0.0"])  # x-release-please-version
	if not _app_id.is_empty():
		headers.append("X-Haiven-App-ID: %s" % _app_id)
	if _token_source.is_valid():
		var token: Variant = _token_source.call()
		if not token is String:
			return _local_error(_SDK_INVALID_CONFIGURATION, "The token source must return a String.")
		if _has_header_control(token):
			return _local_error(
				_SDK_INVALID_CONFIGURATION,
				"The Haiven access token contains a forbidden header character.",
			)
		if not token.is_empty():
			headers.append("Authorization: Bearer %s" % token)
	if body != null:
		headers.append("Content-Type: %s" % content_type)

	var state := RequestState.new()
	var http := HTTPRequest.new()
	state.http = http
	http.timeout = _timeout_seconds
	http.body_size_limit = _body_size_limit
	http.max_redirects = 0
	http.accept_gzip = true
	http.use_threads = false
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	_active[state] = true
	http.request_completed.connect(_on_request_completed.bind(state), CONNECT_ONE_SHOT)
	var start_error := http.request(
		_base_url + path,
		headers,
		_METHODS[method],
		encoded.data,
	)
	if start_error != OK:
		# No caller is awaiting the signal yet, so return this synchronous
		# failure directly instead of emitting a signal that would be missed.
		state.done = true
		_active.erase(state)
		remove_child(http)
		http.free()
		return _local_error(
			_SDK_INVALID_REQUEST,
			"HTTPRequest could not start (%d)." % start_error,
		)
	return await state.settled


## Builds the absolute URL for an operation that must be opened by a browser.
## Invalid paths are reported and resolve to an empty String because generated
## navigation operations return String rather than HaivenRestError.
func url(path: String) -> String:
	if not is_configured():
		push_error(_configuration_error)
		return ""
	if not _is_safe_path(path):
		push_error("The navigation path is not a safe relative API path.")
		return ""
	return _base_url + path


func is_configured() -> bool:
	return _configuration_error.is_empty() and not _base_url.is_empty()


func configuration_error() -> String:
	return _configuration_error


## Cancels every in-flight request and settles each waiter exactly once.
func cancel_all() -> void:
	for state: RequestState in _active.keys().duplicate():
		if state.http != null:
			state.http.cancel_request()
		_settle(
			state,
			_local_error(_SDK_REQUEST_CANCELLED, "The Haiven HTTP request was cancelled."),
		)


func _exit_tree() -> void:
	cancel_all()


func _on_request_completed(
	result: int,
	response_code: int,
	_response_headers: PackedStringArray,
	body: PackedByteArray,
	state: RequestState,
) -> void:
	if state.done:
		return
	var text := body.get_string_from_utf8()
	if text.to_utf8_buffer() != body:
		_settle(
			state,
			RestError.new(
				response_code,
				{"code": _SDK_INVALID_RESPONSE},
				"The Haiven HTTP response body is not valid UTF-8.",
				false,
			),
		)
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_settle(state, _transport_error(result, response_code, text))
		return
	if response_code < 200 or response_code >= 300:
		_settle(state, _http_error(response_code, text))
		return
	if text.is_empty():
		_settle(state, null)
		return
	var unsafe_integer := Protocol.find_unsafe_integer(text)
	if not unsafe_integer.is_empty():
		_settle(
			state,
			RestError.new(
				response_code,
				{"code": Protocol.INTEGER_PRECISION_EXCEEDED},
				"The response contains an integer GDScript cannot represent safely: %s." % unsafe_integer,
				false,
			),
		)
		return
	var decoded := _parse_json(text)
	if not decoded.ok:
		_settle(
			state,
			RestError.new(
				response_code,
				{"code": _SDK_INVALID_RESPONSE},
				"The successful Haiven HTTP response is not valid JSON: %s" % decoded.detail,
				false,
			),
		)
		return
	_settle(state, decoded.value)


func _settle(state: RequestState, value: Variant) -> void:
	if state.done:
		return
	state.done = true
	_active.erase(state)
	var http := state.http
	state.http = null
	if http == null:
		state.settled.emit(value)
		return
	http.cancel_request()
	if http.is_inside_tree():
		# Settle only after the per-call node is gone. This makes cleanup part of
		# request completion rather than leaving a queued child behind when a
		# caller quits the tree immediately after its await resumes.
		http.tree_exited.connect(_emit_settled.bind(state, value), CONNECT_ONE_SHOT)
		http.queue_free()
		return
	http.free()
	state.settled.emit(value)


func _emit_settled(state: RequestState, value: Variant) -> void:
	state.settled.emit(value)


func _transport_error(result: int, status: int, text: String) -> RestError:
	var response_body: Variant = null
	if not text.is_empty():
		var unsafe_integer := Protocol.find_unsafe_integer(text)
		if not unsafe_integer.is_empty():
			return RestError.new(
				status if status > 0 else 0,
				{"code": Protocol.INTEGER_PRECISION_EXCEEDED},
				"The response contains an integer GDScript cannot represent safely: %s." % unsafe_integer,
				false,
			)
		var decoded := _parse_json(text)
		response_body = decoded.value if decoded.ok else text
	var retryable := result in [
		HTTPRequest.RESULT_CANT_CONNECT,
		HTTPRequest.RESULT_CANT_RESOLVE,
		HTTPRequest.RESULT_CONNECTION_ERROR,
		HTTPRequest.RESULT_NO_RESPONSE,
		HTTPRequest.RESULT_REQUEST_FAILED,
		HTTPRequest.RESULT_TIMEOUT,
	]
	return RestError.new(
		status if status > 0 else 0,
		response_body,
		"HTTPRequest failed (%d)." % result,
		retryable,
	)


func _http_error(status: int, text: String) -> RestError:
	if text.is_empty():
		return RestError.new(status)
	var unsafe_integer := Protocol.find_unsafe_integer(text)
	if not unsafe_integer.is_empty():
		return RestError.new(
			status,
			{"code": Protocol.INTEGER_PRECISION_EXCEEDED},
			"The error response contains an integer GDScript cannot represent safely: %s." % unsafe_integer,
			false,
		)
	var decoded := _parse_json(text)
	if not decoded.ok:
		return RestError.new(status, text)
	var detail := ""
	if decoded.value is Dictionary and decoded.value.get("message") is String:
		detail = decoded.value.message
	return RestError.new(status, decoded.value, detail)


func _parse_json(text: String) -> Dictionary:
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		return {"ok": false, "value": null, "detail": json.get_error_message()}
	return {"ok": true, "value": json.data, "detail": ""}


func _encode_body(body: Variant, content_type: String) -> Dictionary:
	if body == null:
		return {"error": null, "data": ""}
	if content_type == "application/json":
		if not _is_json_value(body):
			return {
				"error": _local_error(_SDK_INVALID_REQUEST, "The request body is not JSON-serializable."),
				"data": "",
			}
		var encoded := JSON.stringify(body)
		if not _parse_json(encoded).ok:
			return {
				"error": _local_error(_SDK_INVALID_REQUEST, "The request body is not valid JSON."),
				"data": "",
			}
		return {"error": null, "data": encoded}
	if content_type == "application/x-www-form-urlencoded":
		if not body is Dictionary:
			return {
				"error": _local_error(_SDK_INVALID_REQUEST, "A form request body must be a Dictionary."),
				"data": "",
			}
		var keys: Array = body.keys()
		for key: Variant in body:
			if not key is String or not body[key] is String:
				return {
					"error": _local_error(
						_SDK_INVALID_REQUEST,
						"Form request keys and values must be Strings.",
					),
					"data": "",
				}
		keys.sort()
		var pairs := PackedStringArray()
		for key: String in keys:
			pairs.append("%s=%s" % [key.uri_encode(), body[key].uri_encode()])
		return {"error": null, "data": "&".join(pairs)}
	return {
		"error": _local_error(_SDK_INVALID_REQUEST, "Unsupported request content type: %s." % content_type),
		"data": "",
	}


func _is_json_value(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	if value == null or value is bool or value is int or value is String:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for item: Variant in value:
			if not _is_json_value(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _is_json_value(value[key], depth + 1):
				return false
		return true
	return false


func _read_options(options: Dictionary) -> void:
	for key: Variant in options:
		if not key is String or key not in [
			"timeout_seconds",
			"body_size_limit",
			"max_concurrent_requests",
			"allow_insecure_loopback",
		]:
			_set_configuration_error("Unknown Haiven HTTP transport option: %s." % key)
			return

	var timeout: Variant = options.get("timeout_seconds", DEFAULT_TIMEOUT_SECONDS)
	if not (timeout is int or timeout is float) or timeout is bool or timeout <= 0.0:
		_set_configuration_error("timeout_seconds must be a positive number.")
		return
	_timeout_seconds = float(timeout)

	var body_limit: Variant = options.get("body_size_limit", DEFAULT_BODY_SIZE_LIMIT)
	if not body_limit is int or body_limit is bool or body_limit <= 0:
		_set_configuration_error("body_size_limit must be a positive integer.")
		return
	_body_size_limit = body_limit

	var concurrent: Variant = options.get("max_concurrent_requests", DEFAULT_MAX_CONCURRENT)
	if not concurrent is int or concurrent is bool or concurrent <= 0:
		_set_configuration_error("max_concurrent_requests must be a positive integer.")
		return
	_max_concurrent = concurrent

	var allow_loopback: Variant = options.get("allow_insecure_loopback", false)
	if not allow_loopback is bool:
		_set_configuration_error("allow_insecure_loopback must be a bool.")
		return
	_allow_insecure_loopback = allow_loopback


func _validated_base_url(value: String) -> String:
	if value != value.strip_edges() or value.is_empty() or _has_control(value) or value.contains("\\"):
		_set_configuration_error("The Haiven API base URL is malformed.")
		return ""
	if value.contains("?") or value.contains("#"):
		_set_configuration_error("The Haiven API base URL must not contain a query or fragment.")
		return ""

	var scheme_end := value.find("://")
	if scheme_end <= 0:
		_set_configuration_error("The Haiven API base URL must be absolute.")
		return ""
	var scheme := value.left(scheme_end).to_lower()
	if scheme != "https" and scheme != "http":
		_set_configuration_error("The Haiven API base URL must use HTTPS.")
		return ""
	var remainder := value.substr(scheme_end + 3)
	var path_start := remainder.find("/")
	if path_start <= 0:
		_set_configuration_error("The Haiven API base URL must include its /v0 API root.")
		return ""
	var authority := remainder.left(path_start)
	var root_path := remainder.substr(path_start).rstrip("/")
	if authority.contains("@") or not _is_valid_authority(authority):
		_set_configuration_error("The Haiven API base URL has an invalid authority.")
		return ""
	if scheme == "http" and (not _allow_insecure_loopback or not _is_loopback_authority(authority)):
		_set_configuration_error("Plain HTTP is allowed only for opted-in loopback development servers.")
		return ""
	if not _is_safe_path(root_path) or not root_path.ends_with("/v0"):
		_set_configuration_error("The Haiven API base URL must end at a safe /v0 API root.")
		return ""
	return "%s://%s%s" % [scheme, authority, root_path]


func _is_valid_authority(authority: String) -> bool:
	var host := authority
	var port := ""
	var port_declared := false
	if authority.begins_with("["):
		var bracket := authority.find("]")
		if bracket <= 1:
			return false
		host = authority.substr(1, bracket - 1)
		if not host.is_valid_ip_address() or not host.contains(":"):
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
			host = authority.left(colon)
			port = authority.substr(colon + 1)
		if not _is_dns_or_ipv4_host(host):
			return false
	if port_declared and (not _is_ascii_digits(port) or port.to_int() < 1 or port.to_int() > 65535):
		return false
	return true


func _is_loopback_authority(authority: String) -> bool:
	var lower := authority.to_lower()
	for host: String in ["localhost", "127.0.0.1", "[::1]"]:
		if lower == host:
			return true
		if lower.begins_with(host + ":"):
			return _is_ascii_digits(lower.substr(host.length() + 1))
	return false


func _is_dns_or_ipv4_host(host: String) -> bool:
	if host.is_empty() or host.length() > 253 or host.begins_with(".") or host.ends_with("."):
		return false
	var numeric := true
	for character: String in host:
		if character not in "0123456789.":
			numeric = false
			break
	if numeric:
		return host.is_valid_ip_address()
	for label: String in host.split(".", true):
		if label.is_empty() or label.length() > 63 or label.begins_with("-") or label.ends_with("-"):
			return false
		for character: String in label:
			if character.to_lower() not in "abcdefghijklmnopqrstuvwxyz0123456789-":
				return false
	return true


func _is_safe_path(path: String) -> bool:
	if path.is_empty() or not path.begins_with("/") or path.begins_with("//"):
		return false
	if _has_control(path) or path.contains("\\") or path.contains("#") or path.contains("://"):
		return false
	for index in path.length():
		if path[index] == "%":
			if index + 2 >= path.length() or not _is_hex(path[index + 1]) or not _is_hex(path[index + 2]):
				return false
	var route := path.get_slice("?", 0)
	for segment: String in route.split("/", true):
		# Only normalize bytes that affect path structure. String.uri_decode()
		# deliberately is not used as the security boundary here: Godot's URL
		# decoder does not consistently fold percent-encoded ASCII dot segments.
		var decoded := segment.to_lower().replace("%2e", ".").replace("%2f", "/").replace("%5c", "/")
		# Encoded slashes are legitimate inside generated path parameters. Check
		# the decoded subsegments for traversal without rejecting that encoding.
		for decoded_segment: String in decoded.split("/", true):
			if decoded_segment == "." or decoded_segment == "..":
				return false
	return true


func _local_error(code: String, detail: String) -> RestError:
	return RestError.new(0, {"code": code, "message": detail}, detail, false)


func _set_configuration_error(detail: String) -> void:
	if _configuration_error.is_empty():
		_configuration_error = detail


static func _has_header_control(value: String) -> bool:
	for index in value.length():
		var codepoint := value.unicode_at(index)
		if codepoint < 0x20 or codepoint == 0x7f:
			return true
	return false


static func _has_control(value: String) -> bool:
	for index in value.length():
		var codepoint := value.unicode_at(index)
		if codepoint <= 0x20 or codepoint == 0x7f:
			return true
	return false


static func _is_ascii_digits(value: String) -> bool:
	if value.is_empty():
		return false
	for character: String in value:
		if character not in "0123456789":
			return false
	return true


static func _is_hex(character: String) -> bool:
	return character.to_lower() in "0123456789abcdef"
