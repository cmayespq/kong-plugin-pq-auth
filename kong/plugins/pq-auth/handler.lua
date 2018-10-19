local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local http = require "resty.http"
local helpers = require "kong.plugins.pq-auth.helpers"
local log = helpers.log
local dump = helpers.dump

local ProQuestAuthHandler = BasePlugin:extend()

function ProQuestAuthHandler:new()
  ProQuestAuthHandler.super.new(self, "pq-auth")
end

function ProQuestAuthHandler:access(conf)
  ProQuestAuthHandler.super.access(self)

  local client = http.new()
  client:set_timeouts(conf.connect_timeout, conf.send_timeout, conf.read_timeout)

  local auth_header = kong.request.get_headers()["Authorization"]

  if not auth_header then
    return responses.send_HTTP_BAD_REQUEST("No Authorization header")
  end

  -- Take out the Bearer prefix and strip leading and trailing spaces.
  local auth_header = string.gsub(auth_header, 'Bearer%s*', ''):match("^%s*(.-)%s*$")

  log.notice("Authentication header value: ", auth_header)

  if helpers.isempty(auth_header) then
    return responses.send_HTTP_BAD_REQUEST("No Authorization header value")
  end

  local base_url
  if (helpers.ends_with(conf.url,"/")) then
    base_url = conf.url
  else
    base_url = conf.url .. "/"
  end

  local pqd_url = base_url .. auth_header

  log.notice("PQD URL: ", pqd_url)

  local res, err = client:request_uri(pqd_url)

  log.notice("CALL RESULT: ", dump(res), "err", dump(err))

  if not res then
    log.notice("First 500 with err " .. err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  if res.status == 500 then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR("Error from auth service")
  end

  if res.status ~= 200 then
    return responses.send_HTTP_UNAUTHORIZED("Invalid auth token")
  end
end

ProQuestAuthHandler.PRIORITY = 900

return ProQuestAuthHandler