## Shared access-token ownership for REST handoff and WebSocket authentication.
##
## Games may pass this object directly to [HaivenSession]. The session resolves
## [method read] at each handshake rather than copying [member access_token], so
## a credential written after a game-login handoff is visible to re-auth on the
## already-open socket.
##
## This base class keeps the credential in memory only, so every launch needs a
## new handoff: use it for development and tests. A shipped game extends it and
## overrides [method write], [method clear] and [method load_credential] to keep
## the credential in persistent storage, so [method HaivenHandoff.resume] can
## reuse it after a restart.
class_name HaivenTokenStore
extends RefCounted

var access_token: String

## Absolute Unix time in milliseconds, or -1 for a credential with no fixed
## expiry (ADR 0041's durable credential, or a host bearer of unknown expiry).
var expires_at_msec: int


func _init(initial_access_token: String = "", initial_expires_at_msec: int = -1) -> void:
	access_token = initial_access_token
	expires_at_msec = initial_expires_at_msec


func read() -> String:
	return access_token


func write(next_access_token: String, next_expires_at_msec: int) -> void:
	access_token = next_access_token
	expires_at_msec = next_expires_at_msec


func clear() -> void:
	access_token = ""
	expires_at_msec = -1


## Returns the credential saved before this launch as
## `{access_token, expires_at_msec}`, or an empty dictionary when none is saved.
## The memory-only base returns what this process wrote.
func load_credential() -> Dictionary:
	if access_token.is_empty():
		return {}
	return {"access_token": access_token, "expires_at_msec": expires_at_msec}


func is_expired(now_msec: int = -1) -> bool:
	if expires_at_msec < 0:
		return false
	var current := now_msec
	if current < 0:
		current = int(Time.get_unix_time_from_system() * 1000.0)
	return current >= expires_at_msec
