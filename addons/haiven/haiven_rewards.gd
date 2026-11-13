## Subscriber rewards over [HaivenRestApi].
##
## A claim keeps its UUIDv7 while its result is uncertain. Retrying therefore
## cannot grant twice. Call [method clear] on logout or player replacement: a
## completion from the old player then returns [constant SESSION_CHANGED] and
## cannot be reported as the new player's result.
##
## [method save_claim] records `{claimId, rewardRef}` before the player links
## and does not post it. Pass a store as the fourth constructor argument to keep
## that id across launches; [FileStore] writes `user://haiven-reward-claims.json`.
## After the handoff, [method submit_saved] posts each intent on the user claim
## route under the saved id. Grant loot only when [method Outcome.succeeded] is
## true. [method clear] drops in-flight ids and leaves saved intents.
class_name HaivenRewards
extends RefCounted

const RestError := preload("haiven_rest_error.gd")

enum ClaimResult {
	CLAIMED,
	NOT_ELIGIBLE,
	ALREADY_CLAIMED,
	CLAIM_CONFLICT,
	REFUND_IN_PROGRESS,
	NOT_FOUND,
	FAILED,
	SESSION_CHANGED,
}

enum Confirmation {
	CLIENT_REPORTED,
	SERVER_CONFIRMED,
	UNRECOGNIZED,
}


## One completed claim, grant, confirmation, or refresh.
class Outcome:
	extends RefCounted
	var result: int
	var claim: Dictionary
	var confirmation: int
	var status_code: int
	var error_code: String
	var retryable: bool
	var error: Variant

	func _init(
		claim_result: int,
		recorded_claim: Dictionary = {},
		claim_confirmation: int = Confirmation.UNRECOGNIZED,
		status: int = 0,
		code: String = "",
		can_retry: bool = false,
		failure: Variant = null,
	) -> void:
		result = claim_result
		claim = recorded_claim
		confirmation = claim_confirmation
		status_code = status
		error_code = code
		retryable = can_retry
		error = failure

	func succeeded() -> bool:
		return result == ClaimResult.CLAIMED


## Emitted only for a recorded claim that still belongs to the current player
## session. This is the loot signal. The callback may call [method clear]; the
## awaiting caller then gets [constant SESSION_CHANGED], not a stale success.
##
## One claim can emit this more than once: [method refresh] re-emits a recorded
## claim, and overlapping [method claim] calls for one reward share one claim id
## and each emit on success. The server records the claim once. Grant loot at
## most once per [code]outcome.claim["claimId"][/code].
signal claimed(outcome: Outcome)

## Emitted for every submitted claim that still belongs to the current player,
## including a refusal. A refusal is not loot. [method save_claim] does not emit.
signal settled(outcome: Outcome)

var _api: RefCounted
var _integration_id: String
var _new_claim_id: Callable
var _store: Variant
var _pending_ids: Dictionary = {}
var _saved: Array = []
var _session_generation := 0
var _configuration_error := ""


## Writes the saved-intent document. The default path is under `user://`.
class FileStore:
	extends RefCounted
	var path: String

	func _init(file_path: String = "user://haiven-reward-claims.json") -> void:
		path = file_path

	func load() -> String:
		if not FileAccess.file_exists(path):
			return ""
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return ""
		var text := file.get_as_text()
		file.close()
		return text

	func save(document: String) -> void:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return
		file.store_string(document)
		file.close()


func _init(
	api: RefCounted,
	integration_id: String,
	new_claim_id: Callable = Callable(),
	store: Variant = null,
) -> void:
	_api = api
	_integration_id = integration_id
	_new_claim_id = new_claim_id if new_claim_id.is_valid() else new_uuid_v7
	_store = store
	if api == null:
		_configuration_error = "api is required"
	elif integration_id == "":
		_configuration_error = "integration_id is required"
	else:
		_load_saved()


