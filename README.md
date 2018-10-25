# Kong Plugin for ProQest Authentication

This plugin queries the PQD authentication service
and determines whether the token provided in a request's
`Authorization` header is valid.

If it is valid, the token's associated user is used to create
or fetch a Kong [`consumer`](https://docs.konghq.com/0.14.x/admin-api/#consumer-object), 
which can then be used for tracking and limiting a user's activity.

## Configuration

| Setting               | Default | Required | Purpose    |
|-----------------------|---------|----------|------------|
| url                   | nil     | true     | The base URL for the authentication service |
| connect_timeout       | 10000   | false    | Time in milliseconds to wait for a connection to complete
| send_timeout          | 60000   | false    | Time in milliseconds to wait for a send to complete
| read_timeout          | 60000   | false    | Time in milliseconds to wait for a read to complete
| rate_second           | 600     | false    | The maximum number of requests in a second
| rate_minute           | 6000    | false    | The maximum number of requests in a minute
| rate_hour             | nil     | false    | The maximum number of requests in an hour
| rate_day              | nil     | false    | The maximum number of requests in a day
| rate_month            | nil     | false    | The maximum number of requests in a month
| rate_year             | nil     | false    | The maximum number of requests in a year
| cache_ttl_seconds     | 3600    | false    | The cache expiry in seconds |
| cache_neg_ttl_seconds | 30      | false    | The cache expiry for negative results (missing, invalid, etc.) in seconds

## Examples

These examples use the [IDEA HTTP request format](https://www.jetbrains.com/help/idea/http-client-in-product-code-editor.html).
You may also wish to consult Kong's 
[plugin administration documentation](https://docs.konghq.com/0.14.x/admin-api/#plugin-object).

### Creating a plugin config for a route

```http request
POST http://localhost:8001/plugins/
Content-Type: application/json

{
  "name": "pq-auth",
  "route_id": "3f532f26-9d88-494a-b75d-a6576a529730",
  "config": {
    "url": "http://identity.dev.int.proquest.com/identity/authorization"
  }
}
```

### Creating a plugin config for a route with custom rates

```http request
POST http://localhost:8001/plugins/
Content-Type: application/json

{
  "name": "pq-auth",
  "route_id": "3f532f26-9d88-494a-b75d-a6576a529730",
  "config": {
    "url": "http://identity.dev.int.proquest.com/identity/authorization",
    "rate_minute": 10000,
    "rate_hour": 90000
  }
}
```

