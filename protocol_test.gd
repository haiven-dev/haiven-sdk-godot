# Does the outbound envelope's discriminant survive the crossing into GDScript?
#
# The two server frames are told apart by the PRESENCE of `success`, not its
# value (F10). C# needed `bool?` and an explicit presence check to express that,
# because a non-nullable bool maps an absent field to false and makes every event
# read as a failed reply. GDScript is dynamically typed, so the prediction was
# that presence survives for free — this measures it rather than assuming it.

extends SceneTree

var failures: Array[String] = []
var checks: int = 0


# GDScript has no bool() constructor, so truthiness has to be exercised through
# a branch rather than a cast.
func truthy(value: Variant) -> bool:
	if value:
		return true
	return false


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)


# The parse under test. `has()` asks the dictionary what it contains, which is
# the GDScript equivalent of C#'s TryGetProperty.
func is_reply(frame: Dictionary) -> bool:
	return frame.has("success")


func _initialize() -> void:
	var accepted: Dictionary = JSON.parse_string(
		'{"type":"pong","requestId":"rq-1","success":true}'
	)
	check("an accepted reply is a reply", is_reply(accepted))
	check("and reports its outcome", accepted["success"] == true)

	# The case a value-based discriminant destroys: a refused request is still a
	# reply, and success:false must not read as "no success field".
	var refused: Dictionary = JSON.parse_string(
		'{"type":"chat.send","requestId":"rq-2","success":false,"error":"rate_limited"}'
	)
	check("a refused reply is still a reply", is_reply(refused))
	check("with the outcome it reported", refused["success"] == false)
	check("and a code rather than prose", refused["error"] == "rate_limited")

	var event: Dictionary = JSON.parse_string('{"type":"chat.message","payload":{"id":"m1"}}')
	check("an event is not a reply", not is_reply(event))
	check("because the field is absent", not event.has("success"))
	check("an event carries a payload", event.has("payload"))

	# Absent and empty are both on the wire and both mean something. A
	# server-initiated reply sends requestId "" -- present, empty -- while an
	# event omits the field entirely.
	var announced: Dictionary = JSON.parse_string(
		'{"type":"auth.expired","requestId":"","success":false}'
	)
	check("a server-initiated reply has an empty id", announced["requestId"] == "")
	check("an event has no id at all", not event.has("requestId"))

	# The trap this file exists to record. `get` with no default answers null for
	# an absent key, and null == false is FALSE in GDScript -- but a caller that
	# writes `if frame.get("success"):` gets the same falsy branch for "absent"
	# and for "present and false", which is exactly the C# collapse in a language
	# that was supposed to be immune to it.
	check("absent reads as null, not false", event.get("success") == null)
	check("and null is not false", event.get("success") != false)
	check(
		"but truthiness collapses them, which is the trap",
		not truthy(event.get("success")) and not truthy(refused["success"])
	)

	if failures.size() > 0:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)
		return

	print("ok   GDScript envelope discriminant")
	print("HAIVEN_TEST_PASS protocol %d" % checks)
	quit(0)
