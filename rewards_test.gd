# Headless coverage of high-level Godot reward claims: uncertain retries reuse
# the claim id, final outcomes release it, stale player-session completions are
# invalidated, refusals are finite, and server grant/confirm use the right API.
extends SceneTree

const RestError := preload("res://addons/haiven/haiven_rest_error.gd")
const RestApi := preload("res://addons/haiven/haiven_rest_api.gd")
const PlayerAccess := preload("res://addons/haiven/haiven_player_access.gd")
const Rewards := preload("res://addons/haiven/haiven_rewards.gd")


class MemoryStore:
	extends RefCounted
	var document := ""

	func load() -> String:
		return document

	func save(text: String) -> void:
		document = text


class FakeHandoff:
	extends RefCounted
	signal completed(credential: Dictionary)


class FakeTransport:
	extends RefCounted
	var responses: Array[Variant] = []
	var sent: Array[Dictionary] = []
	var before_reply: Callable

	func next(response: Variant, callback: Callable = Callable()) -> void:
		responses.append(response)
		before_reply = callback

	func _reply() -> Variant:
		if before_reply.is_valid():
			var callback := before_reply
			before_reply = Callable()
			callback.call()
		return responses.pop_front()

	func request(method: String, path: String, body: Variant, content_type: String) -> Variant:
		sent.append({
			"method": method,
			"path": path,
			"body": body.duplicate(true) if body is Dictionary or body is Array else body,
			"content_type": content_type,
		})
		return _reply()


var failures: Array[String] = []
var checks := 0
var _ids := 0


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)


func next_id() -> String:
	_ids += 1
	return "claim-%d" % _ids


