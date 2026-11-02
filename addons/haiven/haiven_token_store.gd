## Shared access-token ownership for REST handoff and WebSocket authentication.
##
## Games may pass this object directly to [HaivenSession]. The session resolves
## [method read] at each handshake rather than copying [member access_token], so
## a credential written after a game-login handoff is visible to re-auth on the
## already-open socket.
class_name HaivenTokenStore
extends RefCounted

var access_token: String

## Absolute Unix time in milliseconds, or -1 when the expiry is not known.
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


func is_expired(now_msec: int = -1) -> bool:
	if expires_at_msec < 0:
		return false
	var current := now_msec
	if current < 0:
		current = int(Time.get_unix_time_from_system() * 1000.0)
	return current >= expires_at_msec
