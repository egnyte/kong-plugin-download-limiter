local plugin = {
  PRIORITY = 800,
  VERSION = "0.1",
}

local cjson = require("cjson")
local limiter = require 'kong.plugins.download-limiter.download_limiter'
local log_record = require 'kong.plugins.download-limiter.download_recorder'

function plugin:init_worker()

  if _G.redis_dl_limit_host == nil then
    redis_dl_limit_host = os.getenv("redis_dl_limit_host")
  end
  if _G.redis_dl_limit_port == nil then
    redis_dl_limit_port = tonumber(os.getenv("redis_dl_limit_port"))
  end
  if _G.redis_dl_limit_key_prefix == nil then
    redis_dl_limit_key_prefix = os.getenv("redis_dl_limit_key_prefix")
  end

  function seed_to_redis(premature)
    local success, err, forcible = ngx.shared.dl_worker_lock:add("dl_worker_lock", 1 , 29)
    if success then
      log_record.send_download_data_keys_to_redis(premature, _G.redis_dl_limit_host, _G.redis_dl_limit_port)
    elseif err == "exists" then
      return
    else
      kong.log.err("Timer not working: for worker : ",ngx.worker.id(), err)
    end
  end

  ok, err = ngx.timer.every(30, seed_to_redis)
  if not ok then
      kong.log.err("failed to create DOWNLOAD_LIMITER Timer: ", err)
  end

end

function plugin:access(plugin_conf)

  local domain_header = kong.request.get_header(plugin_conf.domain_header)

  if (domain_header ~= nil) then
  
    local domain, err = kong.db.download_limiter:select({ domain =  domain_header  })
    if err then
      kong.log.err("Error  :  " .. err)
    end

    if domain then
      local rule = cjson.decode(domain.rule)
      local status = limiter.check_download_limit(rule, domain_header)
      if status then
        kong.response.set_header('X-Retry-After', limiter.generate_retry_header())
        kong.response.set_header(plugin_conf.response_header, 'rate_limited')
        return kong.response.exit(429)
      end
    end
  end

end

function plugin:log(plugin_conf)
    if kong.ctx.plugin.domain then
      log_record.log_download_limit(kong.ctx.plugin.domain)
    end
end

return plugin
