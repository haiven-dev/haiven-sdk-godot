## Ready-to-theme account-linking and Message of the Day modal for Godot games.
##
## Bind a [HaivenIdentity], add this control to the scene tree, and call
## [method open]. The modal never handles OAuth itself: link buttons delegate to
## the facade's browser-context adapter so popup ordering and cookies remain at
## the host boundary. The default controls inherit the game's Theme.
class_name HaivenIdentityModal
extends Control

const PROVIDERS := ["google", "apple"]
const _REQUIRED_METHODS := [
	"begin_link",
	"unlink",
	"dismiss_motd",
	"load_motd",
	"load_sign_in_methods",
]
const _REQUIRED_SIGNALS := [
	"motd_changed",
	"sign_in_methods_changed",
	"identity_linked",
	"identity_link_failed",
]

signal closed
signal motd_action_requested(url: String)
signal diagnostic(code: String, detail: Variant)

var _identity: RefCounted
var _binding_generation := 0
var _busy := false
var _busy_provider := ""
var _linked_providers: Dictionary = {}

var _panel: PanelContainer
var _motd_section: VBoxContainer
var _motd_title: Label
var _motd_body: Label
var _motd_action: Button
var _motd_dismiss: Button
var _provider_buttons: Dictionary = {}
var _provider_details: Dictionary = {}
var _status: Label


func _init(identity: RefCounted = null) -> void:
	visible = false
	_identity = identity


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_controls()
	if _identity != null:
		var invalid := _validate_identity(_identity)
		if invalid == "":
			_connect_identity(_identity)
		else:
			_identity = null
			diagnostic.emit(invalid, null)
	_render_identity_state()


func _exit_tree() -> void:
	_disconnect_identity(_identity)


## Atomically replaces the facade that drives this modal. An invalid facade is
## rejected without disturbing the current binding.
func bind(identity: RefCounted) -> Dictionary:
	if identity == _identity:
		return {"ok": true}
	var invalid := _validate_identity(identity)
	if invalid != "":
		diagnostic.emit(invalid, identity)
		return {"ok": false, "error": invalid}
	var previous := _identity
	_binding_generation += 1
	_busy = false
	_busy_provider = ""
	_identity = identity
	if is_node_ready():
		_disconnect_identity(previous)
		_connect_identity(identity)
		_render_identity_state()
	return {"ok": true}


## Detaches account state without freeing either object.
func unbind() -> void:
	var previous := _identity
	_binding_generation += 1
	_busy = false
	_busy_provider = ""
	_identity = null
	if is_node_ready():
		_disconnect_identity(previous)
		_render_motd(null)
		_render_methods({})
		_set_status("")


## Shows the modal using the facade's current snapshots without network I/O.
func open() -> void:
	visible = true
	if is_node_ready():
		_render_identity_state()
		var first: Button = _provider_buttons.get("google")
		if first != null:
			first.grab_focus()


## Hides the modal. In-flight operations may finish, but a later [method bind]
## or [method unbind] generation prevents them from changing replacement state.
func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Refreshes MOTD and account methods through the bound facade. Both reads are
## attempted so a public MOTD failure never hides usable signed-in account UI.
func refresh() -> Dictionary:
	if _identity == null:
		return _failure("identity_not_bound")
	var generation := _binding_generation
	var target := _identity
	_set_status("Refreshing…")
	var motd_result: Variant = await target.call("load_motd")
	if generation != _binding_generation or target != _identity:
		return _failure("binding_changed")
	var methods_result: Variant = await target.call("load_sign_in_methods")
	if generation != _binding_generation or target != _identity:
		return _failure("binding_changed")
	if not motd_result is Dictionary or not methods_result is Dictionary:
		_set_status("Could not refresh account details.")
		return _failure("invalid_refresh_response")
	var failures: Array[String] = []
	if not bool(motd_result.get("ok", false)):
		failures.append(String(motd_result.get("error", "motd_failed")))
	if not bool(methods_result.get("ok", false)):
		failures.append(String(methods_result.get("error", "methods_failed")))
	if failures.is_empty():
		_set_status("")
		return {"ok": true}
	_set_status("Could not refresh: %s" % ", ".join(failures))
	return {"ok": false, "error": "refresh_failed", "failures": failures}


## Begins a provider link and exposes finite progress/error text in the modal.
func begin_link(provider: String) -> Dictionary:
	var normalized := provider.to_lower().strip_edges()
	if not normalized in PROVIDERS:
		return _operation_failure("invalid_provider", normalized)
	if _identity == null:
		return _operation_failure("identity_not_bound", normalized)
	if _busy:
		return _overlapping_operation_failure(normalized)
	var generation := _binding_generation
	var target := _identity
	_set_busy(normalized, true)
	_set_status("Opening %s…" % _provider_name(normalized))
	var response: Variant = await target.call("begin_link", normalized)
	if generation != _binding_generation or target != _identity:
		return _failure("binding_changed")
	_set_busy(normalized, false)
	if not response is Dictionary or not response.get("ok") is bool:
		return _operation_failure("invalid_link_response", normalized, response)
	if not bool(response["ok"]):
		return _operation_failure(String(response.get("error", "link_failed")), normalized)
	_set_status("Finish connecting %s in the browser." % _provider_name(normalized))
	return {"ok": true, "provider": normalized}


