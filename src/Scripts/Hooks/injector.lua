local io = require('io')
local lfs = require('lfs')
local log = require('log')
local net = require('net')

local writedir = string.gsub(lfs.writedir(), "\\", "/")

---- SETUP LOGGING ----

log.set_output('injector', 'INJECTOR', log.ALL, log.FULL)

local function logInfo(msg)
    log.write('INJECTOR', log.INFO, msg)
end

--- FUNCTIONS ---

local function loadFile(path, dir)
    local file = io.open(path, "r")
    local content = file:read("*a")

    local script = string.format('package.path = "%s/?.lua;" .. package.path; package.cpath = "%s/?.dll;" .. package.cpath; %s', dir, dir, content)
	local result, success = net.dostring_in("mission", "a_do_script([===[" .. script .. "]===])")

    file:close()

    return result, success
end

--- LOAD FILES ---

local loaders = {}
local sourceDir = writedir .. "Scripts/Inject"

local function loadFiles() 
    for entry in lfs.dir(sourceDir) do
        local fullPath = sourceDir .. "/" .. entry

        if lfs.attributes(fullPath, "mode") == "directory" and entry ~= ".." and entry ~= "." then
            local initLua = fullPath .. "/init.lua"

            loaders[entry] = function()
                logInfo("Loading " .. initLua .. " into mission environment")

                local result, success = loadFile(initLua, fullPath)

                if success then
                    logInfo("File was loaded successfully")
                else
                    logInfo("File load result: " .. tostring(result) .. ", success: " .. tostring(success))
                end
            end
        end
    end
end

local loadFileResult, loadFileErr = pcall(loadFiles, nil)

if not loadFileResult then
    logInfo("Failed to load files: " .. tostring(loadFileErr))
end

local callbacks = {}

function callbacks.onSimulationStart()
    logInfo("Handling onSimulationStart")

    for name, loader in pairs(loaders) do
        logInfo("Loading module " .. name)
        loader()
    end
end

DCS.setUserCallbacks(callbacks)