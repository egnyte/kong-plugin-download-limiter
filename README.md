# download-limiter

## Overview

Bandwidth/Egress pricing is a major component of the cloud services model. For a content heavy service like video or document store, egress costs could quickly spiral out of control. To mitigate this, it is important to put limits on the amount of data you users can download in a given interval.

This kong plugin lets you define per-day download limits on your apis. The plugin can be configured to filter specific requests/apis, extract user-defined headers and enforce limits based on custom rules. 

The plugin can be used to rate limit/throttle requests based on bandwidth consumption per user/customer/custom entity wise on a daily consumption basis.
The plugin also supports rate limit [extension on weekends](#config) and daily configurable jitter. 
The jitter extension helps the client identify that they are exhasuting their bandwidth and take remediation steps.

## How does it work
The plugin works on a header in the incoming request(X-Domain -- default,configurable), that is used to aggregate consumption. Plugin also allows to filter out specific requests or filter in only specific requests for rate limiting based on the incoming headers.

The plugin needs the domain header and corresponding values configured to rate limit against. A domain header can be a user/customer/custom entity or any other header as long as we pass it in the request that we want to rate limit. The domain header is configured as part of the plugin [enablement](#plugin-enabling-paramters).

The plugin provides [CRUD API](#plugin-api) for configuring the domain values.

Aggregated domain wise download information is stored in redis. This is achieved by a controller loop, configured in `init_worker_by_lua_block` that seeds to redis every 30 seconds.

<hr>

### Pre-configuration required for the plugin
The plugin needs `redis host`, `redis port`, `redis key prefix` details to store download info, lua_shared_dict's `download_data_counter`(for temporarily storing download data before seeding to redis) and `dl_worker_lock`(to avoid concurrency in nginx workers while seeding).


Since plugin configuration parameters are not available during the [init worker phase](https://docs.konghq.com/gateway-oss/2.5.x/plugin-development/custom-logic/#available-contexts) we need to use a [custom nginx template for kong](https://docs.konghq.com/gateway-oss/2.5.x/configuration/#custom-nginx-templates)

Following is how we can configure `dl_worker_lock` and `download_data_counter` in the `http` section of the template:
```
lua_shared_dict dl_worker_lock 100k;
lua_shared_dict download_data_counter 12m;
```
lua shared dicts can be monitored and tuned with the amazing kong [prometheus](https://docs.konghq.com/hub/kong-inc/prometheus/) plugin

redis host and port needs to be enabled as global variables in the init by lua block. eg:
```
init_by_lua_block {
        Kong = require 'kong'
        Kong.init()
        redis_dl_limit_host = "127.0.0.1"
        redis_dl_limit_port = 6379
        redis_dl_limit_key_prefix="dl_limit"
}

```
To avoid hard coding redis host and port, we can use a configuration management framework like Ansible, Puppet or Chef.

<hr>

### Plugin installation
Clone this repo on the kong node, then `cd` into the directory and run `luarocks make`.<br>
Add the plugin name as a custom plugin in kong.conf. Eg: ```plugins=bundled,download-limiter```<br>
Before starting up kong you will need to run `kong migrations up`.

<hr>

### Plugin enabling paramters
The plugin requires the following paramters while enabling it:
- request_domain(default: X-Domain) : Incoming domain header to rate limit against
- response_header(default: X-Ratelimited) : Response header to be sent if the request is rate limited.

When the request is rate limited, the plugin also sends `X-Retry-After` header which specifies in seconds the time after which the client should re-try. Some randomness is added to `X-Retry-After` to avoid servers getting overwhelmed.

The plugin can be enabled service basis or can be enable globally.

<hr>

### Performance
To maintain performance and not to overwhelm redis, the plugin collects `ngx.var.bytes_sent` domain wise for each eligible request in `lua_shared_dict download_data_counter` and seeds into redis every 30 seconds. Hence, there could be a worst case bound delay of 30 sec to rate limit.

<hr>

### Plugin API
- GET -       \<kong-admin-url-or-host:port\>/download-limiter/domains : To list all configured domains
- GET -       \<kong-admin-url-or-host:port\>/download-limiter/domain/\<domain\> : To view configuration of a domain
- DELETE -    \<kong-admin-url-or-host:port\>/download-limiter/domain/\<domain\> : To delete a domain
- POST -      \<kong-admin-url-or-host:port\>/download-limiter/domains : To add a domain
- PUT -       \<kong-admin-url-or-host:port\>/download-limiter/domain/\<domain\> : To upsert a domain

<hr>

#### Parameters required for POST are:-
- domain : domain value to rate limit against.
- rule : [rule object](#rule-object)

##### **rule object:**
- config : [rate limting paramters](#config)
- exclude_filter: [\[list of exclude filter rules for rate limit\]](#exclude_filter-list)
- include_filter: [\[list of include filter rules for rate limit\]](#include_filter-list)

##### **config:**
- dl_limit : Total permissible download limit in bytes
- extend_limits : Percentage limit to extend on weekends (0.01 is 1% and 1 is 100%)
- extend_range : Percentage of daily [jittered](#jitter) extension allowed post rate limit (0.01 is 1% and 1 is 100%)
- match_path: Path to rate limit, particularly useful if the plugin is globally enabled

##### **exclude_filter list:**
- type: header (only header option available as of now)
- name : name of the header to exclude from rate limit
- pattern : pattern to match against the header value to bypass rate limit

##### **include_filter list:**
- type: header (only header option available as of now)
- name : name of the header to include for rate limit
- pattern : pattern to match against the header value to rate limit against


#### Parameters required for PUT are:-
rule: [rule object](#rule-object)

<hr>

#### **Monitoring:**
The aggregated domain wise values are store in redis in the format `<redis_dl_limit_key_prefix>.<domain>.yyyymmdd`. Eg: `dl_limit.test.20210922`.
This values can be pushed into any monitoring solution like Prometheus and Grafana and would give us info on the domain wise download trends and also aid in alerting.

<hr>

#### **Jitter:**
The jitter helps client konw that they are reaching rate limit and can take steps to remediate the same. 
For example, lets say a client is allowed a daily bandwidth limit of 100 GB via `dl_limit` and an allowed extension of 20%(20GB) via `extend_range`. 
Post reaching 100 GB, the client requests would enter a jitter zone where some requests, based on randomness would pass and some would be rate limited.
This would be till the exhasution of the addtional 20% bandwidth post which all requests would return 429.

<hr>

### **Example**
API examples and usage is available [here](example/)