## Unlinks a connected provider through the facade's authenticated REST path.
func unlink(provider: String) -> Dictionary:
	var normalized := provider.to_lower().strip_edges()
	if not normalized in PROVIDERS:
		return _operation_failure("invalid_provider", normalized)
	if _identity == null:
		return _operation_failure("identity_not_bound", normalized)
	if _busy:
		return _overlapping_operation_failure(normalized)
	var generation := _binding_generation
	var target := _identity
	_set_busy(normalized, true)
	_set_status("Disconnecting %s…" % _provider_name(normalized))
	var response: Variant = await target.call("unlink", normalized)
	if generation != _binding_generation or target != _identity:
		return _failure("binding_changed")
	_set_busy(normalized, false)
	if not response is Dictionary or not response.get("ok") is bool:
		return _operation_failure("invalid_unlink_response", normalized, response)
	if not bool(response["ok"]):
		return _operation_failure(String(response.get("error", "unlink_failed")), normalized)
	_set_status("%s disconnected." % _provider_name(normalized))
	return {"ok": true, "provider": normalized}


## A defensive, test- and accessibility-friendly description of visible state.
func view_state() -> Dictionary:
	var providers := {}
	for provider: String in PROVIDERS:
		var button: Button = _provider_buttons.get(provider)
		var detail: Label = _provider_details.get(provider)
		providers[provider] = {
			"action": button.text if button != null else "",
			"disabled": button.disabled if button != null else true,
			"detail": detail.text if detail != null else "",
		}
	return {
		"visible": visible,
		"motd_visible": _motd_section.visible if _motd_section != null else false,
		"motd_title": _motd_title.text if _motd_title != null else "",
		"motd_body": _motd_body.text if _motd_body != null else "",
		"motd_action": _motd_action.visible if _motd_action != null else false,
		"providers": providers,
		"status": _status.text if _status != null else "",
	}


func _build_controls() -> void:
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.0, 0.0, 0.0, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "IdentityPanel"
	_panel.custom_minimum_size = Vector2(520.0, 0.0)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	_motd_section = VBoxContainer.new()
	_motd_section.name = "Motd"
	_motd_section.add_theme_constant_override("separation", 8)
	content.add_child(_motd_section)
	_motd_title = Label.new()
	_motd_title.name = "MotdTitle"
	_motd_title.add_theme_font_size_override("font_size", 22)
	_motd_section.add_child(_motd_title)
	_motd_body = Label.new()
	_motd_body.name = "MotdBody"
	_motd_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_motd_section.add_child(_motd_body)
	var motd_actions := HBoxContainer.new()
	_motd_section.add_child(motd_actions)
	_motd_action = Button.new()
	_motd_action.name = "MotdAction"
	_motd_action.text = "Learn more"
	_motd_action.pressed.connect(_on_motd_action_pressed)
	motd_actions.add_child(_motd_action)
	_motd_dismiss = Button.new()
	_motd_dismiss.name = "MotdDismiss"
	_motd_dismiss.text = "Dismiss"
	_motd_dismiss.pressed.connect(_on_motd_dismiss_pressed)
	motd_actions.add_child(_motd_dismiss)

	var separator := HSeparator.new()
	content.add_child(separator)
	var title := Label.new()
	title.text = "Connect your Haiven account"
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)
	var explanation := Label.new()
	explanation.text = "Link an account to keep progress and rewards across games."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(explanation)

	for provider: String in PROVIDERS:
		var row := HBoxContainer.new()
		row.name = "%sRow" % _provider_name(provider)
		content.add_child(row)
		var provider_label := Label.new()
		provider_label.text = _provider_name(provider)
		provider_label.custom_minimum_size.x = 88.0
		row.add_child(provider_label)
		var detail := Label.new()
		detail.name = "%sDetail" % _provider_name(provider)
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.text = "Not connected"
		row.add_child(detail)
		_provider_details[provider] = detail
		var action := Button.new()
		action.name = "%sAction" % _provider_name(provider)
		action.text = "Connect"
		action.pressed.connect(_on_provider_pressed.bind(provider))
		row.add_child(action)
		_provider_buttons[provider] = action

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.accessibility_name = "Account link status"
	content.add_child(_status)
	var close_button := Button.new()
	close_button.name = "Close"
	close_button.text = "Close"
	close_button.pressed.connect(close)
	content.add_child(close_button)


func _connect_identity(identity: RefCounted) -> void:
	identity.connect("motd_changed", _on_motd_changed)
	identity.connect("sign_in_methods_changed", _on_methods_changed)
	identity.connect("identity_linked", _on_identity_linked)
	identity.connect("identity_link_failed", _on_identity_link_failed)


