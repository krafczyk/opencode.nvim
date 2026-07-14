# Fork maintenance

This fork is based on upstream-compatible `main` at `8cb752f` (the `0.13.4`
release line) and carries two temporary divergences for MkChad's shared
OpenCode-server integration:

- Every OpenCode HTTP request includes `x-opencode-directory` from the current
  Neovim working directory when one is available. This is the behavior proposed
  by upstream [PR #239](https://github.com/nickjvandyke/opencode.nvim/pull/239).
  MkChad deliberately attaches its TUI with that same directory. Remove this
  divergence when upstream merges PR #239 or a compatible replacement.
- `server.ensure(callback)` prepares an externally managed server before each
  discovery attempt. The callback receives `ok` and optional `err`; `false`
  rejects the requested operation. Remove this divergence when an equivalent
  upstream lifecycle hook is available.

OpenCode v2 may supersede this shared-server architecture. Reassess both
divergences against its documented server and TUI APIs before carrying them
forward.
