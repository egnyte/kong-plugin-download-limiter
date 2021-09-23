-- If you're not sure your plugin is executing, uncomment the line below and restart Kong
-- then it will throw an error which indicates the plugin is being loaded at least.

--assert(ngx.get_phase() == "timer", "The world is coming to an end!")

---------------------------------------------------------------------------------------------
-- In the code below, just remove the opening brackets; `[[` to enable a specific handler
--
-- The handlers are based on the OpenResty handlers, see the OpenResty docs for details
-- on when exactly they are invoked and what limitations each handler has.
---------------------------------------------------------------------------------------------



local plugin = {
  PRIORITY = 800, -- set the plugin priority, which determines plugin execution order
  VERSION = "0.1",
}



-- do initialization here, any module level code runs in the 'init_by_lua_block',
-- before worker processes are forked. So anything you add here will run once,
-- but be available in all workers.

local cjson = require("cjson")
local limiter = require 'kong.plugins.download-limiter.download_limiter'
local log_record = require 'kong.plugins.download-limiter.download_recorder'


ngx.shared.dl_worker_lock:delete("dl_worker_lock")
kong.log.info("ngx.shared.dl_worker_lock:delete complete")

-- handles more initialization, but AFTER the worker process has been forked/created.
-- It runs in the 'init_worker_by_lua_block'
function plugin:init_worker()

  function seed_to_redis(premature)
    log_record.send_download_data_keys_to_redis(premature, _G.redis_dl_limit_host, _G.redis_dl_limit_port)
  end

  local success, err, forcible = ngx.shared.dl_worker_lock:add("dl_worker_lock", 1, 60)
  if success then
      ok, err = ngx.timer.every(30, seed_to_redis)
      if not ok then
          kong.log.err("failed to create DOWNLOAD_LIMITER Timer: ", err)
      else
          kong.log.info("Timer started for DOWNLOAD_LIMITER: ", 30)
      end
  else
      kong.log.info("DOWNLOAD_LIMITER Timer skipped, already started: ", err)
  end

end --]]



--[[ runs in the 'ssl_certificate_by_lua_block'
-- IMPORTANT: during the `certificate` phase neither `route`, `service`, nor `consumer`
-- will have been identified, hence this handler will only be executed if the plugin is
-- configured as a global plugin!
function plugin:certificate(plugin_conf)

  -- your custom code here
  kong.log.debug("saying hi from the 'certificate' handler")

end --]]



--[[ runs in the 'rewrite_by_lua_block'
-- IMPORTANT: during the `rewrite` phase neither `route`, `service`, nor `consumer`
-- will have been identified, hence this handler will only be executed if the plugin is
-- configured as a global plugin!
function plugin:rewrite(plugin_conf)

  -- your custom code here
  kong.log.debug("saying hi from the 'rewrite' handler")

end --]]



-- runs in the 'access_by_lua_block'
function plugin:access(plugin_conf)

  -- your custom code here
  --kong.log.inspect(plugin_conf)   -- check the logs for a pretty-printed config!
  
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

end --]]


-- runs in the 'header_filter_by_lua_block'
-- function plugin:header_filter(plugin_conf)

--   -- your custom code here, for example;
--   kong.response.set_header(plugin_conf.response_header, "this is on the response")

-- end --]]


--[[ runs in the 'body_filter_by_lua_block'
function plugin:body_filter(plugin_conf)

  -- your custom code here
  kong.log.debug("saying hi from the 'body_filter' handler")

end --]]


-- runs in the 'log_by_lua_block'
function plugin:log(plugin_conf)
    if kong.ctx.plugin.domain then
      log_record.log_download_limit(kong.ctx.plugin.domain)
    end
end


-- return our plugin object
return plugin
