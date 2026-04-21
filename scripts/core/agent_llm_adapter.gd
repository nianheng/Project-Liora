extends "res://scripts/core/agent_adapter.gd"
class_name AgentLLMAdapter

const AgentCommandScript = preload("res://scripts/core/types/agent_command.gd")
const RuntimeConfig = preload("res://scripts/core/agent_runtime_config.gd")


func get_adapter_name() -> String:
	return "llm"


func is_async() -> bool:
	return true


func process_player_message(message: String, context, world_graph: WorldGraph):
	var payload: Dictionary = build_request_payload_for_player_message(message, context, world_graph)
	var response: Dictionary = _perform_request(payload)
	if not bool(response.get("ok", false)):
		push_warning("LLM request failed: %s" % JSON.stringify(response))
		return _build_fallback_output(message, world_graph)
	return _parse_response_to_output(response.get("body", {}), message, world_graph)


func process_system_event(event, context, world_graph: WorldGraph):
	var payload: Dictionary = build_request_payload_for_system_event(event, context, world_graph)
	var response: Dictionary = _perform_request(payload)
	if not bool(response.get("ok", false)):
		push_warning("LLM system event request failed: %s" % JSON.stringify(response))
		return _build_system_event_fallback_output(event, context, world_graph)
	return _parse_response_to_output(response.get("body", {}), event.summary_text, world_graph)


func process_player_message_async(host: Node, message: String, context, world_graph: WorldGraph):
	var payload: Dictionary = build_request_payload_for_player_message(message, context, world_graph)
	var response: Dictionary = await _perform_request_async(host, payload)
	if not bool(response.get("ok", false)):
		push_warning("LLM request failed: %s" % JSON.stringify(response))
		return _build_fallback_output(message, world_graph)
	return _parse_response_to_output(response.get("body", {}), message, world_graph)


func process_system_event_async(host: Node, event, context, world_graph: WorldGraph):
	var payload: Dictionary = build_request_payload_for_system_event(event, context, world_graph)
	var response: Dictionary = await _perform_request_async(host, payload)
	if not bool(response.get("ok", false)):
		push_warning("LLM system event request failed: %s" % JSON.stringify(response))
		return _build_system_event_fallback_output(event, context, world_graph)
	return _parse_response_to_output(response.get("body", {}), event.summary_text, world_graph)


func build_system_prompt() -> String:
	return "\n".join([
		"You are the stranded girl agent in a sci-fi mystery exploration game.",
		"Reply naturally and in character.",
		"Never claim world state changes unless the system already provided them.",
		"Only emit commands from the allowed command schema.",
		"If you decide to go somewhere, commands must be an array of objects, not strings.",
		"You may use two command shapes only:",
		"1. {\"type\": \"move_to_location\", \"target_location_id\": string, \"target_location_name\": string}",
		"2. {\"type\": \"act\", \"target_id\": string, \"action\": string, \"params\": object}",
		"3. {\"type\": \"set_auto_explore_interval\", \"seconds\": integer}",
		"Do not invent locations, objects, actions, or hidden state.",
		"Use exact ids and names from the known world locations list and exact object ids from the provided object lists.",
		"For act commands, choose only actions that appear in the target object's actions list.",
		"Use inspect to check an object, pick_up to take an item, use to directly use a carried item such as food, use_item to apply a carried item to a target object, set_value to change an allowed target value, and open to open a door or hatch.",
		"Use set_auto_explore_interval only when you want to change how soon the next automatic exploration update should happen.",
		"set_auto_explore_interval.seconds must be an integer between 10 and 60.",
		"Use a larger value (40-60) if you want to wait longer for the player to respond. Use a smaller value(10-20) if you want to continue exploring by yourself sooner.",
		"For set_value, params is required and must contain both key and value.",
		"Valid example: {\"type\": \"act\", \"target_id\": \"some_object_id\", \"action\": \"set_value\", \"params\": {\"key\": \"some_state_key\", \"value\": 1}}",
		"If you are unsure, return an empty commands array.",
		"The system owns all persistent state.",
		"Return valid JSON only.",
		"Schema:",
		"{\"reply_text\": string, \"commands\": [{\"type\": string, ...}]}"
	])


