local root = assert(arg[1], "pass the plugin root")
vim.opt.runtimepath:append(root)

package.loaded["opencode.config"] = { opts = { server = {} } }
local clears = 0
package.loaded["opencode.events.status"] = {
  clear = function()
    clears = clears + 1
  end,
}
package.loaded["opencode.events"] = { emit = function() end }

local Server = require("opencode.server")
local uv = vim.uv

local function listener(mode)
  local server = assert(uv.new_tcp())
  assert(server:bind("127.0.0.1", 0) == 0)
  local clients = {}
  assert(server:listen(8, function(err)
    assert(not err, err)
    local client = assert(uv.new_tcp())
    assert(server:accept(client) == 0)
    table.insert(clients, client)
    local responded = false
    client:read_start(function(read_err, data)
      assert(not read_err, read_err)
      if data and not responded then
        responded = true
        if mode == "empty" then
          client:write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: 0\r\n\r\n")
          client:read_stop()
          client:close()
        elseif mode == "connected" then
          client:write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: keep-alive\r\n\r\ndata: {\"type\":\"server.connected\"}\n\n")
        end
      end
    end)
  end) == 0)
  return server, server:getsockname().port, clients
end

local function connect_to(port)
  local instance = setmetatable({
    url = "http://127.0.0.1:" .. port,
    heartbeat_timer = assert(uv.new_timer()),
  }, Server)
  local rejected, reason = 0, nil
  instance:connect():catch(function(err)
    rejected = rejected + 1
    reason = err
  end)
  return instance, function()
    return rejected, reason
  end
end

local empty_server, empty_port = listener("empty")
local empty, empty_result = connect_to(empty_port)
assert(vim.wait(2000, function()
  return empty_result() == 1
end, 10), "empty SSE response left connect pending")
local empty_rejections, empty_reason = empty_result()
assert(empty_rejections == 1, "empty SSE connection rejected more than once")
assert(tostring(empty_reason):find("closed before", 1, true), tostring(empty_reason))
assert(not empty.subscription_job_id and not empty.connect_timer and not empty.connect_promise, "empty SSE cleanup was incomplete")
assert(Server.connected == nil and clears == 1, "empty SSE failure did not clear status exactly once")
empty.heartbeat_timer:close()
empty_server:close()

local hanging_server, hanging_port, hanging_clients = listener("hold")
local hanging, hanging_result = connect_to(hanging_port)
local hanging_job = hanging.subscription_job_id
assert(hanging_job and hanging_job > 0, "hanging SSE curl did not start")
assert(vim.wait(4500, function()
  return hanging_result() == 1
end, 10), "SSE initial-connect deadline did not reject")
local hanging_rejections, hanging_reason = hanging_result()
assert(hanging_rejections == 1, "SSE deadline rejected more than once")
assert(tostring(hanging_reason):find("Timed out waiting for server.connected", 1, true), tostring(hanging_reason))
assert(not hanging.subscription_job_id and not hanging.connect_timer and not hanging.connect_promise, "deadline cleanup was incomplete")
assert(vim.wait(1000, function()
  return vim.fn.jobwait({ hanging_job }, 0)[1] ~= -1
end, 10), "deadline did not stop the SSE curl job")
assert(Server.connected == nil and clears == 2, "deadline failure did not clear status exactly once")
hanging.heartbeat_timer:close()
for _, client in ipairs(hanging_clients) do
  if not client:is_closing() then
    client:close()
  end
end
hanging_server:close()

local connected_server, connected_port, connected_clients = listener("connected")
local connected = setmetatable({
  url = "http://127.0.0.1:" .. connected_port,
  heartbeat_timer = assert(uv.new_timer()),
}, Server)
local resolved = 0
connected:connect():next(function()
  resolved = resolved + 1
end)
assert(vim.wait(2000, function()
  return resolved == 1
end, 10), "server.connected did not resolve the initial connection")
local connected_job = connected.subscription_job_id
assert(Server.connected == connected and connected_job and not connected.connect_timer and not connected.connect_promise, "successful connect cleanup was incomplete")
connected:disconnect()
assert(vim.wait(1000, function()
  return vim.fn.jobwait({ connected_job }, 0)[1] ~= -1
end, 10), "disconnect did not stop the connected SSE job")
assert(Server.connected == nil and clears == 3, "connected status cleanup did not run exactly once")
connected.heartbeat_timer:close()
for _, client in ipairs(connected_clients) do
  if not client:is_closing() then
    client:close()
  end
end
connected_server:close()

vim.cmd("qa!")
