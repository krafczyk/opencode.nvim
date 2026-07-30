local M = {}

local MAX_ARTIFACT_BYTES = 16 * 1024
local MAX_DIAGNOSTIC_BYTES = 256
local COMPONENT_IDS = {
  ["mkchad"] = true,
  ["container-runtime"] = true,
  ["nvim-image"] = true,
  ["opencode"] = true,
  ["opencode-nvim"] = true,
  ["opencode-project-reload"] = true,
  ["compound-engineering"] = true,
  ["sprint-loop-controller"] = true,
  ["sprint-loop-nvim"] = true,
  ["prereq-neovim"] = true,
  ["prereq-git"] = true,
  ["prereq-python"] = true,
  ["prereq-node"] = true,
  ["prereq-curl"] = true,
}

local function diagnostic(code)
  return ("opencode.nvim component metadata unavailable: " .. code):sub(1, MAX_DIAGNOSTIC_BYTES)
end

local function is_utf8(text)
  local index = 1
  while index <= #text do
    local byte = text:byte(index)
    if byte < 0x80 then
      index = index + 1
    else
      local length
      local minimum
      if byte >= 0xC2 and byte <= 0xDF then
        length, minimum = 2, 0x80
      elseif byte >= 0xE0 and byte <= 0xEF then
        length, minimum = 3, 0x800
      elseif byte >= 0xF0 and byte <= 0xF4 then
        length, minimum = 4, 0x10000
      else
        return false
      end

      if index + length - 1 > #text then
        return false
      end
      local value = byte % 2 ^ (8 - length - 1)
      for offset = 1, length - 1 do
        local continuation = text:byte(index + offset)
        if continuation < 0x80 or continuation > 0xBF then
          return false
        end
        value = value * 64 + (continuation - 0x80)
      end
      if value < minimum or value > 0x10FFFF or (value >= 0xD800 and value <= 0xDFFF) then
        return false
      end
      index = index + length
    end
  end
  return true
end

local function is_text(value, maximum)
  if type(value) ~= "string" or #value > maximum then
    return false
  end
  for index = 1, #value do
    if value:byte(index) < 32 or value:byte(index) == 127 then
      return false
    end
  end
  return is_utf8(value)
end

local function is_object(value)
  return type(value) == "table" and not vim.islist(value)
end

local function is_integer(value)
  return type(value) == "number" and value % 1 == 0
end