## Whether the signed-in account may receive subscriber rewards.
func eligibility() -> Variant:
	if _configuration_error != "":
		return RestError.new(0, {"code": "invalid_configuration"}, _configuration_error, false)
	return await _api.get_users_me_rewards_eligibility()


## Claims one reward as client-reported, reusing the id of an uncertain attempt.
func claim(reward_ref: String) -> Outcome:
	if _configuration_error != "":
		return _invalid("invalid_configuration", _configuration_error)
	if reward_ref == "" or reward_ref.length() > 128:
		return _invalid("invalid_reward_ref", "reward_ref must be 1 to 128 Unicode code points")
	var generation := _session_generation
	var claim_id := str(_pending_ids.get(reward_ref, ""))
	if claim_id == "":
		claim_id = _saved_claim_id(reward_ref)
		if claim_id == "":
			claim_id = str(_new_claim_id.call())
			if claim_id == "":
				return _invalid("invalid_claim_id", "claim id generator returned an empty value", true)
		_pending_ids[reward_ref] = claim_id
	var outcome := await _settle(func() -> Variant:
		return await _api.post_users_me_rewards_claims({
			"claimId": claim_id,
			"integrationId": _integration_id,
			"rewardRef": reward_ref,
		})
	)
	if generation != _session_generation:
		return _session_changed()
	# Only the attempt that still owns this id may release it.
	if not outcome.retryable and _pending_ids.get(reward_ref) == claim_id:
		_pending_ids.erase(reward_ref)
	if not outcome.retryable:
		_release_saved(reward_ref, claim_id)
	_emit_settled(outcome, generation)
	if generation != _session_generation:
		return _session_changed()
	if outcome.succeeded():
		claimed.emit(outcome)
		if generation != _session_generation:
			return _session_changed()
	return outcome


## Reads a recorded claim's current confirmation without recording it twice.
func refresh(recorded_claim: Dictionary) -> Outcome:
	if _configuration_error != "":
		return _invalid("invalid_configuration", _configuration_error)
	var claim_id := str(recorded_claim.get("claimId", ""))
	var reward_ref := str(recorded_claim.get("rewardRef", ""))
	if claim_id == "" or reward_ref == "":
		return _invalid("invalid_recorded_claim", "a recorded claim is required")
	var generation := _session_generation
	var outcome := await _settle(func() -> Variant:
		return await _api.post_users_me_rewards_claims({
			"claimId": claim_id,
			"integrationId": _integration_id,
			"rewardRef": reward_ref,
		})
	)
	if generation != _session_generation:
		return _session_changed()
	_emit_settled(outcome, generation)
	if generation != _session_generation:
		return _session_changed()
	if outcome.succeeded():
		claimed.emit(outcome)
		if generation != _session_generation:
			return _session_changed()
	return outcome


## Records a claim intent before the player links. Reuses the id already saved
## or pending for this reward. Does not post, and does not report a claim.
func save_claim(reward_ref: String) -> Dictionary:
	if _configuration_error != "" or reward_ref == "" or reward_ref.length() > 128:
		return {}
	for item in _saved:
		if str(item.get("rewardRef", "")) == reward_ref:
			return (item as Dictionary).duplicate()
	var claim_id := str(_pending_ids.get(reward_ref, ""))
	if claim_id == "":
		claim_id = str(_new_claim_id.call())
		if claim_id == "":
			return {}
	var saved := {
		"claimId": claim_id,
		"integrationId": _integration_id,
		"rewardRef": reward_ref,
	}
	_saved.append(saved)
	_persist()
	return saved.duplicate()


## Saved intents in the order they were first recorded.
func saved_claims() -> Array:
	return _saved.duplicate(true)


