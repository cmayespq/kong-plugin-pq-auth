local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local http = require "resty.http"
local constants = require "kong.constants"
local helpers = require "kong.plugins.pq-auth.helpers"
local log = helpers.log
local dump = helpers.dump

local ProQuestAuthHandler = BasePlugin:extend()

function ProQuestAuthHandler:new()
  ProQuestAuthHandler.super.new(self, "pq-auth")
end

local function set_consumer(consumer, credential)
  local const = constants.HEADERS

  local new_headers = {
    [const.CONSUMER_ID] = consumer.id,
    [const.CONSUMER_CUSTOM_ID] = tostring(consumer.custom_id),
    [const.CONSUMER_USERNAME] = consumer.username,
  }

  kong.ctx.shared.authenticated_consumer = consumer -- forward compatibility
  ngx.ctx.authenticated_consumer = consumer -- backward compatibility

  kong.service.request.set_headers(new_headers)
end

local function load_consumer_by_username(username)
  local result, err = kong.db.consumers:select_by_username(username)

  if not result then
    local inserted_plugin, err = kong.db.consumers:insert({
      username = username
    })

    if not inserted_plugin then
      if not creds then
        return nil, err
      end
    end

    return inserted_plugin
  end

  return result
end

function ProQuestAuthHandler:access(conf)
  ProQuestAuthHandler.super.access(self)

  local client = http.new()
  client:set_timeouts(conf.connect_timeout, conf.send_timeout, conf.read_timeout)

  local auth_header = kong.request.get_headers()["Authorization"]

  if not auth_header then
    return responses.send_HTTP_BAD_REQUEST("No Authorization header")
  end

  local auth_header = helpers.strip(string.gsub(auth_header, '[Bb][Ee][Aa][Rr][Ee][Rr]%s*', ''))

  log.notice("Authentication header value: ", auth_header)

  if helpers.isempty(auth_header) then
    return responses.send_HTTP_BAD_REQUEST("No Authorization header value")
  end

  local base_url
  if (helpers.ends_with(conf.url, "/")) then
    base_url = conf.url
  else
    base_url = conf.url .. "/"
  end

  local pqd_url = base_url .. auth_header

  log.notice("PQD URL: ", pqd_url)

  local res, err = client:request_uri(pqd_url)

  log.notice("CALL RESULT: ", dump(res), "err", dump(err))

  if not res then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  if res.status == 500 then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR("Error from auth service")
  end

  if res.status ~= 200 then
    return responses.send_HTTP_UNAUTHORIZED("Invalid auth token")
  end

  local auth_body = res.body

  log.error("Auth body: " .. auth_body)
  log.error("Body type: " .. type(auth_body))

  local _, _, profile_name = auth_body:find('myResearchProfile>([^<]*)<')
  profile_name = helpers.strip(profile_name:gsub('/profile/', ''))
  log.error("Profile name: " .. profile_name)

  local consumer, err = load_consumer_by_username(profile_name)

  log.error("Found consumer: ", helpers.dump(consumer))

  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR("Problems fetching credentials: " .. err)
  end

  set_consumer(consumer)
end



ProQuestAuthHandler.PRIORITY = 900

return ProQuestAuthHandler