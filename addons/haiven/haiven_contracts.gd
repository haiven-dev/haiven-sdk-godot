# Generated from the published Haiven contract schemas. Do not edit by hand.
## Registry and codec boundary for the published Haiven contracts.
class_name HaivenContracts
extends RefCounted

## A link of a Google or Apple identity started from settings that was refused or abandoned.
const ACCOUNT_IDENTITY_LINK_FAILED_V0_ID := "https://schemas.haiven.gg/account-identity-link-failed/v0.json"
## A Google or Apple identity linked to the account from settings.
const ACCOUNT_IDENTITY_LINKED_V0_ID := "https://schemas.haiven.gg/account-identity-linked/v0.json"
## A change to the signed-in player's stored age-gate status, sent to their open sockets.
const AGEGATE_UPDATED_V0_ID := "https://schemas.haiven.gg/agegate-updated/v0.json"
## The active chat channel identifier.
const CHAT_ACTIVE_CHANNEL_V0_ID := "https://schemas.haiven.gg/chat-active-channel/v0.json"
## A chat channel visible to a gaming client.
const CHAT_CHANNEL_V0_ID := "https://schemas.haiven.gg/chat-channel/v0.json"
## A chat community its owner deleted; the last event it sends before its subscribers are dropped.
const CHAT_COMMUNITY_DELETED_V0_ID := "https://schemas.haiven.gg/chat-community-deleted/v0.json"
## A member of a chat community.
const CHAT_COMMUNITY_MEMBER_V0_ID := "https://schemas.haiven.gg/chat-community-member/v0.json"
## A visible update to a chat community.
const CHAT_COMMUNITY_UPDATE_V0_ID := "https://schemas.haiven.gg/chat-community-update/v0.json"
## A direct-message channel and its other participant.
const CHAT_DM_V0_ID := "https://schemas.haiven.gg/chat-dm/v0.json"
## A request to replace a chat message's content.
const CHAT_EDIT_REQUEST_V0_ID := "https://schemas.haiven.gg/chat-edit-request/v0.json"
## A chat message visible to a gaming client.
const CHAT_MESSAGE_V0_ID := "https://schemas.haiven.gg/chat-message/v0.json"
## A moderation decision made after the send or edit reply changed a message's state, sent only to its author's open sockets. It carries the author's own clientMessageId so the client can match it to the message it sent.
const CHAT_MESSAGE_MODERATED_V0_ID := "https://schemas.haiven.gg/chat-message-moderated/v0.json"
## The accepted message projection and its current moderation state.
const CHAT_MESSAGE_SUBMISSION_V0_ID := "https://schemas.haiven.gg/chat-message-submission/v0.json"
## A request to submit a chat message.
const CHAT_SEND_REQUEST_V0_ID := "https://schemas.haiven.gg/chat-send-request/v0.json"
## A user's typing state in a chat channel.
const CHAT_TYPING_V0_ID := "https://schemas.haiven.gg/chat-typing/v0.json"
## The input a client hands to the embedded policy evaluator for one piece of content.
const CONTENT_SAFETY_INPUT_V1_ID := "https://schemas.haiven.gg/content-safety-input/v1.json"
## A refresh hint that the signed-in account's entitlements changed, sent to its open sockets after the change commits. It carries no grants and authorizes nothing: re-read GET /users/me/entitlements unless that read already returned this projection version or a later one.
const ENTITLEMENTS_UPDATED_V0_ID := "https://schemas.haiven.gg/entitlements-updated/v0.json"
## An accepted friendship as seen by one of its two users.
const FRIEND_RELATIONSHIP_V0_ID := "https://schemas.haiven.gg/friend-relationship/v0.json"
## A friendship or pending friend request the other user deleted.
const FRIEND_REMOVED_V0_ID := "https://schemas.haiven.gg/friend-removed/v0.json"
## A pending friend request and the other user it involves.
const FRIEND_REQUEST_V0_ID := "https://schemas.haiven.gg/friend-request/v0.json"
## The advisory result of an embedded policy evaluation, surfaced to the client before the server has decided.
const LOCAL_SAFETY_ASSESSMENT_V1_ID := "https://schemas.haiven.gg/local-safety-assessment/v1.json"
## The platform Message of the Day, sent once to a signed-in SDK connection right after auth.success while an admin-authored message is active. Web clients do not receive it.
const MOTD_V0_ID := "https://schemas.haiven.gg/motd/v0.json"
## A user notification.
const NOTIFICATION_V0_ID := "https://schemas.haiven.gg/notification/v0.json"
## A deleted notification identifier.
const NOTIFICATION_DELETE_V0_ID := "https://schemas.haiven.gg/notification-delete/v0.json"
## A notification lookup request.
const NOTIFICATION_GET_REQUEST_V0_ID := "https://schemas.haiven.gg/notification-get-request/v0.json"
## A list of user notifications.
const NOTIFICATION_LIST_V0_ID := "https://schemas.haiven.gg/notification-list/v0.json"
## A request to mark a notification category as read.
const NOTIFICATION_READ_REQUEST_V0_ID := "https://schemas.haiven.gg/notification-read-request/v0.json"
## A request to update a notification's visible fields.
const NOTIFICATION_UPDATE_REQUEST_V0_ID := "https://schemas.haiven.gg/notification-update-request/v0.json"
## STUN and TURN servers for the caller's session participation, with when to fetch them again.
const P2P_ICE_SERVERS_REPLY_V0_ID := "https://schemas.haiven.gg/p2p-ice-servers-reply/v0.json"
## One signaling message from a session member to another, relayed by the server.
const P2P_SIGNAL_V0_ID := "https://schemas.haiven.gg/p2p-signal/v0.json"
## A recipient's acknowledgement of one signaling message.
const P2P_SIGNAL_ACK_V0_ID := "https://schemas.haiven.gg/p2p-signal-ack/v0.json"
## An acknowledgement delivered to the member that sent the signaling message.
const P2P_SIGNAL_ACK_EVENT_V0_ID := "https://schemas.haiven.gg/p2p-signal-ack-event/v0.json"
## A signaling message delivered to its recipient, with the sender the server authenticated.
const P2P_SIGNAL_RECEIVED_V0_ID := "https://schemas.haiven.gg/p2p-signal-received/v0.json"
## A user's current availability and status.
const PRESENCE_V0_ID := "https://schemas.haiven.gg/presence/v0.json"
## A stable snake_case error discriminator. Clients switch on it and never parse the human-readable message beside it. The listed values are the vocabulary registered for the REST surface at generation time; other surfaces publish a different partition. The set is open: the server may register a new code at any time, so a client must accept, preserve and forward a value it does not recognise rather than discard the value or reject the response. The values are published under x-extensible-enum rather than enum for that reason — a generator that does not understand the extension emits a plain string, which stays open, whereas enum yields a sealed type that breaks on a code minted after the client shipped.
const REST_ERROR_CODE_V0_ID := "https://schemas.haiven.gg/rest-error-code/v0.json"
## The signed manifest a client verifies before accepting a rotatable embedded policy bundle.
const SAFETY_BUNDLE_MANIFEST_V1_ID := "https://schemas.haiven.gg/safety-bundle-manifest/v1.json"
## A peer-to-peer session closed; every member stops playing in it.
const SESSION_CLOSED_V0_ID := "https://schemas.haiven.gg/session-closed/v0.json"
## A player joined the peer-to-peer session.
const SESSION_MEMBER_JOINED_V0_ID := "https://schemas.haiven.gg/session-member-joined/v0.json"
## A member's participation ended; the host closes its connection to that member.
const SESSION_MEMBER_LEFT_V0_ID := "https://schemas.haiven.gg/session-member-left/v0.json"
## The host's report that the data channel to a guest is open.
const SESSION_PEER_CONNECTED_V0_ID := "https://schemas.haiven.gg/session-peer-connected/v0.json"
## The socket a resumed participation is now bound to.
const SESSION_RESUME_REPLY_V0_ID := "https://schemas.haiven.gg/session-resume-reply/v0.json"
## A request to rebind a participation to the socket that sends it, within 30 seconds of losing the old one.
const SESSION_RESUME_REQUEST_V0_ID := "https://schemas.haiven.gg/session-resume-request/v0.json"
## The host changed the session's state, visibility or metadata.
const SESSION_UPDATED_V0_ID := "https://schemas.haiven.gg/session-updated/v0.json"
## Frames discarded after a WebSocket session expired.
const WS_AUTH_EXPIRED_DROPPED_V0_ID := "https://schemas.haiven.gg/ws-auth-expired-dropped/v0.json"
## The payload a client sends on an auth frame, re-authenticating an open socket.
const WS_AUTH_REQUEST_V0_ID := "https://schemas.haiven.gg/ws-auth-request/v0.json"
## The bearer token a client presents as the payload of the auth frame it sends after connecting.
const WS_AUTH_TOKEN_V0_ID := "https://schemas.haiven.gg/ws-auth-token/v0.json"
## The payload a client sends on a chat.channel.active frame, naming the channel it has open.
const WS_CHAT_ACTIVE_CHANNEL_REQUEST_V0_ID := "https://schemas.haiven.gg/ws-chat-active-channel-request/v0.json"
## The payload of a chat channel event.
const WS_CHAT_CHANNEL_EVENT_V0_ID := "https://schemas.haiven.gg/ws-chat-channel-event/v0.json"
## The payload of a direct-message membership event.
const WS_CHAT_DM_EVENT_V0_ID := "https://schemas.haiven.gg/ws-chat-dm-event/v0.json"
## The payload a client sends on a chat.edit frame, replacing the text of a message it authored.
const WS_CHAT_EDIT_REQUEST_V0_ID := "https://schemas.haiven.gg/ws-chat-edit-request/v0.json"
## The payload of a chat community membership change.
const WS_CHAT_MEMBER_EVENT_V0_ID := "https://schemas.haiven.gg/ws-chat-member-event/v0.json"
## The payload of a chat message event.
const WS_CHAT_MESSAGE_EVENT_V0_ID := "https://schemas.haiven.gg/ws-chat-message-event/v0.json"
## The payload a client sends on a chat.send frame, posting a message to a channel.
const WS_CHAT_SEND_REQUEST_V0_ID := "https://schemas.haiven.gg/ws-chat-send-request/v0.json"
## The payload of a chat community update.
const WS_CHAT_SERVER_EVENT_V0_ID := "https://schemas.haiven.gg/ws-chat-server-event/v0.json"
## The payload of a chat typing event.
const WS_CHAT_TYPING_EVENT_V0_ID := "https://schemas.haiven.gg/ws-chat-typing-event/v0.json"
## The payload a client sends on a chat.typing frame, reporting its own typing state.
const WS_CHAT_TYPING_REQUEST_V0_ID := "https://schemas.haiven.gg/ws-chat-typing-request/v0.json"
## Every frame a client sends over the /v0/ws socket.
const WS_CLIENT_FRAME_V0_ID := "https://schemas.haiven.gg/ws-client-frame/v0.json"
## A report of the server-originated frames discarded while a session was expired.
const WS_DROPPED_FRAMES_V0_ID := "https://schemas.haiven.gg/ws-dropped-frames/v0.json"
## A stable snake_case error discriminator. Clients switch on it and never parse the human-readable message beside it. The listed values are the vocabulary registered for the WebSocket surface at generation time; other surfaces publish a different partition. The set is open: the server may register a new code at any time, so a client must accept, preserve and forward a value it does not recognise rather than discard the value or reject the response. The values are published under x-extensible-enum rather than enum for that reason — a generator that does not understand the extension emits a plain string, which stays open, whereas enum yields a sealed type that breaks on a code minted after the client shipped.
const WS_ERROR_CODE_V0_ID := "https://schemas.haiven.gg/ws-error-code/v0.json"
## The negotiated contract and optional SDK identity for a WebSocket connection.
const WS_HANDSHAKE_V0_ID := "https://schemas.haiven.gg/ws-handshake/v0.json"
## A stable dotted frame discriminator, carried in the "type" field of every message and response. The listed values are the client-visible vocabulary registered at generation time. The set is open: the server may register a new frame type at any time, so a client must accept, preserve and forward a type it does not recognise — routing it to an unhandled-frame path — rather than crash or drop the frame. The values are published under x-extensible-enum rather than enum so that no generator emits a sealed type.
const WS_MESSAGE_TYPE_V0_ID := "https://schemas.haiven.gg/ws-message-type/v0.json"
## A stored notification belonging to the authenticated user.
const WS_NOTIFICATION_V0_ID := "https://schemas.haiven.gg/ws-notification/v0.json"
## The payload a client sends on a notifications.get frame, selecting one notification.
const WS_NOTIFICATION_GET_REQUEST_V0_ID := "https://schemas.haiven.gg/ws-notification-get-request/v0.json"
## The payload a client sends on a notifications.read frame, marking a whole category read.
const WS_NOTIFICATION_READ_REQUEST_V0_ID := "https://schemas.haiven.gg/ws-notification-read-request/v0.json"
## The payload a client sends on a notifications.update frame, revising one notification.
const WS_NOTIFICATION_UPDATE_REQUEST_V0_ID := "https://schemas.haiven.gg/ws-notification-update-request/v0.json"
## The payload of a presence update.
const WS_PRESENCE_EVENT_V0_ID := "https://schemas.haiven.gg/ws-presence-event/v0.json"
## A server frame the client did not ask for.
const WS_SERVER_EVENT_V0_ID := "https://schemas.haiven.gg/ws-server-event/v0.json"
## A server frame that answers one frame the client sent.
const WS_SERVER_REPLY_V0_ID := "https://schemas.haiven.gg/ws-server-reply/v0.json"

static func decode_contract(value: Variant, required_fields: PackedStringArray = []) -> Variant:
	if not value is Dictionary:
		push_error("contract payload must be a Dictionary")
		return null
	for field in required_fields:
		if not value.has(field):
			push_error("contract payload is missing required field: " + field)
			return null
	return value

static func encode_contract(value: Dictionary) -> String:
	return JSON.stringify(value)
