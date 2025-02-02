local config = require("http-nvim.config")

local fs = require("http-nvim.fs")

local M = {}

M.get_all_active_envs = function()
    if not fs.file_exists(config.options.active_envs_file) then
        return {}
    end

    local contents = fs.read_file(config.options.active_envs_file)
    if contents == "" then
        return {}
    end

    local active_envs = vim.json.decode(contents)
    if active_envs == nil then
        return {}
    end

    return active_envs
end

return M
