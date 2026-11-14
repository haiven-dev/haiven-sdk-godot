# Generated from the published Haiven contract schemas — do not edit by hand.
#
# The values are the `x-extensible-enum` published for this vocabulary in the
# Haiven contract schemas.
#
# The set is open: an unrecognised value is one this binding predates, not an
# invalid one. Never reject on it.

extends RefCounted
## Registered ErrorCode wire values and recognition helper.
class_name HaivenErrorCode

## The registered `unauthorized` wire value.
const UNAUTHORIZED: String = "unauthorized"
## The registered `forbidden` wire value.
const FORBIDDEN: String = "forbidden"
## The registered `bad_request` wire value.
const BAD_REQUEST: String = "bad_request"
## The registered `internal_error` wire value.
const INTERNAL_ERROR: String = "internal_error"
## The registered `invalid_json` wire value.
const INVALID_JSON: String = "invalid_json"
## The registered `failed_to_decode_json` wire value.
const FAILED_TO_DECODE_JSON: String = "failed_to_decode_json"
## The registered `request_body_too_large` wire value.
const REQUEST_BODY_TOO_LARGE: String = "request_body_too_large"
## The registered `resource_not_found` wire value.
const RESOURCE_NOT_FOUND: String = "resource_not_found"
## The registered `resource_already_exists` wire value.
const RESOURCE_ALREADY_EXISTS: String = "resource_already_exists"
## The registered `media_rejected` wire value.
const MEDIA_REJECTED: String = "media_rejected"
## The registered `invalid_form_request` wire value.
const INVALID_FORM_REQUEST: String = "invalid_form_request"
## The registered `message_not_found` wire value.
const MESSAGE_NOT_FOUND: String = "message_not_found"
## The registered `rate_limited` wire value.
const RATE_LIMITED: String = "rate_limited"
## The registered `user_exists` wire value.
const USER_EXISTS: String = "user_exists"
## The registered `user_unverified` wire value.
const USER_UNVERIFIED: String = "user_unverified"
## The registered `user_creation_failed` wire value.
const USER_CREATION_FAILED: String = "user_creation_failed"
## The registered `username_required` wire value.
const USERNAME_REQUIRED: String = "username_required"
## The registered `username_or_email_required` wire value.
const USERNAME_OR_EMAIL_REQUIRED: String = "username_or_email_required"
## The registered `username_invalid` wire value.
const USERNAME_INVALID: String = "username_invalid"
## The registered `display_name_invalid` wire value.
const DISPLAY_NAME_INVALID: String = "display_name_invalid"
## The registered `date_of_birth_invalid` wire value.
const DATE_OF_BIRTH_INVALID: String = "date_of_birth_invalid"
## The registered `date_of_birth_required` wire value.
const DATE_OF_BIRTH_REQUIRED: String = "date_of_birth_required"
## The registered `email_required` wire value.
const EMAIL_REQUIRED: String = "email_required"
## The registered `email_invalid` wire value.
const EMAIL_INVALID: String = "email_invalid"
## The registered `email_exists` wire value.
const EMAIL_EXISTS: String = "email_exists"
## The registered `early_access_code_required` wire value.
const EARLY_ACCESS_CODE_REQUIRED: String = "early_access_code_required"
## The registered `early_access_code_invalid` wire value.
const EARLY_ACCESS_CODE_INVALID: String = "early_access_code_invalid"
## The registered `password_invalid` wire value.
const PASSWORD_INVALID: String = "password_invalid"
## The registered `passwords_match` wire value.
const PASSWORDS_MATCH: String = "passwords_match"
## The registered `password_required` wire value.
const PASSWORD_REQUIRED: String = "password_required"
## The registered `new_password_required` wire value.
const NEW_PASSWORD_REQUIRED: String = "new_password_required"
## The registered `previous_password_required` wire value.
const PREVIOUS_PASSWORD_REQUIRED: String = "previous_password_required"
## The registered `challenge_unsupported` wire value.
const CHALLENGE_UNSUPPORTED: String = "challenge_unsupported"
## The registered `challenge_session_required` wire value.
const CHALLENGE_SESSION_REQUIRED: String = "challenge_session_required"
## The registered `challenge_field_required` wire value.
const CHALLENGE_FIELD_REQUIRED: String = "challenge_field_required"
## The registered `logout_failed` wire value.
const LOGOUT_FAILED: String = "logout_failed"
## The registered `dev_eula_required` wire value.
const DEV_EULA_REQUIRED: String = "dev_eula_required"
## The registered `legal_version_stale` wire value.
const LEGAL_VERSION_STALE: String = "legal_version_stale"
## The registered `legal_version_exists` wire value.
const LEGAL_VERSION_EXISTS: String = "legal_version_exists"
## The registered `email_not_verified` wire value.
const EMAIL_NOT_VERIFIED: String = "email_not_verified"
## The registered `token_required` wire value.
const TOKEN_REQUIRED: String = "token_required"
## The registered `token_expired_or_not_found` wire value.
const TOKEN_EXPIRED_OR_NOT_FOUND: String = "token_expired_or_not_found"
## The registered `validation_secret_mismatch` wire value.
const VALIDATION_SECRET_MISMATCH: String = "validation_secret_mismatch"
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
## The registered `friend_self_forbidden` wire value.
const FRIEND_SELF_FORBIDDEN: String = "friend_self_forbidden"
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
## The registered `block_self_forbidden` wire value.
const BLOCK_SELF_FORBIDDEN: String = "block_self_forbidden"
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
## The registered `bio_too_long` wire value.
const BIO_TOO_LONG: String = "bio_too_long"
## The registered `headline_too_long` wire value.
const HEADLINE_TOO_LONG: String = "headline_too_long"
## The registered `invalid_visibility` wire value.
const INVALID_VISIBILITY: String = "invalid_visibility"
## The registered `image_fields_required` wire value.
const IMAGE_FIELDS_REQUIRED: String = "image_fields_required"
## The registered `invalid_image_type` wire value.
const INVALID_IMAGE_TYPE: String = "invalid_image_type"
## The registered `unsupported_content_type` wire value.
const UNSUPPORTED_CONTENT_TYPE: String = "unsupported_content_type"
## The registered `invite_not_found` wire value.
const INVITE_NOT_FOUND: String = "invite_not_found"
## The registered `invalid_invite_code` wire value.
const INVALID_INVITE_CODE: String = "invalid_invite_code"
## The registered `unable_to_delete_invite` wire value.
const UNABLE_TO_DELETE_INVITE: String = "unable_to_delete_invite"
## The registered `community_id_required` wire value.
const COMMUNITY_ID_REQUIRED: String = "community_id_required"
## The registered `invalid_studio_id` wire value.
const INVALID_STUDIO_ID: String = "invalid_studio_id"
## The registered `unable_to_parse_quantity` wire value.
const UNABLE_TO_PARSE_QUANTITY: String = "unable_to_parse_quantity"
## The registered `quantity_required` wire value.
const QUANTITY_REQUIRED: String = "quantity_required"
## The registered `unable_to_create_codes` wire value.
const UNABLE_TO_CREATE_CODES: String = "unable_to_create_codes"
## The registered `member_id_required` wire value.
const MEMBER_ID_REQUIRED: String = "member_id_required"
## The registered `invalid_link` wire value.
const INVALID_LINK: String = "invalid_link"
## The registered `studio_id_required` wire value.
const STUDIO_ID_REQUIRED: String = "studio_id_required"
## The registered `app_id_required` wire value.
const APP_ID_REQUIRED: String = "app_id_required"
## The registered `build_id_required` wire value.
const BUILD_ID_REQUIRED: String = "build_id_required"
## The registered `user_id_required` wire value.
const USER_ID_REQUIRED: String = "user_id_required"
## The registered `hook_name_required` wire value.
const HOOK_NAME_REQUIRED: String = "hook_name_required"
## The registered `invalid_hook_name` wire value.
const INVALID_HOOK_NAME: String = "invalid_hook_name"
## The registered `invalid_app_id` wire value.
const INVALID_APP_ID: String = "invalid_app_id"
## The registered `invalid_file_name` wire value.
const INVALID_FILE_NAME: String = "invalid_file_name"
## The registered `invalid_status_type` wire value.
const INVALID_STATUS_TYPE: String = "invalid_status_type"
## The registered `studio_slug_required` wire value.
const STUDIO_SLUG_REQUIRED: String = "studio_slug_required"
## The registered `player_name_required` wire value.
const PLAYER_NAME_REQUIRED: String = "player_name_required"
## The registered `steam_id_required` wire value.
const STEAM_ID_REQUIRED: String = "steam_id_required"
## The registered `invite_code_required` wire value.
const INVITE_CODE_REQUIRED: String = "invite_code_required"
## The registered `confirmation_code_required` wire value.
const CONFIRMATION_CODE_REQUIRED: String = "confirmation_code_required"
## The registered `studio_name_exists` wire value.
const STUDIO_NAME_EXISTS: String = "studio_name_exists"
## The registered `invalid_handoff_request` wire value.
const INVALID_HANDOFF_REQUEST: String = "invalid_handoff_request"
## The registered `unsupported_pkce` wire value.
const UNSUPPORTED_PKCE: String = "unsupported_pkce"
## The registered `invalid_handoff_code` wire value.
const INVALID_HANDOFF_CODE: String = "invalid_handoff_code"
## The registered `handoff_session_expired` wire value.
const HANDOFF_SESSION_EXPIRED: String = "handoff_session_expired"
## The registered `handoff_unavailable` wire value.
const HANDOFF_UNAVAILABLE: String = "handoff_unavailable"
## The registered `avatar_frame_invalid` wire value.
const AVATAR_FRAME_INVALID: String = "avatar_frame_invalid"
## The registered `avatar_frame_not_owned` wire value.
const AVATAR_FRAME_NOT_OWNED: String = "avatar_frame_not_owned"
## The registered `auth_unavailable` wire value.
const AUTH_UNAVAILABLE: String = "auth_unavailable"
## The registered `federation_unavailable` wire value.
const FEDERATION_UNAVAILABLE: String = "federation_unavailable"
## The registered `federation_provider_invalid` wire value.
const FEDERATION_PROVIDER_INVALID: String = "federation_provider_invalid"
## The registered `federation_state_invalid` wire value.
const FEDERATION_STATE_INVALID: String = "federation_state_invalid"
## The registered `federation_exchange_failed` wire value.
const FEDERATION_EXCHANGE_FAILED: String = "federation_exchange_failed"
## The registered `continuation_invalid` wire value.
const CONTINUATION_INVALID: String = "continuation_invalid"
## The registered `stale_purchase_revision` wire value.
const STALE_PURCHASE_REVISION: String = "stale_purchase_revision"
## The registered `purchase_in_progress` wire value.
const PURCHASE_IN_PROGRESS: String = "purchase_in_progress"
## The registered `accept_before_expired` wire value.
const ACCEPT_BEFORE_EXPIRED: String = "accept_before_expired"
## The registered `purchase_unavailable` wire value.
const PURCHASE_UNAVAILABLE: String = "purchase_unavailable"
## The registered `reward_not_eligible` wire value.
const REWARD_NOT_ELIGIBLE: String = "reward_not_eligible"
## The registered `reward_already_claimed` wire value.
const REWARD_ALREADY_CLAIMED: String = "reward_already_claimed"
## The registered `reward_claim_conflict` wire value.
const REWARD_CLAIM_CONFLICT: String = "reward_claim_conflict"
## The registered `refund_in_progress` wire value.
const REFUND_IN_PROGRESS: String = "refund_in_progress"
## The registered `app_in_review` wire value.
const APP_IN_REVIEW: String = "app_in_review"
## The registered `email_registered_with_sso` wire value.
const EMAIL_REGISTERED_WITH_SSO: String = "email_registered_with_sso"
## The registered `email_registered_with_password` wire value.
const EMAIL_REGISTERED_WITH_PASSWORD: String = "email_registered_with_password"
## The registered `identity_already_linked` wire value.
const IDENTITY_ALREADY_LINKED: String = "identity_already_linked"
## The registered `provider_already_linked` wire value.
const PROVIDER_ALREADY_LINKED: String = "provider_already_linked"
## The registered `password_already_set` wire value.
const PASSWORD_ALREADY_SET: String = "password_already_set"
## The registered `last_sign_in_method` wire value.
const LAST_SIGN_IN_METHOD: String = "last_sign_in_method"
## The registered `jurisdiction_required` wire value.
const JURISDICTION_REQUIRED: String = "jurisdiction_required"
## The registered `jurisdiction_invalid` wire value.
const JURISDICTION_INVALID: String = "jurisdiction_invalid"
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
## The registered `age_gate_no_pending_challenge` wire value.
const AGE_GATE_NO_PENDING_CHALLENGE: String = "age_gate_no_pending_challenge"
## The registered `age_gate_no_active_session` wire value.
const AGE_GATE_NO_ACTIVE_SESSION: String = "age_gate_no_active_session"
## The registered `age_gate_vendor_rejected` wire value.
const AGE_GATE_VENDOR_REJECTED: String = "age_gate_vendor_rejected"
## The registered `age_gate_jurisdiction_unknown` wire value.
const AGE_GATE_JURISDICTION_UNKNOWN: String = "age_gate_jurisdiction_unknown"
## The registered `age_gate_already_classified` wire value.
const AGE_GATE_ALREADY_CLASSIFIED: String = "age_gate_already_classified"
## The registered `age_gate_details_on_file` wire value.
const AGE_GATE_DETAILS_ON_FILE: String = "age_gate_details_on_file"
## The registered `parental_consent_denied` wire value.
const PARENTAL_CONSENT_DENIED: String = "parental_consent_denied"
## The registered `age_gate_retry_not_yet` wire value.
const AGE_GATE_RETRY_NOT_YET: String = "age_gate_retry_not_yet"
## The registered `age_gate_nothing_to_retry` wire value.
const AGE_GATE_NOTHING_TO_RETRY: String = "age_gate_nothing_to_retry"
## The registered `already_on_waitlist` wire value.
const ALREADY_ON_WAITLIST: String = "already_on_waitlist"
## The registered `invite_already_redeemed` wire value.
const INVITE_ALREADY_REDEEMED: String = "invite_already_redeemed"
## The registered `email_send_failed` wire value.
const EMAIL_SEND_FAILED: String = "email_send_failed"
## The registered `steam_app_not_found` wire value.
const STEAM_APP_NOT_FOUND: String = "steam_app_not_found"
## The registered `invalid_app_name` wire value.
const INVALID_APP_NAME: String = "invalid_app_name"
## The registered `client_closed_request` wire value.
const CLIENT_CLOSED_REQUEST: String = "client_closed_request"
## The registered `session_not_found` wire value.
const SESSION_NOT_FOUND: String = "session_not_found"
## The registered `session_full` wire value.
const SESSION_FULL: String = "session_full"
## The registered `session_locked` wire value.
const SESSION_LOCKED: String = "session_locked"
## The registered `kicked_from_session` wire value.
const KICKED_FROM_SESSION: String = "kicked_from_session"
## The registered `already_in_session` wire value.
const ALREADY_IN_SESSION: String = "already_in_session"
## The registered `connection_not_bound` wire value.
const CONNECTION_NOT_BOUND: String = "connection_not_bound"
## The registered `session_update_refused` wire value.
const SESSION_UPDATE_REFUSED: String = "session_update_refused"
## The registered `game_access_required` wire value.
const GAME_ACCESS_REQUIRED: String = "game_access_required"
## The registered `relay_unavailable` wire value.
const RELAY_UNAVAILABLE: String = "relay_unavailable"