## Posts every saved intent on the user claim route under the id [method save_claim]
## kept. A [constant SESSION_CHANGED] result stays in the returned array and the
## remaining intents are still submitted. Grant loot only for a succeeded outcome.
func submit_saved() -> Array:
	var reward_refs: Array[String] = []
	for item in _saved:
		reward_refs.append(str(item.get("rewardRef", "")))
	var outcomes: Array = []
	for reward_ref in reward_refs:
		if _saved_claim_id(reward_ref) == "":
			continue
		outcomes.append(await claim(reward_ref))
	return outcomes


## Submits saved intents when the handoff stores a credential.
func follow_handoff(handoff: Object) -> void:
	if handoff == null or not handoff.has_signal("completed"):
		return
	handoff.completed.connect(func(_credential: Dictionary) -> void:
		await submit_saved()
	)


## The claim id that the next attempt for this reward will reuse.
func pending(reward_ref: String) -> String:
	return str(_pending_ids.get(reward_ref, ""))


## Forgets uncertain claim ids because the signed-in player changed.
## Saved intents stay, so the next link submits the same claim id.
func clear() -> void:
	_pending_ids.clear()
	_session_generation += 1


## Grants a reward from a trusted game server. The API transport must add the
## integration key, which must never ship in a player client.
static func grant(server_api: RefCounted, user_id: String, reward_ref: String, claim_id: String) -> Outcome:
	if server_api == null or user_id == "" or reward_ref == "" or claim_id == "":
		return _invalid("invalid_grant", "server_api, user_id, reward_ref, and claim_id are required")
	return await _settle(func() -> Variant:
		return await server_api.post_integrations_rewards_claims({
			"claimId": claim_id,
			"rewardRef": reward_ref,
			"userId": user_id,
		})
	)


## Confirms a player-client claim from a trusted game server.
static func confirm(server_api: RefCounted, claim_id: String) -> Outcome:
	if server_api == null or claim_id == "":
		return _invalid("invalid_confirmation", "server_api and claim_id are required")
	return await _settle(func() -> Variant:
		return await server_api.post_integrations_rewards_claims_claim_id_confirm(claim_id)
	)


## A UUIDv7 (RFC 9562): Unix milliseconds, version 7, and secure random bits.
static func new_uuid_v7() -> String:
	return format_uuid_v7(
		int(Time.get_unix_time_from_system() * 1000.0),
		Crypto.new().generate_random_bytes(10),
	)


static func format_uuid_v7(unix_milliseconds: int, random: PackedByteArray) -> String:
	if random.size() < 10:
		return ""
	var bytes := PackedByteArray()
	bytes.resize(16)
	for index in range(6):
		bytes[index] = (unix_milliseconds >> (8 * (5 - index))) & 0xff
	bytes[6] = 0x70 | (random[0] & 0x0f)
	bytes[7] = random[1]
	bytes[8] = 0x80 | (random[2] & 0x3f)
	for index in range(3, 10):
		bytes[index + 6] = random[index]
	var encoded := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		encoded.substr(0, 8),
		encoded.substr(8, 4),
		encoded.substr(12, 4),
		encoded.substr(16, 4),
		encoded.substr(20),
	]


static func confirmation_of(value: Variant) -> int:
	match value:
		"client_reported":
			return Confirmation.CLIENT_REPORTED
		"server_confirmed":
			return Confirmation.SERVER_CONFIRMED
		_:
			return Confirmation.UNRECOGNIZED


