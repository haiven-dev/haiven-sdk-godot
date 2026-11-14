# Headless coverage of the Godot analytics batcher: enqueue never performs I/O,
# snapshots are immutable, batches are bounded, retries preserve event IDs,
# diagnostics are deferred, server rejections identify their event, and dispose
# accounts for every buffered event.
extends SceneTree

const Analytics := preload("res://addons/haiven/haiven_analytics.gd")
const RestApi := preload("res://addons/haiven/haiven_rest_api.gd")
const RestError := preload("res://addons/haiven/haiven_rest_error.gd")


class FakeTransport:
	extends RefCounted
	var responses: Array[Variant] = []
	var sent: Array[Dictionary] = []
	var before_reply: Callable

	func request(method: String, path: String, body: Variant, content_type: String) -> Variant:
		sent.append({
			"method": method,
			"path": path,
			"body": body.duplicate(true),
			"content_type": content_type,
		})
		if before_reply.is_valid():
			var callback := before_reply
			before_reply = Callable()
			callback.call()
		return responses.pop_front()


var failures: Array[String] = []
var checks := 0
var _ids := 0


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)


func next_id() -> String:
	_ids += 1
	return "event-%d" % _ids


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _batch_and_snapshot()
	await _retry_and_drop()
	await _batch_partition()
	await _queue_bound_and_dispose()
	await _dispose_inflight()
	await _dispose_during_retry_delay()
	await _invalid_configuration()
	await _default_scheduler()
	await process_frame
	_report()


func _batch_and_snapshot() -> void:
	var transport := FakeTransport.new()
	var api := RestApi.new(transport.request)
	var pumps: Array[Callable] = []
	var posts: Array[Callable] = []
	var delays: Array[float] = []
	var diagnostics: Array[Dictionary] = []
	var analytics := Analytics.new(
		api,
		{"integrationId": "game-1", "environment": "test", "platform": "godot",
			"sdk": {"name": "godot", "version": "0.0.0"}},
		{"batch_size": 2, "max_buffered_events": 4, "max_retries": 2,
			"flush_interval_seconds": 0.0},
		"analytics-session-1",
		next_id,
		func() -> String: return "2026-10-14T00:00:00Z",
		func(seconds: float) -> void: delays.append(seconds),
		func(operation: Callable) -> void: pumps.append(operation),
		func(callback: Callable) -> void: posts.append(callback),
	)
	analytics.diagnostic.connect(func(value: Dictionary) -> void: diagnostics.append(value))

	var properties := {"score": 7}
	check("the first enqueue is accepted", analytics.enqueue("session.end", properties))
	check("the second enqueue joins the same scheduled pump", analytics.enqueue("unsupported.event", {"reason": "quit"}))
	properties["score"] = 99
	check("enqueue performs no request inline", transport.sent.is_empty() and pumps.size() == 1)
	check("accepted events count as buffered", analytics.buffered_event_count() == 2)

	transport.responses.append({"accepted": 1, "duplicate": 0,
		"rejected": [{"index": 1, "reason": "unsupported event"}]})
	await pumps.pop_front().call()
	check("the pump uses the generated analytics endpoint",
		transport.sent.size() == 1
		and transport.sent[0]["method"] == "POST"
		and transport.sent[0]["path"] == "/sdk/analytics/events"
		and transport.sent[0]["content_type"] == "application/json")
	var body: Dictionary = transport.sent[0]["body"]
	check("the request carries the immutable context and one bounded batch",
		body["context"]["integrationId"] == "game-1" and body["events"].size() == 2)
	check("the queued event is an immutable snapshot with stable generated fields",
		body["events"][0]["properties"]["score"] == 7
		and body["events"][0]["eventId"] == "event-1"
		and body["events"][0]["analyticsSessionId"] == "analytics-session-1"
		and body["events"][0]["occurredAt"] == "2026-10-14T00:00:00Z")
	check("a completed batch releases its buffer", analytics.buffered_event_count() == 0)
	check("diagnostics do not invoke subscribers inside the pump", diagnostics.is_empty() and posts.size() == 1)
	posts.pop_front().call()
	check("a server rejection identifies the rejected event",
		diagnostics[0]["kind"] == Analytics.EVENT_REJECTED
		and diagnostics[0]["eventIds"] == ["event-2"]
		and diagnostics[0]["reason"] == "unsupported event")
	check("a successful batch does not retry or drop", analytics.retry_count() == 0
		and analytics.dropped_event_count() == 0 and delays.is_empty())
	posts.clear()
	analytics = null