const _REGISTERED := {
	UNAUTHORIZED: true,
	FORBIDDEN: true,
	BAD_REQUEST: true,
	INTERNAL_ERROR: true,
	INVALID_JSON: true,
	FAILED_TO_DECODE_JSON: true,
	REQUEST_BODY_TOO_LARGE: true,
	RESOURCE_NOT_FOUND: true,
	RESOURCE_ALREADY_EXISTS: true,
	MEDIA_REJECTED: true,
	INVALID_FORM_REQUEST: true,
	MESSAGE_NOT_FOUND: true,
	RATE_LIMITED: true,
	USER_EXISTS: true,
	USER_UNVERIFIED: true,
	USER_CREATION_FAILED: true,
	USERNAME_REQUIRED: true,
	USERNAME_OR_EMAIL_REQUIRED: true,
	USERNAME_INVALID: true,
	DISPLAY_NAME_INVALID: true,
	DATE_OF_BIRTH_INVALID: true,
	DATE_OF_BIRTH_REQUIRED: true,
	EMAIL_REQUIRED: true,
	EMAIL_INVALID: true,
	EMAIL_EXISTS: true,
	EARLY_ACCESS_CODE_REQUIRED: true,
	EARLY_ACCESS_CODE_INVALID: true,
	PASSWORD_INVALID: true,
	PASSWORDS_MATCH: true,
	PASSWORD_REQUIRED: true,
	NEW_PASSWORD_REQUIRED: true,
	PREVIOUS_PASSWORD_REQUIRED: true,
	CHALLENGE_UNSUPPORTED: true,
	CHALLENGE_SESSION_REQUIRED: true,
	CHALLENGE_FIELD_REQUIRED: true,
	LOGOUT_FAILED: true,
	DEV_EULA_REQUIRED: true,
	LEGAL_VERSION_STALE: true,
	LEGAL_VERSION_EXISTS: true,
	EMAIL_NOT_VERIFIED: true,
	TOKEN_REQUIRED: true,
	TOKEN_EXPIRED_OR_NOT_FOUND: true,
	VALIDATION_SECRET_MISMATCH: true,
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
	FRIEND_SELF_FORBIDDEN: true,
	REQUEST_NOT_FOUND: true,
	USER_NOT_FOUND: true,
	REPORT_REASON_INVALID: true,
	REPORT_SELF_FORBIDDEN: true,
	REPORT_LIMIT_REACHED: true,
	BLOCK_SELF_FORBIDDEN: true,
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
	BIO_TOO_LONG: true,
	HEADLINE_TOO_LONG: true,
	INVALID_VISIBILITY: true,
	IMAGE_FIELDS_REQUIRED: true,
	INVALID_IMAGE_TYPE: true,
	UNSUPPORTED_CONTENT_TYPE: true,
	INVITE_NOT_FOUND: true,
	INVALID_INVITE_CODE: true,
	UNABLE_TO_DELETE_INVITE: true,
	COMMUNITY_ID_REQUIRED: true,
	INVALID_STUDIO_ID: true,
	UNABLE_TO_PARSE_QUANTITY: true,
	QUANTITY_REQUIRED: true,
	UNABLE_TO_CREATE_CODES: true,
	MEMBER_ID_REQUIRED: true,
	INVALID_LINK: true,
	STUDIO_ID_REQUIRED: true,
	APP_ID_REQUIRED: true,
	BUILD_ID_REQUIRED: true,
	USER_ID_REQUIRED: true,
	HOOK_NAME_REQUIRED: true,
	INVALID_HOOK_NAME: true,
	INVALID_APP_ID: true,
	INVALID_FILE_NAME: true,
	INVALID_STATUS_TYPE: true,
	STUDIO_SLUG_REQUIRED: true,
	PLAYER_NAME_REQUIRED: true,
	STEAM_ID_REQUIRED: true,
	INVITE_CODE_REQUIRED: true,
	CONFIRMATION_CODE_REQUIRED: true,
	STUDIO_NAME_EXISTS: true,
	INVALID_HANDOFF_REQUEST: true,
	UNSUPPORTED_PKCE: true,
	INVALID_HANDOFF_CODE: true,
	HANDOFF_SESSION_EXPIRED: true,
	HANDOFF_UNAVAILABLE: true,
	AVATAR_FRAME_INVALID: true,
	AVATAR_FRAME_NOT_OWNED: true,
	AUTH_UNAVAILABLE: true,
	FEDERATION_UNAVAILABLE: true,
	FEDERATION_PROVIDER_INVALID: true,
	FEDERATION_STATE_INVALID: true,
	FEDERATION_EXCHANGE_FAILED: true,
	CONTINUATION_INVALID: true,
	STALE_PURCHASE_REVISION: true,
	PURCHASE_IN_PROGRESS: true,
	ACCEPT_BEFORE_EXPIRED: true,
	PURCHASE_UNAVAILABLE: true,
	REWARD_NOT_ELIGIBLE: true,
	REWARD_ALREADY_CLAIMED: true,
	REWARD_CLAIM_CONFLICT: true,
	REFUND_IN_PROGRESS: true,
	APP_IN_REVIEW: true,
	EMAIL_REGISTERED_WITH_SSO: true,
	EMAIL_REGISTERED_WITH_PASSWORD: true,
	IDENTITY_ALREADY_LINKED: true,
	PROVIDER_ALREADY_LINKED: true,
	PASSWORD_ALREADY_SET: true,
	LAST_SIGN_IN_METHOD: true,
	JURISDICTION_REQUIRED: true,
	JURISDICTION_INVALID: true,
	AGE_ASSURANCE_UNAVAILABLE: true,
	AGE_VERIFICATION_REQUIRED: true,
	PARENTAL_CONSENT_REQUIRED: true,
	JURISDICTION_PROHIBITED: true,
	OWN_AGE_VERIFICATION_REQUIRED: true,
	CHILD_LITE_ACCESS_AVAILABLE: true,
	AGE_GATE_NO_PENDING_CHALLENGE: true,
	AGE_GATE_NO_ACTIVE_SESSION: true,
	AGE_GATE_VENDOR_REJECTED: true,
	AGE_GATE_JURISDICTION_UNKNOWN: true,
	AGE_GATE_ALREADY_CLASSIFIED: true,
	AGE_GATE_DETAILS_ON_FILE: true,
	PARENTAL_CONSENT_DENIED: true,
	AGE_GATE_RETRY_NOT_YET: true,
	AGE_GATE_NOTHING_TO_RETRY: true,
	ALREADY_ON_WAITLIST: true,
	INVITE_ALREADY_REDEEMED: true,
	EMAIL_SEND_FAILED: true,
	STEAM_APP_NOT_FOUND: true,
	INVALID_APP_NAME: true,
	CLIENT_CLOSED_REQUEST: true,
	SESSION_NOT_FOUND: true,
	SESSION_FULL: true,
	SESSION_LOCKED: true,
	KICKED_FROM_SESSION: true,
	ALREADY_IN_SESSION: true,
	CONNECTION_NOT_BOUND: true,
	SESSION_UPDATE_REFUSED: true,
	GAME_ACCESS_REQUIRED: true,
	RELAY_UNAVAILABLE: true,
}

## Whether this binding was compiled knowing the value. Never a parse gate.
static func is_recognised(value: String) -> bool:
	return _REGISTERED.has(value)
