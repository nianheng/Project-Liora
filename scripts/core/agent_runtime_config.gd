extends RefCounted
class_name AgentRuntimeConfig

const MODE_TEST := "test"
const MODE_LLM := "llm"

const ACTIVE_MODE := MODE_LLM

const API_BASE_URL := "https://api.ikuncode.cc/v1"
const API_KEY := "sk-wtjANIHdcy5AMeCBDxdGmfNKA6mBxBNIfqX0DvspHRO5j29t"
const MODEL_NAME := "gemini-2.5-flash"
const REQUEST_TIMEOUT_MS := 20000


static func is_llm_mode() -> bool:
	return ACTIVE_MODE == MODE_LLM
