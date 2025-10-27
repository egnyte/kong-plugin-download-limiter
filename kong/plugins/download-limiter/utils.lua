local module = {}

local ngx_log = ngx.log

function module.redis_auth(red)
    if _G.redis_dl_limit_password and _G.redis_dl_limit_password ~= "" then
        local ok, err
        if _G.redis_dl_limit_username and _G.redis_dl_limit_username ~= "" then
            ok, err = red:auth(_G.redis_dl_limit_username, _G.redis_dl_limit_password)
        else
            ok, err = red:auth(_G.redis_dl_limit_password)
        end
        if not ok then
            return false, err
        end
    end
    return true, nil
end

return module