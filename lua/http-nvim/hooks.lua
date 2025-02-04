local config = require("http-nvim.config")
local fs = require("http-nvim.fs")

---@alias http.BeforeHook function(request: http.Request, run_request: function(): nil): nil
---@alias http.AfterHook function(request: http.Request, response: http.Response, raw: http.Raw): nil

local M = {}

---Load the hook functions that run before and after a request
---@param before_hook string?
---@param after_hook string?
---@return http.BeforeHook?
---@return http.AfterHook?
M.load_hook_functions = function(before_hook, after_hook)
    local hooks_path = config.get_hooks_path()

    if not fs.file_exists(hooks_path) then
        return nil, nil
    end

    local hooks = dofile(hooks_path)
    if hooks == nil then
        return nil, nil
    end

    return hooks[before_hook], hooks[after_hook]
end

M.open_hooks_file = function()
    local hooks_path = config.get_hooks_path()
    vim.cmd([[split ]] .. hooks_path)
end

return M
