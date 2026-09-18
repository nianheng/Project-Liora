extends RefCounted
class_name AgentRuntimeConfig

const MODE_TEST := "test"
const MODE_LLM := "llm"

const API_PROTOCOL_OPENAI := "openai"
const API_PROTOCOL_GEMINI := "gemini"

const LOCAL_CONFIG_PATH := "res://agent_runtime.local.json"

const DEFAULT_ACTIVE_MODE := MODE_TEST
const DEFAULT_API_BASE_URL := ""
const DEFAULT_API_KEY := ""
const DEFAULT_API_PROTOCOL := API_PROTOCOL_OPENAI
const DEFAULT_MODEL_NAME := ""
const DEFAULT_REQUEST_TIMEOUT_MS := 60000

static var _config_loaded := false
static var _local_config: Dictionary = {}


static func _ensure_local_config_loaded() -> void:
	if _config_loaded:
		return
	_config_loaded = true
	_local_config = {}
	if not FileAccess.file_exists(LOCAL_CONFIG_PATH):
		return
	var file := FileAccess.open(LOCAL_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("AgentRuntimeConfig could not open local config file: %s" % LOCAL_CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("AgentRuntimeConfig local config is not a JSON object: %s" % LOCAL_CONFIG_PATH)
		return
	_local_config = (parsed as Dictionary).duplicate(true)


static func get_active_mode() -> String:
	_ensure_local_config_loaded()
	var configured_mode: String = str(_local_config.get("mode", DEFAULT_ACTIVE_MODE)).strip_edges()
	if configured_mode == MODE_LLM:
		return MODE_LLM
	return MODE_TEST


static func get_api_base_url() -> String:
	_ensure_local_config_loaded()
	return str(_local_config.get("api_base_url", DEFAULT_API_BASE_URL)).strip_edges()


static func get_api_key() -> String:
	_ensure_local_config_loaded()
	return str(_local_config.get("api_key", DEFAULT_API_KEY)).strip_edges()


static func get_api_protocol() -> String:
	_ensure_local_config_loaded()
	var configured_protocol := str(_local_config.get("api_protocol", DEFAULT_API_PROTOCOL)).strip_edges().to_lower()
	if configured_protocol == API_PROTOCOL_OPENAI or configured_protocol == API_PROTOCOL_GEMINI:
		return configured_protocol
	push_warning("AgentRuntimeConfig unknown api_protocol '%s'; using '%s'." % [configured_protocol, DEFAULT_API_PROTOCOL])
	return DEFAULT_API_PROTOCOL


static func get_model_name() -> String:
	_ensure_local_config_loaded()
	return str(_local_config.get("model_name", DEFAULT_MODEL_NAME)).strip_edges()


static func get_request_timeout_ms() -> int:
	_ensure_local_config_loaded()
	return max(1000, int(_local_config.get("request_timeout_ms", DEFAULT_REQUEST_TIMEOUT_MS)))


static func is_llm_mode() -> bool:
	return (
		get_active_mode() == MODE_LLM
		and not get_api_base_url().is_empty()
		and not get_api_key().is_empty()
		and not get_model_name().is_empty()
	)
