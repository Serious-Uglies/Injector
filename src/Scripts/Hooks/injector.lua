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

local function loadHook(path, dir)
    local env = setmetatable({}, { __index = _G })
    env.package.path = dir .. "/?.lua;" .. package.path;
    return pcall(setfenv(loadfile(path), env))
end

local function loadFile(path, dir)
    return net.dostring_in("mission", string.format([=[
        a_do_script('package.path = "%s/?.lua;" .. package.path; package.cpath = "%s/?.dll;" .. package.cpath;')
        a_do_script('loadfile(%q)()')
    ]=], dir, dir, path))
end

local function logResult(success, result)
    if success then
        logInfo("File was loaded successfully")
    else
        logInfo("File could not be loaded: " .. tostring(result))
    end
end

--- LOAD FILES ---

local loaders = {}
local sourceDir = writedir .. "Scripts/Inject"

local function loadFiles()
    for entry in lfs.dir(sourceDir) do
        local fullPath = sourceDir .. "/" .. entry

        if lfs.attributes(fullPath, "mode") == "directory" and entry ~= ".." and entry ~= "." then
            local initLua = fullPath .. "/init.lua"
            local hookLua = fullPath .. "/hook.lua"

            loaders[entry] = function()
                if lfs.attributes(hookLua) ~= nil then
                    logInfo("Loading " .. hookLua .. " into hook environment")
                    logResult(loadHook(hookLua, fullPath))
                end

                if lfs.attributes(initLua) ~= nil then
                    logInfo("Loading " .. initLua .. " into mission environment")
                    logResult(loadFile(initLua, fullPath))
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
    for name, loader in pairs(loaders) do
        logInfo("Loading module " .. name)
        loader()
    end

end


DCS.setUserCallbacks(callbacks)