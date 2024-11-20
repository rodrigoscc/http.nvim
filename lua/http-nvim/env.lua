local config = require("http-nvim.config")

local open = require("plenary.context_manager").open
local with = require("plenary.context_manager").with

local M = {}

M.get_all_active_envs = function()
    if vim.fn.findfile(config.options.active_envs_file) == "" then
        return {}
    end

    local contents = with(
        open(config.options.active_envs_file, "r"),
        function(reader)
            return reader:read("*a")
        end
    )

    local active_envs = vim.json.decode(contents)
    if active_envs == nil then
        return {}
    end

    return active_envs
end

return M