func build_player_prompt(message: String, context, world_graph: WorldGraph) -> String:
	var route_lines: Array[String] = []
	for route in context.visible_routes:
		route_lines.append("- %s | %s | %s" % [
			route.get("to_location_name", "unknown"),
			route.get("direction_label", "unknown"),
			"allowed" if bool(route.get("allowed", false)) else "blocked"
		])

	var known_location_lines: Array[String] = []
	for location in world_graph.get_locations():
		known_location_lines.append("- %s | %s" % [
			location.get("id", "unknown"),
			location.get("name", "unknown")
		])

	var current_location_object_lines: Array[String] = _format_visible_object_lines(context.current_location_objects)
	var inventory_object_lines: Array[String] = _format_visible_object_lines(context.inventory_objects)
	var memory_lines: Array[String] = _format_memory_lines(context.memory_entries)

	return "\n".join([
		"Protocol: agent_output.v1",
		"Character name: %s" % context.character_name,
		"Character profile: %s" % context.character_profile,
		"Character status: %s" % JSON.stringify(context.character_status),
		"Hunger prompt hint: %s" % context.hunger_prompt_hint,
		"Current auto explore interval seconds: %d" % int(context.auto_explore_interval_seconds),
		"Time: %s" % context.format_clock(),
		"Location: %s" % context.current_location_name,
		"Agent state: %s" % context.agent_state,
		"Short-term goal: %s" % context.short_term_goal,
		"Recent dialogue summary: %s" % context.recent_dialogue_summary,
		"Desired locations: %s" % ", ".join(context.desired_location_ids),
		"Memory:",
		"\n".join(memory_lines),
		"Current location objects:",
		"\n".join(current_location_object_lines),
		"Inventory objects:",
		"\n".join(inventory_object_lines),
		"Known world locations (use exact id and exact name if issuing a move command):",
		"\n".join(known_location_lines),
		"Visible routes:",
		"\n".join(route_lines),
		"Allowed commands: %s" % ", ".join(context.allowed_command_types),
		"Act command reminder: use target_id from current_location_objects or inventory_objects, and only use actions listed on that target.",
		"set_value reminder: always include params.key and params.value. Never omit key.",
		"set_auto_explore_interval reminder: seconds must be an integer between 10 and 60.",
		"Player message: %s" % message
	])


func build_request_payload_for_player_message(message: String, context, world_graph: WorldGraph) -> Dictionary:
	return _build_request_payload_from_prompt(build_player_prompt(message, context, world_graph))


func build_request_payload_for_system_event(event, context, world_graph: WorldGraph) -> Dictionary:
	return _build_request_payload_from_prompt(build_system_event_prompt(event, context, world_graph))


