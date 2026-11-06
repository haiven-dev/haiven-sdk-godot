## Engine-independent Message of the Day presentation state machine.
##
## HaivenMotdPanel delegates every REST/realtime/dismiss transition here, and
## the exact cross-engine fixture corpus drives this same class in Godot CI.
class_name HaivenMotdProjection
extends RefCounted

const FALLBACK_TITLE := "Message of the day"
const FAILURE_COPY := "Unable to load message of the day."
const Identity := preload("haiven_identity.gd")

var _state: Dictionary
var _active_request_id := ""


func _init(initial: Variant = null) -> void:
	reset(initial)


func reset(initial: Variant = null) -> void:
	_active_request_id = ""
	if initial is Dictionary:
		_state = initial.duplicate(true)
	else:
		_state = _projection(0, "absent", false, null, null, null)


func view_state() -> Dictionary:
	return _state.duplicate(true)


## Applies one event from spec/presentation/motd-v1.json. Unknown or stale
## events are finite no-ops; invalid messages become the reviewed failure state.
func apply(event: Dictionary) -> Dictionary:
	var event_type := String(event.get("type", ""))
	match event_type:
		"load_started":
			var request_id := String(event.get("requestId", ""))
			if request_id.is_empty():
				return view_state()
			_active_request_id = request_id
			_commit("loading", true, null, null)
		"rest_absent":
			if not _consume_request(event):
				return view_state()
			_commit("absent", false, null, null)
		"rest_present":
			if not _consume_request(event):
				return view_state()
			_accept_message(event.get("message"), true)
		"rest_failure":
			if not _consume_request(event):
				return view_state()
			_commit("failure", true, null, FAILURE_COPY)
		"realtime_present":
			var before := _state.duplicate(true)
			_accept_message(event.get("message"))
			if before != _state:
				_active_request_id = ""
		"realtime_clear":
			_active_request_id = ""
			_commit("absent", false, null, null)
		"dismiss":
			if _state.get("status") != "present":
				return view_state()
			var current: Variant = _state.get("message")
			if not current is Dictionary:
				return view_state()
			var dismissed_id := String(current.get("id", ""))
			if dismissed_id.is_empty():
				return view_state()
			_commit("absent", false, null, null, dismissed_id, true)
		_:
			return view_state()
	return view_state()


func _consume_request(event: Dictionary) -> bool:
	var request_id := String(event.get("requestId", ""))
	if request_id.is_empty() or request_id != _active_request_id:
		return false
	_active_request_id = ""
	return true


func _accept_message(value: Variant, settle_suppressed := false) -> void:
	if not value is Dictionary:
		_commit("failure", true, null, FAILURE_COPY)
		return
	var message_id := String(value.get("id", ""))
	var body := String(value.get("body", ""))
	if message_id.is_empty() or body.is_empty():
		_commit("failure", true, null, FAILURE_COPY)
		return
	var dismissed: Variant = _state.get("dismissedId")
	if dismissed != null and String(dismissed) == message_id:
		if settle_suppressed:
			_commit("absent", false, null, null)
		return
	var current: Variant = _state.get("message")
	if (_state.get("status") == "present" and current is Dictionary
			and String(current.get("id", "")) == message_id):
		return
	var title_value: Variant = value.get("title")
	var title := "" if title_value == null else String(title_value).strip_edges()
	if title.is_empty():
		title = FALLBACK_TITLE
	var message := {"id": message_id, "title": title, "body": body}
	var url := String(value.get("url", ""))
	if Identity.is_secure_web_url(url):
		message["url"] = url
	_commit("present", true, message, null)


func _commit(
	status: String,
	visible: bool,
	message: Variant,
	error: Variant,
	dismissed_override: Variant = null,
	use_dismissed_override := false,
) -> void:
	var dismissed: Variant = dismissed_override if use_dismissed_override else _state.get("dismissedId")
	var candidate := _projection(0, status, visible, message, error, dismissed)
	var comparable := _state.duplicate(true)
	comparable.erase("revision")
	var next_comparable := candidate.duplicate(true)
	next_comparable.erase("revision")
	if comparable == next_comparable:
		return
	candidate["revision"] = int(_state.get("revision", 0)) + 1
	_state = candidate


static func _projection(
	revision: int,
	status: String,
	visible: bool,
	message: Variant,
	error: Variant,
	dismissed: Variant,
) -> Dictionary:
	return {
		"revision": revision,
		"status": status,
		"visible": visible,
		"message": message.duplicate(true) if message is Dictionary else null,
		"error": error,
		"dismissedId": dismissed,
	}
