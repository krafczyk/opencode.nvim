local root = assert(arg[1], "pass the plugin root")
vim.opt.runtimepath:append(root)

local password = "audit-password-must-not-appear"
local body_value = "audit-body-must-not-appear"
package.loaded["opencode.config"] = {
  opts = { server = { username = "audit-user", password = password } },
}

local Server = require("opencode.server")
local succeeded = false
local job = Server.curl({ url = "http://127.0.0.1:48888" }, "/hold", "POST", {
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
assert(cmdline:find("%-%-config\0%-", 1), "curl must receive protected stdin config")
assert(vim.wait(5000, function()
  return succeeded
end, 10), "curl request did not complete through protected stdin config")
vim.cmd("qa!")