func build_system_event_prompt(event, context, world_graph: WorldGraph) -> String:
	var route_lines: Array[String] = []
	for route in context.visible_routes:
		route_lines.append("- %s | %s | %s" % [
			route.get("to_location_name", "unknown"),
			route.get("direction_label", "unknown"),
			"allowed" if bool(route.get("allowed", false)) else "blocked"
		])

	var known_location_lines: Array[String] = []
	for location in world_graph.get_locations():
		known_location_lines.append("- %s | %s" % [
			location.get("id", "unknown"),
			location.get("name", "unknown")
		])

	var current_location_object_lines: Array[String] = _format_visible_object_lines(context.current_location_objects)
	var inventory_object_lines: Array[String] = _format_visible_object_lines(context.inventory_objects)
	var memory_lines: Array[String] = _format_memory_lines(context.memory_entries)

	return "\n".join([
		"Protocol: agent_output.v1",
		"Trigger type: system_event",
		"Trigger reason: %s" % str(context.trigger_reason),
		"Character name: %s" % context.character_name,
		"Character profile: %s" % context.character_profile,
		"Character status: %s" % JSON.stringify(context.character_status),
		"Hunger prompt hint: %s" % context.hunger_prompt_hint,
		"Current auto explore interval seconds: %d" % int(context.auto_explore_interval_seconds),
		"Time: %s" % context.format_clock(),
		"Location: %s" % context.current_location_name,
		"Agent state: %s" % context.agent_state,
		"Short-term goal: %s" % context.short_term_goal,
		"Recent dialogue summary: %s" % context.recent_dialogue_summary,
		"Desired locations: %s" % ", ".join(context.desired_location_ids),
		"Memory:",
		"\n".join(memory_lines),
		"Current location objects:",
		"\n".join(current_location_object_lines),
		"Inventory objects:",
		"\n".join(inventory_object_lines),
		"Known world locations (use exact id and exact name if issuing a move command):",
		"\n".join(known_location_lines),
		"Visible routes:",
		"\n".join(route_lines),
		"Allowed commands: %s" % ", ".join(context.allowed_command_types),
		"Act command reminder: use target_id from current_location_objects or inventory_objects, and only use actions listed on that target.",
		"set_value reminder: always include params.key and params.value. Never omit key.",
		"set_auto_explore_interval reminder: seconds must be an integer between 10 and 60.",
		"System event type: %s" % str(event.event_type),
		"System event summary: %s" % str(event.summary_text),
		"System event payload: %s" % JSON.stringify(event.payload)
	])


func _format_visible_object_lines(objects: Array) -> Array[String]:
	var lines: Array[String] = []
	if objects.is_empty():
		return ["- none"]
	for object_variant in objects:
		if typeof(object_variant) != TYPE_DICTIONARY:
			continue
		var object_data: Dictionary = object_variant
		lines.append("- %s | %s | %s | actions=%s | state=%s" % [
			str(object_data.get("id", "unknown")),
			str(object_data.get("name", "unknown")),
			str(object_data.get("type", "object")),
			JSON.stringify(object_data.get("actions", [])),
			JSON.stringify(object_data.get("state", {}))
		])
	return lines


func _format_memory_lines(entries: Array) -> Array[String]:
	var lines: Array[String] = []
	if entries.is_empty():
		return ["- none"]
	for entry_variant in entries:
		var entry_text: String = str(entry_variant).strip_edges()
		if entry_text.is_empty():
			continue
		lines.append("- " + entry_text.replace("\n", "\n  "))
	return lines if not lines.is_empty() else ["- none"]


func _build_request_payload_from_prompt(prompt_text: String) -> Dictionary:
	if _is_gemini_model():
		return {
			"systemInstruction": {
				"parts": [
					{
						"text": build_system_prompt()
					}
				]
			},
			"contents": [
				{
					"role": "user",
					"parts": [
						{
							"text": prompt_text
						}
					]
				}
			],
			"generationConfig": {
				"temperature": 0.4,
				"responseMimeType": "application/json"
			}
		}

	return {
		"model": RuntimeConfig.get_model_name(),
		"temperature": 0.4,
		"messages": [
			{
				"role": "system",
				"content": build_system_prompt()
			},
			{
				"role": "user",
				"content": prompt_text
			}
		],
		"response_format": {
			"type": "json_object"
		}
	}


