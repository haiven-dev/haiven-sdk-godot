# The envelope, as GDScript sees it.
#
# The two outbound shapes are told apart by the PRESENCE of `success`, not its
# value (F10). `protocol_test.gd` measured what that costs here and found the
# trap dynamic typing was predicted to remove: `frame.get("success")` answers
# `null` for an absent key and `null` is falsy, so the natural spelling collapses
# absent and present-and-false — the same collapse a non-nullable `bool` causes
# in C#, in the language that was supposed to be immune.
#
# So classification lives in one place and asks `has()`. A binding that spreads
# this across call sites is one call site away from the collapse, and the trap is
# invisible at the site where it happens because it reads as ordinary GDScript.
class_name HaivenProtocol
extends RefCounted

const AUTH := "auth"
const AUTH_SUCCESS := "auth.success"
const AUTH_EXPIRED := "auth.expired"


## Whether a received frame answers something the client sent.
##
## `has()` and only `has()`. See the note above before changing this to
## anything that reads the value.
static func is_reply(frame: Dictionary) -> bool:
	return frame.has("success")


## Whether a reply reports success. Meaningless for an event; ask [method is_reply] first.
static func succeeded(frame: Dictionary) -> bool:
	return frame.get("success") == true


## Parses one text frame, or returns an empty Dictionary if it is not an object.
##
## A non-object is dropped rather than raised. The server does not send one, so
## a binding that raised here would convert a hypothetical into a crash in a
## shipped game, and an empty Dictionary classifies as an event with no type —
## which every caller already has to handle.
static func parse(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


## Builds a client frame. `payload` is omitted when null, matching the wire.
static func frame(type: String, request_id: String, payload: Variant = null) -> Dictionary:
	var built := {"type": type, "requestId": request_id}
	if payload != null:
		built["payload"] = payload
	return built
