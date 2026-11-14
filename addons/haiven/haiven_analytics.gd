## Non-blocking, bounded analytics batching over [HaivenRestApi].
##
## [method enqueue] never waits for network I/O. Events are deep-copied once,
## receive stable event/session IDs, and keep the same payload across retries.
## The default scheduler runs the pump and diagnostics on later Godot frames.
class_name HaivenAnalytics
extends RefCounted

const RestError := preload("haiven_rest_error.gd")
const Rewards := preload("haiven_rewards.gd")

const QUEUE_FULL := "queue_full"
const RETRY_SCHEDULED := "retry_scheduled"
const BATCH_DROPPED := "batch_dropped"
const EVENT_REJECTED := "event_rejected"
const INVALID_CONFIGURATION := "invalid_configuration"

## A non-fatal pipeline observation. Keys are `kind`, `eventIds`, `attempt`,
## `delaySeconds`, `error`, and `reason`.
signal diagnostic(value: Dictionary)
## Emitted whenever the queue and current batch become idle.
signal idle

var _api: RefCounted
var _context: Dictionary
var _options: Dictionary
var _analytics_session_id: String
var _next_event_id: Callable
var _now: Callable
var _delay: Callable
var _start: Callable
var _post: Callable
var _queue: Array[Dictionary] = []
var _pumping := false
var _disposed := false
var _buffered_events := 0
var _dropped_events := 0
var _retry_count := 0
var _configuration_error := ""


func _init(
	api: RefCounted,
	context: Dictionary,
	options: Dictionary = {},
	analytics_session_id: String = "",
	next_event_id: Callable = Callable(),
	now: Callable = Callable(),
	delay: Callable = Callable(),
	start: Callable = Callable(),
	post: Callable = Callable(),
) -> void:
	_api = api
	_context = context.duplicate(true)
	_options = {
		"batch_size": int(options.get("batch_size", 100)),
		"max_buffered_events": int(options.get("max_buffered_events", 1000)),
		"max_retries": int(options.get("max_retries", 3)),
		"flush_interval_seconds": float(options.get("flush_interval_seconds", 1.0)),
		"initial_retry_delay_seconds": float(options.get("initial_retry_delay_seconds", 1.0)),
		"max_retry_delay_seconds": float(options.get("max_retry_delay_seconds", 30.0)),
	}
	_configuration_error = _validate_options()
	_analytics_session_id = analytics_session_id if analytics_session_id != "" else Rewards.new_uuid_v7()
	_next_event_id = next_event_id if next_event_id.is_valid() else Rewards.new_uuid_v7
	_now = now if now.is_valid() else _utc_now
	_delay = delay if delay.is_valid() else _default_delay
	_start = start if start.is_valid() else _defer
	_post = post if post.is_valid() else _defer


## Adds an event without waiting for a frame, timer, or network request.
## Returns false when the memory bound has been reached or after [method dispose].
func enqueue(type: String, properties: Dictionary = {}, occurred_at: String = "") -> bool:
	if _disposed:
		return false
	if _configuration_error != "":
		_publish(_diagnostic(INVALID_CONFIGURATION, [], 0, 0.0, null, _configuration_error))
		return false
	if type == "":
		_publish(_diagnostic(EVENT_REJECTED, [], 0, 0.0, null, "analytics event type is required"))
		return false
	var event := {
		"analyticsSessionId": _analytics_session_id,
		"eventId": str(_next_event_id.call()),
		"occurredAt": occurred_at if occurred_at != "" else str(_now.call()),
		"properties": properties.duplicate(true),
		"type": type,
	}
	if _buffered_events >= _options["max_buffered_events"]:
		_dropped_events += 1
		_publish(_diagnostic(QUEUE_FULL, [event["eventId"]], 0, 0.0, null, "analytics queue is full"))
		return false
	_queue.append(event)
	_buffered_events += 1
	if not _pumping:
		_pumping = true
		_start.call(_pump)
	return true


func buffered_event_count() -> int:
	return _buffered_events


func dropped_event_count() -> int:
	return _dropped_events


func retry_count() -> int:
	return _retry_count


## Empty when this batcher can accept events; otherwise describes why it cannot.
func configuration_error() -> String:
	return _configuration_error


## Completes after every event accepted before the queue becomes idle is sent
## or dropped. Events enqueued by callbacks before idle are included.
func flush() -> void:
	while _pumping:
		await idle


## Stops future work and drops queued events. An in-flight request may finish,
## but its result is ignored and its batch is counted as dropped.
func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	if not _queue.is_empty():
		var ids := _event_ids(_queue)
		_dropped_events += _queue.size()
		_buffered_events -= _queue.size()
		_queue.clear()
		_publish(_diagnostic(BATCH_DROPPED, ids, 0, 0.0, null, "batcher disposed"))
	if not _pumping:
		idle.emit()