## Classifies a transport or HTTP failure without branching on prose.
static func classify(error: Variant) -> Outcome:
	if not error is RestError:
		return Outcome.new(ClaimResult.FAILED, {}, Confirmation.UNRECOGNIZED, 0, "", true, error)
	var status: int = error.status_code
	var code: String = error.code
	var result := ClaimResult.FAILED
	if status == 403 and code == "reward_not_eligible":
		result = ClaimResult.NOT_ELIGIBLE
	elif status == 409 and code == "reward_already_claimed":
		result = ClaimResult.ALREADY_CLAIMED
	elif status == 409 and code == "reward_claim_conflict":
		result = ClaimResult.CLAIM_CONFLICT
	elif status == 409 and code == "refund_in_progress":
		result = ClaimResult.REFUND_IN_PROGRESS
	elif status == 404:
		result = ClaimResult.NOT_FOUND
	# A 2xx the transport could not decode (invalid UTF-8, malformed JSON, an
	# unsafe integer) means the server may already have recorded the claim, so
	# the outcome is uncertain: keep the id for a replay rather than releasing it.
	var accepted_unreadable := status >= 200 and status < 300
	return Outcome.new(
		result,
		{},
		Confirmation.UNRECOGNIZED,
		status,
		code,
		(accepted_unreadable or error.is_retryable()) if result == ClaimResult.FAILED else false,
		error,
	)


static func _settle(send: Callable) -> Outcome:
	var response: Variant = await send.call()
	if response is RestError:
		return classify(response)
	if not response is Dictionary or str(response.get("claimId", "")) == "":
		return Outcome.new(
			ClaimResult.FAILED,
			{},
			Confirmation.UNRECOGNIZED,
			0,
			"",
			true,
			"haiven: the reward reply carried no claim",
		)
	return Outcome.new(
		ClaimResult.CLAIMED,
		response,
		confirmation_of(response.get("confirmation")),
	)


static func _invalid(code: String, message: String, can_retry: bool = false) -> Outcome:
	return Outcome.new(
		ClaimResult.FAILED,
		{},
		Confirmation.UNRECOGNIZED,
		0,
		code,
		can_retry,
		message,
	)


static func _session_changed() -> Outcome:
	return Outcome.new(
		ClaimResult.SESSION_CHANGED,
		{},
		Confirmation.UNRECOGNIZED,
		0,
		"session_changed",
		false,
		"haiven: the reward response belongs to an invalidated player session",
	)


func _saved_claim_id(reward_ref: String) -> String:
	for item in _saved:
		if str(item.get("rewardRef", "")) == reward_ref:
			return str(item.get("claimId", ""))
	return ""


func _release_saved(reward_ref: String, claim_id: String) -> void:
	for index in range(_saved.size()):
		var item: Dictionary = _saved[index]
		if str(item.get("rewardRef", "")) == reward_ref and str(item.get("claimId", "")) == claim_id:
			_saved.remove_at(index)
			_persist()
			return


func _persist() -> void:
	if _store == null or not _store.has_method("save"):
		return
	_store.call("save", JSON.stringify(_saved))


func _json_string(value: Variant) -> bool:
	var kind := typeof(value)
	return kind == TYPE_STRING or kind == TYPE_STRING_NAME


func _load_saved() -> void:
	if _store == null or not _store.has_method("load"):
		return
	var raw: Variant = _store.call("load")
	if not raw is String or str(raw) == "":
		return
	var text := str(raw).strip_edges()
	# Godot logs an error for a failed parse, and the headless gate treats that
	# line as a failure. A document that is not an array is left unloaded.
	if not text.begins_with("["):
		return
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Array:
		return
	var loaded: Array = []
	for item in parsed:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = item
		if not _json_string(record.get("claimId")) or not _json_string(record.get("integrationId")) or not _json_string(record.get("rewardRef")):
			continue
		var claim_id := str(record.get("claimId"))
		var integration_id := str(record.get("integrationId"))
		var reward_ref := str(record.get("rewardRef"))
		if claim_id == "" or integration_id != _integration_id or reward_ref == "" or reward_ref.length() > 128:
			continue
		var duplicate := false
		for existing in loaded:
			if str(existing.get("rewardRef", "")) == str(reward_ref):
				duplicate = true
				break
		if duplicate:
			continue
		loaded.append({
			"claimId": claim_id,
			"integrationId": integration_id,
			"rewardRef": reward_ref,
		})
	_saved = loaded


func _emit_settled(outcome: Outcome, generation: int) -> void:
	if generation != _session_generation:
		return
	settled.emit(outcome)