local function reject_duplicate_keys(raw)
  local position = 1
  local length = #raw

  local function whitespace()
    while position <= length and raw:sub(position, position):match("[%s]") do
      position = position + 1
    end
  end

  local function string_value()
    local start = position
    if raw:sub(position, position) ~= '"' then
      return nil
    end
    position = position + 1
    while position <= length do
      local byte = raw:byte(position)
      if byte == 34 then
        position = position + 1
        local ok, value = pcall(vim.json.decode, raw:sub(start, position - 1))
        return ok and value or nil
      elseif byte == 92 then
        position = position + 1
        local escape = raw:sub(position, position)
        if escape == "u" then
          if not raw:sub(position + 1, position + 4):match("^%x%x%x%x$") then
            return nil
          end
          position = position + 4
        elseif not escape:match('^["\\/bfnrt]$') then
          return nil
        end
      elseif byte < 32 then
        return nil
      end
      position = position + 1
    end
    return nil
  end

  local value
  local object
  local array

  local function literal(expected)
    if raw:sub(position, position + #expected - 1) ~= expected then
      return false
    end
    position = position + #expected
    return true
  end

  function object()
    position = position + 1
    whitespace()
    local keys = {}
    if raw:sub(position, position) == "}" then
      position = position + 1
      return true
    end
    while true do
      local key = string_value()
      if key == nil or keys[key] then
        return false
      end
      keys[key] = true
      whitespace()
      if raw:sub(position, position) ~= ":" then
        return false
      end
      position = position + 1
      if not value() then
        return false
      end
      whitespace()
      local delimiter = raw:sub(position, position)
      if delimiter == "}" then
        position = position + 1
        return true
      end
      if delimiter ~= "," then
        return false
      end
      position = position + 1
      whitespace()
    end
  end

  function array()
    position = position + 1
    whitespace()
    if raw:sub(position, position) == "]" then
      position = position + 1
      return true
    end
    while true do
      if not value() then
        return false
      end
      whitespace()
      local delimiter = raw:sub(position, position)
      if delimiter == "]" then
        position = position + 1
        return true
      end
      if delimiter ~= "," then
        return false
      end
      position = position + 1
      whitespace()
    end
  end

  function value()
    whitespace()
    local character = raw:sub(position, position)
    if character == "{" then
      return object()
    end
    if character == "[" then
      return array()
    end
    if character == '"' then
      return string_value() ~= nil
    end
    if character == "t" then
      return literal("true")
    end
    if character == "f" then
      return literal("false")
    end
    if character == "n" then
      return literal("null")
    end
    if character:match("[-0-9]") then
      repeat
        position = position + 1
        character = raw:sub(position, position)
      until character == "" or character:match("[%s,%]}]")
      return true
    end
    return false
  end

  if not value() then
    return false
  end
  whitespace()
  return position > length
end

local function validate_text_values(value, depth)
  if depth > 32 then
    return nil, "metadata-too-deep"
  end
  if type(value) == "string" then
    return is_text(value, MAX_ARTIFACT_BYTES) and true or nil, "invalid-text"
  end
  if type(value) ~= "table" then
    return true
  end
  if vim.islist(value) then
    for _, child in ipairs(value) do
      local ok, code = validate_text_values(child, depth + 1)
      if not ok then
        return nil, code
      end
    end
    return true
  end
  for key, child in pairs(value) do
    if not is_text(key, MAX_ARTIFACT_BYTES) then
      return nil, "invalid-text"
    end
    local ok, code = validate_text_values(child, depth + 1)
    if not ok then
      return nil, code
    end
  end
  return true
end

local function validate_version(version)
  return is_text(version, 128) and #version > 0
end

local function validate_contract(contract)
  if not is_object(contract) or type(contract.kind) ~= "string" then
    return nil, "invalid-contract"
  end
  if #vim.json.encode(contract) > 768 then
    return nil, "contract-too-large"
  end

  if contract.kind == "identity" then
    return is_text(contract.profile, 64) and true or nil, "invalid-identity-contract"
  end
  if
    contract.kind ~= "exact"
    and contract.kind ~= "exact-set"
    and contract.kind ~= "range"
    and contract.kind ~= "tested-baseline"
  then
    return nil, "invalid-contract-kind"
  end
  if contract.suffix_policy ~= "literal" and contract.suffix_policy ~= "explicit-equivalence" then
    return nil, "invalid-suffix-policy"
  end

  if contract.kind == "exact" or contract.kind == "tested-baseline" then
    if not validate_version(contract.version) then
      return nil, "invalid-contract-version"
    end
  elseif contract.kind == "exact-set" then
    if not vim.islist(contract.versions) or #contract.versions == 0 or #contract.versions > 4 then
      return nil, "invalid-contract-versions"
    end
    local versions = {}
    for _, version in ipairs(contract.versions) do
      if not validate_version(version) or versions[version] then
        return nil, "invalid-contract-versions"
      end
      versions[version] = true
    end
  else
    if not vim.islist(contract.clauses) or #contract.clauses == 0 or #contract.clauses > 8 then
      return nil, "invalid-contract-clauses"
    end
    local clauses = {}
    for _, clause in ipairs(contract.clauses) do
      if not is_object(clause) or not validate_version(clause.min_inclusive) then
        return nil, "invalid-contract-clauses"
      end
      if clause.max_exclusive ~= nil and not validate_version(clause.max_exclusive) then
        return nil, "invalid-contract-clauses"
      end
      local key = clause.min_inclusive .. "\0" .. (clause.max_exclusive or "")
      if clauses[key] then
        return nil, "invalid-contract-clauses"
      end
      clauses[key] = true
    end
  end

  if contract.suffix_policy == "explicit-equivalence" then
    if not vim.islist(contract.equivalences) or #contract.equivalences > 4 then
      return nil, "invalid-equivalences"
    end
    local equivalences = {}
    for _, equivalence in ipairs(contract.equivalences) do
      if
        not is_object(equivalence)
        or not validate_version(equivalence.observed)
        or not validate_version(equivalence.equivalent_to)
        or equivalences[equivalence.observed]
      then
        return nil, "invalid-equivalences"
      end
      equivalences[equivalence.observed] = true
    end
  end
  return true
end

local function validate(metadata)
  local text_ok, text_code = validate_text_values(metadata, 0)
  if not text_ok then
    return nil, text_code
  end
  if not is_object(metadata) then
    return nil, "invalid-root"
  end
  if metadata.schema == nil then
    return nil, "missing-schema"
  end
  if not is_integer(metadata.schema) or metadata.schema ~= 1 then
    return nil, "unsupported-schema"
  end
  if not is_text(metadata.component_id, 64) or metadata.component_id ~= "opencode-nvim" then
    return nil, "invalid-component-id"
  end
  if metadata.component_version ~= nil and not validate_version(metadata.component_version) then
    return nil, "invalid-component-version"
  end
  if not vim.islist(metadata.relationships) or #metadata.relationships > 4 then
    return nil, "invalid-relationships"
  end

  local ids = {}
  local tested_with
  for _, relationship in ipairs(metadata.relationships) do
    if
      not is_object(relationship)
      or not is_text(relationship.id, 64)
      or not relationship.id:match("^[A-Za-z0-9][A-Za-z0-9._-]*$")
      or ids[relationship.id]
    then
      return nil, "invalid-relationship-id"
    end
    ids[relationship.id] = true
    if
      relationship.type ~= "ships"
      and relationship.type ~= "requires"
      and relationship.type ~= "supports"
      and relationship.type ~= "tested-with"
    then
      return nil, "invalid-relationship-type"
    end
    if not is_text(relationship.target_component, 64) or not COMPONENT_IDS[relationship.target_component] then
      return nil, "invalid-target-component"
    end
    local contract_ok, contract_code = validate_contract(relationship.contract)
    if not contract_ok then
      return nil, contract_code
    end
    if relationship.type == "tested-with" and relationship.target_component == "opencode" then
      if relationship.contract.kind ~= "tested-baseline" or tested_with then
        return nil, "invalid-tested-with"
      end
      tested_with = relationship
    end
  end
  if not tested_with then
    return nil, "missing-tested-with"
  end
  if metadata.identity_profile ~= nil then
    return nil, "invalid-identity-profile"
  end
  return true
end

local function artifact_path()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":h:h:h") .. "/opencode-component.json"
end

