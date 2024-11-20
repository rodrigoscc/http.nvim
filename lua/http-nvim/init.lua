local http = require("http-nvim.http")
local project = require("http-nvim.project")
local hooks = require("http-nvim.hooks")
local ui = require("http-nvim.ui")
local Source = require("http-nvim.source").Source
local SourceType = require("http-nvim.source").type
local id = require("http-nvim.requests").id
local tree_sitter_nodes = require("http-nvim.constants").tree_sitter_nodes
local config = require("http-nvim.config")

local has_cmp, cmp = pcall(require, "cmp")
local http_cmp_source = require("http-nvim.cmp_source")

local has_telescope = pcall(require, "telescope")
if not has_telescope then
    error("This plugins requires nvim-telescope/telescope.nvim")
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")

local function get_variable_name_under_cursor()
    local node = vim.treesitter.get_node()

    assert(node ~= nil, "There must be a node here.")

    if node:type() ~= tree_sitter_nodes.variable_ref then
        return nil
    end

    local node_text =
        vim.trim(vim.treesitter.get_node_text(node, vim.fn.bufnr()))

    -- Remove the leading and trailing braces (e.g. `{{` and `}}`) from the
    -- variable reference.
    local variable_name = string.sub(node_text, 3, #node_text - 2)
    return variable_name
end

---@class HttpSubcommand
---@field impl fun(args:string[], opts: table) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[] (optional) Command completions callback, taking the lead of the subcommand's arguments

---@type table<string, HttpSubcommand>
local subcommand_tbl = {
    run_closest = {
        impl = function(args, opts)
            local cursor_line = unpack(vim.api.nvim_win_get_cursor(0))

            local source = Source.new(SourceType.BUFFER, vim.fn.bufnr())
            local closest_request = source:get_closest_request_from(cursor_line)

            if closest_request then
                http:run(closest_request)
            end
        end,
    },
    inspect = {
        impl = function(args, opts)
            local variable_name = get_variable_name_under_cursor()

            if variable_name == nil then
                return
            end

            local cursor_line = unpack(vim.api.nvim_win_get_cursor(0))
            local source = Source.new(SourceType.BUFFER, vim.fn.bufnr())
            local closest_request = source:get_closest_request_from(cursor_line)

            if closest_request then
                local request_context =
                    source:get_request_context(closest_request)
                local env_context = project:get_env_variables()

                local context = vim.tbl_extend(
                    "force",
                    env_context,
                    request_context,
                    closest_request.local_context
                )

                local value = context[variable_name]

                if value == nil then
                    value = ""
                end

                ui.show_in_floating(value)
            end
        end,
    },
    run = {
        impl = function(args, opts)
            local requests = project.get_requests()

            pickers
                .new({}, {
                    prompt_title = "Run HTTP request",
                    finder = finders.new_table({
                        results = requests,
                        entry_maker = function(request)
                            local line, _, _ = request.node:start()

                            return {
                                value = id(request),
                                ordinal = id(request),
                                display = id(request),
                                filename = request.source.route,
                                lnum = line + 1,
                                request = request,
                            }
                        end,
                    }),
                    previewer = conf.grep_previewer({}),
                    sorter = conf.generic_sorter({}),
                    attach_mappings = function(prompt_bufnr, map)
                        local run_selected_request = function()
                            actions.close(prompt_bufnr)

                            local selection = actions.state.get_selected_entry()

                            http:run(selection.request)
                        end

                        map("i", "<CR>", run_selected_request)
                        map("n", "<CR>", run_selected_request)

                        return true
                    end,
                })
                :find()
        end,
    },
    jump = {
        impl = function(args, opts)
            local requests = project.get_requests()

            pickers
                .new({}, {
                    prompt_title = "Jump to HTTP request",
                    finder = finders.new_table({
                        results = requests,
                        entry_maker = function(request)
                            local line, _, _ = request.node:start()

                            return {
                                value = id(request),
                                ordinal = id(request),
                                display = id(request),
                                filename = request.source.route,
                                lnum = line + 1,
                            }
                        end,
                    }),
                    previewer = conf.grep_previewer({}),
                    sorter = conf.generic_sorter({}),
                })
                :find()
        end,
    },
    run_last = {
        impl = function(args, opts)
            http:run_last()
        end,
    },
    select_env = {
        impl = function(args, opts)
            local envs = project.get_existing_envs()
            local available_envs = vim.tbl_keys(envs)

            vim.ui.select(
                available_envs,
                { prompt = "Select environment" },
                function(selected_env)
                    if selected_env ~= nil then
                        project.select_env(selected_env)
                    end
                end
            )
        end,
    },
    create_env = {
        impl = function(args, opts)
            vim.ui.input({ prompt = "Create environment" }, function(new_env)
                if new_env == nil then
                    return
                end

                project.create_env(new_env)
            end)
        end,
    },
    open_env = {
        impl = function(args, opts)
            local envs = project.get_existing_envs()
            local available_envs = vim.tbl_keys(envs)

            vim.ui.select(
                available_envs,
                { prompt = "Open env" },
                function(selected_env)
                    if selected_env ~= nil then
                        project.open_env(selected_env)
                    end
                end
            )
        end,
    },
    open_hooks = {
        impl = function(args, opts)
            hooks.open_hooks_file()
        end,
    },
}

---@param opts table :h lua-guide-commands-create
local function http_cmd(opts)
    local fargs = opts.fargs

    local subcommand_name = fargs[1]
    local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}

    local subcommand = subcommand_tbl[subcommand_name]

    if not subcommand then
        vim.notify(
            "Http: Unknown command: " .. subcommand_name,
            vim.log.levels.ERROR
        )
        return
    end

    subcommand.impl(args, opts)
end

vim.api.nvim_create_user_command("Http", http_cmd, {
    nargs = "+",
    desc = "Run Http commands",
    complete = function(arg_lead, cmdline, _)
        local subcmd_key, subcmd_arg_lead =
            cmdline:match("^['<,'>]*Http%s(%S+)%s(.*)$")

        local subcmd_has_completions = subcmd_key
            and subcmd_arg_lead
            and subcommand_tbl[subcmd_key]
            and subcommand_tbl[subcmd_key].complete

        if subcmd_has_completions then
            return subcommand_tbl[subcmd_key].complete(subcmd_arg_lead)
        end

        local is_subcmd = cmdline:match("^['<,'>]*Http%s+%w*$")
        if is_subcmd then
            local subcommand_names = vim.tbl_keys(subcommand_tbl)

            return vim.iter(subcommand_names)
                :filter(function(key)
                    return key:find(arg_lead) ~= nil
                end)
                :totable()
        end
    end,
})

local M = {}

---@param opts? http.Opts
M.setup = function(opts)
    local parser_config =
        require("nvim-treesitter.parsers").get_parser_configs()
    parser_config.http2 = {
        install_info = {
            url = "https://github.com/rstcruzo/tree-sitter-http2",
            branch = "main",
            files = { "src/parser.c" },
        },
        filetype = "http",
    }

    vim.treesitter.language.register("http2", "http")

    vim.filetype.add({
        extension = {
            http = "http",
        },
    })

    config.setup(opts)

    if has_cmp then
        cmp.register_source("http", http_cmp_source)
    end
end

M.http_env_lualine_component = function()
    local env = project.get_active_env()
    if env == nil then
        return ""
    end

    return "[ " .. env .. "]"
end

return M
