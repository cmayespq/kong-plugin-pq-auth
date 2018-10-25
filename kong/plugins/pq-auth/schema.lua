return {
  no_consumer = true,
  fields = {
    url = { required = true, type = "url" },
    connect_timeout = { default = 10000, type = "number" },
    send_timeout = { default = 60000, type = "number" },
    read_timeout = { default = 60000, type = "number" },
    rate_second = { default = 600, type = "number" },
    rate_minute = { default = 6000, type = "number" },
    rate_hour = { type = "number" },
    rate_day = { type = "number" },
    rate_month = { type = "number" },
    rate_year = { type = "number" },
    cache_ttl_seconds = { default = 3600, type = "number" },
    cache_neg_ttl_seconds = { default = 30, type = "number" },
  }
}