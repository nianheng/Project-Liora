extends RefCounted
class_name AgentFactory

const RuntimeConfig = preload("res://scripts/core/agent_runtime_config.gd")
const TestAdapterScript = preload("res://scripts/core/agent_test_simulator.gd")
const LLMAdapterScript = preload("res://scripts/core/agent_llm_adapter.gd")


static func create_agent():
	if RuntimeConfig.is_llm_mode():
		return LLMAdapterScript.new()
	return TestAdapterScript.new()
