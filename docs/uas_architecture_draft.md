# U-A-S Architecture Draft

## Goal

This project uses a three-party separation model:

- `U` (`User`): the player
- `A` (`Agent`): the stranded girl agent
- `S` (`System`): the deterministic game engine

The purpose of this split is to preserve:

- natural dialogue between player and agent
- deterministic world simulation and puzzle logic
- clear debug boundaries
- future replaceability of the test agent with a real LLM


## Core Principle

The world state must be owned by `S`.

`A` may:

- keep memory
- infer intent
- maintain plans
- generate dialogue
- emit structured commands

`A` may not:

- directly move itself in world state
- directly unlock puzzles
- directly alter map state
- directly declare success or failure of world actions

`S` is the single source of truth for:

- map graph
- current location
- travel progress
- visited state
- route validity
- puzzle state
- item state
- time progression


## Communication Channels

### 1. U <-> A

Channel: dialogue box

Purpose:

- player suggestions
- questions
- emotional interaction
- high-level planning

Examples:

- `要不我们去北边看看？`
- `先别进去，检查一下门锁。`

Output form:

- natural language only


### 2. A <-> S

Channel: structured command set

Purpose:

- action requests
- planning execution
- world interaction requests

Examples:

- `move_to_location`
- `inspect_object`
- `ask_for_help`
- `wait`

Output form:

- structured data only


### 3. U <-> S

Channel: UI controls and visualization

Purpose:

- map viewing
- route viewing
- pause
- scanning
- remote puzzle operations
- inventory/quest/system inspection

Examples:

- click a location in the map
- press a system button
- view route and status panels

Output form:

- deterministic UI actions and system responses


## Current Implementation Mapping

### Implemented System Module

Current files:

- `res://scripts/core/world_graph.gd`
- `res://scripts/game_ui.gd`
- `res://scripts/core/agent_test_simulator.gd`
- `res://data/world/graph_demo.json`

### Current Responsibilities

#### `S` currently includes

- world graph loading
- directed connections
- travel time lookup
- reachability validation
- pathfinding
- current location state
- visited state
- travel progress state
- automatic time progression
- route execution

#### `A` currently includes

- reading player text
- detecting location names inside text
- maintaining `desired_location_ids`
- generating a simple natural-language reply
- emitting a command set

#### `U` currently includes

- sending text through chat
- clicking route/map UI
- reading system state from panels


## Current Runtime State Model

### User State

The player currently has no long-lived structured state beyond direct UI interaction.

Future candidates:

- unlocked remote abilities
- discovered map overlays
- player notes
- trust-affecting choices

### Agent State

Current implemented state:

- `desired_location_ids: Array[String]`

Current runtime movement-facing state in UI/system:

- `agent_state`
- `travel_origin_id`
- `travel_destination_id`
- `travel_remaining_seconds`
- `planned_route`

Recommended future split:

- `AgentMindState`
  - desired locations
  - hypotheses
  - short-term goals
  - memory summary
  - emotional state
- `AgentBodyState`
  - idle / moving / exploring / waiting_for_help
  - current route
  - current action
  - movement progress

### System State

Current implemented system state:

- current world time
- graph nodes and edges
- visited flags
- current location
- currently active travel leg
- planned multi-step route

Future system state should also include:

- puzzle states
- object states
- clue states
- item possession
- event flags
- quest states
- chapter state
- ending flags


## Protocol Draft

### U -> A Message

Type: natural language

Draft structure:

```json
{
  "type": "player_message",
  "text": "要不我们去风蚀观测塔看看？",
  "timestamp": "world_time_or_real_time"
}
```

Notes:

- this is not a system command
- this is not guaranteed to produce an action
- the agent may update internal plan state before replying


### A -> U Message

Type: natural language reply

Draft structure:

```json
{
  "type": "agent_reply",
  "text": "好啊，我也觉得风蚀观测塔那边可能会有线索。"
}
```


### A -> S Command Set

Type: structured action request

Current testing version:

```json
{
  "commands": [
	{
	  "type": "move_to_location",
	  "target_location_id": "wind_tower",
	  "target_location_name": "风蚀观测塔"
	}
  ]
}
```

Rules:

- a command set may contain multiple commands
- the system executes commands in order
- command emission does not imply success

Recommended command envelope:

```json
{
  "agent_state_patch": {
	"desired_location_ids": ["wind_tower"]
  },
  "commands": [
	{
	  "type": "move_to_location",
	  "target_location_id": "wind_tower"
	}
  ]
}
```


### S -> A Execution Result

Type: structured result

Recommended future format:

```json
{
  "results": [
	{
	  "type": "path_planned",
	  "target_location_id": "wind_tower",
	  "path": ["crash_canyon", "wind_tower"]
	},
	{
	  "type": "movement_started",
	  "from_location_id": "crash_canyon",
	  "to_location_id": "wind_tower",
	  "travel_time_seconds": 360
	}
  ]
}
```

Important:

- `A` should react to system results
- `A` should not assume its commands succeeded unless `S` confirms


## Current Test-Agent Flow

The current testing flow is:

1. `U` sends a message in the dialogue box.
2. `A` scans the message for a known location name.
3. If a location name is found, `A`:
   - updates `desired_location_ids`
   - replies with a fixed template
   - emits one `move_to_location` command