func recorded(claim_id: String, confirmation: String = "client_reported", reward_ref: String = "hat") -> Dictionary:
	return {
		"claimId": claim_id,
		"claimedAt": "2026-10-14T00:00:00Z",
		"confirmation": confirmation,
		"integrationId": "game-1",
		"rewardRef": reward_ref,
	}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var transport := FakeTransport.new()
	var api := RestApi.new(transport.request)
	var rewards := Rewards.new(api, "game-1", next_id)
	var claimed: Array[RefCounted] = []
	rewards.claimed.connect(func(outcome: RefCounted) -> void: claimed.append(outcome))

	transport.next({"access": true, "basis": "free", "permanent": true, "refundHold": false})
	var access: Variant = await PlayerAccess.game(api, 42)
	check("game access delegates to the generated route",
		access.get("access") == true and transport.sent[-1]["path"] == "/games/42/access")
	transport.next(null)
	check("a successful no-body game access reply remains null", await PlayerAccess.game(api, 42) == null)
	var open_access_error := RestError.new(503, {"code": "auth_backend_changed"})
	transport.next(open_access_error)
	check("game access preserves an open REST error unchanged",
		await PlayerAccess.game(api, 42) == open_access_error and open_access_error.code == "auth_backend_changed")
	var statuses := {
		"eligible": false,
		"statuses": [
			{"code": "founder", "tier": "gold"},
			{"code": "recognised_later", "tier": "one"},
		],
	}
	check("founder status is independent of subscriber eligibility",
		PlayerAccess.founder_status(statuses).get("tier") == "gold" and statuses["eligible"] == false)
	check("unknown player status codes remain findable verbatim",
		PlayerAccess.find_status(statuses, "recognised_later").get("code") == "recognised_later")

	transport.next({"eligible": true, "basis": "subscription"})
	var eligibility: Variant = await rewards.eligibility()
	check("eligibility delegates to the generated API",
		eligibility.get("eligible") == true
		and transport.sent[-1]["method"] == "GET"
		and transport.sent[-1]["path"] == "/users/me/rewards/eligibility")

	transport.next(RestError.new(0, null, "connection reset"))
	var lost: RefCounted = await rewards.claim("hat")
	check("a transport failure is retryable", lost.result == Rewards.ClaimResult.FAILED and lost.retryable)
	check("the first attempt mints and keeps a claim id", rewards.pending("hat") == "claim-1")
	check("a claim carries its integration and reward",
		transport.sent[-1]["path"] == "/users/me/rewards/claims"
		and transport.sent[-1]["body"] == {
			"claimId": "claim-1", "integrationId": "game-1", "rewardRef": "hat"})

	transport.next(RestError.new(503))
	var down: RefCounted = await rewards.claim("hat")
	check("a server failure is retryable under the same id",
		down.retryable and transport.sent[-1]["body"]["claimId"] == "claim-1")

	transport.next({"unexpected": true})
	var unreadable: RefCounted = await rewards.claim("hat")
	check("a 2xx without a claim stays uncertain",
		unreadable.retryable and rewards.pending("hat") == "claim-1")

	transport.next(RestError.new(201, {"code": "sdk_invalid_response"}, "bad JSON", false))
	var undecodable: RefCounted = await rewards.claim("hat")
	check("an undecodable 2xx stays uncertain and keeps its claim id",
		undecodable.result == Rewards.ClaimResult.FAILED and undecodable.retryable
		and undecodable.error_code == "sdk_invalid_response"
		and transport.sent[-1]["body"]["claimId"] == "claim-1"
		and rewards.pending("hat") == "claim-1")

	transport.next(recorded("claim-1"))
	var accepted: RefCounted = await rewards.claim("hat")
	check("the replay after an undecodable 2xx reuses the same claim id",
		transport.sent[-1]["body"]["claimId"] == "claim-1")
	check("a retry records the claim", accepted.succeeded() and accepted.claim["claimId"] == "claim-1")
	check("client confirmation is finite", accepted.confirmation == Rewards.Confirmation.CLIENT_REPORTED)
	check("a final result releases the pending id", rewards.pending("hat") == "")
	check("a current recorded claim emits claimed once", claimed.size() == 1 and claimed[0] == accepted)

	transport.next(recorded("claim-2", "server_confirmed"))
	var next: RefCounted = await rewards.claim("hat")
	check("the next claim mints a new id and reads server confirmation",
		transport.sent[-1]["body"]["claimId"] == "claim-2"
		and next.confirmation == Rewards.Confirmation.SERVER_CONFIRMED)

	transport.next(recorded("claim-2", "notarised"))
	var refreshed: RefCounted = await rewards.refresh(recorded("claim-2"))
	check("an unknown confirmation is never server-confirmed",
		refreshed.confirmation == Rewards.Confirmation.UNRECOGNIZED)
	check("a refreshed recorded claim emits claimed", claimed.size() == 3 and claimed[-1] == refreshed)

	var clear_on_claimed: Callable = func(_outcome: RefCounted) -> void: rewards.clear()
	rewards.claimed.connect(clear_on_claimed)
	transport.next(recorded("claim-2", "server_confirmed"))
	var cleared_refresh: RefCounted = await rewards.refresh(recorded("claim-2"))
	check("clear from a refresh callback invalidates the awaiting result",
		cleared_refresh.result == Rewards.ClaimResult.SESSION_CHANGED)
	rewards.claimed.disconnect(clear_on_claimed)

	var cases := [
		[403, "reward_not_eligible", Rewards.ClaimResult.NOT_ELIGIBLE],
		[409, "reward_already_claimed", Rewards.ClaimResult.ALREADY_CLAIMED],
		[409, "reward_claim_conflict", Rewards.ClaimResult.CLAIM_CONFLICT],
		[409, "refund_in_progress", Rewards.ClaimResult.REFUND_IN_PROGRESS],
		[404, "not_found", Rewards.ClaimResult.NOT_FOUND],
	]
	for row: Array in cases:
		transport.next(RestError.new(row[0], {"code": row[1]}))
		var refused: RefCounted = await rewards.claim("boots")
		check("%s is a finite final refusal" % row[1],
			refused.result == row[2] and refused.error_code == row[1]
			and refused.status_code == row[0] and not refused.retryable)
		check("%s releases its claim id" % row[1], rewards.pending("boots") == "")

	transport.next(RestError.new(409, "{\"code\":\"resource_already_exists\"}"))
	var unknown: RefCounted = await rewards.claim("boots")
	check("an unlisted 409 is a final failure that preserves its code",
		unknown.result == Rewards.ClaimResult.FAILED
		and unknown.error_code == "resource_already_exists" and not unknown.retryable)

	transport.next(recorded("stale-1"), rewards.clear)
	var stale: RefCounted = await rewards.claim("scarf")
	check("clear invalidates a completion from the previous player",
		stale.result == Rewards.ClaimResult.SESSION_CHANGED and stale.error_code == "session_changed")
	check("an invalidated completion does not emit claimed", claimed.size() == 4)
	check("clear forgets the old claim id", rewards.pending("scarf") == "")

	transport.next(recorded("grant-1", "server_confirmed"))
	var granted: RefCounted = await Rewards.grant(api, "user-1", "cape", "grant-1")
	check("a server grant uses the grant operation and payload",
		granted.succeeded()
		and transport.sent[-1]["path"] == "/integrations/rewards/claims"
		and transport.sent[-1]["body"] == {
			"claimId": "grant-1", "rewardRef": "cape", "userId": "user-1"})

	transport.next(recorded("claim/1", "server_confirmed"))
	var confirmed: RefCounted = await Rewards.confirm(api, "claim/1")
	check("a server confirmation delegates the claim id",
		confirmed.succeeded()
		and transport.sent[-1]["path"] == "/integrations/rewards/claims/claim%2F1/confirm")

	var formatted := Rewards.format_uuid_v7(
		0x0192f3a4b5c6,
		PackedByteArray([0xff, 0x12, 0xff, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0]),
	)
	check("UUIDv7 carries its time, version, and variant",
		formatted == "0192f3a4-b5c6-7f12-bf34-56789abcdef0")
	var minted := Rewards.new_uuid_v7()
	check("the default claim id is a UUIDv7", minted.length() == 36 and minted[14] == "7")
	check("short UUID entropy is rejected safely in release exports",
		Rewards.format_uuid_v7(0, PackedByteArray([1, 2, 3])) == "")
	var invalid_rewards := Rewards.new(null, "")
	var invalid_eligibility: Variant = await invalid_rewards.eligibility()
	check("invalid eligibility configuration is a finite local refusal",
		invalid_eligibility is RestError and not invalid_eligibility.is_retryable()
		and invalid_eligibility.code == "invalid_configuration")
	var invalid_claim: RefCounted = await invalid_rewards.claim("")
	check("invalid runtime reward configuration fails finitely",
		invalid_claim.result == Rewards.ClaimResult.FAILED
		and invalid_claim.error_code == "invalid_configuration")

	var store := MemoryStore.new()
	# A lambda assignment does not write the outer local, so the counter lives in an array.
	var deferred_ids := [0]
	var deferred_id := func() -> String:
		deferred_ids[0] += 1
		return "saved-%d" % deferred_ids[0]
	var deferred := Rewards.new(api, "game-1", deferred_id, store)
	var settled: Array[RefCounted] = []
	var deferred_claimed: Array[RefCounted] = []
	deferred.settled.connect(func(outcome: RefCounted) -> void: settled.append(outcome))
	deferred.claimed.connect(func(outcome: RefCounted) -> void: deferred_claimed.append(outcome))
	var sent_before := transport.sent.size()
	var saved: Dictionary = deferred.save_claim("hat")
	check("save does not post and keeps a claim id",
		transport.sent.size() == sent_before and saved.get("claimId") == "saved-1")
	check("a second save reuses the claim id", deferred.save_claim("hat").get("claimId") == "saved-1")
	check("a saved claim is not pending", deferred.pending("hat") == "")
	check("the document keeps the claim id and reward",
		store.document.contains("saved-1") and store.document.contains("hat"))
	var restarted := Rewards.new(api, "game-1", deferred_id, store)
	check("a restart reuses the saved id",
		restarted.save_claim("hat").get("claimId") == "saved-1" and deferred_ids[0] == 1)
	deferred.clear()
	check("sign-out keeps a saved intent",
		deferred.saved_claims().size() == 1
		and deferred.saved_claims()[0]["claimId"] == "saved-1"
		and deferred.pending("hat") == "")

	transport.next(RestError.new(0, null, "offline"))
	var offline_batch: Array = await deferred.submit_saved()
	var offline: RefCounted = offline_batch[0]
	check("a transport failure keeps the saved id",
		offline.result == Rewards.ClaimResult.FAILED and offline.retryable
		and deferred.saved_claims()[0]["claimId"] == "saved-1"
		and transport.sent[-1]["body"]["claimId"] == "saved-1")
	check("a failed submit is settled and is not loot",
		settled.size() == 1 and deferred_claimed.is_empty())

	transport.next(RestError.new(403, {"code": "reward_not_eligible"}))
	var refused_batch: Array = await deferred.submit_saved()
	var refused_saved: RefCounted = refused_batch[0]
	check("a refusal releases the saved id and is not loot",
		refused_saved.result == Rewards.ClaimResult.NOT_ELIGIBLE
		and deferred.saved_claims().is_empty()
		and deferred_claimed.is_empty()
		and settled.size() == 2)

	var cape: Dictionary = deferred.save_claim("cape")
	check("the next save mints a new id", cape.get("claimId") == "saved-2" and deferred_ids[0] == 2)

	var quoted_store := MemoryStore.new()
	var quoted := Rewards.new(api, "game-1", deferred_id, quoted_store)
	quoted.save_claim("hat\"cape")
	var quoted_again := Rewards.new(api, "game-1", deferred_id, quoted_store)
	check("a quoted reward ref round-trips without a new id",
		quoted_again.saved_claims()[0]["rewardRef"] == "hat\"cape" and deferred_ids[0] == 3)

	var broken := MemoryStore.new()
	broken.document = "{"
	var ignored := Rewards.new(api, "game-1", deferred_id, broken)
	check("corrupt json does not invent a saved claim",
		ignored.saved_claims().is_empty() and deferred_ids[0] == 3)

	var duplicated := MemoryStore.new()
	duplicated.document = (
		"[{\"claimId\":\"first\",\"integrationId\":\"game-1\",\"rewardRef\":\"hat\"},"
		+ "{\"claimId\":\"second\",\"integrationId\":\"game-1\",\"rewardRef\":\"hat\"}]"
	)
	var first_wins := Rewards.new(api, "game-1", deferred_id, duplicated)
	check("the first saved id for a reward wins",
		first_wins.saved_claims().size() == 1
		and first_wins.saved_claims()[0]["claimId"] == "first"
		and deferred_ids[0] == 3)

	check("a reward ref past 128 code points is not saved",
		deferred.save_claim("x".repeat(129)).is_empty()
		and deferred.saved_claims().size() == 1
		and deferred_ids[0] == 3)

	transport.next(recorded("saved-2", "client_reported", "cape"))
	var handoff := FakeHandoff.new()
	deferred.follow_handoff(handoff)
	var listeners: Array = handoff.completed.get_connections()
	check("follow listens for handoff completion", listeners.size() == 1)
	await listeners[0]["callable"].call({"access_token": "token"})
	check("handoff submits the saved claim id and that is the loot signal",
		deferred_claimed.size() == 1
		and deferred_claimed[0].claim["claimId"] == "saved-2"
		and deferred.saved_claims().is_empty()
		and transport.sent[-1]["path"] == "/users/me/rewards/claims"
		and transport.sent[-1]["body"]["claimId"] == "saved-2")

	_report()


func _report() -> void:
	if failures.is_empty():
		print("ok   GDScript rewards")
		print("HAIVEN_TEST_PASS rewards %d" % checks)
		quit(0)
		return
	for failure in failures:
		print("FAIL ", failure)
	quit(1)
