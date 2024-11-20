local project = require("http-nvim.project")
local display = require("http-nvim.display")
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

M.show = function(request, response, output)
    vim.schedule(function()
        display.show(request, response, output)
    end)
end

return M
