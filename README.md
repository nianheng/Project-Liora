# Project. Liora

Project. Liora is an AI agent-driven interactive text adventure prototype.

The player establishes radio contact with a girl stranded on an unknown planet after a crash landing, and gradually pushes the story forward through guidance, collaboration, and exploration.

Rather than treating the character as a passive chat window, the project explores a more agent-like form of interaction: time continues to flow, the character can act on her own, observe the environment, receive feedback, and adjust her choices through communication with the player.

This public build is an early prototype intended to present the project's direction and validate its core experience.

## Run

1. Open the project with Godot 4.6 or newer.
2. Run the main scene from the editor.

The public repository defaults to test mode instead of live LLM mode unless a local runtime config file is present.

## Enable LLM Mode

1. Copy `agent_runtime.example.json` to `agent_runtime.local.json`.
2. Fill in your real endpoint, key, and model.

Recommended model: `gemini-3-flash-preview`.

The game will automatically use `agent_runtime.local.json` if it exists and contains valid LLM settings.

Do not commit `agent_runtime.local.json` or real API keys to a public repository.