func _retry_and_drop() -> void:
	var transport := FakeTransport.new()
	var api := RestApi.new(transport.request)
	var pumps: Array[Callable] = []
	var posts: Array[Callable] = []
	var delays: Array[float] = []
	var diagnostics: Array[Dictionary] = []
	var analytics := Analytics.new(
		api,
		{"integrationId": "game-1", "platform": "godot"},
		{"batch_size": 1, "max_buffered_events": 2, "max_retries": 2,
			"flush_interval_seconds": 0.0, "initial_retry_delay_seconds": 1.0,
			"max_retry_delay_seconds": 10.0},
		"analytics-session-2",
		next_id,
		func() -> String: return "2026-10-14T00:00:01Z",
		func(seconds: float) -> void: delays.append(seconds),
		func(operation: Callable) -> void: pumps.append(operation),
		func(callback: Callable) -> void: posts.append(callback),
	)
	analytics.diagnostic.connect(func(value: Dictionary) -> void: diagnostics.append(value))

	transport.responses.append_array([RestError.new(503), RestError.new(429), {"accepted": 1}])
	check("a retryable event is accepted", analytics.enqueue("sdk.health", {"status": "ok"}))
	await pumps.pop_front().call()
	check("retryable failures use capped exponential backoff", delays == [1.0, 2.0])
	check("retry count records retries, not attempts", analytics.retry_count() == 2)
	check("every retry preserves the same event id and payload snapshot",
		transport.sent.size() == 3
		and transport.sent[0]["body"] == transport.sent[1]["body"]
		and transport.sent[1]["body"] == transport.sent[2]["body"])
	check("a successful retry releases the event without dropping it",
		analytics.buffered_event_count() == 0 and analytics.dropped_event_count() == 0)
	check("retry diagnostics are deferred", diagnostics.is_empty() and posts.size() == 2)
	for callback in posts:
		callback.call()
	check("retry diagnostics carry attempts and stable event ids",
		diagnostics.map(func(value: Dictionary) -> int: return value["attempt"]) == [1, 2]
		and diagnostics[0]["eventIds"] == diagnostics[1]["eventIds"])

	posts.clear()
	diagnostics.clear()
	delays.clear()
	transport.responses.append_array([RestError.new(503), RestError.new(503), RestError.new(503)])
	check("a second event is accepted", analytics.enqueue("sdk.health", {"status": "degraded"}))
	await pumps.pop_front().call()
	check("the retry limit drops the batch after the initial try plus two retries",
		transport.sent.size() == 6 and analytics.dropped_event_count() == 1)
	check("retry exhaustion schedules two more delays", delays == [1.0, 2.0])
	for callback in posts:
		callback.call()
	check("retry exhaustion emits one batch-dropped diagnostic",
		diagnostics[-1]["kind"] == Analytics.BATCH_DROPPED
		and diagnostics[-1]["attempt"] == 3
		and diagnostics[-1]["reason"] == "retry limit reached")
	posts.clear()
	analytics = null