func _pump() -> void:
	if _options["flush_interval_seconds"] > 0.0:
		await _delay.call(_options["flush_interval_seconds"])
	while not _disposed:
		if _queue.is_empty():
			_pumping = false
			idle.emit()
			return
		var batch: Array[Dictionary] = []
		while batch.size() < _options["batch_size"] and not _queue.is_empty():
			batch.append(_queue.pop_front())
		await _send_with_retry(batch)
		_buffered_events -= batch.size()
	if _buffered_events > 0:
		# Only an in-flight batch remains: queued events were removed by dispose.
		_dropped_events += _buffered_events
		_buffered_events = 0
	_pumping = false
	idle.emit()


func _send_with_retry(batch: Array[Dictionary]) -> void:
	var ids := _event_ids(batch)
	for attempt in range(_options["max_retries"] + 1):
		if _disposed:
			_dropped_events += batch.size()
			_publish(_diagnostic(BATCH_DROPPED, ids, attempt, 0.0, null, "batcher disposed"))
			return
		var response: Variant = await _api.post_sdk_analytics_events({
			"context": _context.duplicate(true),
			"events": batch.duplicate(true),
		})
		if _disposed:
			_dropped_events += batch.size()
			_publish(_diagnostic(BATCH_DROPPED, ids, attempt + 1, 0.0, null, "batcher disposed"))
			return
		if response is Dictionary:
			_publish_rejections(response, batch)
			return
		var failure: Variant = response
		if not response is RestError:
			failure = RestError.new(0, response, "analytics reply was not an object")
		if not failure.is_retryable() or attempt >= _options["max_retries"]:
			_dropped_events += batch.size()
			_publish(_diagnostic(
				BATCH_DROPPED,
				ids,
				attempt + 1,
				0.0,
				failure,
				"retry limit reached" if failure.is_retryable() else "analytics request was refused",
			))
			return
		var retry_attempt := attempt + 1
		var retry_delay := _backoff(retry_attempt)
		_retry_count += 1
		_publish(_diagnostic(RETRY_SCHEDULED, ids, retry_attempt, retry_delay, failure, ""))
		await _delay.call(retry_delay)


func _publish_rejections(response: Dictionary, batch: Array[Dictionary]) -> void:
	var rejected: Variant = response.get("rejected")
	if not rejected is Array:
		return
	for item: Variant in rejected:
		if not item is Dictionary:
			continue
		var index := int(item.get("index", -1))
		var ids: Array[String] = []
		if index >= 0 and index < batch.size():
			ids.append(str(batch[index].get("eventId", "")))
		_publish(_diagnostic(
			EVENT_REJECTED,
			ids,
			0,
			0.0,
			null,
			str(item.get("reason", "server rejected analytics event")),
		))


func _backoff(retry_attempt: int) -> float:
	return minf(
		_options["initial_retry_delay_seconds"] * pow(2.0, retry_attempt - 1),
		_options["max_retry_delay_seconds"],
	)


func _publish(value: Dictionary) -> void:
	_post.call(func() -> void: diagnostic.emit(value))


func _validate_options() -> String:
	if _api == null:
		return "analytics api is required"
	if _options["batch_size"] < 1 or _options["batch_size"] > 100:
		return "analytics batch_size must be 1 to 100"
	if _options["max_buffered_events"] < _options["batch_size"]:
		return "max_buffered_events must be at least batch_size"
	if _options["max_retries"] < 0:
		return "max_retries cannot be negative"
	if _options["flush_interval_seconds"] < 0.0:
		return "flush_interval_seconds cannot be negative"
	if _options["initial_retry_delay_seconds"] <= 0.0:
		return "initial_retry_delay_seconds must be positive"
	if _options["max_retry_delay_seconds"] < _options["initial_retry_delay_seconds"]:
		return "max_retry_delay_seconds must not be smaller than the initial delay"
	return ""


static func _diagnostic(
	kind: String,
	event_ids: Array,
	attempt: int,
	delay_seconds: float,
	error: Variant,
	reason: String,
) -> Dictionary:
	return {
		"kind": kind,
		"eventIds": event_ids.duplicate(),
		"attempt": attempt,
		"delaySeconds": delay_seconds,
		"error": error,
		"reason": reason,
	}


static func _event_ids(events: Array) -> Array[String]:
	var ids: Array[String] = []
	for event: Dictionary in events:
		ids.append(str(event.get("eventId", "")))
	return ids


static func _utc_now() -> String:
	return Time.get_datetime_string_from_system(true, false) + "Z"


static func _defer(operation: Callable) -> void:
	operation.call_deferred()


static func _default_delay(seconds: float) -> void:
	if seconds > 0.0:
		await (Engine.get_main_loop() as SceneTree).create_timer(seconds).timeout