func _perform_request(payload: Dictionary) -> Dictionary:
	var endpoint: String = _build_endpoint_url()
	var uri: String = endpoint
	var use_tls: bool = false
	if uri.begins_with("https://"):
		use_tls = true
		uri = uri.trim_prefix("https://")
	elif uri.begins_with("http://"):
		uri = uri.trim_prefix("http://")

	var slash_index: int = uri.find("/")
	if slash_index == -1:
		return {"ok": false, "error": "invalid_endpoint"}

	var host: String = uri.substr(0, slash_index)
	var path: String = uri.substr(slash_index)
	var port: int = 443 if use_tls else 80
	if host.contains(":"):
		var parts: PackedStringArray = host.split(":")
		host = parts[0]
		port = int(parts[1])

	var client := HTTPClient.new()
	var connect_error: int
	if use_tls:
		connect_error = client.connect_to_host(host, port, TLSOptions.client())
	else:
		connect_error = client.connect_to_host(host, port)
	if connect_error != OK:
		return {"ok": false, "error": "connect_failed"}

	if not _wait_for_http_status(client, [HTTPClient.STATUS_CONNECTED]):
		return {"ok": false, "error": "connect_timeout"}

	var body_text: String = JSON.stringify(payload)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + RuntimeConfig.get_api_key()
	])
	var request_error: int = client.request(HTTPClient.METHOD_POST, path, headers, body_text)
	if request_error != OK:
		return {"ok": false, "error": "request_failed"}

	if not _wait_for_http_status(client, [HTTPClient.STATUS_BODY, HTTPClient.STATUS_CONNECTED]):
		return {"ok": false, "error": "response_timeout"}

	var response_code: int = client.get_response_code()
	var chunks := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk: PackedByteArray = client.read_response_body_chunk()
		if not chunk.is_empty():
			chunks.append_array(chunk)
		else:
			OS.delay_msec(10)

	var response_text: String = chunks.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid_json", "raw_text": response_text, "status_code": response_code}

	return {
		"ok": response_code >= 200 and response_code < 300,
		"status_code": response_code,
		"body": parsed,
		"raw_text": response_text
	}


func _perform_request_async(host: Node, payload: Dictionary) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = maxi(1, RuntimeConfig.get_request_timeout_ms() / 1000)
	host.add_child(request)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + RuntimeConfig.get_api_key()
	])
	var body_text: String = JSON.stringify(payload)
	var request_error: int = request.request(_build_endpoint_url(), headers, HTTPClient.METHOD_POST, body_text)
	if request_error != OK:
		request.queue_free()
		return {"ok": false, "error": "request_failed", "request_error": request_error}

	var response = await request.request_completed
	request.queue_free()
	if response.size() < 4:
		return {"ok": false, "error": "invalid_response_tuple"}

	var result_code: int = int(response[0])
	var response_code: int = int(response[1])
	var body: PackedByteArray = response[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "http_request_failed", "result_code": result_code, "status_code": response_code}

	var response_text: String = body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid_json", "raw_text": response_text, "status_code": response_code}

	return {
		"ok": response_code >= 200 and response_code < 300,
		"status_code": response_code,
		"body": parsed,
		"raw_text": response_text
	}


func _wait_for_http_status(client: HTTPClient, accepted_statuses: Array[int]) -> bool:
	var deadline: int = Time.get_ticks_msec() + RuntimeConfig.get_request_timeout_ms()
	while Time.get_ticks_msec() < deadline:
		client.poll()
		if accepted_statuses.has(client.get_status()):
			return true
		match client.get_status():
			HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
				return false
		OS.delay_msec(10)
	return false


func _parse_response_to_output(response_body: Dictionary, message: String, world_graph: WorldGraph) -> AgentOutput:
	if _is_gemini_model():
		return _parse_gemini_response_to_output(response_body, message, world_graph)

	var output := AgentOutput.new()
	var choices: Array = response_body.get("choices", [])
	if choices.is_empty():
		return _build_fallback_output(message, world_graph)

	var first_choice: Dictionary = choices[0]
	var message_block: Dictionary = first_choice.get("message", {})
	var content_variant: Variant = message_block.get("content", "")
	var content_text: String = _extract_content_text(content_variant)
	var parsed_content: Variant = JSON.parse_string(content_text)
	if typeof(parsed_content) != TYPE_DICTIONARY:
		output.reply_text = content_text if not content_text.is_empty() else "Received. I will keep observing."
		return output

	var content_dict: Dictionary = parsed_content
	output.reply_text = str(content_dict.get("reply_text", "Received. I will keep observing."))
	_append_commands_from_payload(output, content_dict.get("commands", []), world_graph)
	return output


