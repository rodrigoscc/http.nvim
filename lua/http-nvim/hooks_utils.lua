local project = require("http-nvim.project")
local ui = require("http-nvim.ui")
local http = require("http-nvim.http")

local M = {}

M.update_env = function(override_variables)
    vim.schedule(function()
        project.update_active_env(override_variables)
    end)
end

M.run_request = function(title, override_variables)
    vim.schedule(function()
        http:run_with_title(title, override_variables)
    end)
end

M.show = function(request, response, raw)
    vim.schedule(function()
        http:show(request, response, raw)
    end)
end

return M
