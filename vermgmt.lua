local json = require("dkjson")
local sha1 = require("sha1")
local yaml = require("lyaml")

local vermgmt = {}

function vermgmt.generateYml(folder, properties)
    local data = json.encode(properties)
    local hash = sha1(data)

    local output = folder.."serverix.yml"
    local f = assert(io.open(output, "wb"))
    f:write([[
hash: ]]..hash)
    f:close()
end

function vermgmt.readYml(folder)
    local f = assert(io.open(folder.."serverix.yml", "r"))
    local content = f:read("a")
    f:close()
    local data = yaml.load(content)
    return data
end

return vermgmt

