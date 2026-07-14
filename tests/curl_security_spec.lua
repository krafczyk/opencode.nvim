local root = assert(arg[1], "pass the plugin root")
vim.opt.runtimepath:append(root)

local password = "audit-password-must-not-appear"
local body_value = "audit-body-must-not-appear"
local ca_path = root .. "/README.md"
local ca_resolutions = 0
package.loaded["opencode.config"] = {
  opts = {
    server = {
      username = "audit-user",
      password = password,
      ca_cert = function()
        ca_resolutions = ca_resolutions + 1
        return ca_path
      end,
    },
  },
}

local listener = assert(vim.uv.new_tcp())
local request
assert(listener:bind("127.0.0.1", 0) == 0)
assert(listener:listen(1, function(err)
  assert(not err, err)
  local client = assert(vim.uv.new_tcp())
  assert(listener:accept(client) == 0)
  client:read_start(function(read_err, data)
    assert(not read_err, read_err)
    if data then
      request = data
      client:read_stop()
      vim.defer_fn(function()
        client:write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}")
        client:close()
      end, 200)
    end
  end)
end) == 0)
local port = listener:getsockname().port

local Server = require("opencode.server")
local succeeded = false
local job = Server.curl({ url = "http://127.0.0.1:" .. port }, "/hold", "POST", {
  secret = body_value,
}, function()
  succeeded = true
end, function(message)
  error(message)
end)
assert(job > 0, "curl job did not start")
local pid = vim.fn.jobpid(job)
assert(pid > 0, "curl PID unavailable")
assert(vim.wait(1000, function()
  return vim.uv.fs_stat("/proc/" .. pid .. "/cmdline") ~= nil
end, 10), "curl exited before cmdline inspection")
local cmdline = table.concat(vim.fn.readfile("/proc/" .. pid .. "/cmdline", "b"), "\n")
assert(not cmdline:find(password, 1, true), "password leaked through curl argv")
assert(not cmdline:find(body_value, 1, true), "request body leaked through curl argv")
assert(not cmdline:find(ca_path, 1, true), "CA path leaked through curl argv")
assert(cmdline:find("%-%-config\0%-", 1), "curl must receive protected stdin config")
assert(vim.wait(5000, function()
  return succeeded
end, 10), "curl request did not complete through protected stdin config")
assert(ca_resolutions == 1, "CA resolver was not called exactly once at request time")
assert(request and request:find("x%-opencode%-directory: " .. vim.pesc(vim.fn.getcwd()), 1), "request directory was missing")
assert(request:find("Authorization: Basic", 1, true), "request credentials were missing")
assert(request:find(body_value, 1, true), "request body was missing")
listener:close()
vim.cmd("qa!")
