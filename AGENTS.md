# opencode.nvim Agent Guide

## What It Is

A Neovim Lua plugin that bridges Neovim and the external `opencode` CLI. It
discovers or starts a server, communicates through REST and SSE, and provides
UI for prompting, context injection, session management, and edit review.

## Entrypoints

- **Public API**: `lua/opencode.lua` exports `ask()`, `select()`, `prompt()`,
  `command()`, `operator()`, `format()`, and `statusline`.
- **Config**: `vim.g.opencode_opts` is merged with defaults from
  `lua/opencode/config.lua`; this is not a `setup()` call.
- **Plugin files**: `plugin/highlights.lua` sets highlight groups;
  `plugin/events/` registers the `OpencodeReload`, `OpencodeStatus`,
  `OpencodePermissions`, and `OpencodeEdits` autocmd groups.

## Config Quirks

- `snacks.nvim` nested options belong under `ask.snacks` or `select.snacks`
  before they are merged into `ask` or `select`.
- `vim.o.autoread = true` is required when `events.reload = true`.
- Neovim does not support mixed integer and string keys in `vim.g`; adjust
  `require("opencode.config").opts` directly for affected `snacks.input`
  options.

## Dependencies

- **Required**: `opencode` CLI and `curl`.
- **Auto-discovery**: `pgrep` and `lsof` on Unix unless `server.url` is set.
- **Optional**: `snacks.nvim` for ask/select UI and `blink.cmp` for completion.
- No hard Lua dependencies beyond Neovim itself.

## Verification

Run these commands from this repository when their required tools and fixtures
are available:

```bash
# Type check; requires Neovim, Lua Language Server, and cloned snacks/blink.
lua-language-server --configpath .luarc.ci.json --check=.

# Format check.
stylua --check .

# Focused executable Lua specs; pass the plugin root as the required argument.
nvim --headless -u NONE -l tests/compatibility_spec.lua "$PWD"
nvim --headless -u NONE -l tests/curl_security_spec.lua "$PWD"
nvim --headless -u NONE -l tests/sse_connect_spec.lua "$PWD"
```

`tests/curl_tls_spec.lua` also requires an HTTPS URL and CA certificate. Use
`:checkhealth opencode` for manual integration verification.

## Formatting And Type Checking

StyLua uses `column_width = 120`, `indent_width = 2`, spaces, double quotes,
and no call parentheses. LuaLS uses the LuaJIT runtime and library paths for
Neovim plus cloned `snacks.nvim` and `blink.cmp`.

## Architecture Notes

- **Async**: custom Promise implementation in `lua/opencode/promise/init.lua`.
- **Server discovery**: connected server, configured URL, local process scan
  filtered by CWD overlap, then auto-start and poll with a five-second timeout.
- **Context**: captures buffer, window, cursor, and selection before UI opens,
  then renders placeholders such as `@this` and `@buffer`.
- **Events**: SSE subscriptions dispatch `OpencodeEvent:<type>` User autocmds.
- **Edit review**: opens a diff tab through `:diffpatch` with accept/reject and
  per-hunk keymaps.
- **Ask completion**: in-process LSP server in `lua/opencode/ui/ask/cmp.lua`.
- **Operator**: `operator()` sets `operatorfunc`, then uses `g@` for ranges and
  dot-repeat support.

## Public Integration Policy

Code that bridges another tool to opencode.nvim, such as picker send or
terminal toggle integration, belongs in README examples. Code that enhances
opencode.nvim's own UI, such as snacks input or picker support, stays in the
plugin. Update user-facing documentation with public API, configuration,
dependency, or behavior changes.

See `CONTRIBUTING.md` for project priorities and maintenance philosophy.
