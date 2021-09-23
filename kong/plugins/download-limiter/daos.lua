local cjson = require("cjson")
local Errors = require "kong.db.errors"
local typedefs = require "kong.db.schema.typedefs"

local RULES_SCHEMA = {
	endpoint_key = "domain",
	primary_key = {"domain"},
	name = "download_limiter",
    fields = {
		{ domain = { type = "string" } },
		{ rule  = { type = "string" },}
    },
}

return {
    download_limiter = RULES_SCHEMA
}
