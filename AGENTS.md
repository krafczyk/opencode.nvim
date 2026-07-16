# opencode.nvim — agent guide

## What it is

A Neovim Lua plugin that bridges Neovim and the `opencode` CLI (external binary). It discovers or starts an `opencode` server, communicates via REST + SSE, and provides UI for prompting, context injection, session management, and edit review.

## Parent Sprint Coordination

When this checkout is used under `/data0/matthew/Projects/mkchad`, the parent
workspace owns sprint selection and cross-repository sprint documents. Read
`../AGENTS.md` before sprint work and do not infer a current sprint from this
repository or unchecked tracker rows.

This repository currently participates in the parent selectors
`single-opencode-server/2` and `single-opencode-server/3`, resolved by these
documents:

- `../docs/sprints/single-opencode-server/sprint_plan.md`
- `../docs/sprints/single-opencode-server/2/sprint_spec.md`
- `../docs/sprints/single-opencode-server/2/sprint_checklist.md`
- `../docs/sprints/single-opencode-server/2/threat_model.md`
- `../docs/sprints/single-opencode-server/2/audit_policy.md`
- `../docs/sprints/single-opencode-server/3/sprint_spec.md`
- `../docs/sprints/single-opencode-server/3/sprint_checklist.md`

Sprint 3 inherits the Sprint 2 threat model and audit policy. Keep the explicit
parent-resolved selector fixed for each invocation; shared repositories do not
make either sprint implicit.

If sprint work is requested from this child without an explicit parent-resolved
selector, return to the coordination root or ask the user to select one. Normal
standalone plugin work does not require a sprint selection. Commit child changes
before the parent workspace records the updated gitlink.

## Entrypoints

- **Public API**: `lua/opencode.lua` — exports `ask()`, `select()`, `prompt()`, `command()`, `operator()`, `format()`, `statusline`
- **Config**: `vim.g.opencode_opts` global (not a `setup()` call); merged with defaults from `lua/opencode/config.lua`
- **Plugin files**: `plugin/highlights.lua` sets highlight groups; `plugin/events/` registers four autocmd groups (`OpencodeReload`, `OpencodeStatus`, `OpencodePermissions`, `OpencodeEdits`) that listen for `OpencodeEvent:*` User events to reload edited buffers, update statusline, display permission requests, and diff edit proposals

## Config quirks

- Config is passed via `vim.g.opencode_opts` for simpler UX and faster startup (see `lua/opencode/config.lua:6`)
- `snacks.nvim` nested opts go under `ask.snacks` / `select.snacks`, then get merged into `ask` / `select` at the end of config.lua
- `vim.o.autoread = true` is required when `events.reload = true` (the default)
- Neovim doesn't support mixed integer/string keys in `vim.g`, which affects some `snacks.input` options; workaround: modify `require("opencode.config").opts` directly

## Dependencies

- **Required**: `opencode` CLI, `curl`
- **Auto-discovery**: `pgrep` + `lsof` (Unix, unless `server.url` is set)
- **Optional**: `snacks.nvim` (enhances `ask()` with `snacks.input`, `select()` with `snacks.picker`), `blink.cmp` (completion plugin with LSP source)
- No hard Lua dependencies beyond Neovim itself

## Verification commands

```bash
# Type-check (requires neovim + lua-language-server + cloned snacks/blink)
lua-language-server --configpath .luarc.ci.json --check=.

# Format check
stylua --check .

# Format in place
stylua .
```

## CI

- **`.github/workflows/lua-ls.yml`**: type-check on push/PR to main
- **`.github/workflows/stylua.yml`**: format check on push/PR to main
- **`.github/workflows/release-please.yml`**: automated releases via release-please (non-fork, main branch only)

## Testing

- No test framework — no tests directory, no test runner config
- Manual verification: `:checkhealth opencode`

## Formatting (StyLua)

- `column_width = 120`, `indent_width = 2`, spaces, double quotes, no call parentheses
- File: `.stylua.toml`

## Type-checking (LuaLS)

- Config: `.luarc.ci.json`
- Runtime: `LuaJIT`
- Library paths: `/opt/nvim/share/nvim/runtime/lua`, cloned `snacks.nvim` and `blink.cmp`

## Architecture notes

- **Async**: custom Promise implementation in `lua/opencode/promise/init.lua` (fork of `promise.nvim`)
- **Server discovery flow** (`lua/opencode/server/discovery/init.lua`): connected server → configured URL → local process scan (filtered by CWD overlap) → auto-start + poll (5s timeout)
- **Context system** (`lua/opencode/context/init.lua`): captures buffer/win/cursor/selection before UI opens, renders placeholders (`@this`, `@buffer`, etc.) in prompts
- **Events**: SSE subscribed on `connect()`, dispatched as `OpencodeEvent:<type>` User autocmds
- **Edit review**: opens diff in new tab via `:diffpatch`, keymaps `da`/`dr` to accept/reject, `dp`/`do` for per-hunk
- **Ask completion**: in-process LSP server (`lua/opencode/ui/ask/cmp.lua`) providing context placeholder + agent completions
- **Integration policy**: code that bridges another tool _to_ opencode.nvim (e.g. picker send, terminal toggle) belongs in README examples. Code that enhances opencode.nvim's own UI (ask/select with snacks input/picker) stays in the plugin.
- **Operator**: `operator()` sets `operatorfunc`, uses `g@` for range + dot-repeat support

## Project vision

See [CONTRIBUTING.md](./CONTRIBUTING.md) for project guidelines, priorities, and maintenance philosophy. When in doubt, follow the patterns already in the codebase.
