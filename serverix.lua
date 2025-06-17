local https = require("ssl.https")
local json = require("dkjson")
local vermgmt = require("vermgmt")
local lfs = require('lfs')
local sha1 = require("sha1")

LATEST_VERSION = "1.21.5" --latest available version of Minecraft

local cores = { --after imperative core downloading removal, this table is pretty useless, but i still prefer to leave it here
    "paper", 
    "purpur",
    "spigot",
    "bukkit",
    "fabric",
    "forge",
    "vanilla"
} 

local function checkCore(core)
    for idx, val in ipairs(cores) do
        if val == core then
            return true
        end
    end
    return false
end

local function saveServerProperties(tbl, filepath)
    local f = assert(io.open(filepath or "server.properties", "w"))

    for key, value in pairs(tbl) do
        local line
        if type(value) == "boolean" then
            line = string.format("%s=%s", key, tostring(value))
        elseif type(value) == "number" then
            line = string.format("%s=%d", key, value)
        else
            -- Escape backslashes and colons for safety (as in minecraft\:normal)
            local safe = tostring(value):gsub("\\", "\\\\"):gsub(":", "\\:")
            line = string.format("%s=%s", key, safe)
        end
        f:write(line .. "\n")
    end

    f:close()
    print("✅ server.properties generated!")
end


local function getFileName(path)
    return path:match("^.+[\\/](.+)$") or path  -- fallback to full string
end

local function getNextVersionedFolder(baseFolder)
    -- Normalize: remove trailing slash
    baseFolder = baseFolder:gsub("[/\\]+$", "")
    local baseName = baseFolder:match("([^/\\]+)$")       -- ksmp
    local parentPath = baseFolder:match("^(.-)[/\\]?[^/\\]+/?$") or "./"

    if not lfs.attributes(baseFolder, "mode") then
        return baseFolder, 0
    end

    local max_version = 0
    for entry in lfs.dir(parentPath) do
        local pattern = "^" .. baseName:gsub("([%(%)%.%-%+%*%?%^%$%[%]])", "%%%1") .. " %((%d+)%)$"
        local version = tonumber(entry:match(pattern))
        if version and version > max_version then
            max_version = version
        end
    end

    local next_version = max_version + 1
    local newPath = string.format("%s/%s (%d)/", parentPath, baseName, next_version)
    return newPath, next_version
end



local function runServer(folder)
    os.execute(string.format('chmod +x "%srun.sh"', folder))
    local handle = io.popen(string.format('cd "%s" && exec ./run.sh', folder))
    local output = handle:read("*a")
    handle:close()
    print(output)
end


local serverix = {}


function serverix.InitServer(server)
    local BukkitPlugins = server.server.bukkitPlugins
    local ServerCore = server.server.core
    local ServerMods = server.server.mods
    local ServerName = server.server.properties.motd:gsub("[/\\]", "_") 
    local ServerRunScript = server.server.runscript
    local ServerProperties = server.server.properties
    local ServerFolder = server.server.folder  
    local yml

    -- clear console
    os.execute("clear")
    

    if io.open(ServerFolder.."serverix.yml") then
        local yml = vermgmt.readYml(ServerFolder)
        local current_hash = sha1(json.encode(server.server.properties))
        if yml.hash ~= current_hash then
            local newFolder, version = getNextVersionedFolder(ServerFolder)
            print("[SERVERIX]: Detected config change. Creating versioned folder: "..newFolder)
            os.execute("mkdir -p \""..newFolder.."\"")
            ServerFolder = newFolder
        else
            print("[SERVERIX]: matching config exists — skipping.")
            return
        end
    end

    -- download server core
    
    local DownloadedCore 
    print("[SERVERIX]: downloading "..getFileName(ServerCore).."...")
        print("[SERVERIX]: downloading "..ServerCore)
        local body, code = https.request(ServerCore)
        local output = ServerFolder.."server.jar"
        local f = assert(io.open(output, "wb"))
        f:write(body)
        f:close()
    --os.rename(output, ServerFolder..ServerCore.."-server.jar") renaming sequence is temporaly removed for deep thinking...

    -- write run.sh
    print("[SERVERIX]: creating run.sh")
    local runscript = io.open(ServerFolder.."run.sh", 'w')
    runscript:write(ServerRunScript.content)
    runscript:close()

    -- write properties
    print("[SERVERIX]: generating server.properties")
    saveServerProperties(ServerProperties, ServerFolder.."server.properties")

    -- run once
    print("[SERVERIX]: "..ServerName.."'s first start")
    runServer(ServerFolder)

    -- eula
    if ServerRunScript.autoeula then
        print("[SERVERIX]: accepting EULA")
        local eula = io.open(ServerFolder.."eula.txt", "w")
        eula:write("eula=true")
        eula:close()
    end

    -- plugins
    if BukkitPlugins then
        print("[SERVERIX]: installing plugins")
        for _, url in ipairs(BukkitPlugins) do
            print("[SERVERIX]: downloading "..url)
            local body, code = https.request(url)
            local output = ServerFolder.."plugins/"..getFileName(url)
            local f = assert(io.open(output, "wb"))
            f:write(body)
            f:close()
        end
    end

    -- mods
    if ServerMods then
        print("[SERVERIX]: installing mods")
        for _, url in ipairs(ServerMods) do
            print("[SERVERIX]: downloading "..url)
            local body, code = https.request(url)
            local output = ServerFolder.."mods/"..getFileName(url)
            local f = assert(io.open(output, "w"))
            f:write(body)
            f:close()
        end
    end

    -- generating lock
    vermgmt.generateYml(ServerFolder, ServerProperties)

    print("✅ "..ServerName.." built into: "..ServerFolder)
end


return serverix