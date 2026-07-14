# Fork maintenance

This fork is based on upstream-compatible `main` at `8cb752f` (the `0.13.4`
release line) and carries three temporary divergences for MkChad's shared
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
- `server.ca_cert` accepts a path or request-time resolver and supplies curl's
  `cacert` through protected stdin configuration for every REST and SSE request.
  Remove this divergence if upstream gains equivalent private-CA support.

OpenCode v2 may supersede this shared-server architecture. Reassess all
divergences against its documented server and TUI APIs before carrying them
forward.

## CA-support publication gate

Do not update MkChad's immutable pin until the CA-support commit is published.
Reproduce the candidate from a clean checkout using only temporary paths under
`/tmp/opencode`:

```bash
git clone https://github.com/krafczyk/opencode.nvim /tmp/opencode/opencode-nvim-ca-verify
git -C /tmp/opencode/opencode-nvim-ca-verify checkout <published-ca-revision>
nvim --headless -u NONE -l /tmp/opencode/opencode-nvim-ca-verify/tests/curl_security_spec.lua /tmp/opencode/opencode-nvim-ca-verify
nvim --headless -u NONE -l /tmp/opencode/opencode-nvim-ca-verify/tests/sse_connect_spec.lua /tmp/opencode/opencode-nvim-ca-verify
git clone https://github.com/krafczyk/mkchad /tmp/opencode/mkchad-ca-verify
git -C /tmp/opencode/mkchad-ca-verify checkout <published-mkchad-revision>
git -C /tmp/opencode/mkchad-ca-verify show HEAD:lua/plugins/init.lua
MKCHAD_TLS_TEST_ROOT=/tmp/opencode/mkchad-clean-tls python3 /tmp/opencode/mkchad-ca-verify/tests/tls_proxy_integration.py
```

The TLS integration invokes `curl_tls_spec.lua` against a private-CA fixture and
must prove request-time CA resolution for REST and SSE, keep CA/auth/body values
out of argv, and reject wrong or missing CA configuration. After publication,
update the MkChad pin to that exact reviewed revision and repeat these commands
from another clean checkout. A local worktree diff is not publication evidence.
