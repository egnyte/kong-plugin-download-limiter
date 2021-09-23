-- `<plugin_name>/migrations/000_base_my_plugin.lua`
return {
    postgres = {
      up = [[
          CREATE TABLE IF NOT EXISTS download_limiter(
            domain text,
            rule text,
            PRIMARY KEY (domain)
          );
      ]],
    },
    cassandra = {
      up = [[
          CREATE TABLE IF NOT EXISTS download_limiter(
            domain text,
            rule text,
            PRIMARY KEY (domain)
          );
        ]],
  }
  }