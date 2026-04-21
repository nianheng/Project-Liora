extends RefCounted
class_name AgentRuntimeConfig

const MODE_TEST := "test"
const MODE_LLM := "llm"

const ACTIVE_MODE := MODE_TEST

const API_BASE_URL := "https://catiecli.sukaka.top/v1"
const API_KEY := ""
const MODEL_NAME := "gemini-3-flash-preview"
const REQUEST_TIMEOUT_MS := 60000


static func is_llm_mode() -> bool:
	return ACTIVE_MODE == MODE_LLM
