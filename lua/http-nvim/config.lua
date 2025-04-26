local M = {}

---@class http.Opts
local defaults = {
    ---Http files must be stored in this directory for http.nvim to find them
    ---@type string
    http_dir = ".http",
    ---File that contains the hooks to be executed before and after each request.
    ---This file will be inside the directory defined by `http_dir`.
    ---@type string
    hooks_file = "hooks.lua",
    ---File that contains each project environment. This file will
    ---be inside the directory defined by `http_dir`.
    ---@type string
    environments_file = "environments.json",
    ---File that contains each of the projects active environment
    ---@type string
    active_envs_file = vim.fn.stdpath("data") .. "/http/envs.json",
    ---Window config for the response window. Refer to :help nvim_open_win for the available keys.
    ---@type table
    win_config = { split = "below" },
    ---Set compound filetypes in the response buffers (e.g. "httpnvim.json", "httpnvim.text").
    ---This is primarily useful for blacklisting the buffers in plugins like Lualine.
    ---@type boolean
    use_compound_filetypes = false,
}

---@type http.Opts
M.options = defaults

local function define_highlights()
    vim.cmd([[
    highlight default HttpFinished ctermfg=Green guifg=#96F291
    highlight default HttpRunning ctermfg=Yellow guifg=#FFEC63
    highlight default HttpError ctermfg=Red guifg=#EB6F92
    highlight default HttpSuccessCode ctermbg=Green guibg=#89F291 ctermfg=Black guifg=Black cterm=bold gui=bold
    highlight default HttpErrorCode ctermbg=Red guibg=#EB6F92 ctermfg=Black guifg=Black cterm=bold gui=bold
    ]])
end

---@param opts? http.Opts
M.setup = function(opts)
    define_highlights()
    M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

---@return string
M.get_project_envs_path = function()
    return vim.fs.joinpath(M.options.http_dir, M.options.environments_file)
end

M.open_project_envs_file = function()
    local project_envs_path = M.get_project_envs_path()
    vim.cmd("split " .. project_envs_path)
end

---@return string
M.get_hooks_path = function()
    return vim.fs.joinpath(M.options.http_dir, M.options.hooks_file)
end

M.highlights = {
    finished = "HttpFinished",
    running = "HttpRunning",
    error = "HttpError",
    success_code = "HttpSuccessCode",
    error_code = "HttpErrorCode",
}

return M
