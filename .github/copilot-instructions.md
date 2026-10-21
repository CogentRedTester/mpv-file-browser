When working on Lua files in this repository:

- Use VS Code's Lua Language Server editor diagnostics (the Problems diagnostics) to check affected files after changes. Check before editing when useful to distinguish existing diagnostics from new ones.
- Do not use the LuaLS command-line checker as a substitute unless the user asks for the CI lint workflow or a command-line check.
- Fix diagnostics introduced by your changes. Do not silence or weaken diagnostics just to make the list empty.
- If editor diagnostics are unavailable to you, say so clearly and do not claim the Lua files were checked.
- In your final response, briefly report whether diagnostics were checked and any relevant remaining findings.