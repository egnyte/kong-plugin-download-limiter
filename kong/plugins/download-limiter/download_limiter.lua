local redis = require "resty.redis"
local cjson = require("cjson")
local module = {}

function module.has_key(table, key)
    return table[key]~=nil
end


function module.check_todays_limit(data_downloaded, download_limits, domain, extend_range)
	local extended_limits_for_day = math.random(1,extend_range*100)/100
	local extended_data = (extended_limits_for_day * download_limits) + download_limits
	local max_limit = (extend_range * download_limits) + download_limits

	if data_downloaded <= extended_data then
		kong.log.info("Downloaded Data : ", data_downloaded, " | Allowed Data Extension : ", extended_data, ". Limit reached for domain: ", domain , ". Allowing some extension. Allowed extension percentage is ", (extended_limits_for_day*100), "% uri : ", ngx.var.request_uri, ", ALLOWED")
	end

	if data_downloaded > max_limit then
		kong.log.err("Downloaded Data : ", data_downloaded, " | Max allowed Data : ", max_limit, ". Limit reached for domain: ", domain , " along with the max allowed extension of : ", (extend_range*100) ,"%, uri : ", ngx.var.request_uri, ", BLOCKED" )
		return true
	end

	if data_downloaded > extended_data then
		kong.log.err("Downloaded Data : ", data_downloaded, " | Max allowed Data : ", extended_data, ". Limit reached for domain: ", domain , " along with the allowed extension of : ", (extended_limits_for_day*100) ,"%, max allowed : ", (extend_range*100) ,"%, uri : ", ngx.var.request_uri, ", BLOCKED" )
		return true
	end
	return false
end


function module.generate_retry_header()
	-- make retry afer a day.
	-- add random number to avoid thundering herd problem
	local random_num = math.random(10,60)
	local dt = os.date("*t")
	local remaining_seconds = (dt.hour * -3600 - dt.min * 60 - dt.sec) % 86400
	return (remaining_seconds + random_num)
end

function module.get_header(header_name) 
	local header_name = string.gsub(string.lower('http_'..header_name), "-", "_")
	local header = ngx.var[header_name]
	return header
end

function module.filter_headers(header_list)
	for i=1, #header_list do
		local key = header_list[i].name
		local pattern = header_list[i].pattern
		local value = module.get_header(key)
		if value == nil then
			return false
		end
		if not value:find(pattern) then
			local status = false
			-- Separating the pattern by | since there is no or separator in regex pattern matching for lua
			for subpattern in pattern:gmatch("([^|]+)") do
				if value:find(subpattern) then
					status = true
				end
			end
			if not status then
				return false
			end
		end
	end
	return true
end

function module.check_download_limit(limit_rules, domain)
	
	if limit_rules.exclude_filter ~= nil then
		local forward = module.filter_headers(limit_rules.exclude_filter)
		if forward then
			return
		end
	end

	if limit_rules.include_filter ~= nil then
		local forward = module.filter_headers(limit_rules.include_filter)
		if not forward then
			return
		end
	end

	local dl_limit = limit_rules.config.dl_limit
    local match_path = limit_rules.config.match_path	

	if (ngx.var.request_uri:find(match_path) ~= nil and  dl_limit > 0 ) then

		kong.ctx.plugin.domain = domain

		local red = redis:new()
		red:set_timeout(1000) -- 1 sec
		local ok, err = red:connect( _G.redis_dl_limit_host,  _G.redis_dl_limit_port)
		if not ok then
			kong.log.err("failed to connect to redis: ", err)
			return
		end
		local domain_key = _G.redis_dl_limit_key_prefix .. "." .. domain .. "." .. (os.date("%Y%m%d"))
		
		local data_download_size, err = red:get(domain_key)
		if not data_download_size then
			kong.log.err("Issue in getting download size", err)
			return
		end
		local ok, err = red:set_keepalive(10000, 50)
		if not ok then
			kong.log.err("failed to set keepalive: ", err)
			return
		end
		kong.log.debug("[!] Downloaded content size: ", data_download_size, " Host: ", ngx.var.http_host, " domain: ", domain)

		local data_download_size = tonumber(data_download_size)
		local dl_limit = tonumber(dl_limit)
		
		if data_download_size then
			if data_download_size > dl_limit then
				local extend_limits = tonumber(limit_rules.config.extend_limits)
				local extend_range = tonumber(limit_rules.config.extend_range)
				
				-- on weekends extend limit by N% of existing limits
				-- 7 is saturday and 1 is sunday weekend for Lua 
				local extend_limit_days = {}
				extend_limit_days[7] = true
				extend_limit_days[1] = true
				local day_of_the_week = os.date('*t').wday
				if (extend_limit_days[day_of_the_week] and extend_limits > 0) then
					-- its number * 100; so if its specified as 0.5 that means limits increase is 50%						
					local extended_data = (extend_limits * dl_limit) + dl_limit
					-- send download limit as limits which are calculated for weekend
					return module.check_todays_limit(data_download_size, extended_data, domain, extend_range)
				end
				return module.check_todays_limit(data_download_size, dl_limit, domain, extend_range)
			end
		end
	end
end

return module