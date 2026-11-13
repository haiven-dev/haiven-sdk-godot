## Offline example scene for the packaged Haiven identity modal.
##
## This scene deliberately uses an in-memory facade so it runs immediately after
## installing the addon. Replace OfflineIdentity with HaivenIdentity and a real
## browser-context adapter in a game; the modal wiring stays the same.
extends Control

const IdentityModal := preload("../haiven_identity_modal.gd")


class OfflineIdentity:
	extends RefCounted

	signal motd_changed(message: Variant)
	signal sign_in_methods_changed(methods: Dictionary)
	signal identity_linked(identity: Dictionary)
	signal identity_link_failed(failure: Dictionary)

	var current_motd: Variant = {
		"id": "00000000-0000-4000-8000-000000000117",
		"title": "Haiven offline sample",
		"body": "This Message of the Day came from the installed addon example.",
		"url": "https://docs.haiven.gg",
		"startsAt": "2026-10-14T00:00:00Z",
	}
	var current_sign_in_methods := {"hasPassword": false, "identities": []}


	func begin_link(provider: String) -> Dictionary:
		# A production adapter opens a popup before yielding and makes the SSO POST
		# in that same browser context. This offline sample only demonstrates the
		# event/UI boundary and labels that fact in the scene.
		call_deferred("_complete_link", provider)
		return {"ok": true, "provider": provider}


	func unlink(provider: String) -> Dictionary:
		var kept: Array = []
		for identity: Dictionary in current_sign_in_methods["identities"]:
			if identity["provider"] != provider:
				kept.append(identity.duplicate(true))
		current_sign_in_methods["identities"] = kept
		sign_in_methods_changed.emit(current_sign_in_methods.duplicate(true))
		return {"ok": true, "provider": provider}


	func dismiss_motd() -> void:
		current_motd = null
		motd_changed.emit(null)


	func load_motd() -> Dictionary:
		var snapshot: Variant = current_motd.duplicate(true) if current_motd is Dictionary else null
		motd_changed.emit(snapshot)
		return {"ok": true, "motd": snapshot}


	func load_sign_in_methods() -> Dictionary:
		var snapshot := current_sign_in_methods.duplicate(true)
		sign_in_methods_changed.emit(snapshot)
		return {"ok": true, "methods": snapshot}


	func _complete_link(provider: String) -> void:
		var identity := {"provider": provider, "email": "%s@example.test" % provider}
		current_sign_in_methods["identities"].append(identity.duplicate(true))
		sign_in_methods_changed.emit(current_sign_in_methods.duplicate(true))
		identity_linked.emit(identity.duplicate(true))


var identity_modal: Control
var offline_identity: RefCounted
@onready var motd_panel: PanelContainer = $Layout/HaivenMotdPanel
@onready var _activity: Label = $Layout/Activity


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_launcher()
	offline_identity = OfflineIdentity.new()
	motd_panel.bind(offline_identity)
	motd_panel.action_requested.connect(_on_motd_action_requested)
	motd_panel.load_public()
	identity_modal = IdentityModal.new(offline_identity)
	identity_modal.name = "HaivenIdentityModal"
	identity_modal.closed.connect(_on_modal_closed)
	identity_modal.motd_action_requested.connect(_on_motd_action_requested)
	identity_modal.diagnostic.connect(_on_diagnostic)
	add_child(identity_modal)
	identity_modal.open()


func activity_text() -> String:
	return _activity.text


func open_modal() -> void:
	identity_modal.open()
	_activity.text = "Opened the installed Haiven identity modal."


func _build_launcher() -> void:
	# Layout and controls are authored in the scene for editor inspection.
	$Layout/OpenAccount.pressed.connect(open_modal)


func _on_modal_closed() -> void:
	_activity.text = "Closed the Haiven identity modal."


func _on_motd_action_requested(url: String) -> void:
	# A game decides whether and how to navigate. The example stays offline.
	_activity.text = "MOTD action requested: %s" % url


func _on_diagnostic(code: String, _detail: Variant) -> void:
	_activity.text = "Haiven diagnostic: %s" % code
