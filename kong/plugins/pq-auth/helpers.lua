local url = require "socket.url"

local function dump(t, indent)
  if indent == nil then
    indent = ''
  end
  if type(t)=="table" then
    local s = '{\n'
    for k, v in pairs(t) do
      s = s..indent..'  '..k..": "..dump(v, indent.."  "):gsub("^%s*(.-)%s*$", "%1").."\n"
    end
    return s..indent..'}\n'
  end
  return indent..tostring(t)
end

local function parse_path(path, sep)
  local sep = sep or "/"
  local parts = {}
  local fields = {}
  local token
  local pattern = string.format("([^%s]+)", sep)
  path:gsub(pattern, function(c) parts[#parts+1] = c end)
  for i, v in pairs(parts) do
    token = parse_token(v)
    fields[#fields+1] = token and token or {symbol = v}
  end
  return fields
end

local function parse_url(host_url)
  local parsed_url = url.parse(host_url)
  if not parsed_url.port then
    if parsed_url.scheme == "http" then
      parsed_url.port = 80
     elseif parsed_url.scheme == HTTPS then
      parsed_url.port = 443
     end
  end
  if not parsed_url.path then
    parsed_url.path = "/"
  end
  parsed_url.path_parts = parse_path(parsed_url.path)
  return parsed_url
end

local function isempty(s)
  return s == nil or s == ''
end

local function strip(s)
  if isempty(s) then
    return s
  end

  return s:match("^%s*(.-)%s*$")
end

local function keys(t)
  local keyset={}
  local n=0
  for k, v in pairs(t) do
    n=n+1
    keyset[n]=k
  end
  return keyset
end

local function starts_with(str, start)
  return str:sub(1, #start) == start
end

local function ends_with(str, ending)
  return ending == "" or str:sub(-#ending) == ending
end

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
