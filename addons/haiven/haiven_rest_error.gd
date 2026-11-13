## A failed Haiven REST request returned by a GDScript transport.
##
## GDScript has no catchable exceptions, so transports return this value for a
## non-2xx response or a network failure. Generated REST methods pass it through
## unchanged. High-level clients use [member status_code] and [member code] for
## finite decisions and keep [member message] for diagnostics only.
class_name HaivenRestError
extends RefCounted

var status_code: int
var body: Variant
var code: String
var message: String
var retryable_override: Variant


func _init(
	status: int,
	response_body: Variant = null,
	detail: String = "",
	can_retry: Variant = null,
) -> void:
	status_code = status
	body = response_body
	code = _code_of(response_body)
	retryable_override = can_retry
	message = detail if detail != "" else (
		"haiven: the request failed before receiving an HTTP response"
		if status == 0 else "haiven: the request failed with HTTP %d" % status
	)


## Whether repeating an idempotent request may succeed.
func is_retryable() -> bool:
	if retryable_override is bool:
		return retryable_override
	return status_code == 0 or status_code == 429 or status_code >= 500


static func _code_of(response_body: Variant) -> String:
	var decoded: Variant = response_body
	if response_body is String and response_body != "":
		# JSON.parse_string logs an engine error for an ordinary non-JSON HTTP
		# error body. Parse explicitly so text error responses remain quiet while
		# still exposing a structured server code when one exists.
		var json := JSON.new()
		if json.parse(response_body) != OK:
			return ""
		decoded = json.data
	if decoded is Dictionary and decoded.get("code") is String:
		return decoded["code"]
	return ""
