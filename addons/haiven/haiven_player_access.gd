## Thin Phase 1 helpers for game access and player statuses.
class_name HaivenPlayerAccess
extends RefCounted

const FOUNDER_STATUS := "founder"


## Reads whether the signed-in player may launch a game. The generated transport's
## null success and HaivenRestError values pass through unchanged.
static func game(api: RefCounted, game_id: int) -> Variant:
	return await api.get_games_game_id_access(game_id)


## Finds an exact open status code without rejecting codes minted after this SDK.
static func find_status(eligibility: Variant, code: String) -> Variant:
	if code == "" or not eligibility is Dictionary:
		return null
	var statuses: Variant = eligibility.get("statuses", [])
	if not statuses is Array:
		return null
	for status: Variant in statuses:
		if status is Dictionary and status.get("code") == code:
			return status
	return null


## The founder status, independent of subscriber eligibility.
static func founder_status(eligibility: Variant) -> Variant:
	return find_status(eligibility, FOUNDER_STATUS)
