local url = require "socket.url"

--- Stringifies the given table entry.
-- @param t The table to extract.
-- @param indent A value to prepend to each line of this call.
-- @return A string representation of the given table.
--
local function dump(t, indent)
  if indent == nil then
    indent = ''
  end
  if type(t) == "table" then
    local s = '{\n'
    for k, v in pairs(t) do
      s = s .. indent .. '  ' .. k .. ": " .. dump(v, indent .. "  "):gsub("^%s*(.-)%s*$", "%1") .. "\n"
    end
    return s .. indent .. '}\n'
  end
  return indent .. tostring(t)
end

--- Creates a structured description of the given URI path.
-- @param path The path to evaluate.
-- @param sep The string that separates path segments.
-- @return A table containing the fields of the path.
--
local function parse_path(path, sep)
  local sep = sep or "/"
  local parts = {}
  local fields = {}
  local token
  local pattern = string.format("([^%s]+)", sep)
  path:gsub(pattern, function(c) parts[#parts + 1] = c end)
  for i, v in pairs(parts) do
    token = parse_token(v)
    fields[#fields + 1] = token and token or { symbol = v }
  end
  return fields
end

--- Parses the given URL, returning a description of the URL's parts.
-- @param host_url The URL to parse.
-- @return A table with the URL's port, scheme, path and path_parts.
--
local function parse_url(host_url)
  local parsed_url = url.parse(host_url)
  if not parsed_url.port then
    if parsed_url.scheme == "http" then
      parsed_url.port = 80
    elseif parsed_url.scheme == "https" then
      parsed_url.port = 443
    end
  end
  if not parsed_url.path then
    parsed_url.path = "/"
  end
  parsed_url.path_parts = parse_path(parsed_url.path)
  return parsed_url
end

--- Returns whether the given string is nil or empty.
-- @param s The string to check.
--
local function isempty(s)
  return s == nil or s == ''
end

--- Strips the leading and trailing whitespace from the given string.
-- @param s The string to strip.
--
local function strip(s)
  if isempty(s) then
    return s
  end

  return s:match("^%s*(.-)%s*$")
end

--- Returns the keys for the given table.
-- @param t The table to evaluate.
--
local function keys(t)
  local keyset = {}

  if keys == nil then
    return keyset
  end

  local n = 0
  for k in pairs(t) do
    n = n + 1
    keyset[n] = k
  end
  return keyset
end

--- Returns whether the given string starts with the given prefix.
-- @param str The string to check.
-- @param start The prefix to check for.
--
local function starts_with(str, start)
  if isempty(str) then
    return false
  end
  return str:sub(1, #start) == start
end

--- Returns whether the given string ends with the given suffix.
-- @param str The string to check.
-- @param ending The suffix to check for.
--
local function ends_with(str, ending)
  if isempty(str) then
    return false
  end
  return ending == "" or str:sub(-#ending) == ending
end

-- Bundles up the functions to expose.
return {
  parse_path = parse_path,
  parse_url = parse_url,
  isempty = isempty,
  strip = strip,
  dump = dump,
  keys = keys,
  starts_with = starts_with,
  ends_with = ends_with,
}
