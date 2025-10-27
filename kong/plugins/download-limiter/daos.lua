local cjson = require("cjson")
local Errors = require "kong.db.errors"
local typedefs = require "kong.db.schema.typedefs"

local RULES_SCHEMA = {
	generate_admin_api = false,
	endpoint_key = "domain",
	primary_key = {"domain"},
	name = "download_limiter",
    fields = {
		{ domain = { type = "string" } },
		{ rule  = { type = "string" },}
    },
}

return {
    RULES_SCHEMA
}
