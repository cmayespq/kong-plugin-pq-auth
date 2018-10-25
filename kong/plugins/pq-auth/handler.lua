--- Handles ProQuest authentication for Kong proxies.
-- @module handler
--
-- Calls internal services to validate the provided credentials and associates
-- a Kong consumer with the user to allow for per-user rate limiting and tracking.
-- Note that the `kong` variable is an implicit global.

local pqd_auth_cache_prefix = "pqd_auth"

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

--- Creates the key for caching PQD authentication call results.
-- @param auth_key The auth key to be validated.
--
local function pqd_cache_key(auth_key)
  return pqd_auth_cache_prefix .. ":" .. auth_key
end

--- Performs initialization tasks, including subscribing to change events for consumers.
--
function ProQuestAuthHandler:init_worker()
  log.notice("In init_worker")
  ProQuestAuthHandler.super.init_worker(self)
  local worker_events = kong.worker_events

  worker_events.register(function(data)
    if data.operation ~= "create" then
      log.notice("Invalidating cache for consumer: " .. dump(data.entity))
      local consumer_cache_key = kong.db.consumers:cache_key(data.entity.username)
      kong.cache:invalidate(consumer_cache_key)
      local auth_cache_key = pqd_cache_key(data.entity.custom_id)
      kong.cache:invalidate(auth_cache_key)
    end
  end, "crud", "consumers")
end

--- Sets consumer (Kong's concept of a user) header data.
-- @param consumer The consumer object for the request's user.
--
local function set_consumer(consumer)
  local const = constants.HEADERS

  log.info("Setting consumer headers for: ", dump(consumer))

  local new_headers = {
    [const.CONSUMER_ID] = consumer.id,
    [const.CONSUMER_CUSTOM_ID] = tostring(consumer.custom_id),
    [const.CONSUMER_USERNAME] = consumer.username,
  }

  kong.ctx.shared.authenticated_consumer = consumer -- forward compatibility
  ngx.ctx.authenticated_consumer = consumer -- backward compatibility

  kong.service.request.set_headers(new_headers)
end

--- Queries the Kong database for the given user, creating a new entry if nothing is found.
-- @param username The user to search for.
-- @param auth_key The authentication key for the user.
-- @param conf The plugin's configuration.
-- @return The found or created consumer for the given user name.
--
local function load_or_create_consumer(username, auth_key, conf)
  kong.log.notice("Loading consumer for user " .. username)
  local found_consumer = kong.db.consumers:select_by_username(username)

  if not found_consumer then
    local inserted_consumer, err = kong.db.consumers:insert({
      username = username,
      custom_id = auth_key
    })

    if not inserted_consumer then
      return nil, err
    end

    log.debug("Conf before inserting limiter: " .. dump(conf))

    local inserted_limiter, err = kong.dao.plugins:insert {
      name = "rate-limiting",
      consumer_id = inserted_consumer.id,
      config = {
        second = conf.rate_second,
        minute = conf.rate_minute,
        hour = conf.rate_hour,
        day = conf.rate_day,
        month = conf.rate_month,
        year = conf.rate_year,
      },
    }

    if not inserted_limiter then
      log.warn("Problems creating rate limiter for user " .. username .. ": " .. dump(err))
    end

    return inserted_consumer
  end

  if found_consumer.custom_id == purge_cache_custom_id then
    return nil, error({
      message = "Customer " .. found_consumer.username .. "should have its cache purged",
      code = purge_cache_error_code
    })
  end

  return found_consumer
end

--- Gets the Kong consumer for the given user name.
-- @param username The name of the user to fetch.
-- @param auth_key The authentication key for the user.
-- @param conf The plugin's configuration.
-- @return The found or created consumer.
--
local function get_consumer_by_username(username, auth_key, conf)
  local cache = kong.cache

  local consumer_cache_key = kong.db.consumers:cache_key(username)

  local cache_opts = { ttl = conf.cache_ttl_seconds, neg_ttl = conf.cache_neg_ttl_seconds }

  local consumer, err = cache:get(consumer_cache_key, cache_opts,
    load_or_create_consumer, username, auth_key, conf)

  if err then
    kong.log.err(err)
    return nil, { status = 500, message = "Problems fetching consumer info" }
  end

  return consumer
end

--- Queries PQD auth server specified in `conf.url` using the given auth key.
-- @param auth_key The key to query for.
-- @param conf The plugin's configuration.
--
local function load_authentication(auth_key, conf)
  log.notice("Loading authentication for " .. auth_key)

  local base_url
  if (helpers.ends_with(conf.url, "/")) then
    base_url = conf.url
  else
    base_url = conf.url .. "/"
  end

  local pqd_url = base_url .. auth_key

  log.debug("PQD URL: ", pqd_url)

  local client = http.new()
  client:set_timeouts(conf.connect_timeout, conf.send_timeout, conf.read_timeout)

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
  return helpers.strip(profile_name:gsub('/profile/', ''))
end

--- Determines whether the given authentication key is valid, returning the user name
-- associated with the key.
-- @param auth_key The key to validate.
-- @param conf The plugin's configuration.
--
local function do_authentication(auth_key, conf)
  local cache = kong.cache

  local auth_cache_key = pqd_cache_key(auth_key)

  local cache_opts = { ttl = conf.cache_ttl_seconds, neg_ttl = conf.cache_neg_ttl_seconds }

  local user_name, err = cache:get(auth_cache_key, cache_opts,
    load_authentication, auth_key, conf)

  if err then
    kong.log.err(err)
    return nil, { status = 500, message = "Problems during authentication" }
  end

  return user_name
end

--- Authenticates the requesting user and adds user metadata to the request.
-- This is the entry point for the plugin.
-- @param conf The plugin's configuration.
--
function ProQuestAuthHandler:access(conf)
  ProQuestAuthHandler.super.access(self)

  local auth_header = kong.request.get_headers()["Authorization"]

  if not auth_header then
    return responses.send_HTTP_BAD_REQUEST("No Authorization header")
  end

  local auth_key = helpers.strip(string.gsub(auth_header, '[Bb][Ee][Aa][Rr][Ee][Rr]%s*', ''))

  log.debug("Authentication header value: ", auth_key)

  if helpers.isempty(auth_key) then
    return responses.send_HTTP_BAD_REQUEST("No Authorization header value")
  end

  local username, err = do_authentication(auth_key, conf)

  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR("Problems fetching credentials: " .. dump(err))
  end

  local consumer, err = get_consumer_by_username(username, auth_key, conf)

  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR("Problems fetching consumer for " .. username .. ": " .. dump(err))
  end

  set_consumer(consumer)
end

-- Higher number is higher priority.  Most auth plugins start at 1000.
ProQuestAuthHandler.PRIORITY = 1050

return ProQuestAuthHandler