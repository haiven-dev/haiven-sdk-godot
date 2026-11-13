# Generated from the published Haiven contract schemas — do not edit by hand.
#
# The values are the `x-extensible-enum` published for this vocabulary in the
# Haiven contract schemas.
#
# The set is open: an unrecognised value is one this binding predates, not an
# invalid one. Never reject on it.

extends RefCounted
## Registered MessageType wire values and recognition helper.
class_name HaivenMessageType

## The registered `ping` wire value.
const PING: String = "ping"
## The registered `pong` wire value.
const PONG: String = "pong"
## The registered `auth` wire value.
const AUTH: String = "auth"
## The registered `auth.success` wire value.
const AUTH_SUCCESS: String = "auth.success"
## The registered `auth.failure` wire value.
const AUTH_FAILURE: String = "auth.failure"
## The registered `auth.expired` wire value.
const AUTH_EXPIRED: String = "auth.expired"
## The registered `auth.expired.dropped` wire value.
const AUTH_EXPIRED_DROPPED: String = "auth.expired.dropped"
## The registered `chat.send` wire value.
const CHAT_SEND: String = "chat.send"
## The registered `chat.edit` wire value.
const CHAT_EDIT: String = "chat.edit"
## The registered `chat.channel.active` wire value.
const CHAT_CHANNEL_ACTIVE: String = "chat.channel.active"
## The registered `chat.typing` wire value.
const CHAT_TYPING: String = "chat.typing"
## The registered `chat.message` wire value.
const CHAT_MESSAGE: String = "chat.message"
## The registered `chat.message.updated` wire value.
const CHAT_MESSAGE_UPDATED: String = "chat.message.updated"
## The registered `chat.message.deleted` wire value.
const CHAT_MESSAGE_DELETED: String = "chat.message.deleted"
## The registered `chat.message.moderated` wire value.
const CHAT_MESSAGE_MODERATED: String = "chat.message.moderated"
## The registered `chat.dm.new` wire value.
const CHAT_DM_NEW: String = "chat.dm.new"
## The registered `chat.dm.left` wire value.
const CHAT_DM_LEFT: String = "chat.dm.left"
## The registered `chat.community.updated` wire value.
const CHAT_COMMUNITY_UPDATED: String = "chat.community.updated"
## The registered `chat.community.deleted` wire value.
const CHAT_COMMUNITY_DELETED: String = "chat.community.deleted"
## The registered `chat.community.member.joined` wire value.
const CHAT_COMMUNITY_MEMBER_JOINED: String = "chat.community.member.joined"
## The registered `chat.community.member.left` wire value.
const CHAT_COMMUNITY_MEMBER_LEFT: String = "chat.community.member.left"
## The registered `chat.channel` wire value.
const CHAT_CHANNEL: String = "chat.channel"
## The registered `chat.channel.updated` wire value.
const CHAT_CHANNEL_UPDATED: String = "chat.channel.updated"
## The registered `chat.channel.deleted` wire value.
const CHAT_CHANNEL_DELETED: String = "chat.channel.deleted"
## The registered `notifications.update` wire value.
const NOTIFICATIONS_UPDATE: String = "notifications.update"
## The registered `notifications.read` wire value.
const NOTIFICATIONS_READ: String = "notifications.read"
## The registered `notifications.get` wire value.
const NOTIFICATIONS_GET: String = "notifications.get"
## The registered `notifications.list` wire value.
const NOTIFICATIONS_LIST: String = "notifications.list"
## The registered `notifications.list.unread` wire value.
const NOTIFICATIONS_LIST_UNREAD: String = "notifications.list.unread"
## The registered `notifications.new` wire value.
const NOTIFICATIONS_NEW: String = "notifications.new"
## The registered `notifications.delete` wire value.
const NOTIFICATIONS_DELETE: String = "notifications.delete"
## The registered `presence.updated` wire value.
const PRESENCE_UPDATED: String = "presence.updated"
## The registered `friends.request.new` wire value.
const FRIENDS_REQUEST_NEW: String = "friends.request.new"
## The registered `friends.request.accepted` wire value.
const FRIENDS_REQUEST_ACCEPTED: String = "friends.request.accepted"
## The registered `friends.removed` wire value.
const FRIENDS_REMOVED: String = "friends.removed"
## The registered `account.identity.linked` wire value.
const ACCOUNT_IDENTITY_LINKED: String = "account.identity.linked"
## The registered `account.identity.link.failed` wire value.
const ACCOUNT_IDENTITY_LINK_FAILED: String = "account.identity.link.failed"
## The registered `agegate.updated` wire value.
const AGEGATE_UPDATED: String = "agegate.updated"
## The registered `entitlements.updated` wire value.
const ENTITLEMENTS_UPDATED: String = "entitlements.updated"
## The registered `motd` wire value.
const MOTD: String = "motd"
## The registered `session.resume` wire value.
const SESSION_RESUME: String = "session.resume"
## The registered `session.peer.connected` wire value.
const SESSION_PEER_CONNECTED: String = "session.peer.connected"
## The registered `session.member.joined` wire value.
const SESSION_MEMBER_JOINED: String = "session.member.joined"
## The registered `session.member.left` wire value.
const SESSION_MEMBER_LEFT: String = "session.member.left"
## The registered `session.updated` wire value.
const SESSION_UPDATED: String = "session.updated"
## The registered `session.closed` wire value.
const SESSION_CLOSED: String = "session.closed"
## The registered `p2p.signal` wire value.
const P2P_SIGNAL: String = "p2p.signal"
## The registered `p2p.signal.received` wire value.
const P2P_SIGNAL_RECEIVED: String = "p2p.signal.received"
## The registered `p2p.signal.ack` wire value.
const P2P_SIGNAL_ACK: String = "p2p.signal.ack"
## The registered `p2p.ice.servers` wire value.
const P2P_ICE_SERVERS: String = "p2p.ice.servers"

