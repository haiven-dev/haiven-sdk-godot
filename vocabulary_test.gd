# Headless proof that the installed addon exposes open vocabulary helpers.
extends SceneTree

const ErrorCode := preload("res://addons/haiven/haiven_error_code.gd")
const MessageType := preload("res://addons/haiven/haiven_message_type.gd")
const WsErrorCode := preload("res://addons/haiven/haiven_ws_error_code.gd")

var failures: Array[String] = []
var checks := 0


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	check("REST constant preserves its wire value", ErrorCode.RATE_LIMITED == "rate_limited")
	check("message constant preserves its dotted wire value", MessageType.AUTH_EXPIRED == "auth.expired")
	check("WebSocket constant preserves its wire value", WsErrorCode.EXPIRED_TOKEN == "expired_token")
	check("REST registered value is recognised", ErrorCode.is_recognised(ErrorCode.RATE_LIMITED))
	check("message registered value is recognised", MessageType.is_recognised(MessageType.AUTH_EXPIRED))
	check("WebSocket registered value is recognised", WsErrorCode.is_recognised(WsErrorCode.EXPIRED_TOKEN))

	var minted_later: String = "minted_after_this_build"
	check("an unknown value remains a String", minted_later is String)
	check("an unknown value compares by its wire string", minted_later == "minted_after_this_build")
	check("REST recognition does not accept an unknown value", not ErrorCode.is_recognised(minted_later))
	check("message recognition does not accept an unknown value", not MessageType.is_recognised(minted_later))
	check("WebSocket recognition does not accept an unknown value", not WsErrorCode.is_recognised(minted_later))
	check("recognition never changes an unknown value", minted_later == "minted_after_this_build")

	if failures.is_empty():
		print("ok   GDScript open vocabularies")
		print("HAIVEN_TEST_PASS vocabulary %d" % checks)
		quit(0)
		return
	for failure in failures:
		print("FAIL ", failure)
	quit(1)
