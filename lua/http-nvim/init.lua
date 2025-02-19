local http = require("http-nvim.http")
local project = require("http-nvim.project")
local hooks = require("http-nvim.hooks")
local ui = require("http-nvim.ui")
local job = require("http-nvim.job")
local Source = require("http-nvim.source").Source
local SourceType = require("http-nvim.source").type
local id = require("http-nvim.requests").id
local tree_sitter_nodes = require("http-nvim.constants").tree_sitter_nodes
local config = require("http-nvim.config")

local has_cmp, cmp = pcall(require, "cmp")
local http_cmp_source = require("http-nvim.cmp_source")

local has_telescope = pcall(require, "telescope")
local has_fzf_lua = pcall(require, "fzf-lua")
local has_snacks = pcall(require, "snacks")

local function telescope_run(requests)
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")

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

                    local selection =
                        require("telescope.actions.state").get_selected_entry()

                    http:run(selection.request)
                end

                map("i", "<CR>", run_selected_request)
                map("n", "<CR>", run_selected_request)

                return true
            end,
        })
        :find()
end

local function telescope_jump(requests)
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values

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
end

local function fzf_lua_entry_maker(request)
    local fzf_lua = require("fzf-lua")
    local node_start, _, _ = request.node:start()

    local line = node_start + 1

    return request.source.route .. ":" .. fzf_lua.utils.ansi_codes.magenta(
        string.format("%d", line)
    ) .. ":" .. fzf_lua.utils.ansi_codes.blue(id(request)),
        request.source.route .. ":" .. line .. ":" .. id(request)
end

local function fzf_lua_jump(requests)
    local fzf_lua = require("fzf-lua")

    local entries = vim.tbl_map(function(request)
        local entry, _ = fzf_lua_entry_maker(request)
        return entry
    end, requests)

    fzf_lua.fzf_exec(entries, {
        actions = fzf_lua.defaults.actions.files,
        previewer = "builtin",
    })
end

local function fzf_lua_run(requests)
    local fzf_lua = require("fzf-lua")

    local entries_to_request = {}

    local entries = vim.tbl_map(function(request)
        local entry, clean_line = fzf_lua_entry_maker(request)
        -- Store entry line without ansi codes because that's what the action will receive
        entries_to_request[clean_line] = request
        return entry
    end, requests)

    fzf_lua.fzf_exec(entries, {
        actions = {
            default = function(selected)
                local request = entries_to_request[selected[1]]
                http:run(request)
            end,
        },
        previewer = "builtin",
    })
end

local function snacks_jump(requests)
    local items = vim.iter(ipairs(requests))
        :map(function(i, request)
            local node_start, _, _ = request.node:start()
            local line = node_start + 1

            local item = {
                text = id(request),
                idx = i,
                score = 1,
                file = request.source.route,
                pos = { line, 0 },
            }

            return item
        end)
        :totable()

    local file = require("snacks.picker.format").file
    local text = require("snacks.picker.format").text

    Snacks.picker.pick({
        title = "Go to HTTP request",
        items = items,
        format = function(item, picker)
            return vim.list_extend(file(item, picker), text(item, picker))
        end,
    })
end

local function snacks_run(requests)
    local id_to_request = {}

    local items = vim.iter(ipairs(requests))
        :map(function(i, request)
            local node_start, _, _ = request.node:start()
            local line = node_start + 1

            local item = {
                text = id(request),
                idx = i,
                score = 1,
                file = request.source.route,
                pos = { line, 0 },
            }

            id_to_request[i] = request

            return item
        end)
        :totable()

    local file = require("snacks.picker.format").file
    local text = require("snacks.picker.format").text

    Snacks.picker.pick({
        title = "Run HTTP request",
        items = items,
        format = function(item, picker)
            return vim.list_extend(file(item, picker), text(item, picker))
        end,
        confirm = function(picker, item)
            picker:close()
            http:run(id_to_request[item.idx])
        end,
    })
end

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
                local context = http:get_aggregate_context(closest_request)

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

            if has_telescope then
                telescope_run(requests)
            elseif has_fzf_lua then
                fzf_lua_run(requests)
            elseif has_snacks then
                snacks_run(requests)
            else
                error(
                    "Either nvim-telescope/telescope.nvim or ibhagwan/fzf-lua are required to run this command"
                )
            end
        end,
    },
    jump = {
        impl = function(args, opts)
            local requests = project.get_requests()

            if has_telescope then
                telescope_jump(requests)
            elseif has_fzf_lua then
                fzf_lua_jump(requests)
            elseif has_snacks then
                snacks_jump(requests)
            else
                error(
                    "Either nvim-telescope/telescope.nvim or ibhagwan/fzf-lua are required to run this command"
                )
            end
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
    yank_curl = {
        impl = function(args, opts)
            local cursor_line = unpack(vim.api.nvim_win_get_cursor(0))

            local source = Source.new(SourceType.BUFFER, vim.fn.bufnr())
            local closest_request = source:get_closest_request_from(cursor_line)

            if closest_request == nil then
                vim.notify("No request found under the cursor")
                return
            end

            local request_content = source:get_request_content(closest_request)

            local context = http:get_aggregate_context(closest_request)

            closest_request = http:complete_request(closest_request, context)
            request_content = http:complete_content(request_content, context)

            local curl_command =
                job.build_curl_command(closest_request, request_content)

            curl_command = ui.present_command(curl_command)

            vim.fn.setreg("+", curl_command)
            vim.notify("Yanked curl command to clipboard")
        end,
    },
    update_grammar_queries = {
        impl = function(args, opts)
            require("http-nvim.queries").update_grammar_queries()
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
