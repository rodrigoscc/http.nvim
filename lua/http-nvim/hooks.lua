local Path = require("plenary.path")
local config = require("http-nvim.config")
local with = require("plenary.context_manager").with
local open = require("plenary.context_manager").open

---@alias http.BeforeHook function(request: http.Request, run_request: function(): nil): nil
---@alias http.AfterHook function(request: http.Request, response: http.Response, stdout: string): nil

local M = {}

---Load the hook functions that run before and after a request
---@param before_hook string?
---@param after_hook string?
---@return http.BeforeHook?
---@return http.AfterHook?
M.load_hook_functions = function(before_hook, after_hook)
    local hooks_path = config.get_hooks_path()

    if not hooks_path:exists() then
        return nil, nil
    end

    local hooks_file_exists = with(
        open(hooks_path:absolute(), "r"),
        function(file)
            return file ~= nil
        end
    )

    if hooks_file_exists then
        local hooks = dofile(hooks_path:absolute())
        if hooks == nil then
            return nil, nil
        end

        return hooks[before_hook], hooks[after_hook]
    end

    return nil, nil
end

M.open_hooks_file = function()
    local hooks_path = config.get_hooks_path()
    vim.cmd([[split ]] .. hooks_path:absolute())
end

return M
