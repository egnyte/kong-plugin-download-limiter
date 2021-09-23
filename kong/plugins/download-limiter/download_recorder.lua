require "socket"

local redis = require "resty.redis"
local module = {}
local shm = ngx.shared.download_data_counter

function module.send_download_data_keys_to_redis(premature, redis_dl_limit_host, redis_dl_limit_port)
    
    kong.log.info("sending keys to redis")
    local start_time = ngx.now()

    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(redis_dl_limit_host, redis_dl_limit_port)
    if not ok then
        kong.log.err("!! .. Failed to connect to redis :- ", err)
        return
    end

    red:init_pipeline()

    local keys = shm:get_keys(0)
    local count = 0;
    for _, key in pairs(keys) do
        -- Known race condition, ngx.shared.DICT does not have an atomic getAndSet
        local value = shm:get(key)
        shm:delete(key)
        if value then
            local ing, ing_err = red:incrby(key, value)
            count = count + 1
        end
    end
 
    local ok, err = red:commit_pipeline()
    if not ok then
        kong.log.err("Pipeline commit failed", err)
    end
   
    kong.log.info("Finished send_download_data_keys_to_redis, keys=", count, ", time=",
        ngx.now() - start_time, " seconds, pending timers=", ngx.timer.pending_count(),
        ", running_timers=", ngx.timer.running_count())
    
  
    local ok, err = red:set_keepalive(10000, 50)
    if not ok then
        kong.log.err("failed to set keepalive: ", err)
        return
    end

end

function module.log_download_limit(domain)

    local ok_dwn, err_dwn = ngx.timer.at(0, module.log_download, domain, ngx.var.bytes_sent, ngx.var.request_uri)
    
    if not ok_dwn then
		kong.log.err("Could not submit job: ", err_dwn)
		return
    end
end

function module.log_download(premature, domain, total_chunk_downloaded, request_uri)
    
    kong.log.debug("!!!.Logging Download for day ..!!! ",  domain)
    local host_downloading = _G.redis_dl_limit_key_prefix .. "." .. domain .. "." .. (os.date("%Y%m%d"))
    local total_chunk_sent = tonumber(total_chunk_downloaded)
    local newval, err = shm:incr(host_downloading, total_chunk_sent, 0, 1800)
    if not newval then
            kong.log.err("could not increment counter for '", host_downloading, "': ", err)
            return
    end
end

return module