func _parse_gemini_response_to_output(response_body: Dictionary, message: String, world_graph: WorldGraph) -> AgentOutput:
	var output := AgentOutput.new()
	var candidates: Array = response_body.get("candidates", [])
	if candidates.is_empty():
		return _build_fallback_output(message, world_graph)

	var first_candidate: Dictionary = candidates[0]
	var content_block: Dictionary = first_candidate.get("content", {})
	var parts: Array = content_block.get("parts", [])
	var content_text: String = ""
	for part_variant in parts:
		if typeof(part_variant) != TYPE_DICTIONARY:
			continue
		var part: Dictionary = part_variant
		var text: String = str(part.get("text", ""))
		if not text.is_empty():
			content_text = text
			break

	var parsed_content: Variant = JSON.parse_string(content_text)
	if typeof(parsed_content) != TYPE_DICTIONARY:
		output.reply_text = content_text if not content_text.is_empty() else "Received. I will keep observing."
		return output

	var content_dict: Dictionary = parsed_content
	output.reply_text = str(content_dict.get("reply_text", "Received. I will keep observing."))
	_append_commands_from_payload(output, content_dict.get("commands", []), world_graph)
	return output


func _extract_content_text(content_variant: Variant) -> String:
	if typeof(content_variant) == TYPE_STRING:
		return String(content_variant)
	if typeof(content_variant) == TYPE_ARRAY:
		var parts: Array[String] = []
		for item_variant in content_variant:
			if typeof(item_variant) != TYPE_DICTIONARY:
				continue
			var item: Dictionary = item_variant
			if str(item.get("type", "")) == "text":
				parts.append(str(item.get("text", "")))
		return "".join(parts)
	return ""


func _append_commands_from_payload(output: AgentOutput, commands_variant: Variant, world_graph: WorldGraph) -> void:
	if typeof(commands_variant) != TYPE_ARRAY:
		return

	for command_variant in commands_variant:
		if typeof(command_variant) == TYPE_STRING:
			var command_text: String = str(command_variant).strip_edges()
			if command_text.begins_with("move_to "):
				var target_name_from_string: String = command_text.trim_prefix("move_to ").strip_edges()
				var target_location_from_string: Dictionary = world_graph.get_location_by_name(target_name_from_string)
				var target_id_from_string: String = str(target_location_from_string.get("id", ""))
				if not target_id_from_string.is_empty():
					output.add_command(AgentCommandScript.move_to_location(target_id_from_string, target_name_from_string))
			continue

		if typeof(command_variant) != TYPE_DICTIONARY:
			continue

		var command_dict: Dictionary = command_variant
		var command_type: String = str(command_dict.get("type", ""))
		match command_type:
			AgentCommandScript.TYPE_MOVE_TO_LOCATION:
				var target_id: String = str(command_dict.get("target_location_id", ""))
				var target_name: String = str(command_dict.get("target_location_name", ""))
				if target_id.is_empty() and not target_name.is_empty():
					var target_location: Dictionary = world_graph.get_location_by_name(target_name)
					target_id = str(target_location.get("id", ""))
				if target_name.is_empty() and not target_id.is_empty():
					target_name = str(world_graph.get_location(target_id).get("name", target_id))
				if target_id.is_empty():
					continue
				output.add_command(AgentCommandScript.move_to_location(target_id, target_name))
			AgentCommandScript.TYPE_SET_AUTO_EXPLORE_INTERVAL:
				if not command_dict.has("seconds"):
					continue
				output.add_command(AgentCommandScript.set_auto_explore_interval(int(command_dict.get("seconds", 0))))
			AgentCommandScript.TYPE_ACT:
				var target_object_id: String = str(command_dict.get("target_id", ""))
				var action_name: String = str(command_dict.get("action", ""))
				if target_object_id.is_empty() or action_name.is_empty():
					continue
				var params: Dictionary = {}
				if typeof(command_dict.get("params", {})) == TYPE_DICTIONARY:
					params = (command_dict.get("params", {}) as Dictionary).duplicate(true)
				output.add_command(AgentCommandScript.act(target_object_id, action_name, params))
			_:
				continue


