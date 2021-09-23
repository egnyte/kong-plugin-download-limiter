local crud = require "kong.api.endpoints"
local endpoints = require "kong.api.endpoints"
local utils = require "kong.tools.utils"

local download_limiter_schema = kong.db.download_limiter.schema
local cjson = require "cjson"

return {
  ["/download-limiter/domains"] = {
    schema = download_limiter_schema,
    methods = {
      GET = endpoints.get_collection_endpoint(download_limiter_schema),
      POST = endpoints.post_collection_endpoint(download_limiter_schema),
    },
  },
  ["/download-limiter/domain/:domain"] = {
    schema = download_limiter_schema,
    methods = {
      GET  = function(self, db, helpers)  
          local domain, err = kong.db.download_limiter:select({ domain =  self.params["domain"]  })
          if err then
            kong.log.err("Error  :  " .. err)
          end
          if not domain then
            return kong.response.exit(404, { message = "Not found" })
          end                                            
          return kong.response.exit(200, cjson.encode(domain), { ["Content-Type"] = "application/json" })
        end,

      PATCH = function(self, db, helpers)
        local entity, err = kong.db.download_limiter:update( { domain = self.params["domain"] }, { rule = self.params["rule"] })
        
        if not entity then
          kong.log.err("Error when updating : " .. err)
          return kong.response.exit(500, { message = "Error"}, { ["Content-Type"] = "application/json" })
        end
      end,

      PUT = function(self, db, helpers)
        local entity, err = kong.db.download_limiter:upsert( { domain = self.params["domain"] }, { rule = self.params["rule"] })
        
        if not entity then
          kong.log.err("Error when upserting : " .. err)
          return kong.response.exit(500, { message = "Error"}, { ["Content-Type"] = "application/json" })
        end
      end,

      DELETE = function(self, db, helpers)                  
        local ok, err = kong.db.download_limiter:delete({ domain =  self.params["domain"]  })
        if not ok then
          kong.log.err("Error when deleting Rule : " .. err)
          return kong.response.exit(500, { message = "Error"}, { ["Content-Type"] = "application/json" })
        end
        return kong.response.exit(200, "success")
      end,
    }

  }



}
