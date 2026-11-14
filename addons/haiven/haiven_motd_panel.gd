## Editor-authored Message of the Day presentation for Godot games.
##
## The scene owns layout and theme hooks. This script owns only the normalized
## loading/absent/present/failure projection and delegates navigation to the host.
class_name HaivenMotdPanel
extends PanelContainer

const MotdProjection := preload("haiven_motd_projection.gd")
const FAILURE_COPY := MotdProjection.FAILURE_COPY
const FALLBACK_TITLE := MotdProjection.FALLBACK_TITLE
const Identity := preload("haiven_identity.gd")

signal state_changed(state: Dictionary)
signal action_requested(url: String)
signal diagnostic(code: String)

@onready var _status_label: Label = %Status
@onready var _message: VBoxContainer = %Message
@onready var _title: Label = %Title
@onready var _body: Label = %Body
@onready var _action: Button = %Action
@onready var _dismiss: Button = %Dismiss
@onready var _retry: Button = %Retry

var _identity: RefCounted
var _model := MotdProjection.new()
var _next_request_id := 0


func _ready() -> void:
	_render()


## Binds a HaivenIdentity-shaped facade without starting authenticated work.
func bind(identity: RefCounted) -> Dictionary:
	if identity == _identity:
		return {"ok": true}
	var invalid := _validate_identity(identity)
	if invalid != "":
		diagnostic.emit(invalid)
		return {"ok": false, "error": invalid}
	_disconnect_identity()
	_identity = identity
	_model.reset()
	_identity.connect("motd_changed", _on_motd_changed)
	var snapshot: Variant = _identity.get("current_motd")
	if snapshot is Dictionary and not snapshot.is_empty():
		_apply({"type": "realtime_present", "message": snapshot})
	else:
		_set_absent()
	return {"ok": true}


func unbind() -> void:
	_disconnect_identity()
	_identity = null
	_model.reset()
	_after_transition()


## Loads the public MOTD. No access token or authenticated session is consulted.
## A signal delivered while REST is in flight owns the newer revision, so the
## older completion cannot replace it with either content or an error.
func load_public() -> Dictionary:
	if _identity == null:
		_set_failure()
		return {"ok": false, "error": "identity_not_bound"}
	_next_request_id += 1
	var request_id := "panel-%d" % _next_request_id
	_apply({"type": "load_started", "requestId": request_id})
	var target := _identity
	var result: Variant = await target.call("load_motd")
	if target != _identity:
		return result if result is Dictionary else {"ok": false, "error": "superseded"}
	if not result is Dictionary or not result.get("ok") is bool:
		_apply({"type": "rest_failure", "requestId": request_id, "privateDetail": "invalid_result"})
		return {"ok": false, "error": "invalid_motd_result"}
	if not bool(result["ok"]):
		_apply({"type": "rest_failure", "requestId": request_id, "privateDetail": "request_failed"})
		return result
	var message: Variant = result.get("motd")
	if message == null:
		_apply({"type": "rest_absent", "requestId": request_id, "httpStatus": 204})
	elif message is Dictionary:
		_apply({"type": "rest_present", "requestId": request_id, "message": message})
	else:
		_apply({"type": "rest_failure", "requestId": request_id, "privateDetail": "invalid_message"})
		return {"ok": false, "error": "invalid_motd_result"}
	return result


## Suppresses this message id for the panel's lifetime. The identity facade also
## records the dismissal so a late REST response cannot restore the same id.
func dismiss() -> bool:
	var before := _model.view_state()
	if before.get("status") != "present":
		return false
	_apply({"type": "dismiss"})
	if _identity != null:
		_identity.call("dismiss_motd")
	return true


## Defensive snapshot matching the cross-engine presentation contract.
func view_state() -> Dictionary:
	return _model.view_state()


func _set_absent() -> void:
	_apply({"type": "realtime_clear"})


func _set_failure() -> void:
	_next_request_id += 1
	var request_id := "panel-%d" % _next_request_id
	_apply({"type": "load_started", "requestId": request_id})
	_apply({"type": "rest_failure", "requestId": request_id, "privateDetail": "invalid_state"})


func _apply(event: Dictionary) -> void:
	var before := _model.view_state()
	_model.apply(event)
	if before == _model.view_state():
		return
	_after_transition()


func _after_transition() -> void:
	_render()
	state_changed.emit(view_state())


func _render() -> void:
	if not is_node_ready():
		return
	var projection := _model.view_state()
	var status := String(projection.get("status", "absent"))
	var surface_visible := bool(projection.get("visible", false))
	visible = surface_visible
	var has_message := status == "present" and projection.get("message") is Dictionary
	_message.visible = has_message
	_retry.visible = status == "failure"
	match status:
		"loading":
			_status_label.text = "Loading message of the day…"
		"failure":
			_status_label.text = FAILURE_COPY
		_:
			_status_label.text = ""
	if not has_message:
		_title.text = ""
		_body.text = ""
		_action.visible = false
		_action.set_meta("url", "")
		return
	var message: Dictionary = projection["message"]
	_title.text = String(message["title"])
	_body.text = String(message["body"])
	var url := String(message.get("url", ""))
	_action.set_meta("url", url)
	_action.visible = url != ""


func _disconnect_identity() -> void:
	if _identity != null and is_instance_valid(_identity):
		var callback := Callable(self, "_on_motd_changed")
		if _identity.is_connected("motd_changed", callback):
			_identity.disconnect("motd_changed", callback)


func _validate_identity(identity: RefCounted) -> String:
	if identity == null:
		return "identity_required"
	for method: String in ["load_motd", "dismiss_motd"]:
		if not identity.has_method(method):
			return "identity_missing_%s" % method
	if not identity.has_signal("motd_changed"):
		return "identity_missing_motd_changed"
	for property: Dictionary in identity.get_property_list():
		if String(property.get("name", "")) == "current_motd":
			return ""
	return "identity_missing_current_motd"


func _on_motd_changed(message: Variant) -> void:
	if message == null:
		_apply({"type": "realtime_clear"})
	elif message is Dictionary:
		_apply({"type": "realtime_present", "message": message})
	else:
		_set_failure()


func _on_action_pressed() -> void:
	var projection := _model.view_state()
	if projection.get("status") != "present":
		return
	var url := String(projection.get("message", {}).get("url", ""))
	if _is_secure_absolute_url(url):
		action_requested.emit(url)


func _on_dismiss_pressed() -> void:
	dismiss()


func _on_retry_pressed() -> void:
	load_public()


static func _is_secure_absolute_url(url: String) -> bool:
	return Identity.is_secure_web_url(url)