func _build_endpoint_url() -> String:
	var base_url: String = RuntimeConfig.get_api_base_url().trim_suffix("/")
	if _is_gemini_model():
		var gemini_base_url: String = base_url
		if gemini_base_url.ends_with("/v1"):
			gemini_base_url = gemini_base_url.trim_suffix("/v1")
		return "%s/v1beta/models/%s%%3AgenerateContent" % [gemini_base_url, RuntimeConfig.get_model_name()]
	return base_url + "/chat/completions"


func _is_gemini_model() -> bool:
	return RuntimeConfig.get_model_name().begins_with("gemini-")


func _build_fallback_output(message: String, world_graph: WorldGraph) -> AgentOutput:
	var output := AgentOutput.new()
	var target_location: Dictionary = _find_location_in_message(message, world_graph)
	if target_location.is_empty():
		output.reply_text = "Received. I will keep observing."
		return output

	var target_id: String = str(target_location.get("id", ""))
	var target_name: String = str(target_location.get("name", "unknown"))
	output.reply_text = "I also think %s may contain useful clues." % target_name
	output.add_command(AgentCommandScript.move_to_location(target_id, target_name))
	return output


func _build_system_event_fallback_output(event, context, world_graph: WorldGraph) -> AgentOutput:
	var output := AgentOutput.new()
	var target_location: Dictionary = _choose_exploration_target(context, world_graph)
	match str(event.event_type):
		SystemEvent.TYPE_ARRIVED_AT_LOCATION:
			var location_name: String = str(event.payload.get("location_name", context.current_location_name))
			if target_location.is_empty():
				output.reply_text = "I have arrived at %s. I will inspect the area first." % location_name
				return output
			var target_id: String = str(target_location.get("id", ""))
			var target_name: String = str(target_location.get("name", "unknown"))
			output.reply_text = "I have arrived at %s. %s looks like the next place to check." % [location_name, target_name]
			output.add_command(AgentCommandScript.move_to_location(target_id, target_name))
			return output
		SystemEvent.TYPE_EXPLORATION_IDLE:
			if target_location.is_empty():
				output.reply_text = "Nothing new has happened yet, so I will keep observing nearby."
				return output
			var idle_target_id: String = str(target_location.get("id", ""))
			var idle_target_name: String = str(target_location.get("name", "unknown"))
			output.reply_text = "It has been quiet for a while. I want to head toward %s." % idle_target_name
			output.add_command(AgentCommandScript.move_to_location(idle_target_id, idle_target_name))
			return output
		SystemEvent.TYPE_INSPECTION_RESULT:
			output.reply_text = "I checked it carefully. That gives me a better sense of what to try next."
			return output
	return output


func _find_location_in_message(message: String, world_graph: WorldGraph) -> Dictionary:
	for location in world_graph.get_locations():
		var location_name: String = str(location.get("name", ""))
		if not location_name.is_empty() and message.find(location_name) != -1:
			return location
	return {}


func _choose_exploration_target(context, world_graph: WorldGraph) -> Dictionary:
	for desired_id in context.desired_location_ids:
		if desired_id == context.current_location_id:
			continue
		for route in context.visible_routes:
			if str(route.get("to_location_id", "")) != desired_id:
				continue
			if not bool(route.get("allowed", false)):
				continue
			return world_graph.get_location(desired_id)

	for route in context.visible_routes:
		if not bool(route.get("allowed", false)):
			continue
		var route_location_id: String = str(route.get("to_location_id", ""))
		var route_location: Dictionary = world_graph.get_location(route_location_id)
		if route_location.is_empty():
			continue
		if not bool(route_location.get("visited", false)):
			return route_location

	for route in context.visible_routes:
		if not bool(route.get("allowed", false)):
			continue
		var fallback_id: String = str(route.get("to_location_id", ""))
		return world_graph.get_location(fallback_id)

	return {}
