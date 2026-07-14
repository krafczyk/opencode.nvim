local root = assert(arg[1], "pass the plugin root")
local url = assert(arg[2], "pass the HTTPS URL")
local ca = assert(arg[3], "pass the CA certificate")
vim.opt.runtimepath:append(root)

local password = "plugin-tls-password"
local body_secret = "plugin-tls-body"
local resolutions = 0
package.loaded["opencode.config"] = {
  opts = {
    server = {
      username = "plugin-user",
      password = password,
      ca_cert = function()
        resolutions = resolutions + 1
        return ca
      end,
    },
  },
}

local Server = require("opencode.server")
local complete = false
local job = Server.curl({ url = url }, "/client", "POST", { secret = body_secret }, function(response)
  assert(response.healthy == true)
  complete = true
end, function(message)
  error(message)
end)
assert(job > 0)
local pid = vim.fn.jobpid(job)
assert(pid > 0)
assert(vim.wait(1000, function()
  return vim.uv.fs_stat("/proc/" .. pid .. "/cmdline") ~= nil
end, 10))
local argv = table.concat(vim.fn.readfile("/proc/" .. pid .. "/cmdline", "b"), "\n")
assert(not argv:find(password, 1, true), "password leaked through curl argv")
assert(not argv:find(body_secret, 1, true), "body leaked through curl argv")
assert(not argv:find(ca, 1, true), "CA path leaked through curl argv")
assert(vim.wait(5000, function()
  return complete
end, 10), "pinned HTTPS plugin request did not complete")

local sse_event = false
local instance = setmetatable({ url = url }, Server)
local sse_job
sse_job = instance:sse_subscribe(function(event)
  if event.type == "server.connected" then
    sse_event = true
    vim.fn.jobstop(sse_job)
  end
end, function(message)
  if not sse_event then
    error(message)
  end
end)
assert(sse_job > 0)
local sse_pid = vim.fn.jobpid(sse_job)
assert(sse_pid > 0)
local sse_argv = table.concat(vim.fn.readfile("/proc/" .. sse_pid .. "/cmdline", "b"), "\n")
assert(not sse_argv:find(password, 1, true), "SSE password leaked through curl argv")
assert(not sse_argv:find(ca, 1, true), "SSE CA path leaked through curl argv")
assert(vim.wait(5000, function()
  return sse_event
end, 10), "pinned HTTPS SSE did not receive server.connected")
assert(resolutions == 2, "CA was not resolved for both REST and SSE requests")

local function expect_tls_failure(label, resolver)
  package.loaded["opencode.config"].opts.server.ca_cert = function()
    resolutions = resolutions + 1
    return resolver()
  end
  local failed = false
  local failure_job = Server.curl({ url = url }, "/global/health", "GET", nil, function()
    error(label .. " CA unexpectedly authenticated the private HTTPS server")
  end, function()
    failed = true
  end)
  assert(failure_job > 0, label .. " CA curl job did not start")
  assert(vim.wait(5000, function()
    return failed
  end, 10), label .. " CA did not fail closed")
end

expect_tls_failure("wrong", function()
  return ca .. ".does-not-exist"
end)
expect_tls_failure("missing", function()
  return nil
end)
assert(resolutions == 4, "CA resolver was not called for each failed request")
vim.cmd("qa!")
