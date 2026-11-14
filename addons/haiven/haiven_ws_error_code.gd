# Generated from the published Haiven contract schemas — do not edit by hand.
#
# The values are the `x-extensible-enum` published for this vocabulary in the
# Haiven contract schemas.
#
# The set is open: an unrecognised value is one this binding predates, not an
# invalid one. Never reject on it.

extends RefCounted
## Registered WsErrorCode wire values and recognition helper.
class_name HaivenWsErrorCode

## The registered `unauthorized` wire value.
const UNAUTHORIZED: String = "unauthorized"
## The registered `forbidden` wire value.
const FORBIDDEN: String = "forbidden"
## The registered `internal_error` wire value.
const INTERNAL_ERROR: String = "internal_error"
## The registered `invalid_payload` wire value.
const INVALID_PAYLOAD: String = "invalid_payload"
## The registered `room_not_found` wire value.
const ROOM_NOT_FOUND: String = "room_not_found"
## The registered `message_not_found` wire value.
const MESSAGE_NOT_FOUND: String = "message_not_found"
## The registered `db_failed` wire value.
const DB_FAILED: String = "db_failed"
## The registered `invalid_token` wire value.
const INVALID_TOKEN: String = "invalid_token"
## The registered `expired_token` wire value.
const EXPIRED_TOKEN: String = "expired_token"
## The registered `unknown_message_type` wire value.
const UNKNOWN_MESSAGE_TYPE: String = "unknown_message_type"
## The registered `rate_limited` wire value.
const RATE_LIMITED: String = "rate_limited"
## The registered `invalid_channel_id` wire value.
const INVALID_CHANNEL_ID: String = "invalid_channel_id"
## The registered `invalid_community_id` wire value.
const INVALID_COMMUNITY_ID: String = "invalid_community_id"
## The registered `invalid_before_community_id` wire value.
const INVALID_BEFORE_COMMUNITY_ID: String = "invalid_before_community_id"
## The registered `invalid_message_id` wire value.
const INVALID_MESSAGE_ID: String = "invalid_message_id"
## The registered `invalid_parent_message_id` wire value.
const INVALID_PARENT_MESSAGE_ID: String = "invalid_parent_message_id"
## The registered `invalid_before_message_id` wire value.
const INVALID_BEFORE_MESSAGE_ID: String = "invalid_before_message_id"
## The registered `invalid_member_id` wire value.
const INVALID_MEMBER_ID: String = "invalid_member_id"
## The registered `invalid_group_id` wire value.
const INVALID_GROUP_ID: String = "invalid_group_id"
## The registered `invalid_group_name` wire value.
const INVALID_GROUP_NAME: String = "invalid_group_name"
## The registered `invalid_user_id` wire value.
const INVALID_USER_ID: String = "invalid_user_id"
## The registered `invalid_limit` wire value.
const INVALID_LIMIT: String = "invalid_limit"
## The registered `invalid_community_name` wire value.
const INVALID_COMMUNITY_NAME: String = "invalid_community_name"
## The registered `invalid_channel_name` wire value.
const INVALID_CHANNEL_NAME: String = "invalid_channel_name"
## The registered `not_community_owner` wire value.
const NOT_COMMUNITY_OWNER: String = "not_community_owner"
## The registered `not_community_member` wire value.
const NOT_COMMUNITY_MEMBER: String = "not_community_member"
## The registered `not_channel_member` wire value.
const NOT_CHANNEL_MEMBER: String = "not_channel_member"
## The registered `not_message_author` wire value.
const NOT_MESSAGE_AUTHOR: String = "not_message_author"
## The registered `content_required` wire value.
const CONTENT_REQUIRED: String = "content_required"
## The registered `content_too_long` wire value.
const CONTENT_TOO_LONG: String = "content_too_long"
## The supplied client message ID is invalid.
const CLIENT_MESSAGE_ID_INVALID: String = "client_message_id_invalid"
## The supplied client message ID conflicts with an existing message.
const CLIENT_MESSAGE_ID_CONFLICT: String = "client_message_id_conflict"
## The registered `cannot_remove_owner` wire value.
const CANNOT_REMOVE_OWNER: String = "cannot_remove_owner"
## The registered `dm_self_forbidden` wire value.
const DM_SELF_FORBIDDEN: String = "dm_self_forbidden"
## The registered `not_friends` wire value.
const NOT_FRIENDS: String = "not_friends"
## The registered `request_not_found` wire value.
const REQUEST_NOT_FOUND: String = "request_not_found"
## The registered `user_not_found` wire value.
const USER_NOT_FOUND: String = "user_not_found"
## The registered `report_reason_invalid` wire value.
const REPORT_REASON_INVALID: String = "report_reason_invalid"
## The registered `report_self_forbidden` wire value.
const REPORT_SELF_FORBIDDEN: String = "report_self_forbidden"
## The registered `report_limit_reached` wire value.
const REPORT_LIMIT_REACHED: String = "report_limit_reached"
## The registered `message_not_accessible` wire value.
const MESSAGE_NOT_ACCESSIBLE: String = "message_not_accessible"
## The registered `invalid_scope` wire value.
const INVALID_SCOPE: String = "invalid_scope"
## The registered `invalid_resource_id` wire value.
const INVALID_RESOURCE_ID: String = "invalid_resource_id"
## The registered `invalid_role_id` wire value.
const INVALID_ROLE_ID: String = "invalid_role_id"
## The registered `invalid_role_name` wire value.
const INVALID_ROLE_NAME: String = "invalid_role_name"
## The registered `no_permissions_provided` wire value.
const NO_PERMISSIONS_PROVIDED: String = "no_permissions_provided"
## The registered `unknown_permission` wire value.
const UNKNOWN_PERMISSION: String = "unknown_permission"
## The registered `permission_not_in_scope` wire value.
const PERMISSION_NOT_IN_SCOPE: String = "permission_not_in_scope"
## The registered `user_not_member` wire value.
const USER_NOT_MEMBER: String = "user_not_member"
## The registered `role_not_in_scope` wire value.
const ROLE_NOT_IN_SCOPE: String = "role_not_in_scope"
## The registered `role_not_owned` wire value.
const ROLE_NOT_OWNED: String = "role_not_owned"
## The registered `system_role_forbidden` wire value.
const SYSTEM_ROLE_FORBIDDEN: String = "system_role_forbidden"
## The registered `role_not_found` wire value.
const ROLE_NOT_FOUND: String = "role_not_found"
## The registered `unknown_availability` wire value.
const UNKNOWN_AVAILABILITY: String = "unknown_availability"
## The registered `invalid_status_emoji` wire value.
const INVALID_STATUS_EMOJI: String = "invalid_status_emoji"
## The registered `status_text_too_long` wire value.
const STATUS_TEXT_TOO_LONG: String = "status_text_too_long"
## The registered `age_assurance_unavailable` wire value.
const AGE_ASSURANCE_UNAVAILABLE: String = "age_assurance_unavailable"
## The registered `age_verification_required` wire value.
const AGE_VERIFICATION_REQUIRED: String = "age_verification_required"
## The registered `parental_consent_required` wire value.
const PARENTAL_CONSENT_REQUIRED: String = "parental_consent_required"
## The registered `jurisdiction_prohibited` wire value.
const JURISDICTION_PROHIBITED: String = "jurisdiction_prohibited"
## The registered `own_age_verification_required` wire value.
const OWN_AGE_VERIFICATION_REQUIRED: String = "own_age_verification_required"
## The registered `child_lite_access_available` wire value.
const CHILD_LITE_ACCESS_AVAILABLE: String = "child_lite_access_available"
## The registered `parental_consent_denied` wire value.
const PARENTAL_CONSENT_DENIED: String = "parental_consent_denied"
## The registered `client_closed_request` wire value.
const CLIENT_CLOSED_REQUEST: String = "client_closed_request"
## The registered `session_not_found` wire value.
const SESSION_NOT_FOUND: String = "session_not_found"
## The registered `peer_not_in_session` wire value.
const PEER_NOT_IN_SESSION: String = "peer_not_in_session"
## The registered `relay_unavailable` wire value.
const RELAY_UNAVAILABLE: String = "relay_unavailable"