4. `S` receives the command.
5. `S` calls pathfinding.
6. If a valid path exists, `S`:
   - stores the full planned route
   - starts the first travel leg
   - advances automatically over time
7. When one leg finishes, `S` starts the next leg until arrival.
8. When final arrival completes, `S` clears the route and removes the reached target from the test agent's desired list.


## Why This Structure Is Good

This architecture already has the correct replacement seam for a real LLM.

To replace the current test agent, the future LLM module only needs to preserve:

- input: player message + allowed world context + agent memory
- output:
  - natural-language reply
  - structured command set
  - optional structured internal-state patch

If that contract remains stable, the rest of the system does not need to be rewritten.


## Context Boundary For Future Real LLM

When replacing the test simulator, do not pass the whole game state blindly into the LLM.

The LLM should receive only:

- current agent-visible location
- nearby routes visible to the agent
- recent conversation summary
- current goal summary
- relevant memory summary
- recent system results
- current allowed action schema

The LLM should not automatically receive:

- hidden future plot
- puzzle solutions
- full omniscient map state unless intended by design
- system-internal-only flags


## Recommended Future Interfaces

### `AgentAdapter`

Purpose:

- stable runtime interface between UI/system and the current agent implementation

Suggested methods:

- `process_player_message(message, context) -> AgentOutput`
- `process_system_results(results, context) -> AgentOutput`
- `tick(context) -> AgentOutput`

Current implementation:

- `agent_test_simulator.gd`

Future implementation:

- `agent_llm_adapter.gd`


### `AgentOutput`

Recommended shape:

```json
{
  "reply_text": "好啊，我也觉得风蚀观测塔那边可能会有线索。",
  "state_patch": {
    "desired_location_ids": ["wind_tower"]
  },
  "commands": [
    {
      "type": "move_to_location",
      "target_location_id": "wind_tower"
    }
  ]
}
```


### `SystemResult`

Recommended shape:

```json
{
  "results": [
    {
      "type": "movement_started",
      "from_location_id": "crash_canyon",
      "to_location_id": "wind_tower",
      "direction": "N",
      "travel_time_seconds": 360
    }
  ]
}
```


## Command Specification v0

Currently implemented:

- `move_to_location`

Reserved for next phase:

- `inspect_object`
- `collect_item`
- `ask_player_for_help`
- `wait`
- `report_observation`
- `interact_with_puzzle`

All commands should be:

- explicit
- schema-validatable
- side-effect free until system execution


## Execution Rules v0

1. `A` emits intent, not world truth.
2. `S` validates path/requirements.
3. `S` executes only validated commands.
4. `S` updates world state.
5. `S` returns structured results.
6. `A` updates its internal state from those results.


## Logging And Debugging Recommendation

Every future turn should be traceable as:

1. player message
2. agent input context summary
3. agent internal-state change
4. agent reply
5. agent command set
6. system execution result
7. world state change summary

This log chain will be critical once a real LLM is introduced.


## Immediate Next Refactor Targets

To prepare for a real LLM, the next recommended steps are:

1. Extract an explicit `AgentOutput` structure in code.
2. Extract an explicit `SystemResult` structure in code.
3. Make `game_ui.gd` depend on an `AgentAdapter` interface rather than directly on `agent_test_simulator.gd`.
4. Move runtime movement state out of UI into a dedicated system/controller module.
5. Add a dedicated agent-state panel in UI showing:
   - desired locations
   - current route
   - current action state
6. Add structured result callbacks from `S` back into `A`.


## Current Replacement Strategy

When replacing `agent_test_simulator.gd` with a real LLM, the safest migration plan is:

1. keep the same output structure
2. keep the same command names
3. keep the same execution pipeline in `S`
4. gradually enrich agent context
5. gradually enrich available command types

This minimizes risk and keeps debugging manageable.


## Protocol Freeze v1

### `AgentContext` v1

Current stable fields:

```json
{
  "protocol_version": "agent_context.v1",
  "trigger_type": "player_message",
  "trigger_reason": "player_submitted_message",
  "world_time_seconds": 80040,
  "current_location_id": "crash_canyon",
  "current_location_name": "坠落峡谷",
  "agent_state": "EXPLORING",
  "short_term_goal": "保持通讯稳定并继续调查周边区域",
  "recent_dialogue_summary": "玩家与少女刚建立稳定联系，正在共同规划探索方向。",
  "desired_location_ids": [],
  "visible_routes": [],
  "active_travel_route": {},
  "allowed_command_types": ["move_to_location"]
}
```

Rules:

- assembled only by `S`
- injected into `A` only on explicit triggers
- contains system-owned agent-facing state
- should stay compact and deterministic


### `AgentOutput` v1

Current stable fields:

```json
{
  "protocol_version": "agent_output.v1",
  "reply_text": "好啊，我也觉得风蚀观测塔那边可能会有线索。",
  "commands": [
    {
      "type": "move_to_location",
      "target_location_id": "wind_tower",
      "target_location_name": "风蚀观测塔"
    }
  ]
}
```

Rules:

- `A` currently outputs only `reply_text` and `commands`
- `S` remains the owner of all persistent agent-facing state
- `A` emits commands as declarative requests only
- future LLM integration should preserve these field names and meanings

Implementation note:

- the current codebase has simplified `AgentOutput` further than the earlier draft
- agent-facing state changes are now inferred and applied by `S` from accepted commands instead of being emitted as a separate `state_patch`