func _disconnect_identity(identity: RefCounted) -> void:
	if identity == null or not is_instance_valid(identity):
		return
	var connections := {
		"motd_changed": _on_motd_changed,
		"sign_in_methods_changed": _on_methods_changed,
		"identity_linked": _on_identity_linked,
		"identity_link_failed": _on_identity_link_failed,
	}
	for signal_name: String in connections:
		var callback: Callable = connections[signal_name]
		if identity.is_connected(signal_name, callback):
			identity.disconnect(signal_name, callback)


func _render_identity_state() -> void:
	if _identity == null:
		_render_motd(null)
		_render_methods({})
		return
	_render_motd(_identity.get("current_motd"))
	var methods: Variant = _identity.get("current_sign_in_methods")
	_render_methods(methods if methods is Dictionary else {})


func _render_motd(message: Variant) -> void:
	if _motd_section == null:
		return
	if not message is Dictionary or message.is_empty():
		_motd_section.visible = false
		_motd_title.text = ""
		_motd_body.text = ""
		_motd_action.visible = false
		_motd_action.set_meta("url", "")
		return
	_motd_title.text = String(message.get("title", "Message from Haiven"))
	_motd_body.text = String(message.get("body", ""))
	var url := String(message.get("url", ""))
	_motd_action.set_meta("url", url)
	_motd_action.visible = url != ""
	_motd_section.visible = true


func _render_methods(methods: Dictionary) -> void:
	_linked_providers.clear()
	var identities: Variant = methods.get("identities", [])
	if identities is Array:
		for identity: Variant in identities:
			if not identity is Dictionary:
				continue
			var provider := String(identity.get("provider", ""))
			if provider in PROVIDERS:
				_linked_providers[provider] = String(identity.get("email", ""))
	for provider: String in PROVIDERS:
		var detail: Label = _provider_details.get(provider)
		var button: Button = _provider_buttons.get(provider)
		if detail == null or button == null:
			continue
		var linked := _linked_providers.has(provider)
		var email := String(_linked_providers.get(provider, ""))
		detail.text = email if linked and email != "" else "Connected" if linked else "Not connected"
		button.text = "Disconnect" if linked else "Connect"
		button.disabled = _busy


func _set_busy(provider: String, busy: bool) -> void:
	_busy = busy
	_busy_provider = provider if busy else ""
	for key: String in _provider_buttons:
		var button: Button = _provider_buttons[key]
		button.disabled = busy
		if busy and key == provider:
			button.text = "Working…"
		else:
			button.text = "Disconnect" if _linked_providers.has(key) else "Connect"


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _operation_failure(code: String, provider: String, detail: Variant = null) -> Dictionary:
	if _busy and _busy_provider == provider:
		_set_busy(provider, false)
	_set_status("Could not update %s (%s)." % [_provider_name(provider), code])
	diagnostic.emit(code, detail)
	return _failure(code, detail)


## Rejects a second click without changing the first operation's controls or
## progress text. In particular, this must not flow through _operation_failure:
## that helper releases the lock owned by the operation that just completed.
func _overlapping_operation_failure(provider: String) -> Dictionary:
	var detail := {"provider": provider, "activeProvider": _busy_provider}
	diagnostic.emit("operation_in_progress", detail.duplicate())
	return _failure("operation_in_progress", detail)


func _failure(code: String, detail: Variant = null) -> Dictionary:
	var result := {"ok": false, "error": code}
	if detail != null:
		result["detail"] = detail
	return result


func _validate_identity(identity: RefCounted) -> String:
	if identity == null:
		return "identity_required"
	for method: String in _REQUIRED_METHODS:
		if not identity.has_method(method):
			return "identity_missing_%s" % method
	for signal_name: String in _REQUIRED_SIGNALS:
		if not identity.has_signal(signal_name):
			return "identity_missing_%s" % signal_name
	var properties := {}
	for property: Dictionary in identity.get_property_list():
		properties[String(property.get("name", ""))] = true
	for property_name: String in ["current_motd", "current_sign_in_methods"]:
		if not properties.has(property_name):
			return "identity_missing_%s" % property_name
	return ""


func _provider_name(provider: String) -> String:
	return provider.capitalize() if provider != "" else "account"


func _on_provider_pressed(provider: String) -> void:
	if _linked_providers.has(provider):
		unlink(provider)
	else:
		begin_link(provider)


func _on_motd_changed(message: Variant) -> void:
	_render_motd(message)


func _on_methods_changed(methods: Dictionary) -> void:
	_render_methods(methods)


func _on_identity_linked(identity: Dictionary) -> void:
	var provider := String(identity.get("provider", ""))
	_set_status("%s connected." % _provider_name(provider))


func _on_identity_link_failed(failure: Dictionary) -> void:
	var provider := String(failure.get("provider", ""))
	var code := String(failure.get("code", "link_failed"))
	_set_status("Could not connect %s (%s)." % [_provider_name(provider), code])


func _on_motd_action_pressed() -> void:
	var url := String(_motd_action.get_meta("url", ""))
	if url != "":
		motd_action_requested.emit(url)


func _on_motd_dismiss_pressed() -> void:
	if _identity != null:
		_identity.call("dismiss_motd")


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