function M.read(path)
  local file = io.open(path or artifact_path(), "rb")
  if not file then
    return nil, diagnostic("artifact-unavailable")
  end
  local raw = file:read(MAX_ARTIFACT_BYTES + 1)
  file:close()
  if not raw then
    return nil, diagnostic("artifact-unavailable")
  end
  return M.decode(raw)
end

function M.decode(raw)
  if type(raw) ~= "string" then
    return nil, diagnostic("malformed-json")
  end
  if #raw > MAX_ARTIFACT_BYTES then
    return nil, diagnostic("artifact-too-large")
  end

  local decoded, metadata = pcall(vim.json.decode, raw)
  if not decoded then
    return nil, diagnostic("malformed-json")
  end
  if not reject_duplicate_keys(raw) then
    return nil, diagnostic("duplicate-keys")
  end
  local valid, code = validate(metadata)
  if not valid then
    return nil, diagnostic(code)
  end
  return metadata
end

function M.tested_with(metadata)
  for _, relationship in ipairs(metadata.relationships) do
    if relationship.type == "tested-with" and relationship.target_component == "opencode" then
      return relationship
    end
  end
end

function M.tested_with_judgment(contract, version)
  if version == contract.version then
    return "tested"
  end
  if contract.suffix_policy == "explicit-equivalence" then
    for _, equivalence in ipairs(contract.equivalences) do
      if equivalence.observed == version and equivalence.equivalent_to == contract.version then
        return "tested-equivalent"
      end
    end
  end
  return "outside-tested-matrix"
end

return M
