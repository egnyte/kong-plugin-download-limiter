local typedefs = require "kong.db.schema.typedefs"

-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local schema = {
  name = plugin_name,
  fields = { 
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { domain_header = { type = "string" , default ="X-Domain" },},
          { response_header = { type = "string", default = "X-Ratelimited" },},
        },
      },
    },
  },
}

return schema
