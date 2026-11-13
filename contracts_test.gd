# Headless coverage that the generated contract surface ships in the addon.
# The generator writes addons/haiven/haiven_contracts.gd directly,
# because the addon is copied into a game project whole.
extends SceneTree

const Contracts := preload("res://addons/haiven/haiven_contracts.gd")

var failures: Array[String] = []
var checks := 0


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	check("contract ids are published", Contracts.WS_SERVER_REPLY_V0_ID == "https://schemas.haiven.gg/ws-server-reply/v0.json")

	var event: Variant = Contracts.decode_contract(JSON.parse_string('{"type":"chat.message","requestId":""}'), ["type"])
	check("a payload decodes to its Dictionary", event is Dictionary)
	check("and an absent success stays absent", event is Dictionary and not event.has("success"))

	var encoded := Contracts.encode_contract({"type": "ping", "requestId": "rq-1"})
	check("encoding round-trips", JSON.parse_string(encoded) == {"type": "ping", "requestId": "rq-1"})

	if failures.is_empty():
		print("ok   GDScript generated contracts")
		print("HAIVEN_TEST_PASS contracts %d" % checks)
		quit(0)
		return
	for failure in failures:
		print("FAIL ", failure)
	quit(1)
