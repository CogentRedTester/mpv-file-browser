# Agent Guidance

## Repository

- This is a directory-based Lua script for mpv, not a standalone application. mpv loads the root `main.lua`; do not add another top-level `main.*` file, because mpv may select a different scripting backend.
- The minimum supported mpv version is v0.33. Keep code compatible with the supported LuaJIT, Lua 5.1, and Lua 5.2 runtimes, and avoid platform-specific dependencies unless required.
- `main.lua` initializes the script and registers observers, script messages, and key bindings. Shared code is in `modules/`; built-in parsers are in `modules/addons/`.
- LuaLS annotations are used throughout the project. Consult `modules/defs/` for project types and hand-maintained mpv API definitions; update those definitions when their contracts change.

## Before Changing Behavior

- First check whether the requested behavior is already available through [configuration](docs/file_browser.conf), [custom keybinds](docs/custom-keybinds.md), or [addons](docs/addons.md). If one fits, guide the user to it instead of implementing duplicate functionality. Ask a concise clarifying question when the intended behavior or preferred approach is unclear.
- Inspect existing file-browser and mpv APIs before adding a feature or changing behavior. Reuse an API when it already meets the need. Do not rely on memory of mpv's API: confirm new or changed usage against the current upstream [Lua scripting documentation](https://github.com/mpv-player/mpv/blob/master/DOCS/man/lua.rst) and relevant [mpv manual pages](https://github.com/mpv-player/mpv/tree/master/DOCS/man).
- Follow existing module boundaries, shared utilities, type definitions, and import names. Check neighboring files before adding a `require`.
- Keep addon/parser changes compatible with the API contract and versioning rules in [docs/addons.md](docs/addons.md), and keep implementation, definitions, and documentation in sync when the contract changes.

## mpv Lifecycle

- Each mpv script runs in its own thread. Keep the main chunk's initialization bounded so it returns promptly and mpv can enter its event loop.
- Properties may not be populated during startup. Use `mp.observe_property` or read them from an appropriate event handler.
- Use mpv events, observers, and timers for ongoing work. Avoid blocking or endless loops that prevent event dispatch or shutdown.

## Validation and Review

- For Lua changes, follow `.github/copilot-instructions.md`.
- Run the narrowest relevant validation. Consider error and empty cases, supported platforms, mpv versions, and lifecycle effects; add or update focused tests and documentation when behavior or contracts change.
- Review the final diff for accidental, generated, or unrelated changes. When reporting or proposing a PR, summarize what changed and why, note user-visible and compatibility impact, and list the checks actually run and any that could not be run.

## Publishing

- Never push a branch or create/publish a PR without the user's direct, explicit request in the current conversation. Pushing and creating a PR are separate permissions; if an action requires both and consent for either is unclear, ask first. Code edits, preparing a PR description, or prior consent for another action do not authorize either operation.
