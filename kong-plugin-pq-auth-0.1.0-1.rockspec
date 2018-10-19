package = "kong-plugin-pq-auth"
version = "0.1.0-1"

local pluginName = package:match("^kong%-plugin%-(.+)$")

supported_platforms = {"linux", "macosx"}
source = {
  url = "https://github.com/cmayespq/kong-plugin-" .. pluginName,
  tag = "0.1.0"
}

description = {
  summary = "Kong plugin to authenticate requests using ProQuest http services.",
  license = "Apache 2.0",
  homepage = "https://github.com/cmayespq/kong-plugin-" ..  pluginName,
  detailed = [[
      Kong plugin to authenticate requests using ProQuest http services.
  ]]
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins." .. pluginName .. ".handler"] = "kong/plugins/" .. pluginName .. "/handler.lua",
    ["kong.plugins." .. pluginName .. ".schema"] = "kong/plugins/" .. pluginName .. "/schema.lua",
    ["kong.plugins." .. pluginName .. ".helpers"] = "kong/plugins/" .. pluginName .. "/helpers.lua",
  }
}