func _batch_partition() -> void:
	var transport := FakeTransport.new()
	var api := RestApi.new(transport.request)
	var pumps: Array[Callable] = []
	var analytics := Analytics.new(
		api,
		{"integrationId": "game-1", "platform": "godot"},
		{"batch_size": 2, "max_buffered_events": 4, "flush_interval_seconds": 0.0},
		"analytics-session-3",
		next_id,
		func() -> String: return "2026-10-14T00:00:02Z",
		Callable(),
		func(operation: Callable) -> void: pumps.append(operation),
		func(callback: Callable) -> void: callback.call(),
	)
	transport.responses.append_array([{"accepted": 2}, {"accepted": 1}])
	analytics.enqueue("one")
	analytics.enqueue("two")
	analytics.enqueue("three")
	check("three enqueues schedule one drain", pumps.size() == 1 and analytics.buffered_event_count() == 3)
	await pumps.pop_front().call()
	check("batch_size partitions the drain into two requests",
		transport.sent.size() == 2
		and transport.sent[0]["body"]["events"].size() == 2
		and transport.sent[1]["body"]["events"].size() == 1)
	analytics = null


func _queue_bound_and_dispose() -> void:
	var transport := FakeTransport.new()
	var api := RestApi.new(transport.request)
	var pumps: Array[Callable] = []
	var posts: Array[Callable] = []
	var diagnostics: Array[Dictionary] = []
	var analytics := Analytics.new(
		api,
		{"integrationId": "game-1", "platform": "godot"},
		{"batch_size": 2, "max_buffered_events": 2, "flush_interval_seconds": 0.0},
		"analytics-session-4",
		next_id,
		func() -> String: return "2026-10-14T00:00:03Z",
		Callable(),
		func(operation: Callable) -> void: pumps.append(operation),
		func(callback: Callable) -> void: posts.append(callback),
	)
	analytics.diagnostic.connect(func(value: Dictionary) -> void: diagnostics.append(value))
	check("the bounded queue accepts its capacity", analytics.enqueue("one") and analytics.enqueue("two"))
	check("the bounded queue refuses overflow without starting another pump", not analytics.enqueue("three")
		and pumps.size() == 1 and transport.sent.is_empty())
	check("queue-full accounting is immediate but its callback is deferred",
		analytics.dropped_event_count() == 1 and diagnostics.is_empty() and posts.size() == 1)
	analytics.dispose()
	check("dispose releases and accounts for queued events",
		analytics.buffered_event_count() == 0 and analytics.dropped_event_count() == 3)
	check("enqueue after dispose is refused", not analytics.enqueue("four"))
	await pumps.pop_front().call()
	check("a disposed pending pump performs no request", transport.sent.is_empty())
	for callback in posts:
		callback.call()
	check("queue-full and dispose diagnostics keep distinct reasons",
		diagnostics.map(func(value: Dictionary) -> String: return value["kind"])
		== [Analytics.QUEUE_FULL, Analytics.BATCH_DROPPED])
	posts.clear()
	analytics = null


func _dispose_inflight() -> void:
	var transport := FakeTransport.new()
	var api := RestApi.new(transport.request)
	var pumps: Array[Callable] = []
	var posts: Array[Callable] = []
	var diagnostics: Array[Dictionary] = []
	var analytics := Analytics.new(
		api,
		{"integrationId": "game-1", "platform": "godot"},
		{"batch_size": 1, "max_buffered_events": 1, "flush_interval_seconds": 0.0},
		"analytics-session-5",
		next_id,
		func() -> String: return "2026-10-14T00:00:04Z",
		Callable(),
		func(operation: Callable) -> void: pumps.append(operation),
		func(callback: Callable) -> void: posts.append(callback),
	)
	analytics.diagnostic.connect(func(value: Dictionary) -> void: diagnostics.append(value))
	transport.responses.append({"accepted": 1})
	transport.before_reply = analytics.dispose
	check("an event can be disposed while its request is in flight", analytics.enqueue("in.flight"))
	await pumps.pop_front().call()
	check("dispose ignores and accounts for an in-flight response",
		analytics.buffered_event_count() == 0 and analytics.dropped_event_count() == 1)
	for callback in posts:
		callback.call()
	check("in-flight disposal emits one batch-dropped diagnostic",
		diagnostics.size() == 1 and diagnostics[0]["kind"] == Analytics.BATCH_DROPPED
		and diagnostics[0]["reason"] == "batcher disposed")
	posts.clear()
	transport.before_reply = Callable()
	analytics = null