const _REGISTERED := {
	PING: true,
	PONG: true,
	AUTH: true,
	AUTH_SUCCESS: true,
	AUTH_FAILURE: true,
	AUTH_EXPIRED: true,
	AUTH_EXPIRED_DROPPED: true,
	CHAT_SEND: true,
	CHAT_EDIT: true,
	CHAT_CHANNEL_ACTIVE: true,
	CHAT_TYPING: true,
	CHAT_MESSAGE: true,
	CHAT_MESSAGE_UPDATED: true,
	CHAT_MESSAGE_DELETED: true,
	CHAT_MESSAGE_MODERATED: true,
	CHAT_DM_NEW: true,
	CHAT_DM_LEFT: true,
	CHAT_COMMUNITY_UPDATED: true,
	CHAT_COMMUNITY_DELETED: true,
	CHAT_COMMUNITY_MEMBER_JOINED: true,
	CHAT_COMMUNITY_MEMBER_LEFT: true,
	CHAT_CHANNEL: true,
	CHAT_CHANNEL_UPDATED: true,
	CHAT_CHANNEL_DELETED: true,
	NOTIFICATIONS_UPDATE: true,
	NOTIFICATIONS_READ: true,
	NOTIFICATIONS_GET: true,
	NOTIFICATIONS_LIST: true,
	NOTIFICATIONS_LIST_UNREAD: true,
	NOTIFICATIONS_NEW: true,
	NOTIFICATIONS_DELETE: true,
	PRESENCE_UPDATED: true,
	FRIENDS_REQUEST_NEW: true,
	FRIENDS_REQUEST_ACCEPTED: true,
	FRIENDS_REMOVED: true,
	ACCOUNT_IDENTITY_LINKED: true,
	ACCOUNT_IDENTITY_LINK_FAILED: true,
	AGEGATE_UPDATED: true,
	ENTITLEMENTS_UPDATED: true,
	MOTD: true,
	SESSION_RESUME: true,
	SESSION_PEER_CONNECTED: true,
	SESSION_MEMBER_JOINED: true,
	SESSION_MEMBER_LEFT: true,
	SESSION_UPDATED: true,
	SESSION_CLOSED: true,
	P2P_SIGNAL: true,
	P2P_SIGNAL_RECEIVED: true,
	P2P_SIGNAL_ACK: true,
	P2P_ICE_SERVERS: true,
}

## Whether this binding was compiled knowing the value. Never a parse gate.
static func is_recognised(value: String) -> bool:
	return _REGISTERED.has(value)
