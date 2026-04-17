extends RefCounted
class_name SystemEvent

const TYPE_ARRIVED_AT_LOCATION := "arrived_at_location"
const TYPE_EXPLORATION_IDLE := "exploration_idle"

var event_type: String = ""
var summary_text: String = ""
var payload: Dictionary = {}


static func make(type: String, summary: String, event_payload: Dictionary = {}) -> SystemEvent:
	var event := SystemEvent.new()
	event.event_type = type
	event.summary_text = summary
	event.payload = event_payload.duplicate(true)
	return event