func _dispose_during_retry_delay() -> void:
	var transport := FakeTransport.new()
	var api := RestApi.new(transport.request)
	var pumps: Array[Callable] = []
	var posts: Array[Callable] = []
	var diagnostics: Array[Dictionary] = []
	var holder: Array[RefCounted] = []
	var analytics := Analytics.new(
		api,
		{"integrationId": "game-1", "platform": "godot"},
		{"batch_size": 1, "max_buffered_events": 1, "flush_interval_seconds": 0.0},
		"analytics-session-delay-dispose",
		next_id,
		func() -> String: return "2026-10-14T00:00:04Z",
		func(_seconds: float) -> void: holder[0].dispose(),
		func(operation: Callable) -> void: pumps.append(operation),
		func(callback: Callable) -> void: posts.append(callback),
	)
	holder.append(analytics)
	analytics.diagnostic.connect(func(value: Dictionary) -> void: diagnostics.append(value))
	transport.responses.append(RestError.new(503))
	check("a retrying event can be disposed during backoff", analytics.enqueue("sdk.health"))
	await pumps.pop_front().call()
	check("retry-delay disposal releases and accounts for the in-flight batch",
		analytics.buffered_event_count() == 0 and analytics.dropped_event_count() == 1)
	for callback in posts:
		callback.call()
	check("retry-delay disposal emits exactly one batch-dropped diagnostic",
		diagnostics.filter(func(value: Dictionary) -> bool:
			return value["kind"] == Analytics.BATCH_DROPPED).size() == 1)
	posts.clear()
	holder.clear()
	analytics = null


func _invalid_configuration() -> void:
	var transport := FakeTransport.new()
	var api := RestApi.new(transport.request)
	var posts: Array[Callable] = []
	var diagnostics: Array[Dictionary] = []
	var analytics := Analytics.new(
		api,
		{"integrationId": "game-1", "platform": "godot"},
		{"batch_size": 0},
		"analytics-session-invalid",
		next_id,
		Callable(),
		Callable(),
		Callable(),
		func(callback: Callable) -> void: posts.append(callback),
	)
	analytics.diagnostic.connect(func(value: Dictionary) -> void: diagnostics.append(value))
	check("invalid release configuration is reported without relying on assertions",
		analytics.configuration_error() == "analytics batch_size must be 1 to 100")
	check("invalid configuration refuses enqueue without scheduling or I/O",
		not analytics.enqueue("sdk.health") and analytics.buffered_event_count() == 0
		and transport.sent.is_empty())
	for callback in posts:
		callback.call()
	check("invalid configuration emits a deferred finite diagnostic",
		diagnostics.size() == 1 and diagnostics[0]["kind"] == Analytics.INVALID_CONFIGURATION)
	posts.clear()
	analytics = null


func _default_scheduler() -> void:
	var transport := FakeTransport.new()
	transport.responses.append({"accepted": 1})
	var api := RestApi.new(transport.request)
	var analytics := Analytics.new(
		api,
		{"integrationId": "game-1", "platform": "godot"},
		{"batch_size": 1, "max_buffered_events": 1, "flush_interval_seconds": 0.0},
		"analytics-session-default",
		next_id,
		func() -> String: return "2026-10-14T00:00:05Z",
	)
	check("the public default scheduler accepts without inline I/O",
		analytics.enqueue("sdk.health", {"status": "ok"}) and transport.sent.is_empty())
	await analytics.flush()
	check("the public default scheduler drains on a later engine frame",
		transport.sent.size() == 1 and analytics.buffered_event_count() == 0)
	analytics = null


func _report() -> void:
	if failures.is_empty():
		print("ok   GDScript analytics")
		print("HAIVEN_TEST_PASS analytics %d" % checks)
		quit(0)
		return
	for failure in failures:
		print("FAIL ", failure)
	quit(1)
