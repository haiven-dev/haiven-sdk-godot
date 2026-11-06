# Headless coverage for the generated REST operations. The transport is a
# recording Callable, so this measures the generated half alone: the method,
# path, query, body, and content type each operation hands the transport, and
# that a coroutine transport is awaited rather than returned as a state object.
extends SceneTree

const RestApi := preload("res://addons/haiven/haiven_rest_api.gd")

var failures: Array[String] = []
var checks := 0
var _requests: Array[Dictionary] = []
var _response: Variant = null


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)


func _initialize() -> void:
	call_deferred("_run")


# A coroutine, like a transport built on HTTPRequest's request_completed signal.
func _request(method: String, path: String, body: Variant, content_type: String) -> Variant:
	_requests.append({"method": method, "path": path, "body": body, "content_type": content_type})
	await process_frame
	return _response


func _url(path: String) -> String:
	return "https://api.example.test" + path


func _last() -> Dictionary:
	return _requests[-1] if not _requests.is_empty() else {}


func _run() -> void:
	var api := RestApi.new(_request, _url)

	_response = {"projectionVersion": 7, "entitlements": [{"kind": "founder", "state": "active"}]}
	var entitlements: Variant = await api.get_users_me_entitlements()
	check("the entitlement read is a GET", _last().get("method") == "GET")
	check("of the account entitlements path", _last().get("path") == "/users/me/entitlements")
	check("without a body", _last().get("body") == null and _last().get("content_type") == "")
	check("a coroutine transport is awaited", entitlements is Dictionary)
	check("and its decoded body is returned", entitlements is Dictionary and entitlements.get("projectionVersion") == 7)

	_response = null
	await api.get_chat_channels_channel_id_messages("chan/1 x", null, "thread")
	check("the old third argument still binds to parentMessageId",
		_last().get("path") == "/chat/channels/chan%2F1%20x/messages?parentMessageId=thread")
	await api.get_chat_channels_channel_id_messages("chan/1 x", "m&2", null, 25, "m-after")
	check("path parameters are percent-encoded",
		_last().get("path") == "/chat/channels/chan%2F1%20x/messages?beforeMessageId=m%262&afterMessageId=m-after&limit=25")

	await api.get_apps(null, ["rpg", "co op"], null, true)
	check("array queries repeat and booleans are lower case",
		_last().get("path") == "/apps?tag=rpg&tag=co%20op&earlyAccess=true")

	var login := {"username": "player", "password": "pw"}
	await api.post_auth_login(login)
	check("JSON bodies are declared as JSON", _last().get("content_type") == "application/json")
	check("and handed over unencoded", _last().get("body") == login)

	await api.post_auth_handoff_exchange({"code": "c"})
	check("the handoff exchange is declared as a form",
		_last().get("content_type") == "application/x-www-form-urlencoded")

	var sent := _requests.size()
	var sso: String = api.get_auth_sso_provider_url("google", "challenge", "S256")
	check("SSO initiation is a URL, not a request", _requests.size() == sent)
	check("resolved by the url Callable with its PKCE challenge",
		sso == "https://api.example.test/auth/sso/google?code_challenge=challenge&code_challenge_method=S256")
	check("the callback is a URL too",
		api.get_auth_callback_url("code", "st ate") == "https://api.example.test/auth/callback?code=code&state=st%20ate")

	_report()


func _report() -> void:
	if failures.is_empty():
		print("ok   GDScript generated REST operations")
		print("HAIVEN_TEST_PASS rest %d" % checks)
		quit(0)
		return
	for failure in failures:
		print("FAIL ", failure)
	quit(1)
