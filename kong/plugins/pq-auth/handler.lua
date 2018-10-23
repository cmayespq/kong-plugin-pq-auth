--- Handles ProQuest authentication for Kong proxies.
-- @module handler
--
-- Calls internal services to validate the provided credentials and associates
-- a Kong consumer with the user to allow for per-user rate limiting and tracking.
-- Note that the `kong` variable is an implicit global.

local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local http = require "resty.http"
local constants = require "kong.constants"
local helpers = require "kong.plugins.pq-auth.helpers"
local log = kong.log
local dump = helpers.dump

local ProQuestAuthHandler = BasePlugin:extend()

function ProQuestAuthHandler:new()
  ProQuestAuthHandler.super.new(self, "pq-auth")
end

--- Sets consumer (Kong's concept of a user) header data.
-- @param consumer The consumer object for the request's user.
--
local function set_consumer(consumer)
  local const = constants.HEADERS

  log.info("Setting consumer headers for: ", helpers.dump(consumer))

  local new_headers = {
    [const.CONSUMER_ID] = consumer.id,
    [const.CONSUMER_CUSTOM_ID] = tostring(consumer.custom_id),
    [const.CONSUMER_USERNAME] = consumer.username,
  }

  kong.ctx.shared.authenticated_consumer = consumer -- forward compatibility
  ngx.ctx.authenticated_consumer = consumer -- backward compatibility

  kong.service.request.set_headers(new_headers)
end

--- Queries the Kong database for the given user, creating a new entry if nothing found.
-- @param username The user to search for.
-- @return The found or created consumer for the given user name.
--
local function load_or_create_consumer(username)
  kong.log.debug("Loading consumer for user " .. username)
  local result = kong.db.consumers:select_by_username(username)

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

---  Gets the Kong consumer for the given user name.
-- @param username The name of the user to fetch.
--
local function get_consumer_by_username(username)
  local cache = kong.cache

  local consumer_cache_key = kong.db.consumers:cache_key(username)

  local consumer, err = cache:get(consumer_cache_key, nil,
    load_or_create_consumer, username)

  if err then
    kong.log.err(err)
    return nil, { status = 500, message = "Problems fetching consumer info" }
  end

  return consumer
end

--- Authenticates the requesting user and adds user metadata to the request.
-- This is the entry point for the plugin.
-- @param conf The plugin's configuration.
--
function ProQuestAuthHandler:access(conf)
  ProQuestAuthHandler.super.access(self)

  local client = http.new()
  client:set_timeouts(conf.connect_timeout, conf.send_timeout, conf.read_timeout)

  local auth_header = kong.request.get_headers()["Authorization"]

  if not auth_header then
    return responses.send_HTTP_BAD_REQUEST("No Authorization header")
  end

  local auth_header = helpers.strip(string.gsub(auth_header, '[Bb][Ee][Aa][Rr][Ee][Rr]%s*', ''))

  log.debug("Authentication header value: ", auth_header)

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

  log.debug("PQD URL: ", pqd_url)

  local res, err = client:request_uri(pqd_url)

  log.debug("CALL RESULT: ", dump(res), "err", dump(err))

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

  local _, _, profile_name = auth_body:find('myResearchProfile>([^<]*)<')
  local user_name = helpers.strip(profile_name:gsub('/profile/', ''))

  local consumer, err = get_consumer_by_username(user_name)

  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR("Problems fetching credentials: " .. err)
  end

  set_consumer(consumer)
end

ProQuestAuthHandler.PRIORITY = 900

return ProQuestAuthHandler