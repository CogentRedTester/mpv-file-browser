# Agent Guidance

## Repository

- This is a directory-based Lua script for mpv, not a standalone application. mpv loads the root `main.lua`; do not add another top-level `main.*` file, because mpv may select a different scripting backend.
- The minimum supported mpv version is v0.33. Keep code compatible with the supported LuaJIT, Lua 5.1, and Lua 5.2 runtimes, and avoid platform-specific dependencies unless required.
- `main.lua` wires setup and events; shared code is in `modules/`. Parser selection and async scanning are in `modules/navigation/scanning.lua`, parser loading and ordering in `modules/addons.lua`, and addon APIs in `modules/apis/`.
- Built-in parsers are in `modules/addons/`. Parser/API contracts are documented in [docs/addons.md](docs/addons.md).
- LuaLS annotations are used throughout the project. Consult `modules/defs/` for project types and hand-maintained mpv API definitions; update those definitions when their contracts change.
- User-triggered operations (parsing, keybinds, script-messages, etc.) are generally run in coroutines using the custom coroutine APIs in `modules/utils.lua`.

## mpv Lifecycle

- Each mpv script runs in its own thread. Keep the main chunk's initialization bounded so it returns promptly and mpv can enter its event loop.
- Properties may not be populated during startup. Use `mp.observe_property` or read them from an appropriate event handler.
- Use mpv events, observers, and timers for ongoing work. Avoid blocking or endless loops that prevent event dispatch or shutdown.

## Before Changing Behavior

- First check whether the requested behavior is already available through [configuration](docs/file_browser.conf), [custom keybinds](docs/custom-keybinds.md), or [addons](docs/addons.md).
- Prefer implementations in this order: custom keybind (including `run-statement` with `fb` and `mp`), standalone addon, then core changes. Move to the next option only when the previous one cannot meet the request or the user asks for it; for addons, verify the documented APIs and keybind contracts. Also consider mpv Lua APIs, which can be used directly by keybinds and addons.
- Before starting an implementation, inspect `modules/apis/fb.lua` and `modules/utils.lua` for existing project-specific APIs. Read relevant implementations, definitions, documentation, and call sites in other files as needed to understand their actual behavior and contracts; do not infer semantics from function names alone. Reuse an API when it already meets the need.
- Do not rely on memory of mpv's API. Confirm new or changed mpv API usage against the current upstream [Lua scripting documentation](https://github.com/mpv-player/mpv/blob/master/DOCS/man/lua.rst) and relevant [mpv manual pages](https://github.com/mpv-player/mpv/tree/master/DOCS/man).
- Follow existing module boundaries, shared utilities, type definitions, import names, and other code conventions. Check neighboring files before adding a `require`.
- Keep addon/parser changes compatible with the API contract and versioning rules in [docs/addons.md](docs/addons.md), and keep implementation, definitions, and documentation in sync when the contract changes.

## Validation and Review

- If using VS Code, and when making changes to Lua code, use the Lua Language Server editor diagnostics to identify problems. Do not use a CLI syntax checker if the editor diagnostics are available. Check before editing when useful to distinguish existing diagnostics from new ones.
- Fix diagnostics introduced by your changes. Do not silence or weaken diagnostics just to make the list empty.
- If editor diagnostics are unavailable, say so clearly and do not claim the Lua files were checked.
- In the final response, briefly report whether diagnostics were checked and any relevant remaining findings.
- Check that any changes to Lua code are compatible with LuaJit, Lua5.1, and Lua5.2.
- Run the narrowest relevant validation. Consider error and empty cases, supported platforms, mpv versions, and lifecycle effects; add or update focused tests and documentation when behavior or contracts change.
- Review the final diff for accidental, generated, or unrelated changes. When reporting or proposing a PR, summarize what changed and why, note user-visible and compatibility impact, and list the checks actually run and any that could not be run.

## Publishing

- Never push a branch or create/publish a PR without the user's direct, explicit request in the current conversation. Pushing and creating a PR are separate permissions; if an action requires both and consent for either is unclear, ask first. Code edits, preparing a PR description, or prior consent for another action do not authorize either operation.
