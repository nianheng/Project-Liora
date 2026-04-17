extends RefCounted
class_name AgentContext

const PROTOCOL_VERSION := "agent_context.v1"
const TRIGGER_PLAYER_MESSAGE := "player_message"
const TRIGGER_SYSTEM_EVENT := "system_event"

var protocol_version: String = PROTOCOL_VERSION
var trigger_type: String = TRIGGER_PLAYER_MESSAGE
var trigger_reason: String = ""

var world_time_seconds: int = 0
var current_location_id: String = ""
var current_location_name: String = ""
var agent_state: String = ""

var short_term_goal: String = ""
var recent_dialogue_summary: String = ""
var desired_location_ids: Array[String] = []

var visible_routes: Array[Dictionary] = []
var active_travel_route: Dictionary = {}
var allowed_command_types: Array[String] = []


func format_clock() -> String:
	var normalized: int = posmod(world_time_seconds, 24 * 3600)
	var hours: int = normalized / 3600
	var minutes: int = (normalized % 3600) / 60
	var seconds: int = normalized % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]
