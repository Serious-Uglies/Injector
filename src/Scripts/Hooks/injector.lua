---@diagnostic disable: undefined-field

local lfs = require('lfs')
local log = require('log')
local net = require('net')

local writedir = string.gsub(lfs.writedir(), "\\", "/")
local sourcedir = string.format("%sScripts/Inject", writedir)

local sandbox_script = [==[
    local function create_sandbox()
        local lfs = require("lfs")

        local gmatch = string.gmatch
        local gsub = string.gsub
        local format = string.format

        local sandbox = {}
        local sandbox_package = {}
        local sandbox_loaded  = {
            string = string,
            table = table
        }
        local sandbox_preload = {}
        local sandbox_loaders = {}

        local function my_assert(expected, msg, lvl)
            if expected then
                return
            end

            error(msg, lvl)
        end

        local function search_file(name, path)
            my_assert(type(path) == "string", format("path must be a string, got %s", type(path)), 2)

            name = gsub(name, "%.", '\\')
            path = gsub(path, "%?", name)

            local searched = {}

            for candidate_path in gmatch(path, "[^;]+") do
                table.insert(searched, candidate_path)

                if lfs.attributes(candidate_path) ~= nil then
                    return candidate_path
                end
            end

            return nil, searched
        end

        local function preload_loader(name)
            my_assert(type(sandbox_preload) == "table", "`package.preload' must be a table", 2)

            return sandbox_preload[name]
        end

        local function script_loader(name)
            local filename, searched = search_file(name, sandbox_package.path)
            if not filename then
                return false, searched
            end

            local f, err = loadfile(filename)
            if not f then
                error(format("error loading module `%s' (%s)", name, err))
            end

            return f
        end

        local function parent_loader(name)
            local success, mod = pcall(require, name)

            if not success then
                local _, searched = search_file(name, sandbox_package.path)
                return false, searched
            end

            return mod
        end

        local function load(name, loaders)
            my_assert(type(loaders) == "table", "`package.loaders' must be a table", 2)

            local msg = ""

            for i = 1, #loaders do
                local mod, searched = loaders[i](name)

                if mod then
                    if type(mod) == "function" then
                        return setfenv(mod, sandbox)()
                    end

                    return mod
                end

                if searched then
                    for s = 1, #searched do
                        msg = msg .. "        no file: " .. searched[s] .. "\n"
                    end
                end
            end

            error("module `" .. name .. "' not found:\n" .. msg, 2)
        end

        local function sandbox_require(name)
            if type(name) == "number" then
                name = tostring(name)
            elseif type(name) ~= "string" then
                error("bad argument #1 to `require' (string expected, got " .. type(name) .. ")", 3)
            end

            local mod = sandbox_loaded[name]
            if mod then
                return mod
            end

            mod = load(name, sandbox_loaders)

            if mod == nil then
                if sandbox_loaded[name] then
                    return sandbox_loaded[name]
                else
                    mod = true
                end
            end

            sandbox_loaded[name] = mod
            return mod
        end

        local function sandbox_module(name, ...)
            local t = sandbox_loaded[name] or sandbox[name] or {}
            sandbox[name] = t
            sandbox_loaded[name] = t

            local name_parts = {}

            for part in gmatch(name, "[^.]+") do
                table.insert(name_parts, part)
            end

            local package_name = ""

            for i = 1, #name_parts - 1 do
                if package_name == "" then
                    package_name = name_parts[i]
                else
                    package_name = package_name .. "." .. name_parts[i]
                end
            end

            t._NAME = name
            t._M = t
            t._PACKAGE = package_name

            setfenv(2, t)

            for _, wrapper in ipairs(arg) do
                wrapper(t)
            end
        end

        sandbox_loaders[#sandbox_loaders + 1] = preload_loader
        sandbox_loaders[#sandbox_loaders + 1] = script_loader
        sandbox_loaders[#sandbox_loaders + 1] = parent_loader
        sandbox_loaded.package = sandbox_package

        sandbox_package.config = package.config
        sandbox_package.path = package.path
        sandbox_package.cpath = package.cpath
        sandbox_package.seeall = package.seeall
        sandbox_package.loaded = sandbox_loaded
        sandbox_package.preload = sandbox_preload
        sandbox_package.loaders = sandbox_loaders

        sandbox.require = sandbox_require
        sandbox.package = sandbox_package
        sandbox.module = sandbox_module

        setmetatable(sandbox, {
            __index = function(table, key)
                local value = rawget(table, key)

                if value ~= nil then
                    return value
                end

                return _G[key]
            end
        })

        return sandbox
    end

    return create_sandbox
]==]

local create_sandbox = loadstring(sandbox_script, "loadstring: injector-sandbox")()

---- SETUP LOGGING ----

log.set_output('injector', 'INJECTOR', log.ALL, log.FULL)

local function write_log(level, msg, ...)
    log.write('INJECTOR', level, string.format(msg, ...))
end

--- FUNCTIONS ---

local function load_gui_script(path, dir)
    local env = create_sandbox()
    env.package.path = string.format("%s/?.lua;%s", dir, env.package.path)

    local hook = loadfile(path)

    if not hook then
        return
    end

    return pcall(setfenv(hook, env))
end

local function load_mission_script(path, dir)
    return net.dostring_in("mission", string.format([=[
        a_do_script([[
            local path = %q
            local dir = %q
            local env = injector_create_sandbox()

            env.package.path = dir .. "/?.lua;" .. env.package.path; 

            local success, err = pcall(setfenv(loadfile(path), env))

            if success then
                log.write("INJECTOR", log.INFO, "Successfully loaded " .. path .. " into mission environment")
            else 
                log.write("INJECTOR", log.ERROR, "Failed to load " .. path .. " into mission environment: " .. tostring(err))
            end
        ]])
    ]=], path, dir))
end

--- LOAD FILES ---


local function load()
    for entry in lfs.dir(sourcedir) do
        local full_path = string.format("%s/%s", sourcedir, entry)

        if lfs.attributes(full_path, "mode") == "directory" and entry ~= ".." and entry ~= "." then
            write_log(log.INFO, "Loading module %s", entry)

            local gui_script = string.format("%s/hook.lua", full_path)
            local mission_script = string.format("%s/init.lua", full_path)

            if lfs.attributes(gui_script) ~= nil then
                write_log(log.INFO, "Loading file %q into GUI environment", gui_script)

                local success, err = load_gui_script(gui_script, full_path)

                if success then
                    write_log(log.INFO, "Successfully loaded %q into GUI environment", gui_script)
                else
                    write_log(log.ERROR, "Failed to load %q into GUI environment: %s", gui_script, tostring(err))
                end
            end

            if lfs.attributes(mission_script) ~= nil then
                write_log(log.INFO, "Loading file %q into mission environment", mission_script)
                load_mission_script(mission_script, full_path)
            end
        end
    end
end

local callbacks = {}

function callbacks.onSimulationStart()
    net.dostring_in("mission", string.format([==[
        a_do_script([=[
            injector_create_sandbox = loadstring([[%s]], "loadstring: injector-sandbox")()
        ]=])
    ]==], sandbox_script))

    local success, error = pcall(load)

    if not success then
        write_log(log.ERROR, "Could not load files: %s", error)
    end
end

DCS.setUserCallbacks(callbacks)