const _REGISTERED := {
	UNAUTHORIZED: true,
	FORBIDDEN: true,
	INTERNAL_ERROR: true,
	INVALID_PAYLOAD: true,
	ROOM_NOT_FOUND: true,
	MESSAGE_NOT_FOUND: true,
	DB_FAILED: true,
	INVALID_TOKEN: true,
	EXPIRED_TOKEN: true,
	UNKNOWN_MESSAGE_TYPE: true,
	RATE_LIMITED: true,
	INVALID_CHANNEL_ID: true,
	INVALID_COMMUNITY_ID: true,
	INVALID_BEFORE_COMMUNITY_ID: true,
	INVALID_MESSAGE_ID: true,
	INVALID_PARENT_MESSAGE_ID: true,
	INVALID_BEFORE_MESSAGE_ID: true,
	INVALID_MEMBER_ID: true,
	INVALID_GROUP_ID: true,
	INVALID_GROUP_NAME: true,
	INVALID_USER_ID: true,
	INVALID_LIMIT: true,
	INVALID_COMMUNITY_NAME: true,
	INVALID_CHANNEL_NAME: true,
	NOT_COMMUNITY_OWNER: true,
	NOT_COMMUNITY_MEMBER: true,
	NOT_CHANNEL_MEMBER: true,
	NOT_MESSAGE_AUTHOR: true,
	CONTENT_REQUIRED: true,
	CONTENT_TOO_LONG: true,
	CLIENT_MESSAGE_ID_INVALID: true,
	CLIENT_MESSAGE_ID_CONFLICT: true,
	CANNOT_REMOVE_OWNER: true,
	DM_SELF_FORBIDDEN: true,
	NOT_FRIENDS: true,
	REQUEST_NOT_FOUND: true,
	USER_NOT_FOUND: true,
	REPORT_REASON_INVALID: true,
	REPORT_SELF_FORBIDDEN: true,
	REPORT_LIMIT_REACHED: true,
	MESSAGE_NOT_ACCESSIBLE: true,
	INVALID_SCOPE: true,
	INVALID_RESOURCE_ID: true,
	INVALID_ROLE_ID: true,
	INVALID_ROLE_NAME: true,
	NO_PERMISSIONS_PROVIDED: true,
	UNKNOWN_PERMISSION: true,
	PERMISSION_NOT_IN_SCOPE: true,
	USER_NOT_MEMBER: true,
	ROLE_NOT_IN_SCOPE: true,
	ROLE_NOT_OWNED: true,
	SYSTEM_ROLE_FORBIDDEN: true,
	ROLE_NOT_FOUND: true,
	UNKNOWN_AVAILABILITY: true,
	INVALID_STATUS_EMOJI: true,
	STATUS_TEXT_TOO_LONG: true,
	AGE_ASSURANCE_UNAVAILABLE: true,
	AGE_VERIFICATION_REQUIRED: true,
	PARENTAL_CONSENT_REQUIRED: true,
	JURISDICTION_PROHIBITED: true,
	OWN_AGE_VERIFICATION_REQUIRED: true,
	CHILD_LITE_ACCESS_AVAILABLE: true,
	PARENTAL_CONSENT_DENIED: true,
	CLIENT_CLOSED_REQUEST: true,
	SESSION_NOT_FOUND: true,
	PEER_NOT_IN_SESSION: true,
	RELAY_UNAVAILABLE: true,
}

## Whether this binding was compiled knowing the value. Never a parse gate.
static func is_recognised(value: String) -> bool:
	return _REGISTERED.has(value)
