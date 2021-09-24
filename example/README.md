## **Example**

Before we begin the example, we need to complete the [pre-configuration](../README.md#pre-configuration-required-for-the-plugin), [installation](../README.md#plugin-installation) and [enablement](../README.md#plugin-enabling-paramters) for the plugin.

- Lets create a service:

```
curl -i -X POST \
  --url http://localhost:8001/services/ \
  --data 'name=download-service' \
  --data 'url=http://localhost:1001'
```

- Creating a route to the service:
```
curl -i -X POST \
  --url http://localhost:8001/services/download-service/routes \
  --data 'strip_path=false' \
  --data 'name=download-route' \
  --data 'paths[]=/download'
```

- Assigning the download limiter plugin to the service:
```
curl -i -X POST \
  --url http://localhost:8001/services/download-service/plugins/ \
  --data 'name=download-limiter' \
  --data 'config.domain_header=X-Domain' \
  --data 'config.response_header=X-Ratelimited'
```

- Configuring a domain to rate limit:<br>
via create
```
curl -v -X POST --url http://localhost:8001/download-limiter/domains  \
--data 'domain=test' \
--data 'rule={
        "config" : {"match_path": "^/download/data", "dl_limit":1000, "extend_limits":1, "extend_range": 0.5} ,
        "exclude_filter": [{ "type": "Header", "name": "X-Integration-User-Agent", "pattern": "bypass" }],
        "include_filter": [{ "type": "Header", "name": "X-Integration-User-Agent", "pattern": "ratelimit" }]}'
```
&emsp;&emsp;OR via upsert
```
curl -v -X PUT --url http://localhost:8001/download-limiter/domain/test  \
--data 'rule={
        "config" : {"match_path": "^/download/data", "dl_limit":1000, "extend_limits":1, "extend_range": 0.5} ,
        "exclude_filter": [{ "type": "Header", "name": "X-Integration-User-Agent", "pattern": "bypass" }],
        "include_filter": [{ "type": "Header", "name": "X-Integration-User-Agent", "pattern": "ratelimit" }] }'
```
&emsp;&emsp;Explanation about the parameters is available [here](../README.md#parameters-required-for-post-are-)

- Create a mock upstream service for our kong service created above:
```
mkdir -p /tmp/mock-backend/logs
cp nginx-mock-backend.conf /tmp/mock-backend/
/usr/local/openresty/nginx/sbin/nginx -p /tmp/mock-backend -c nginx-mock-backend.conf
```


- Now our plugin is ready to serve :) Lets put some traffic through it.
```
curl -v -I -H 'X-Integration-User-Agent: ratelimit' -H 'X-Domain: test' localhost:8000/download/data
```
After a few hits, the banwidth limit would be exhausted and the service rate limited with 429 return status code.<br>
`X-Ratelimited`(configurable) and `X-Retry-After` headers would be sent as part of the response headers.<br>
Since for performance reasons we seed to redis every 30 seconds, there could be worst case rate limit delay of 30 seconds.<br>
Also we rate limit basis `ngx.var.bytes_sent` whereas kong logs `ngx.var.body_bytes_sent`.<br>
So you would see some difference in banwidth consumption in aggregated redis data vs access logs.<br>
Reference : https://nginx.org/en/docs/http/ngx_http_core_module.html#variables

However,if we use headers configured in `exclude_filter` then we'll be able to bypass rate limiting.<br>
Following request would not be rate limited.
```
curl -v -I -H 'X-Integration-User-Agent: bypass' -H 'X-Domain: test' localhost:8000/download/data
```

We can store the required config for services, routes, plugins, domains in a version control system and use GitOps to make management easier.<br>
Kong's [**decK**](https://docs.konghq.com/deck/) is also a good option.

## **Clean up**
- Deleting configured route, service, plugin and registered domain.
```
curl -X DELETE http://localhost:8001/services/download-service/routes/download-route
curl -X DELETE http://localhost:8001/services/download-service
curl -X DELETE http://localhost:8001/download-limiter/domain/test
```

- Bring down the mock service.
```
Run `ps -ef | grep -i nginx` and kill the master and worker process.
Delete `/tmp/mock-backend` directory.
```


  
