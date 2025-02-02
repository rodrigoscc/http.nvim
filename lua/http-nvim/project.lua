local Source = require("http-nvim.source").Source
local SourceType = require("http-nvim.source").type
local config = require("http-nvim.config")
local env = require("http-nvim.env")
local utils = require("http-nvim.utils")

local fs = require("http-nvim.fs")

local M = {}

M.get_requests = function()
    local files = vim.fs.find(function(name)
        return vim.endswith(name, ".http")
    end, { type = "file", limit = math.huge, path = config.options.http_dir })

    ---@type http.Request[]
    local requests = {}

    for _, file in ipairs(files) do
        local source = Source.new(SourceType.FILE, file)
        local file_requests = source:get_requests()
        vim.list_extend(requests, file_requests)
    end

    return requests
end

M.get_existing_envs = function()
    local env_file_path = config.get_project_envs_path()

    if not fs.file_exists(env_file_path) then
        return {}
    end

    local envs_file_contents = fs.read_file(env_file_path)

    if envs_file_contents == "" then
        return {}
    end

    return vim.json.decode(envs_file_contents) or {}
end

M.get_active_env = function()
    local all_active_envs = env.get_all_active_envs()
    local active_env = all_active_envs[vim.fn.getcwd()]
    if active_env == nil then
        return nil
    end

    return active_env
end

M.get_env_variables = function()
    local active_env = M.get_active_env()
    if active_env == nil then
        return {}
    end

    local envs = M.get_existing_envs()

    return envs[active_env] or {}
end

M.update_active_env = function(override_variables)
    local env_name = M.get_active_env()

    if env_name == nil then
        return
    end

    local envs = M.get_existing_envs()
    local variables = envs[env_name]
    variables = vim.tbl_extend("force", variables, override_variables)
    envs[env_name] = variables

    local updated_envs = vim.json.encode(envs)
    updated_envs = utils.format_if_jq_installed(updated_envs)

    local project_envs_path = config.get_project_envs_path()

    fs.touch_file(project_envs_path)
    fs.write_file(project_envs_path, updated_envs)
end

M.create_env = function(new_env)
    local project_envs_path = config.get_project_envs_path()

    fs.touch_file(project_envs_path)

    local envs = M.get_existing_envs()

    envs[new_env] = vim.empty_dict()

    local new_envs_file_contents = vim.json.encode(envs)

    new_envs_file_contents =
        utils.format_if_jq_installed(new_envs_file_contents)

    fs.write_file(project_envs_path, new_envs_file_contents)

    M.open_env(new_env)
    M.select_env(new_env)
end

M.open_env = function(e)
    config.open_project_envs_file()
    vim.fn.search('"' .. e .. '"')
end

M.select_env = function(e)
    fs.touch_file(config.options.active_envs_file)

    local active_envs = env.get_all_active_envs()

    active_envs[vim.fn.getcwd()] = e

    local envs_file_updated = vim.json.encode(active_envs)

    envs_file_updated = utils.format_if_jq_installed(envs_file_updated)

    fs.write_file(config.options.active_envs_file, envs_file_updated)
end

return M
