extends RefCounted
class_name SystemResult

const TYPE_PATH_PLANNED := "path_planned"
const TYPE_MOVEMENT_STARTED := "movement_started"
const TYPE_COMMAND_REJECTED := "command_rejected"
const TYPE_ALREADY_AT_TARGET := "already_at_target"

var result_type: String = ""
var success: bool = false
var summary_text: String = ""
var target_location_id: String = ""
var path: Array[String] = []
var from_location_id: String = ""
var to_location_id: String = ""
var direction_label: String = ""
var travel_time_seconds: int = 0


static func make(result_type_value: String, success_value: bool, summary: String) -> SystemResult:
	var result := SystemResult.new()
	result.result_type = result_type_value
	result.success = success_value
	result.summary_text = summary
	return result
