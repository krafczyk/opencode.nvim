local root = assert(arg[1], "pass the plugin root")

-- External inventory consumers read this artifact directly and never load the plugin.
assert(package.loaded["opencode"] == nil)
assert(package.loaded["opencode.health"] == nil)
assert(package.loaded["opencode.component"] == nil)
local artifact = assert(io.open(root .. "/opencode-component.json", "rb"))
local raw_artifact = artifact:read("*a")
artifact:close()
local external_metadata = assert(vim.json.decode(raw_artifact))
assert(external_metadata.component_id == "opencode-nvim")
assert(external_metadata.relationships[1].type == "tested-with")
assert(external_metadata.relationships[1].target_component == "opencode")

vim.opt.runtimepath:append(root)
local component = require("opencode.component")
local metadata = assert(component.read())
local relationship = assert(component.tested_with(metadata))
assert(relationship.contract.version == external_metadata.relationships[1].contract.version)
assert(component.tested_with_judgment(relationship.contract, relationship.contract.version) == "tested")
assert(component.tested_with_judgment(relationship.contract, "1.17.5") == "outside-tested-matrix")

local explicit_metadata = vim.deepcopy(external_metadata)
local explicit_contract = explicit_metadata.relationships[1].contract
explicit_contract.suffix_policy = "explicit-equivalence"
explicit_contract.equivalences = {
  { observed = "1.17.4-mkchad.7", equivalent_to = "1.17.4" },
}
assert(component.decode(vim.json.encode(explicit_metadata)))
assert(component.tested_with_judgment(explicit_contract, "1.17.4-mkchad.7") == "tested-equivalent")
assert(component.tested_with_judgment(explicit_contract, "1.17.4-mkchad.8") == "outside-tested-matrix")

local function with_artifact(contents, expected_code)
  local value, diagnostic = component.decode(contents)
  assert(value == nil)
  assert(diagnostic:find(expected_code, 1, true), diagnostic)
  assert(#diagnostic <= 256, "metadata diagnostic exceeded its bound")
end

assert(component.read(root .. "/missing-opencode-component.json") == nil)
with_artifact("{}", "missing-schema")
with_artifact("{", "malformed-json")
with_artifact('{"schema":2,"component_id":"opencode-nvim","relationships":[]}', "unsupported-schema")
with_artifact('{"schema":1,"schema":1,"component_id":"opencode-nvim","relationships":[]}', "duplicate-keys")
with_artifact(
  '{"schema":1,"component_id":"opencode-nvim","relationships":[{"id":"a","type":"tested-with","target_component":"opencode","contract":{"kind":"tested-baseline","version":"1.17.4","suffix_policy":"implicit"}}]}',
  "invalid-suffix-policy"
)
with_artifact(
  '{"schema":1,"component_id":"opencode-nvim","relationships":[{"id":"a","type":"tested-with","target_component":"opencode","contract":{"kind":"tested-baseline","version":"1.17.4","suffix_policy":"literal","padding":"'
    .. string.rep("x", 769)
    .. '"}}]}',
  "contract-too-large"
)
with_artifact(
  '{"schema":1,"component_id":"opencode-nvim","relationships":[{"id":"a","type":"tested-with","target_component":"opencode","contract":{"kind":"tested-baseline","version":"1.17.4","suffix_policy":"literal"}}],"identity_profile":{}}',
  "invalid-identity-profile"
)
with_artifact(
  '{"schema":1,"component_id":"opencode-nvim","relationships":[{"id":"a","type":"tested-with","target_component":"opencode","contract":{"kind":"tested-baseline","version":"1.17.4","suffix_policy":"literal"}}],"future":"bad\\u007ftext"}',
  "invalid-text"
)
with_artifact(string.rep(" ", 16385), "artifact-too-large")
local too_many_relationships = vim.deepcopy(external_metadata)
for index = 2, 5 do
  local extra = vim.deepcopy(too_many_relationships.relationships[1])
  extra.id = "extra-" .. index
  table.insert(too_many_relationships.relationships, extra)
end
with_artifact(vim.json.encode(too_many_relationships), "invalid-relationships")
assert(
  component.decode(
    '{"schema":1,"component_id":"opencode-nvim","relationships":[{"id":"a","type":"tested-with","target_component":"opencode","contract":{"kind":"tested-baseline","version":"1.17.4","suffix_policy":"literal"}}],"future":{"allowed":true}}'
  )
)

local messages = {}
local original_health = vim.health
local original_executable = vim.fn.executable
local original_system = vim.fn.system
vim.health = {
  start = function() end,
  info = function(message)
    table.insert(messages, message)
  end,
  ok = function(message)
    table.insert(messages, message)
  end,
  warn = function(message)
    table.insert(messages, message)
  end,
  error = function(message)
    table.insert(messages, message)
  end,
}
vim.fn.executable = function(binary)
  return (binary == "opencode" or binary == "curl") and 1 or 0
end
vim.fn.system = function(command)
  if command == "opencode --version" then
    return "1.17.5\n"
  end
  return "test-git-hash\n"
end
package.loaded["opencode.config"] = { opts = { events = { reload = false }, server = {} } }
local health = require("opencode.health")
health.check()

local health_output = table.concat(messages, "\n")
assert(health_output:find(metadata.component_id, 1, true), health_output)
assert(health_output:find(relationship.contract.version, 1, true), health_output)
assert(health_output:find("outside the tested matrix", 1, true), health_output)
assert(health_output:find("does not establish support", 1, true), health_output)

messages = {}
package.loaded["opencode.component"] = {
  read = function()
    return nil, "opencode.nvim component metadata unavailable: malformed-json"
  end,
}
health.check()
assert(table.concat(messages, "\n"):find("component metadata unavailable: malformed-json", 1, true))
package.loaded["opencode.component"] = component
vim.health = original_health
vim.fn.executable = original_executable
vim.fn.system = original_system

vim.cmd("qa!")
