local M = {}

---@class http.BufferAction
---@field [1] string
---@field opts table

---@class http.BufferOpts
---@field [1] http.BufferType?
---@field keys table<string, string|http.BufferAction|fun()>

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
    ---Disable builtin winbar if you are explicitly using the public
    ---winbar functions with plugins like lualine and want to avoid flickering.
    ---@type boolean
    builtin_winbar = true,
    ---Options for each of the response buffers.
    ---@type (http.BufferType|http.BufferOpts)[]
    buffers = {
        "body",
        "headers",
        "raw",
    },
    ---Default options for every response buffer.
    ---@type http.BufferOpts
    buffer_defaults = {
        keys = {
            ["<Tab>"] = "next_buffer",
            ["<C-r>"] = "rerun",
            q = "close",
        },
    },
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

local function merge_defaults(opts)
    local options = vim.tbl_deep_extend("force", defaults, opts or {})

    for i, buffer in ipairs(options.buffers) do
        if type(buffer) == "string" then
            local full_buffer_config = vim.deepcopy(options.buffer_defaults)
            full_buffer_config[1] = buffer

            options.buffers[i] = full_buffer_config
        end
    end

    return options
end

---@param opts? http.Opts
M.setup = function(opts)
    define_highlights()
    M.options = merge_defaults(opts)
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
