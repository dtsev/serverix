local https = require("ssl.https")
local json = require("dkjson")
local vermgmt = require("vermgmt")
local lfs = require('lfs')
local sha1 = require("sha1")

LATEST_VERSION = "1.21.5" --latest available version of Minecraft

local cores = {
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


local function runFzf(buildList)
    local input = table.concat(buildList, "\n")
    local tmp = os.tmpname()
    local f = assert(io.open(tmp, "w"))
    f:write(input)
    f:close()

    local handle = io.popen("fzf < " .. tmp)
    local result = handle:read("*a")
    handle:close()

    os.remove(tmp)
    return result:match("Build #%d+")
end

local function downloadCore(core, version, destination)
    local builds_url
    if core == "paper" then
        builds_url = "https://api.papermc.io/v2/projects/paper/versions/"..version.."/builds"
    elseif core == "purpur" then
        builds_url = "https://api.purpurmc.org/v2/purpur/"..version
    elseif core == "fabric" then
        builds_url = "https://meta.fabricmc.net/v2/versions/loader"
    else
        error("Unsupported core: " .. core)
    end

    local body, code = https.request(builds_url)
    if code ~= 200 then error("Failed to fetch builds list: HTTP "..tostring(code)) end
    local parsed = json.decode(body)
    if not parsed then error("Invalid JSON") end

    local builds = {}
    local displayList = {}

    if core == "paper" then
        builds = parsed.builds
        for _, build in ipairs(builds) do
            local b = build.build
            local iso = build.time or ""
            local y, m, d, H, M = iso:match("(%d+)%-(%d+)%-(%d+)T(%d+):(%d+)")
            local formatted_time = "unknown"
            if y and m and d and H and M then
                formatted_time = os.date("%b %d, %Y %H:%M", os.time{
                    year=tonumber(y), month=tonumber(m), day=tonumber(d),
                    hour=tonumber(H), min=tonumber(M)
                })
            end
            table.insert(displayList, string.format("Build #%d - %s", b, formatted_time))
        end
    elseif core == "purpur" then
        builds = parsed.builds.all
        for _, b in ipairs(builds) do
            table.insert(displayList, "Build #" .. b)
        end
    elseif core == "fabric" then
        -- For Fabric, we need to get loader versions and let user pick one
        builds = parsed
        for _, loader in ipairs(builds) do
            if loader.stable then
                table.insert(displayList, string.format("Loader %s (stable)", loader.version))
            else
                table.insert(displayList, string.format("Loader %s", loader.version))
            end
        end
    end

    -- Check if we have items in displayList
    if #displayList == 0 then
        error("No builds/versions found for " .. core)
    end
    
    -- Try fzf first, fallback to manual selection if it fails
    local selected_line = runFzf(displayList)
    if not selected_line then 
        print("unfortunately, fzf failed, so u need to use manual selection:")
        print("\nAvailable options:")
        for i, item in ipairs(displayList) do
            print(string.format("%2d: %s", i, item))
        end
        
        
        io.write(string.format("\nSelect option (1[latest]-%d): ", #displayList))
        local choice = io.read()
        local choice_num = tonumber(choice)
        
        if not choice_num or choice_num < 1 or choice_num > #displayList then
            error("Invalid selection. Please enter a number between 1 and " .. #displayList)
        end
        
        selected_line = displayList[choice_num]
        print("Selected: " .. selected_line)
    end

    local download_url
    local filename

    if core == "paper" then
        local selected_build = selected_line:match("#(%d+)")
        if not selected_build then error("Failed to extract build number.") end

        local build_meta_url = string.format("https://api.papermc.io/v2/projects/paper/versions/%s/builds/%s", version, selected_build)
        local meta_body, meta_code = https.request(build_meta_url)
        if meta_code ~= 200 then error("Failed to get metadata") end
        local meta = json.decode(meta_body)
        filename = meta.downloads.application.name
        download_url = string.format("https://api.papermc.io/v2/projects/paper/versions/%s/builds/%s/downloads/%s", version, selected_build, filename)
    elseif core == "purpur" then
        local selected_build = selected_line:match("#(%d+)")
        if not selected_build then error("Failed to extract build number.") end

        filename = "purpur-server.jar"
        download_url = string.format("https://api.purpurmc.org/v2/purpur/%s/%s/download", version, selected_build)
    elseif core == "fabric" then
        local loader_version = selected_line:match("Loader ([%d%.]+)")
        if not loader_version then error("Failed to extract loader version.") end

        -- Get the latest installer version
        local installer_url = "https://meta.fabricmc.net/v2/versions/installer"
        local installer_body, installer_code = https.request(installer_url)
        if installer_code ~= 200 then error("Failed to fetch installer versions: HTTP "..tostring(installer_code)) end
        local installer_parsed = json.decode(installer_body)
        if not installer_parsed or #installer_parsed == 0 then error("No installer versions found") end
        
        local installer_version = installer_parsed[1].version -- Get latest stable installer
        
        filename = string.format("fabric-server-%s-%s-%s.jar", version, loader_version, installer_version)
        download_url = string.format("https://meta.fabricmc.net/v2/versions/loader/%s/%s/%s/server/jar", version, loader_version, installer_version)
    end

    print("Downloading "..filename.." ...")
    local jar_body, jar_code = https.request(download_url)
    if jar_code ~= 200 then error("Failed to download jar: HTTP "..tostring(jar_code)) end

    local output = destination..filename
    local f = assert(io.open(output, "wb"))
    f:write(jar_body)
    f:close()

    print("✅ Saved to: "..output)
    return filename
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
    local ServerName = server.server.properties.motd:gsub("[/\\]", "_") -- sanitize folder name
    local ServerVersion = server.server.version
    local ServerRunScript = server.server.runscript
    local ServerProperties = server.server.properties
    local ServerFolder = server.server.folder  -- e.g. /home/denis/servers/
    local yml

    -- check core
    os.execute("clear")
    if not checkCore(ServerCore) then
        print("[SERVERIX]: "..ServerCore.." is not an available core, available cores are: "..table.concat(cores, ", "))
        return
    end

    local ServerFolder = server.server.folder

    if io.open(ServerFolder.."serverix.yml") then
        local yml = vermgmt.readYml(ServerFolder)
        local current_hash = sha1(json.encode(server.server.properties))
        if yml.hash ~= current_hash then
            local newFolder, version = getNextVersionedFolder(ServerFolder)
            print("[SERVERIX]: Detected config change. Creating versioned folder: "..newFolder)
            os.execute("mkdir -p \""..newFolder.."\"")
            ServerFolder = newFolder
        else
            print("[SERVERIX]: Matching config exists — skipping.")
            return
        end
    end



    -- download server core
    local DownloadedCore = downloadCore(ServerCore, ServerVersion, ServerFolder)
    os.rename(ServerFolder..DownloadedCore, ServerFolder..ServerCore.."-server.jar")

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

    -- lock
    vermgmt.generateYml(ServerFolder, ServerProperties)

    print("✅ "..ServerName.." built into: "..ServerFolder)
end


return serverix